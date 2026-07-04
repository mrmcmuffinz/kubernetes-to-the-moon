# Supply Chain Security Tutorial: Image Scanning, Dockerfile Hygiene, and SBOMs

## Introduction

Supply chain security in Kubernetes is about answering one question before a workload ever runs: can you trust the software artifact you are about to execute? Every container image you deploy is a supply chain artifact. It carries an operating system base, a set of installed packages with their own dependency trees, and the application code layered on top. Any one of those layers can introduce a known vulnerability, a leaked credential, or a configuration weakness that an attacker can exploit once the container is running. The CKA exam domains include supply chain security explicitly because the exam tests whether you can evaluate and harden what goes into the cluster, not just what runs inside it.

This tutorial teaches three complementary techniques. First, you will use Trivy to scan images for known vulnerabilities (CVEs), learning to read the scan output, filter by severity, and remediate by updating the base image. Second, you will examine Dockerfile patterns that introduce security risk and learn to identify and correct each one. Third, you will generate Software Bills of Materials (SBOMs) in the CycloneDX and SPDX formats that are becoming mandatory in regulated environments and are increasingly expected by security teams as proof of what software a workload contains. The tutorial works through all three techniques against real images with real findings, so you leave with concrete experience rather than theoretical knowledge.

## Prerequisites

This tutorial requires a single-node kind cluster created per [`docs/cluster-setup.md#single-node-kind-cluster`](../../../docs/cluster-setup.md#single-node-kind-cluster) and a local registry running at `localhost:5001` set up per the Container Images assignment (21-container-images/assignment-1). You will need `nerdctl` available for image builds. Trivy is installed during this tutorial, so no prior Trivy setup is required.

## Setup

Create the tutorial namespace before running any of the exercises in this file.

```bash
kubectl create namespace tutorial-supply-chain
```

Create a working directory for the tutorial's Dockerfile examples:

```bash
mkdir -p /tmp/tutorial-supply-chain
cd /tmp/tutorial-supply-chain
```

## Installing Trivy

Trivy is a comprehensive open-source vulnerability scanner from Aqua Security. It can scan container images, filesystems, git repositories, and Infrastructure-as-Code configurations. In this tutorial you will install it as a standalone binary so it is available everywhere without a container runtime dependency.

Download the Trivy binary directly from the GitHub releases page. The following commands install version v0.55.0 for Linux amd64, which is a stable release with full support for container image scanning, SBOM generation, and IaC configuration scanning.

```bash
cd /tmp
curl -sL https://github.com/aquasecurity/trivy/releases/download/v0.55.0/trivy_0.55.0_Linux-64bit.tar.gz -o trivy.tar.gz
tar -xzf trivy.tar.gz trivy
sudo mv trivy /usr/local/bin/trivy
trivy --version
```

The output should show `Version: 0.55.0`. If the version command prints correctly, Trivy is installed and on your PATH. Trivy downloads its vulnerability database on first use, which takes 30 to 60 seconds and requires outbound HTTPS to `ghcr.io`. Subsequent scans reuse the cached database.

## Scanning Your First Image

With Trivy installed, you can scan any public image without pulling it locally first. Trivy fetches the image manifest and layer archives directly from the registry, unpacks them into a temporary workspace, and matches installed packages against the CVE database. The basic command is:

```bash
trivy image nginx:1.14.2
```

`nginx:1.14.2` is a deliberately old release with a large number of known vulnerabilities, making it a useful benchmark for learning to read scan output. The scan will take 30 to 60 seconds on first run while the vulnerability database is downloaded and cached. On subsequent runs it completes in a few seconds.

The output is organized as a table grouped by layer or package ecosystem. Each row shows:

- **Library**: the package name (for example, `libssl1.0.2`, `libsystemd0`, `apt`)
- **Vulnerability ID**: the CVE identifier (for example, `CVE-2021-3711`)
- **Severity**: one of `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, or `UNKNOWN`
- **Installed Version**: the version currently present in the image
- **Fixed Version**: the version in which the vulnerability was patched (blank if no fix is available yet)
- **Title**: a short human-readable description of the vulnerability

An abbreviated example of what Trivy output looks like for `nginx:1.14.2`:

```text
nginx:1.14.2 (debian 9.9)

Total: 147 (UNKNOWN: 0, LOW: 31, MEDIUM: 65, HIGH: 41, CRITICAL: 10)

┌───────────────┬────────────────┬──────────┬────────────────┬──────────────────┬──────────────────────────────────────────────────────┐
│    Library    │ Vulnerability  │ Severity │    Installed   │    Fixed Version │                        Title                        │
│               │       ID       │          │    Version     │                  │                                                      │
├───────────────┼────────────────┼──────────┼────────────────┼──────────────────┼──────────────────────────────────────────────────────┤
│ libssl1.0.2   │ CVE-2019-1551  │ MEDIUM   │ 1.0.2q-2       │ 1.0.2u-1~deb9u1  │ openssl: integer overflow in RSAZ modular exponenti..│
│ libssl1.0.2   │ CVE-2021-3711  │ CRITICAL │ 1.0.2q-2       │ 1.0.2u-1~deb9u4  │ openssl: SM2 Decryption Buffer Overflow              │
│ libc-bin      │ CVE-2021-35942 │ CRITICAL │ 2.24-11+deb9u4 │                  │ glibc: Arbitrary read in wordexp()                   │
└───────────────┴────────────────┴──────────┴────────────────┴──────────────────┴──────────────────────────────────────────────────────┘
```

Reading this output correctly is a skill. The total line at the top (`Total: 147`) gives you the aggregate count broken down by severity. For most security policies, CRITICAL findings require immediate action: they represent vulnerabilities with known exploits, severe impact, or both. HIGH findings usually require remediation within a defined window. For exam purposes, focus on CRITICAL and HIGH as the tiers that block deployment or require justification.

## Filtering by Severity

Scanning against all severities for every image in a CI pipeline produces too much noise to act on. The `--severity` flag lets you specify which tiers to report:

```bash
trivy image --severity CRITICAL,HIGH nginx:1.14.2
```

This narrows the output to only CRITICAL and HIGH findings. You can pass a single tier or a comma-separated list. The severity values that Trivy accepts are `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, and `UNKNOWN`. If you pass a value that does not match one of these exactly, Trivy ignores the invalid tier and continues with whatever valid tiers remain; this is a common source of missed findings if a typo is introduced in a CI configuration.

### Trivy Flag Reference

The following table documents the key `trivy image` flags you will use most frequently. Understanding the default behavior is important for CI configuration, because the defaults are often not what you want for a security gate.

| Flag | What it does | Valid values | Default when omitted | Behavior when misconfigured |
|------|-------------|--------------|---------------------|---------------------------|
| `--severity` | Filter reported findings by severity tier | `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, `UNKNOWN` (comma-separated) | All severities reported | Typo in a tier name causes that tier to be silently skipped |
| `--exit-code` | Override exit code when findings are found | `0` or `1` | `0` (Trivy always exits 0 regardless of findings) | Not applicable; only 0 or 1 are meaningful |
| `--format` | Output format | `table`, `json`, `sarif`, `template`, `cyclonedx`, `spdx`, `spdx-json`, `github` | `table` | An unrecognized format string causes an immediate error |
| `--ignore-unfixed` | Suppress findings that have no available fix | boolean flag (no value) | Unfixed findings are shown | Not applicable; the flag is a boolean |
| `--vuln-type` | Restrict what types of vulnerabilities to scan | `os`, `library`, or `os,library` | `os,library` | Invalid value causes Trivy to error at startup |
| `--insecure` | Allow scanning from HTTP (non-TLS) registries | boolean flag | HTTPS required; HTTP is rejected | Not applicable; without the flag, scanning `localhost:5001` images will fail |
| `--output` | Write results to a file instead of stdout | any valid file path | stdout | If the path is not writable, Trivy errors at the end of the scan |

## Using --exit-code for CI Enforcement

By default, Trivy always exits with code 0 even if it finds thousands of vulnerabilities. This is intentional: in exploration mode you want the tool to report findings without failing a pipeline. To use Trivy as a security gate that blocks a build or deployment, use `--exit-code 1`:

```bash
trivy image --severity CRITICAL --exit-code 1 nginx:1.14.2
echo "Exit code: $?"
```

When CRITICAL findings exist, Trivy exits with code 1. When there are no CRITICAL findings, Trivy exits with code 0. In a CI system you wire this exit code to the build pass/fail status. In the exercises you will use this pattern to verify that a remediated image passes the severity gate.

If you set `--exit-code 1` but the image has CRITICAL findings and you see exit code 0, check whether `--severity` was also specified and whether the tier values are correctly spelled. Trivy does not emit a warning when a tier is silently skipped due to a typo.

## Remediating CVEs by Updating the Base Image

Most CVEs in a container image exist in the operating system packages installed in the base image layer. When you upgrade from an old base image to a more recent one, the package maintainer has already patched most of those vulnerabilities. This is the fastest and most effective remediation path available to you.

Create a simple Dockerfile that uses an old base image:

```dockerfile
FROM python:3.9-slim
WORKDIR /app
COPY . .
RUN pip install --no-cache-dir flask==3.0.3
CMD ["python", "app.py"]
```

Write this to `/tmp/tutorial-supply-chain/Dockerfile.v1` and scan it without building by using `trivy fs` (which we cover below), or build and scan the image:

```bash
cat > /tmp/tutorial-supply-chain/Dockerfile.v1 << 'EOF'
FROM python:3.9-slim
WORKDIR /app
RUN pip install --no-cache-dir flask==3.0.3
CMD ["python", "app.py"]
EOF

nerdctl build -t localhost:5001/tutorial-app:v1 -f /tmp/tutorial-supply-chain/Dockerfile.v1 /tmp/tutorial-supply-chain/
nerdctl push --insecure-registry localhost:5001/tutorial-app:v1
trivy image --insecure --severity CRITICAL,HIGH localhost:5001/tutorial-app:v1
```

Now update the base image to `python:3.12-slim`:

```bash
cat > /tmp/tutorial-supply-chain/Dockerfile.v2 << 'EOF'
FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir flask==3.0.3
CMD ["python", "app.py"]
EOF

nerdctl build -t localhost:5001/tutorial-app:v2 -f /tmp/tutorial-supply-chain/Dockerfile.v2 /tmp/tutorial-supply-chain/
nerdctl push --insecure-registry localhost:5001/tutorial-app:v2
trivy image --insecure --severity CRITICAL,HIGH localhost:5001/tutorial-app:v2
```

Compare the total counts between v1 and v2. In practice, moving from a 3.9-slim base to a 3.12-slim base dramatically reduces the CVE surface because `python:3.12-slim` uses a more recent Debian release with up-to-date package versions. The remediation action is not to patch individual CVEs by pinning packages; it is to move to a base image that has already incorporated those patches.

## Scanning Filesystems with trivy fs

`trivy fs` scans a local directory tree rather than a container image. It is useful during development to check a project's dependencies before the image is built. Run it against a directory containing a `requirements.txt` or `package.json`:

```bash
mkdir -p /tmp/tutorial-supply-chain/webapp
cat > /tmp/tutorial-supply-chain/webapp/requirements.txt << 'EOF'
flask==2.0.0
requests==2.25.1
EOF

trivy fs /tmp/tutorial-supply-chain/webapp
```

Trivy detects the `requirements.txt` and scans the listed packages against the CVE database. Any vulnerabilities in `flask==2.0.0` or `requests==2.25.1` are reported exactly as they would be in an image scan. The `trivy fs` subcommand also scans for secrets (API keys, passwords, private keys) in file contents using pattern matching, which makes it a lightweight pre-commit check.

## Scanning Dockerfiles with trivy config

`trivy config` scans Infrastructure-as-Code files including Dockerfiles, Kubernetes YAML manifests, Terraform configurations, and Helm charts for security misconfigurations. When pointed at a Dockerfile it checks against a set of built-in rules derived from CIS Benchmark recommendations.

```bash
cat > /tmp/tutorial-supply-chain/Dockerfile.audit << 'EOF'
FROM ubuntu:18.04
RUN apt-get update && apt-get install -y curl
COPY app /app
CMD ["/app/server"]
EOF

trivy config /tmp/tutorial-supply-chain/
```

Trivy will flag issues such as running as root (no USER instruction), using a non-pinned or outdated base image, and including packages with elevated privilege requirements. The output format mirrors the image scan output but uses rule IDs rather than CVE IDs. Each finding includes a description, severity, and a link to the relevant benchmark section.

## Dockerfile Anti-Patterns and Best Practices

The tutorial now covers the security anti-patterns that appear in Level 3 and Level 5 exercises. Understanding each pattern at this stage means you can diagnose broken Dockerfiles without hints.

### Secrets in ENV and ARG

Placing credentials directly in a Dockerfile is the most critical supply chain mistake because those values are baked into the image layers permanently. Consider:

```dockerfile
FROM python:3.12-slim
ENV AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
ENV AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
RUN pip install boto3
CMD ["python", "app.py"]
```

Even if you later add a layer that unsets the environment variable, the value remains readable in the layer history. Anyone who can pull the image can run `nerdctl image history <image>` or extract the image layers and read the metadata. The fix is to inject secrets at runtime via Kubernetes Secrets mounted as environment variables or volumes, never at build time.

The ARG instruction has the same problem. Build arguments passed with `--build-arg` are visible in the image history. If your Dockerfile contains `ARG DB_PASSWORD` and the build is invoked with `--build-arg DB_PASSWORD=secret`, that value is stored in the image manifest.

### COPY of Credential Files

Another common mistake is copying SSH keys, API token files, or TLS private keys into the image:

```dockerfile
FROM node:18-slim
COPY .ssh/id_rsa /root/.ssh/id_rsa
COPY . /app
RUN npm install
CMD ["node", "/app/index.js"]
```

Even if the file is removed in a subsequent layer, it remains extractable from the preceding layer. Multi-stage builds mitigate this if the credential is only ever present in a builder stage that is not included in the final image. The safest approach is never to COPY credential files at all; inject them at runtime.

### Running as Root

By default, containers run as root (UID 0) unless a USER instruction is present. While the container is isolated from the host by the kernel namespace boundary, running as root inside the container means that any process escape vulnerability grants the attacker root-equivalent access to whatever the container can reach. The fix is explicit:

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
RUN useradd --uid 1001 --no-create-home appuser
USER 1001
CMD ["python", "app.py"]
```

The `USER` instruction accepts either a username or a numeric UID. Using a numeric UID is preferred in container images because it does not rely on the `/etc/passwd` entry existing in the image. The default when USER is omitted is root (UID 0). If you set USER to a UID that has no corresponding `/etc/passwd` entry, the container still runs under that UID, which is fine; some tools that inspect `/etc/passwd` will show the UID numerically rather than as a name.

### ADD with Remote URLs

The ADD instruction accepts remote URLs as a source, which introduces two problems: the content is fetched at build time without integrity verification, and the content can change between builds, making the image non-reproducible. Use COPY for local files and a verified RUN curl/wget with a checksum for remote content if you must fetch at build time:

```dockerfile
# Anti-pattern
ADD https://example.com/setup.sh /setup.sh

# Preferred
RUN curl -fsSL https://example.com/setup.sh -o /setup.sh \
    && echo "expectedsha256hash  /setup.sh" | sha256sum -c \
    && chmod +x /setup.sh
```

### Unpinned Base Images

Using `:latest` or a floating tag makes image builds non-reproducible. When the upstream publisher releases a new version, your next build silently picks up a different set of packages. Pin base images to a specific version tag at minimum, and to a digest for the strongest guarantee:

```dockerfile
# Minimum: version-pinned tag
FROM python:3.12-slim

# Strongest: digest-pinned (guarantees bit-for-bit identity)
FROM python:3.12-slim@sha256:a1b2c3d4e5f6...
```

Digest pinning means `trivy image` will always scan exactly the same layers, and any future scan that finds new findings is definitely caused by new CVE database entries rather than base image drift.

## SBOM Generation

A Software Bill of Materials (SBOM) is a structured inventory of every software component in an artifact, including the component's name, version, supplier, license, and known vulnerabilities. SBOMs are required by US executive order EO 14028 for software supplied to federal agencies and are increasingly required by enterprise security policies. For Kubernetes workloads, generating an SBOM for each image you deploy means you can answer "what packages does this workload run?" immediately, without re-scanning.

Trivy generates SBOMs in both CycloneDX and SPDX-JSON formats with the `--format` flag on the `trivy image` subcommand. Both formats are open standards; CycloneDX is JSON-native and tool-friendly, while SPDX-JSON is used by many compliance toolchains.

### CycloneDX SBOM

```bash
trivy image --format cyclonedx --output /tmp/tutorial-supply-chain/sbom-cyclonedx.json nginx:1.25.3
```

Inspect the output:

```bash
python3 -c "
import json
with open('/tmp/tutorial-supply-chain/sbom-cyclonedx.json') as f:
    data = json.load(f)
print('Format:', data['bomFormat'])
print('Spec version:', data['specVersion'])
print('Component count:', len(data.get('components', [])))
"
```

The `bomFormat` field should be `CycloneDX`. The `components` array contains one entry per software component Trivy found in the image. Each component entry includes the package name, version, type (library, OS package, container), the PURL (Package URL, a standardized identifier), and a list of any CVEs affecting that version.

### SPDX-JSON SBOM

```bash
trivy image --format spdx-json --output /tmp/tutorial-supply-chain/sbom-spdx.json nginx:1.25.3
```

The SPDX-JSON format uses a different schema. The root object contains `SPDXID`, `spdxVersion`, `name`, and a `packages` array. Each package entry includes the package name, version, download location, and a list of `externalRefs` that include the PURL.

```bash
python3 -c "
import json
with open('/tmp/tutorial-supply-chain/sbom-spdx.json') as f:
    data = json.load(f)
print('SPDX version:', data['spdxVersion'])
print('Document name:', data['name'])
print('Package count:', len(data.get('packages', [])))
"
```

### Why SBOMs Matter

SBOMs are most valuable in incident response. When a new vulnerability like Log4Shell (CVE-2021-44228) is disclosed, an organization with SBOMs for all deployed images can query those documents programmatically and answer "which of our running workloads contain log4j-core?" in minutes rather than hours. Without SBOMs, the answer requires rescanning every running image, which takes time and requires all images to still be accessible. Generate SBOMs at build time and store them alongside the image in your registry.

## Building a Hardened Image

Bring together everything covered so far to build a hardened image that:
- Uses a recent, version-pinned base image
- Runs as a non-root user with a numeric UID
- Has no secrets baked in
- Uses COPY, not ADD
- Installs only what is needed

```dockerfile
FROM python:3.12-slim
LABEL org.opencontainers.image.source="https://github.com/example/tutorial-app"

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && rm -rf /root/.cache

COPY app.py .

RUN useradd --uid 1001 --no-create-home --shell /usr/sbin/nologin appuser
USER 1001

EXPOSE 8080
CMD ["python", "app.py"]
```

Write this to `/tmp/tutorial-supply-chain/Dockerfile.hardened`. Create a minimal `requirements.txt` and `app.py`, build the image, and scan it:

```bash
cat > /tmp/tutorial-supply-chain/requirements.txt << 'EOF'
flask==3.0.3
EOF

cat > /tmp/tutorial-supply-chain/app.py << 'EOF'
from flask import Flask
app = Flask(__name__)

@app.route("/")
def hello():
    return "ok"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF

cat > /tmp/tutorial-supply-chain/Dockerfile.hardened << 'EOF'
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

nerdctl build -t localhost:5001/tutorial-hardened:v1 -f /tmp/tutorial-supply-chain/Dockerfile.hardened /tmp/tutorial-supply-chain/
nerdctl push --insecure-registry localhost:5001/tutorial-hardened:v1
trivy image --insecure --severity CRITICAL,HIGH --exit-code 1 localhost:5001/tutorial-hardened:v1
echo "Exit code: $?"
```

Compare the exit code here to the exit code you saw with `nginx:1.14.2`. A clean image built from a current base exits 0.

## Deploying and Scanning in Kubernetes

Once an image passes scanning, deploy it to the tutorial namespace:

```bash
kubectl create deployment tutorial-app \
  --image=localhost:5001/tutorial-hardened:v1 \
  --namespace=tutorial-supply-chain

kubectl rollout status deployment/tutorial-app -n tutorial-supply-chain
kubectl get pods -n tutorial-supply-chain
```

Verify the pod is not running as root by checking the security context:

```bash
kubectl get pod -n tutorial-supply-chain -l app=tutorial-app -o jsonpath='{.items[0].spec.containers[0].securityContext}'
```

If no security context is set at the pod or container level in the Deployment, the container's effective UID is determined by the USER instruction in the Dockerfile. You can confirm this with:

```bash
kubectl exec -n tutorial-supply-chain deploy/tutorial-app -- id
# Expected: uid=1001(appuser) gid=1001(appuser) groups=1001(appuser)
```

## Cleanup

Remove all tutorial resources:

```bash
kubectl delete namespace tutorial-supply-chain
rm -rf /tmp/tutorial-supply-chain
nerdctl rmi localhost:5001/tutorial-app:v1 localhost:5001/tutorial-app:v2 localhost:5001/tutorial-hardened:v1 2>/dev/null || true
```

## Reference Commands

### Trivy Image Scanning

| Command | Description |
|---------|-------------|
| `trivy image <image>` | Scan an image (pulls from registry if not local) |
| `trivy image --severity CRITICAL,HIGH <image>` | Show only CRITICAL and HIGH findings |
| `trivy image --exit-code 1 --severity CRITICAL <image>` | Exit 1 if any CRITICAL findings exist |
| `trivy image --insecure <image>` | Allow HTTP registry (for localhost:5001) |
| `trivy image --format json --output results.json <image>` | Write JSON results to file |
| `trivy image --ignore-unfixed <image>` | Hide findings with no available fix |

### Trivy SBOM Generation

| Command | Description |
|---------|-------------|
| `trivy image --format cyclonedx --output sbom.json <image>` | Generate CycloneDX SBOM |
| `trivy image --format spdx-json --output sbom.json <image>` | Generate SPDX-JSON SBOM |

### Trivy Filesystem and Config Scanning

| Command | Description |
|---------|-------------|
| `trivy fs /path/to/dir` | Scan filesystem for vulns and secrets |
| `trivy config /path/to/dir` | Scan IaC (Dockerfiles, K8s YAML, Terraform) for misconfigurations |
| `trivy config Dockerfile` | Scan a specific Dockerfile |

### nerdctl Image Operations

| Command | Description |
|---------|-------------|
| `nerdctl build -t localhost:5001/img:tag .` | Build image and tag for local registry |
| `nerdctl push --insecure-registry localhost:5001/img:tag` | Push to HTTP registry |
| `nerdctl image history <image>` | Show image layer history (useful for spotting secrets) |
| `nerdctl rmi <image>` | Remove local image |

### Verification

| Command | Description |
|---------|-------------|
| `trivy image --exit-code 1 --severity CRITICAL <image>; echo "Exit: $?"` | Check exit code |
| `python3 -c "import json; d=json.load(open('sbom.json')); print(d['bomFormat'])"` | Verify CycloneDX SBOM format field |
| `kubectl exec deploy/<name> -- id` | Confirm container runs as expected UID |
