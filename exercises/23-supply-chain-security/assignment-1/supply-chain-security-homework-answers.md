# Supply Chain Security Homework Answers: Image Scanning, Dockerfile Hygiene, and SBOMs

---

## Exercise 1.1 Solution

**Approach:** Run `trivy image` with `--severity CRITICAL` and extract the package names from the Library column of the output.

```bash
# Run the scan, capture full output
trivy image --severity CRITICAL python:3.9-slim 2>&1 | tee /tmp/ex-1-1/full-scan.txt

# Extract package names from the Library column
# Trivy's table output uses "│" as a column separator
trivy image --severity CRITICAL python:3.9-slim 2>&1 \
  | grep "│.*CRITICAL" \
  | awk -F'│' '{print $2}' \
  | sed 's/[[:space:]]//g' \
  | sort -u \
  > /tmp/ex-1-1/critical-packages.txt

cat /tmp/ex-1-1/critical-packages.txt
```

The exact package list depends on the current Trivy database and what CVEs have been added since the image was published. At the time this assignment was written, `python:3.9-slim` based on Debian Bullseye carries CRITICAL findings in several system libraries. What matters for this exercise is that you run the scan with the correct severity filter and capture the Library column values.

An alternative approach that works regardless of the table column separator style is to use the JSON format:

```bash
trivy image --format json --severity CRITICAL python:3.9-slim 2>&1 \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
packages = set()
for result in data.get('Results', []):
    for vuln in result.get('Vulnerabilities', []):
        if vuln.get('Severity') == 'CRITICAL':
            packages.add(vuln.get('PkgName', ''))
for p in sorted(packages):
    if p:
        print(p)
" > /tmp/ex-1-1/critical-packages.txt
```

---

## Exercise 1.2 Solution

**Approach:** Run `trivy image` with `--severity CRITICAL,HIGH` and write to a file, then locate the openssl-related package entry.

```bash
# Write full scan output to file
trivy image --severity CRITICAL,HIGH nginx:1.14.2 2>&1 > /tmp/ex-1-2/nginx-scan.txt

# Find the highest-severity finding for libssl1.0.2 / openssl
# Use JSON format for reliable parsing
trivy image --format json nginx:1.14.2 2>&1 | python3 -c "
import json, sys
data = json.load(sys.stdin)
severity_rank = {'CRITICAL': 4, 'HIGH': 3, 'MEDIUM': 2, 'LOW': 1, 'UNKNOWN': 0}
best = None
for result in data.get('Results', []):
    for vuln in result.get('Vulnerabilities', []):
        pkg = vuln.get('PkgName', '')
        if 'ssl' in pkg.lower() or 'openssl' in pkg.lower():
            if best is None or severity_rank.get(vuln.get('Severity',''),0) > severity_rank.get(best.get('Severity',''),0):
                best = vuln
if best:
    fixed = best.get('FixedVersion', '') or 'no-fix-available'
    print(f\"Package: {best.get('PkgName')}\")
    print(f\"CVE: {best.get('VulnerabilityID')}\")
    print(f\"Severity: {best.get('Severity')}\")
    print(f\"Installed: {best.get('InstalledVersion')}\")
    print(f\"Fixed-in: {fixed}\")
" > /tmp/ex-1-2/openssl-finding.txt

cat /tmp/ex-1-2/openssl-finding.txt
```

`nginx:1.14.2` is based on Debian 9 (Stretch), which reached end of life in June 2022. The `libssl1.0.2` package present in that base image carries multiple HIGH and CRITICAL CVEs. The exact CVE IDs you see depend on the Trivy database version, but the pattern is consistent: very old Debian packages without security updates accumulate findings rapidly.

---

## Exercise 1.3 Solution

**Approach:** Run each scan command and capture the exit code immediately after using `$?`.

```bash
mkdir -p /tmp/ex-1-3

# Scan 1: --exit-code 1 --severity CRITICAL
trivy image --exit-code 1 --severity CRITICAL ubuntu:18.04 > /dev/null 2>&1
SCAN1_EC=$?

# Scan 2: --exit-code 1 --severity LOW
trivy image --exit-code 1 --severity LOW ubuntu:18.04 > /dev/null 2>&1
SCAN2_EC=$?

# Scan 3: --exit-code 0 --severity CRITICAL
trivy image --exit-code 0 --severity CRITICAL ubuntu:18.04 > /dev/null 2>&1
SCAN3_EC=$?

cat > /tmp/ex-1-3/exit-codes.txt << EOF
Scan 1 (--exit-code 1 --severity CRITICAL): ${SCAN1_EC}
Scan 2 (--exit-code 1 --severity LOW): ${SCAN2_EC}
Scan 3 (--exit-code 0 --severity CRITICAL): ${SCAN3_EC}
EOF

cat /tmp/ex-1-3/exit-codes.txt
```

Expected content of `exit-codes.txt`:
```
Scan 1 (--exit-code 1 --severity CRITICAL): 1
Scan 2 (--exit-code 1 --severity LOW): 1
Scan 3 (--exit-code 0 --severity CRITICAL): 0
```

`ubuntu:18.04` reached end of life in April 2023 and carries a large number of unfixed vulnerabilities across all severity tiers. Scans 1 and 2 both exit 1 because findings exist at those severity levels and `--exit-code 1` was requested. Scan 3 exits 0 because `--exit-code 0` overrides the finding-based exit behavior: Trivy always exits 0 when that flag is set, regardless of what it found. This is the default behavior and explains why Trivy does not break CI pipelines unless you explicitly opt in with `--exit-code 1`.

---

## Exercise 2.1 Solution

**Approach:** Build and push the original image, scan it, update the base image in a new Dockerfile, build and push the fixed image, re-scan.

```bash
# Build and push original
nerdctl build -t localhost:5001/ex-2-1-app:original -f /tmp/ex-2-1/Dockerfile /tmp/ex-2-1/
nerdctl push --insecure-registry localhost:5001/ex-2-1-app:original

# Scan original and note findings
trivy image --insecure --severity CRITICAL,HIGH localhost:5001/ex-2-1-app:original

# Create the fixed Dockerfile
cat > /tmp/ex-2-1/Dockerfile.fixed << 'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
CMD ["python", "-c", "print('running')"]
EOF

# Build and push fixed
nerdctl build -t localhost:5001/ex-2-1-app:fixed -f /tmp/ex-2-1/Dockerfile.fixed /tmp/ex-2-1/
nerdctl push --insecure-registry localhost:5001/ex-2-1-app:fixed

# Scan fixed and compare
trivy image --insecure --severity CRITICAL,HIGH localhost:5001/ex-2-1-app:fixed

# Run fixed to verify it still works
nerdctl run --rm --insecure-registry localhost:5001/ex-2-1-app:fixed
```

The remediation is a single change: `FROM python:3.9-slim` becomes `FROM python:3.12-slim`. Python 3.9-slim uses a Debian Bullseye base (Debian 11), while Python 3.12-slim uses a Debian Bookworm base (Debian 12). Bookworm receives active security maintenance and has up-to-date package versions for most of the system libraries where CVEs accumulate. The CVE count typically drops significantly after this single base image change because the underlying OS packages have been patched.

This is the most important pattern this exercise teaches: you do not patch individual CVEs by installing specific package versions inside your Dockerfile. You move to a base image where those packages are already at patched versions. The Trivy re-scan is how you verify the improvement quantitatively.

---

## Exercise 2.2 Solution

**Approach:** Use `trivy image --format cyclonedx` with `--output` to write the SBOM, then parse with Python to confirm the required fields.

```bash
# Generate CycloneDX SBOM
trivy image --format cyclonedx --output /tmp/ex-2-2/sbom-cyclonedx.json nginx:1.25.3

# Verify it is valid JSON and check the bomFormat field
python3 -c "
import json
with open('/tmp/ex-2-2/sbom-cyclonedx.json') as f:
    data = json.load(f)
print('bomFormat:', data['bomFormat'])
print('specVersion:', data['specVersion'])
count = len(data.get('components', []))
print('Component count:', count)
" 

# Write the component count to the required file
python3 -c "
import json
with open('/tmp/ex-2-2/sbom-cyclonedx.json') as f:
    data = json.load(f)
print(len(data.get('components', [])))
" > /tmp/ex-2-2/component-count.txt

cat /tmp/ex-2-2/component-count.txt
```

A CycloneDX SBOM generated for `nginx:1.25.3` will contain a `bomFormat` of `CycloneDX` and a `specVersion` of `1.5` or similar. The `components` array will typically contain 100 to 150 entries for a full nginx image, each representing an installed OS package. Each component entry includes a `purl` (Package URL), which is a standardized way to identify the exact package in a format like `pkg:deb/debian/libssl3@3.0.13-1~deb12u1`.

---

## Exercise 2.3 Solution

**Approach:** Build the custom alpine image with curl pinned, push it, generate the SPDX-JSON SBOM, and verify curl appears in the packages array.

```bash
# Build and push the custom image
nerdctl build -t localhost:5001/ex-2-3-alpine:v1 -f /tmp/ex-2-3/Dockerfile /tmp/ex-2-3/
nerdctl push --insecure-registry localhost:5001/ex-2-3-alpine:v1

# Generate SPDX-JSON SBOM
trivy image --insecure --format spdx-json --output /tmp/ex-2-3/sbom-spdx.json localhost:5001/ex-2-3-alpine:v1

# Verify the SBOM
python3 -c "
import json
with open('/tmp/ex-2-3/sbom-spdx.json') as f:
    data = json.load(f)
print('SPDX version:', data['spdxVersion'])
names = [p['name'] for p in data.get('packages', [])]
print('curl found:', 'curl' in names)
print('Total packages:', len(names))
"
```

The `--insecure` flag is required when scanning images from `localhost:5001` because that registry does not use TLS. Without it, Trivy rejects the connection. The SPDX-JSON output uses a different schema from CycloneDX: the top-level `packages` array contains one entry for the image itself and one entry for each installed component. The `name` field in each package entry matches the package name as installed by the system package manager (apk in this case). Because the Dockerfile explicitly installs `curl=8.5.0-r0`, that package will appear in the SBOM with that exact version.

---

## Exercise 3.1 Solution

### Diagnosis

The first step when debugging a Dockerfile for security issues is to run `trivy config` against the file and also read the Dockerfile manually, since `trivy config` catches some patterns but not all:

```bash
trivy config /tmp/ex-3-1/Dockerfile
```

Look at the ENV instructions in the Dockerfile itself:

```bash
cat /tmp/ex-3-1/Dockerfile
```

The output shows:
```dockerfile
ENV DB_PASSWORD=s3cur3P@ssw0rd!
ENV API_TOKEN=tok_live_abc123def456ghi789
```

These are plaintext credentials baked into the image. You can also verify they appear in the image history after building:

```bash
nerdctl build -t localhost:5001/ex-3-1-app:broken -f /tmp/ex-3-1/Dockerfile /tmp/ex-3-1/ 2>/dev/null || true
nerdctl image history localhost:5001/ex-3-1-app:broken
```

The history output will show the `ENV` instructions including the credential values. Anyone with access to the image can read these values.

### What the bug is and why it happens

The Dockerfile uses `ENV` instructions to embed a database password and an API token directly in the image. This is dangerous for two reasons. First, environment variables set with `ENV` are stored permanently in the image layer metadata. Even if a later layer runs `unset DB_PASSWORD` or sets `ENV DB_PASSWORD=`, the original value is preserved in the preceding layer and is trivially extractable with `nerdctl image history` or by pulling and inspecting the image manifest. Second, any system or person with registry pull access to the image gains access to these credentials, which is almost certainly a broader audience than intended.

The correct approach for runtime secrets is to inject them at container start time through Kubernetes Secrets mounted as environment variables or files. The Dockerfile should not carry secrets at all; the application should read them from the environment at runtime without having them baked into the build artifact.

### The fix

```bash
cat > /tmp/ex-3-1/Dockerfile.fixed << 'EOF'
FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir flask==3.0.3 psycopg2-binary==2.9.9
COPY app.py .
RUN useradd --uid 1001 --no-create-home --shell /usr/sbin/nologin appuser
USER 1001
CMD ["python", "app.py"]
EOF

nerdctl build -t localhost:5001/ex-3-1-app:fixed -f /tmp/ex-3-1/Dockerfile.fixed /tmp/ex-3-1/
nerdctl push --insecure-registry localhost:5001/ex-3-1-app:fixed
```

The fixed Dockerfile removes both `ENV` lines entirely. The application reads `DB_PASSWORD` and `API_TOKEN` from its runtime environment, which is supplied by Kubernetes via a Secret. The `USER 1001` instruction is added as an improvement since the original was also running as root, though the primary bug was the embedded credentials.

---

## Exercise 3.2 Solution

### Diagnosis

Start by reading the Dockerfile carefully:

```bash
cat /tmp/ex-3-2/Dockerfile
```

The output shows:
```dockerfile
COPY .ssh/id_rsa /root/.ssh/id_rsa
```

This is copying an SSH private key into the image. Next check whether a USER instruction is present:

```bash
grep "^USER" /tmp/ex-3-2/Dockerfile
```

No output: there is no USER instruction, so the process runs as root (UID 0).

Build the image and check the history to confirm the key copy is visible:

```bash
nerdctl build -t localhost:5001/ex-3-2-app:broken -f /tmp/ex-3-2/Dockerfile /tmp/ex-3-2/ 2>/dev/null || true
nerdctl image history localhost:5001/ex-3-2-app:broken
```

The history shows the COPY instruction that brought in the SSH key.

### What the bugs are and why they happen

There are two issues. The first is the SSH key being copied into the image. Even though the key might not be needed by the running application (it might have been used for a `git clone` during development and accidentally left in the Dockerfile), it is permanently present in the image layer. Any user who pulls the image can extract the key by running `nerdctl run --rm <image> cat /root/.ssh/id_rsa`. The correct approach is to never COPY credentials into an image; use SSH agent forwarding via `--ssh` build secrets if SSH is needed during the build, and mount secrets at runtime.

The second issue is the absence of a USER instruction, which means the Node.js process runs as root inside the container. If the application is compromised, the attacker has root-level access within the container context, which increases the blast radius of any exploit.

### The fix

```bash
cat > /tmp/ex-3-2/Dockerfile.fixed << 'EOF'
FROM node:18-slim
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY index.js .
RUN groupadd --gid 1001 nodeuser && \
    useradd --uid 1001 --gid 1001 --no-create-home --shell /usr/sbin/nologin nodeuser
USER 1001
EXPOSE 3000
CMD ["node", "index.js"]
EOF

nerdctl build -t localhost:5001/ex-3-2-app:fixed -f /tmp/ex-3-2/Dockerfile.fixed /tmp/ex-3-2/
nerdctl push --insecure-registry localhost:5001/ex-3-2-app:fixed
```

The SSH key COPY line is removed entirely. The application does not need the SSH key at runtime; if it was used during development for deployment, that concern belongs in CI pipeline configuration, not the container image. The USER instruction ensures the Node.js process runs as UID 1001 rather than root.

---

## Exercise 3.3 Solution

### Diagnosis

Read the Dockerfile carefully to identify all issues:

```bash
cat /tmp/ex-3-3/Dockerfile
```

The output shows:
```dockerfile
FROM ubuntu:latest
ADD setup-data.tar.gz.fake /opt/data/
```

Check the FROM line: `ubuntu:latest` uses a floating tag that resolves to a different image on every build. Check the ADD instruction: `ADD` with a local archive unpacks the tar automatically, which is a less-understood behavior than COPY and can introduce unexpected filesystem state. While `ADD` with a local tar is not as severe as `ADD` with a remote URL, it is still a Dockerfile hygiene concern because it obscures what ends up in the image. `COPY` is always preferred for local files.

Run `trivy config` to see what Trivy flags:

```bash
trivy config /tmp/ex-3-3/Dockerfile
```

Trivy will flag the `:latest` tag and potentially the missing USER instruction.

### What the bugs are and why they happen

The primary issue is `FROM ubuntu:latest`. Using `:latest` means the image you build today may differ from the image you build next month because the upstream publisher updates what `:latest` points to. This breaks reproducibility: you cannot guarantee that the same Dockerfile produces the same image, and you cannot pin a specific security posture. For security scanning purposes, a floating tag also means a cached scan result from two weeks ago may not reflect the current state of the base image.

The secondary issue is `ADD` being used where `COPY` should be used. When the source is a local tar archive, `ADD` automatically unpacks it, which is almost always unintentional. This can result in unexpected files being present in the image without a clear record in the Dockerfile. Using `COPY` makes the operation explicit: what you copy is what appears in the image, and unpacking is a separate explicit step if needed.

The container also has no USER instruction, so it runs as root.

### The fix

```bash
cat > /tmp/ex-3-3/Dockerfile.fixed << 'EOF'
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y python3 python3-pip curl \
    && rm -rf /var/lib/apt/lists/*
COPY setup-data.tar.gz.fake /opt/data/setup-data.tar.gz
COPY app.py /app/app.py
RUN pip3 install --no-cache-dir flask==3.0.3 \
    && useradd --uid 1001 --no-create-home --shell /usr/sbin/nologin appuser
USER 1001
EXPOSE 8080
CMD ["python3", "/app/app.py"]
EOF

nerdctl build -t localhost:5001/ex-3-3-app:fixed -f /tmp/ex-3-3/Dockerfile.fixed /tmp/ex-3-3/
nerdctl push --insecure-registry localhost:5001/ex-3-3-app:fixed
```

`ubuntu:latest` is replaced with `ubuntu:22.04` (Jammy Jellyfish, current LTS). `ADD` is replaced with `COPY`, making the operation explicit. A USER instruction is added with a non-root UID.

---

## Exercise 4.1 Solution

The Dockerfile contains four distinct security issues: (1) `FROM python:latest` uses an unpinned tag, (2) `ARG DEPLOY_TOKEN` bakes a credential into the build arguments (visible in image history), (3) `ENV GITHUB_TOKEN=${DEPLOY_TOKEN}` copies that credential into a persistent environment variable, and (4) `ADD https://bootstrap.pypa.io/get-pip.py` fetches a remote file without integrity verification.

```bash
cat > /tmp/ex-4-1/Dockerfile.fixed << 'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
RUN useradd --uid 1001 --no-create-home --shell /usr/sbin/nologin appuser
USER 1001
EXPOSE 8080
CMD ["python", "app.py"]
EOF

nerdctl build -t localhost:5001/ex-4-1-app:fixed -f /tmp/ex-4-1/Dockerfile.fixed /tmp/ex-4-1/
nerdctl push --insecure-registry localhost:5001/ex-4-1-app:fixed
trivy image --insecure --severity CRITICAL --exit-code 1 localhost:5001/ex-4-1-app:fixed
echo "Scan exit code: $?"
```

The fix removes all four issues. The base image is pinned to `python:3.12-slim`. The `ARG DEPLOY_TOKEN` and `ENV GITHUB_TOKEN` lines are removed entirely; these credentials should be passed to the CI system as environment variables or secrets, not incorporated into the image. The `ADD` with a remote URL is removed; `pip` is already available in the `python:3.12-slim` image (it was not in the original image only because the Dockerfile incorrectly assumed a bare Python image), so the `get-pip.py` step is unnecessary. The `requirements.txt` is now installed directly with `pip install`. A non-root USER is added.

---

## Exercise 4.2 Solution

```bash
cat > /tmp/ex-4-2/Dockerfile << 'EOF'
FROM nginx:1.25.3
COPY nginx.conf /etc/nginx/conf.d/default.conf
RUN groupadd --gid 1001 nginxuser && \
    useradd --uid 1001 --gid 1001 --no-create-home --shell /usr/sbin/nologin nginxuser && \
    chown -R nginxuser:nginxuser /var/cache/nginx /var/run /var/log/nginx && \
    touch /run/nginx.pid && chown nginxuser:nginxuser /run/nginx.pid
USER 1001
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
EOF

nerdctl build -t localhost:5001/ex-4-2-nginx:v1 -f /tmp/ex-4-2/Dockerfile /tmp/ex-4-2/
nerdctl push --insecure-registry localhost:5001/ex-4-2-nginx:v1

kubectl create deployment nginx-hardened \
  --image=localhost:5001/ex-4-2-nginx:v1 \
  --namespace=ex-4-2

kubectl rollout status deployment/nginx-hardened -n ex-4-2
```

Running nginx as a non-root user requires granting that user write access to the directories nginx uses at runtime: the cache directory, the log directory, and the PID file location. The `chown` commands in the RUN instruction handle this. Without them, nginx will fail to start because it cannot write its PID file or cache directory as UID 1001. The nginx config listens on port 8080 rather than 80 because ports below 1024 require elevated privileges that a non-root user does not have by default.

---

## Exercise 4.3 Solution

The issues in the multi-stage Dockerfile are: (1) `FROM golang:latest` in the builder stage uses an unpinned tag, (2) `ENV GITHUB_TOKEN=ghp_build_token_example_1234567890` bakes a credential into the builder layer, (3) `FROM ubuntu:20.04` in the runtime stage uses an older Ubuntu release, and (4) the runtime stage installs `curl` and `wget`, which are not needed at runtime and increase attack surface.

```bash
cat > /tmp/ex-4-3/Dockerfile.fixed << 'EOF'
# Build stage
FROM golang:1.22-bullseye AS builder
WORKDIR /build
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o server .

# Runtime stage
FROM ubuntu:22.04
WORKDIR /app
COPY --from=builder /build/server .
COPY config.json .
RUN useradd --uid 1001 --no-create-home --shell /usr/sbin/nologin appuser
USER 1001
EXPOSE 8080
CMD ["./server"]
EOF

nerdctl build -t localhost:5001/ex-4-3-server:fixed -f /tmp/ex-4-3/Dockerfile.fixed /tmp/ex-4-3/
nerdctl push --insecure-registry localhost:5001/ex-4-3-server:fixed
trivy image --insecure --severity CRITICAL,HIGH --exit-code 1 localhost:5001/ex-4-3-server:fixed
echo "Scan exit code: $?"
```

The builder stage pins to `golang:1.22-bullseye` and removes the `ENV GITHUB_TOKEN` line. If a GitHub token is needed during the build to fetch private modules, it should be passed using Docker BuildKit secrets (`--secret id=gh_token,env=GITHUB_TOKEN`), which do not appear in the image history. The runtime stage updates from `ubuntu:20.04` to `ubuntu:22.04` and removes the `curl` and `wget` installs. The static Go binary does not need any additional runtime dependencies, so the runtime image can be extremely minimal. A USER instruction is added.

---

## Exercise 5.1 Solution

### Diagnosis

Start by scanning the deployed image:

```bash
trivy image --insecure --severity CRITICAL,HIGH localhost:5001/ex-5-1-webapp:v1
```

Note the vulnerability count. Then inspect the image history to look for sensitive data:

```bash
nerdctl image history localhost:5001/ex-5-1-webapp:v1
```

The history output shows the ENV instructions from the Dockerfile. Look for lines that include credential-like patterns:

```text
... ENV SECRET_KEY=django-insecure-abc123def456ghi789jkl012mno345
... ENV DATABASE_URL=postgresql://admin:password123@db.internal:5432/myapp
```

These values are plaintext in the image history and are accessible to anyone who can pull the image. The image also uses `python:3.9-slim` as its base, which carries CRITICAL CVEs.

Check the Deployment's current image:

```bash
kubectl get deployment webapp -n ex-5-1 -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### What the bugs are and why they happen

There are two problems. First, `python:3.9-slim` is an older base image with accumulated CVE exposure. This is remediable by updating the base image to `python:3.12-slim`. Second, both `SECRET_KEY` and `DATABASE_URL` are hardcoded in `ENV` instructions. The `SECRET_KEY` appears to be a Django secret key; the `DATABASE_URL` contains a database password. Both are baked into the image layers permanently, regardless of whether the application uses them at runtime. Anyone with registry pull access can read these values from the image history without running the container.

The correct approach for both values is to supply them at runtime via Kubernetes Secrets, not at build time in the Dockerfile.

### The fix

```bash
cat > /tmp/ex-5-1/Dockerfile.fixed << 'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY app.py .
RUN pip install --no-cache-dir flask==3.0.3 \
    && useradd --uid 1001 --no-create-home --shell /usr/sbin/nologin appuser
USER 1001
CMD ["python", "app.py"]
EOF

nerdctl build -t localhost:5001/ex-5-1-webapp:v2 -f /tmp/ex-5-1/Dockerfile.fixed /tmp/ex-5-1/
nerdctl push --insecure-registry localhost:5001/ex-5-1-webapp:v2

kubectl set image deployment/webapp webapp=localhost:5001/ex-5-1-webapp:v2 -n ex-5-1
kubectl rollout status deployment/webapp -n ex-5-1
```

The fixed Dockerfile removes both `ENV` lines and updates the base image. If the application needs `SECRET_KEY` and `DATABASE_URL` at runtime, supply them via a Kubernetes Secret:

```bash
kubectl create secret generic webapp-config \
  --from-literal=SECRET_KEY=<runtime-value> \
  --from-literal=DATABASE_URL=<runtime-value> \
  -n ex-5-1
```

Then reference the secret in the Deployment's container spec with `envFrom` or individual `env` entries referencing `secretKeyRef`. The Dockerfile itself carries no credentials.

---

## Exercise 5.2 Solution

### Diagnosis

Scan the running image:

```bash
trivy image --insecure --severity CRITICAL,HIGH localhost:5001/ex-5-2-api:v1
```

Note the total CRITICAL and HIGH count. `node:14-slim` reached end of life in April 2023 and carries significant CVE exposure.

Run `trivy config` against the Dockerfile to check for configuration issues:

```bash
trivy config /tmp/ex-5-2/Dockerfile
```

Trivy will flag the missing USER instruction (container runs as root) and potentially the outdated base image.

Check the image history:

```bash
nerdctl image history localhost:5001/ex-5-2-api:v1
```

No credential leakage here. The issues are the CVE-heavy base image and the root user.

Check the running pod to confirm it is running as root:

```bash
kubectl exec -n ex-5-2 deploy/api-service -- id
```

Expected output: `uid=0(root) gid=0(root) groups=0(root)` -- confirming the process runs as root.

### What the bugs are and why they happen

There are two issues. The base image `node:14-slim` uses Node.js 14, which was end-of-life and is no longer receiving security updates. The underlying OS packages accumulated CVEs that were never patched in that image series. Updating to a current LTS release such as `node:20-slim` moves to an active release that receives security updates. The second issue is the missing USER instruction: the application runs as root inside the container, increasing the blast radius of any compromise.

### The fix

```bash
cat > /tmp/ex-5-2/Dockerfile.fixed << 'EOF'
FROM node:20-slim
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY index.js .
RUN groupadd --gid 1001 nodeuser && \
    useradd --uid 1001 --gid 1001 --no-create-home --shell /usr/sbin/nologin nodeuser
USER 1001
EXPOSE 3000
CMD ["node", "index.js"]
EOF

nerdctl build -t localhost:5001/ex-5-2-api:v2 -f /tmp/ex-5-2/Dockerfile.fixed /tmp/ex-5-2/
nerdctl push --insecure-registry localhost:5001/ex-5-2-api:v2

kubectl set image deployment/api-service api=localhost:5001/ex-5-2-api:v2 -n ex-5-2
kubectl rollout status deployment/api-service -n ex-5-2

# Verify non-root
kubectl exec -n ex-5-2 deploy/api-service -- id
# Expected: uid=1001(nodeuser) gid=1001(nodeuser)
```

---

## Exercise 5.3 Solution

### Diagnosis

Start with a full scan of the image:

```bash
trivy image --insecure --severity CRITICAL,HIGH localhost:5001/ex-5-3-svc:v1
```

`ubuntu:18.04` (Bionic Beaver) reached end of life in April 2023 and has a very large number of unfixed vulnerabilities. The total count will be substantial.

Inspect the image history for credential exposure:

```bash
nerdctl image history localhost:5001/ex-5-3-svc:v1
```

Look for the ARG instruction with the build secret:

```text
... ARG BUILD_SECRET=super_secret_deploy_key_12345
```

Build arguments are visible in the image history even though they are not ENV instructions. This is a common misconception: developers assume ARG values are transient, but Trivy and `nerdctl image history` both reveal them.

Run `trivy config` against the Dockerfile:

```bash
trivy config /tmp/ex-5-3/Dockerfile
```

Trivy will flag the outdated base image, the missing USER instruction, and the ARG with what appears to be a secret value.

Check the container user:

```bash
kubectl exec -n ex-5-3 deploy/backend-svc -- id
# Expected: uid=0(root) ...
```

### What the bugs are and why they happen

Three issues are present. First, `ubuntu:18.04` is an end-of-life base image with extensive CVE exposure. Second, `ARG BUILD_SECRET=super_secret_deploy_key_12345` bakes a default value for the build argument into the Dockerfile, and that default appears in the image history even if `--build-arg BUILD_SECRET=` is not passed at build time. The build was actually invoked with `--build-arg BUILD_SECRET=super_secret_deploy_key_12345`, making the value doubly visible. Build arguments are intended to be used during the build process only, but when a default value is included in the Dockerfile, it is stored in the image manifest. Third, there is no USER instruction, so the Flask process runs as root.

The `flask==2.0.0` version is also old and carries library-level CVEs in its dependencies, though those are secondary to the base image and ARG issues.

### The fix

```bash
cat > /tmp/ex-5-3/Dockerfile.fixed << 'EOF'
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*
RUN pip3 install --no-cache-dir flask==3.0.3
COPY app.py /app/app.py
RUN useradd --uid 1001 --no-create-home --shell /usr/sbin/nologin appuser
USER 1001
EXPOSE 8080
CMD ["python3", "/app/app.py"]
EOF

nerdctl build -t localhost:5001/ex-5-3-svc:v2 -f /tmp/ex-5-3/Dockerfile.fixed /tmp/ex-5-3/
nerdctl push --insecure-registry localhost:5001/ex-5-3-svc:v2

kubectl set image deployment/backend-svc backend=localhost:5001/ex-5-3-svc:v2 -n ex-5-3
kubectl rollout status deployment/backend-svc -n ex-5-3

# Verify user
kubectl exec -n ex-5-3 deploy/backend-svc -- id
# Expected: uid=1001(appuser) ...

# Verify scan improvement
trivy image --insecure --severity CRITICAL,HIGH --exit-code 1 localhost:5001/ex-5-3-svc:v2
echo "Scan exit code: $?"
```

The `ARG BUILD_SECRET` line is removed entirely. If a deploy key is genuinely needed during the build (for example, to fetch private dependencies), use Docker BuildKit's `--secret` mechanism: `RUN --mount=type=secret,id=deploy_key cat /run/secrets/deploy_key`. This makes the secret available during the RUN step but does not persist it in the image layers. The base image is updated to `ubuntu:22.04`, `flask` is updated to `3.0.3`, `wget` is removed (not needed at runtime), and a USER instruction is added.

---

## Common Mistakes

### Assuming --exit-code 1 changes what Trivy reports

`--exit-code 1` only changes the process exit code when findings are present. It does not change what Trivy scans or reports. A common mistake in CI configuration is writing `trivy image --exit-code 1 --severity CRITICAL image:tag` and expecting that Trivy will fail the build whenever CRITICAL findings exist, then discovering that even when Trivy finds CRITICAL findings it exits 0. The issue is almost always that `--exit-code 1` was specified but a flag was accidentally written as `--exit-code=0` in some configurations, or the `$?` check is happening after a command that resets the exit code. Always echo `$?` immediately after the trivy command to confirm the exit code was captured correctly.

### Believing that deleting a file in a later layer removes it

A very common Dockerfile mistake is copying a credential file (or an SSH key, or a `.env` file) in one layer and then removing it in a subsequent layer:

```dockerfile
COPY .env /app/.env
RUN pip install -r requirements.txt
RUN rm /app/.env
```

The file is present in the layer created by `COPY` and is accessible to anyone who extracts that layer from the image, even after the `rm` removes it from the final filesystem view. The only way to prevent a credential from being present in any layer is to never copy it into the image in the first place. Multi-stage builds provide a controlled way to use credentials during the build stage without including them in the final image, as long as the credential is not placed in the build stage's ENV or ARG with a default value.

### Thinking ARG values are private because they are not ENV

Build arguments passed with `--build-arg` are visible in the image history under `nerdctl image history` and in the image manifest metadata. The distinction between ARG and ENV in Dockerfile semantics is that ARG values are not present in the running container's environment, while ENV values are. However, both are stored in the image layer metadata that Trivy and other tools can read. If a secret must be present during the build (for example, a private registry password or a private npm token), use BuildKit secrets, which are designed precisely to make values available during a RUN step without persisting them in any layer.

### Using CRITICAL-only filtering in CI gates and missing HIGH exploits

Setting `--severity CRITICAL` in a CI gate feels conservative but in practice creates a significant gap: HIGH-severity vulnerabilities include many actively exploited weaknesses that do not meet the CVSS 9.0+ threshold for CRITICAL only because of limited scope or assumed user interaction. In practice, `--severity CRITICAL,HIGH` is the minimum recommended filter for a security gate. The distinction between tiers matters most when triaging and prioritizing remediation, not when deciding whether to block a deployment.

### Forgetting --insecure when scanning from a local HTTP registry

Trivy requires TLS by default when fetching images from a registry. Scanning images pushed to `localhost:5001` without the `--insecure` flag causes Trivy to reject the connection and report an error that looks like a registry failure rather than a configuration issue. Always include `--insecure` when working with the local development registry. In production, all registries should use TLS and the flag is not needed.

---

## Verification Commands Cheat Sheet

| Task | Command | Expected outcome |
|------|---------|-----------------|
| Scan an image, all severities | `trivy image <image>` | Table output of all findings |
| Scan with severity filter | `trivy image --severity CRITICAL,HIGH <image>` | Only CRITICAL and HIGH rows |
| Security gate (exit 1 on findings) | `trivy image --exit-code 1 --severity CRITICAL <image>` | Exit 0 = clean, Exit 1 = CRITICAL found |
| Scan local registry image | `trivy image --insecure localhost:5001/img:tag` | Results for the image |
| Scan a filesystem path | `trivy fs /path/to/project` | Findings for packages and secrets |
| Scan a Dockerfile | `trivy config Dockerfile` | Misconfiguration findings |
| Generate CycloneDX SBOM | `trivy image --format cyclonedx --output sbom.json <image>` | JSON file at sbom.json |
| Generate SPDX-JSON SBOM | `trivy image --format spdx-json --output sbom.json <image>` | JSON file at sbom.json |
| Verify CycloneDX SBOM format | `python3 -c "import json; d=json.load(open('sbom.json')); print(d['bomFormat'])"` | `CycloneDX` |
| Check image history for secrets | `nerdctl image history <image>` | Look for ENV/ARG lines with values |
| Check container runs as non-root | `kubectl exec deploy/<name> -- id` | uid != 0 |
| Confirm rollout after image update | `kubectl rollout status deployment/<name> -n <ns>` | `successfully rolled out` |
| Update Deployment image | `kubectl set image deployment/<name> <container>=<image> -n <ns>` | Triggers rolling update |
| Check image in Deployment | `kubectl get deployment <name> -n <ns> -o jsonpath='{.spec.template.spec.containers[0].image}'` | Expected image:tag |
