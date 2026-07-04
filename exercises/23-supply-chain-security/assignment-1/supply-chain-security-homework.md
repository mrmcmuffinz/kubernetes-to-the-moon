# Supply Chain Security Homework: Image Scanning, Dockerfile Hygiene, and SBOMs

Work through the tutorial in `supply-chain-security-tutorial.md` before starting these exercises. The tutorial installs Trivy, covers every command pattern used here, and explains the Dockerfile anti-patterns that appear in Levels 3 and 5. Attempting the exercises without completing the tutorial will slow you down significantly.

Each exercise creates its own namespace. The exercises are independent of each other, so you can restart any exercise from scratch by deleting and recreating its namespace. Most exercises also create a working directory under `/tmp/` for Dockerfile and build artifacts; those are listed in the per-exercise setup.

---

## Level 1: Trivy Scanning Fundamentals

Level 1 exercises build your ability to run Trivy, read the output, and extract specific data points. Each exercise targets a single skill.

### Exercise 1.1

**Objective:** Scan a container image with Trivy and identify every package that has at least one CRITICAL severity vulnerability.

**Setup:**

```bash
kubectl create namespace ex-1-1
mkdir -p /tmp/ex-1-1
```

**Task:** Scan `python:3.9-slim` using Trivy. Collect the names of all packages (from the Library column) that have at least one CRITICAL severity finding. Write those package names, one per line, to `/tmp/ex-1-1/critical-packages.txt`.

**Verification:**

```bash
# Verify the scan produces CRITICAL findings
trivy image --severity CRITICAL --exit-code 1 python:3.9-slim
echo "Exit code: $?"
# Expected: Exit code: 1 (CRITICAL findings exist)

# Verify the output file exists and is non-empty
wc -l /tmp/ex-1-1/critical-packages.txt
# Expected: one or more lines

# Review the contents
cat /tmp/ex-1-1/critical-packages.txt
# Expected: package names, one per line, matching the Library column in Trivy output
```

---

### Exercise 1.2

**Objective:** Scan an image, identify a specific vulnerability, and record its fixed version.

**Setup:**

```bash
kubectl create namespace ex-1-2
mkdir -p /tmp/ex-1-2
```

**Task:** Scan `nginx:1.14.2` with Trivy, filtering to CRITICAL and HIGH severities only. Write the full Trivy output to `/tmp/ex-1-2/nginx-scan.txt`. Then identify the package named `openssl` (or `libssl1.0.2` on Debian-based images) and write the highest-severity finding for that package to `/tmp/ex-1-2/openssl-finding.txt` in this exact format (filling in real values from the scan output):

```
Package: <package-name>
CVE: <vulnerability-id>
Severity: <severity>
Installed: <installed-version>
Fixed-in: <fixed-version-or-"no-fix-available">
```

**Verification:**

```bash
# Verify the scan output file exists
wc -c /tmp/ex-1-2/nginx-scan.txt
# Expected: non-zero file size (scan output was written)

# Verify the finding file exists with required fields
grep -c "Package:" /tmp/ex-1-2/openssl-finding.txt
# Expected: 1

grep -c "CVE:" /tmp/ex-1-2/openssl-finding.txt
# Expected: 1

grep -c "Severity:" /tmp/ex-1-2/openssl-finding.txt
# Expected: 1

grep -c "Installed:" /tmp/ex-1-2/openssl-finding.txt
# Expected: 1

grep -c "Fixed-in:" /tmp/ex-1-2/openssl-finding.txt
# Expected: 1
```

---

### Exercise 1.3

**Objective:** Use Trivy's `--exit-code` flag as a security gate and confirm the exit code behavior for a known-vulnerable image.

**Setup:**

```bash
kubectl create namespace ex-1-3
```

**Task:** Run three separate Trivy scans against `ubuntu:18.04` and record the exit code from each:

1. Scan with `--exit-code 1` and `--severity CRITICAL`. Record the exit code.
2. Scan with `--exit-code 1` and `--severity LOW`. Record the exit code.
3. Scan with `--exit-code 0` and `--severity CRITICAL`. Record the exit code.

Write a file at `/tmp/ex-1-3/exit-codes.txt` with each result in this format:

```
Scan 1 (--exit-code 1 --severity CRITICAL): <exit-code>
Scan 2 (--exit-code 1 --severity LOW): <exit-code>
Scan 3 (--exit-code 0 --severity CRITICAL): <exit-code>
```

**Verification:**

```bash
cat /tmp/ex-1-3/exit-codes.txt
# Expected:
# Scan 1: exit code 1 (ubuntu:18.04 has CRITICAL vulnerabilities)
# Scan 2: exit code 1 (ubuntu:18.04 has LOW vulnerabilities)
# Scan 3: exit code 0 (--exit-code 0 means always exit 0)

wc -l /tmp/ex-1-3/exit-codes.txt
# Expected: 3
```

---

## Level 2: Remediation and SBOM Generation

Level 2 exercises require you to act on scan findings by updating base images, rebuilding, and confirming improvement, and to generate SBOMs in both standard formats.

### Exercise 2.1

**Objective:** Remediate CVE exposure in a Python application image by updating its base image, then verify the improvement with a re-scan.

**Setup:**

```bash
kubectl create namespace ex-2-1
mkdir -p /tmp/ex-2-1

cat > /tmp/ex-2-1/Dockerfile << 'EOF'
FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
CMD ["python", "-c", "print('running')"]
EOF

cat > /tmp/ex-2-1/requirements.txt << 'EOF'
flask==3.0.3
EOF
```

**Task:**

1. Build the image using the provided Dockerfile and push it to `localhost:5001/ex-2-1-app:original`.
2. Scan `localhost:5001/ex-2-1-app:original` for CRITICAL and HIGH findings. Record the total count.
3. Create a new Dockerfile at `/tmp/ex-2-1/Dockerfile.fixed` that is identical to the original except the base image is changed from `python:3.9-slim` to `python:3.12-slim`.
4. Build the fixed image and push it to `localhost:5001/ex-2-1-app:fixed`.
5. Scan `localhost:5001/ex-2-1-app:fixed` for CRITICAL and HIGH findings.

**Verification:**

```bash
# Verify original image is in the local registry
trivy image --insecure --severity CRITICAL,HIGH --exit-code 1 localhost:5001/ex-2-1-app:original
echo "Original exit code: $?"
# Expected: Original exit code: 1 (findings exist)

# Verify fixed image is in the local registry
trivy image --insecure --severity CRITICAL,HIGH localhost:5001/ex-2-1-app:fixed
# Expected: significantly fewer CRITICAL and HIGH findings than the original

# Run the fixed image to confirm it works
nerdctl run --rm --insecure-registry localhost:5001/ex-2-1-app:fixed
# Expected: prints "running"
```

---

### Exercise 2.2

**Objective:** Generate a CycloneDX SBOM for a container image and verify it is valid.

**Setup:**

```bash
kubectl create namespace ex-2-2
mkdir -p /tmp/ex-2-2
```

**Task:**

1. Generate a CycloneDX-format SBOM for `nginx:1.25.3` and save it to `/tmp/ex-2-2/sbom-cyclonedx.json`.
2. Verify the SBOM is valid by confirming that its `bomFormat` field equals `CycloneDX` and that the `components` array contains at least one entry.
3. Count the total number of components in the SBOM and write the count to `/tmp/ex-2-2/component-count.txt`.

**Verification:**

```bash
# Verify the SBOM file is valid JSON
python3 -m json.tool /tmp/ex-2-2/sbom-cyclonedx.json > /dev/null 2>&1
echo "JSON valid exit code: $?"
# Expected: 0 (valid JSON)

# Verify the bomFormat field
python3 -c "import json; d=json.load(open('/tmp/ex-2-2/sbom-cyclonedx.json')); print(d['bomFormat'])"
# Expected: CycloneDX

# Verify component count is non-zero
python3 -c "import json; d=json.load(open('/tmp/ex-2-2/sbom-cyclonedx.json')); print(len(d.get('components', [])))"
# Expected: a positive integer (typically 100+ for nginx)

# Verify count file exists
cat /tmp/ex-2-2/component-count.txt
# Expected: a positive integer matching the python3 output above
```

---

### Exercise 2.3

**Objective:** Build a custom image, generate an SPDX-JSON SBOM for it, and verify that a known package appears in the SBOM.

**Setup:**

```bash
kubectl create namespace ex-2-3
mkdir -p /tmp/ex-2-3

cat > /tmp/ex-2-3/Dockerfile << 'EOF'
FROM alpine:3.20
RUN apk add --no-cache curl=8.5.0-r0
EOF
```

**Task:**

1. Build the image from the provided Dockerfile and push it to `localhost:5001/ex-2-3-alpine:v1`.
2. Generate an SPDX-JSON SBOM for `localhost:5001/ex-2-3-alpine:v1` and save it to `/tmp/ex-2-3/sbom-spdx.json`.
3. Verify that the SBOM contains a package entry for `curl`.

**Verification:**

```bash
# Verify the image built and scans cleanly
nerdctl image inspect localhost:5001/ex-2-3-alpine:v1 > /dev/null 2>&1
echo "Image exists exit code: $?"
# Expected: 0

# Verify the SBOM is valid JSON with the SPDX version field
python3 -c "import json; d=json.load(open('/tmp/ex-2-3/sbom-spdx.json')); print(d['spdxVersion'])"
# Expected: SPDX-2.3 (or similar SPDX version string)

# Verify curl appears in the packages array
python3 -c "
import json
with open('/tmp/ex-2-3/sbom-spdx.json') as f:
    data = json.load(f)
names = [p['name'] for p in data.get('packages', [])]
print('curl found:', 'curl' in names)
"
# Expected: curl found: True
```

---

## Level 3: Debugging Broken Dockerfiles

Level 3 exercises give you a Dockerfile with one or more security problems. Your task is to identify and fix the issues. Each exercise heading is bare because the objective statement does not name the type or number of problems; you must find them yourself.

### Exercise 3.1

**Objective:** The Dockerfile below has one or more security problems. Find and fix all issues so that the image passes a `trivy config` scan with no HIGH or CRITICAL misconfigurations and does not embed any credentials.

**Setup:**

```bash
kubectl create namespace ex-3-1
mkdir -p /tmp/ex-3-1

cat > /tmp/ex-3-1/Dockerfile << 'EOF'
FROM python:3.12-slim
WORKDIR /app
ENV DB_PASSWORD=s3cur3P@ssw0rd!
ENV API_TOKEN=tok_live_abc123def456ghi789
RUN pip install --no-cache-dir flask==3.0.3 psycopg2-binary==2.9.9
COPY app.py .
CMD ["python", "app.py"]
EOF

cat > /tmp/ex-3-1/app.py << 'EOF'
import os
from flask import Flask
app = Flask(__name__)

@app.route("/")
def hello():
    return "ok"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF
```

**Task:** Produce a corrected Dockerfile at `/tmp/ex-3-1/Dockerfile.fixed`. The fixed Dockerfile must not embed any secret values. Build the fixed image as `localhost:5001/ex-3-1-app:fixed` and push it. The container must start without crashing when run with `nerdctl run --rm`.

**Verification:**

```bash
# Run trivy config against the fixed Dockerfile
trivy config /tmp/ex-3-1/Dockerfile.fixed
# Expected: no HIGH or CRITICAL findings related to exposed secrets

# Build and run the fixed image
nerdctl build -t localhost:5001/ex-3-1-app:fixed -f /tmp/ex-3-1/Dockerfile.fixed /tmp/ex-3-1/
# Expected: build succeeds (exit code 0)

nerdctl push --insecure-registry localhost:5001/ex-3-1-app:fixed
# Expected: push succeeds

# Verify image history shows no secret values
nerdctl image history localhost:5001/ex-3-1-app:fixed
# Expected: no ENV lines containing DB_PASSWORD or API_TOKEN values
```

---

### Exercise 3.2

**Objective:** The Dockerfile below has one or more security problems. Find and fix all issues so that the image does not include sensitive files and follows secure user practices.

**Setup:**

```bash
kubectl create namespace ex-3-2
mkdir -p /tmp/ex-3-2

# Create a fake SSH key for the exercise (not a real private key)
mkdir -p /tmp/ex-3-2/.ssh
echo "-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAA (fake key for exercise)
-----END OPENSSH PRIVATE KEY-----" > /tmp/ex-3-2/.ssh/id_rsa

cat > /tmp/ex-3-2/package.json << 'EOF'
{
  "name": "demo-app",
  "version": "1.0.0",
  "scripts": { "start": "node index.js" },
  "dependencies": { "express": "4.19.2" }
}
EOF

cat > /tmp/ex-3-2/index.js << 'EOF'
const express = require('express');
const app = express();
app.get('/', (req, res) => res.send('ok'));
app.listen(3000);
EOF

cat > /tmp/ex-3-2/Dockerfile << 'EOF'
FROM node:18-slim
WORKDIR /app
COPY .ssh/id_rsa /root/.ssh/id_rsa
COPY package.json .
RUN npm install --production
COPY index.js .
EXPOSE 3000
CMD ["node", "index.js"]
EOF
```

**Task:** Produce a corrected Dockerfile at `/tmp/ex-3-2/Dockerfile.fixed`. The fixed Dockerfile must not copy any SSH key or credential file into the image and must run the application process as a non-root user. Build the image as `localhost:5001/ex-3-2-app:fixed` and push it.

**Verification:**

```bash
# Verify the fixed Dockerfile does not reference .ssh
grep -c "\.ssh" /tmp/ex-3-2/Dockerfile.fixed
# Expected: 0

# Build the fixed image
nerdctl build -t localhost:5001/ex-3-2-app:fixed -f /tmp/ex-3-2/Dockerfile.fixed /tmp/ex-3-2/
# Expected: build succeeds (exit code 0)

nerdctl push --insecure-registry localhost:5001/ex-3-2-app:fixed

# Verify image history shows no SSH key being copied
nerdctl image history localhost:5001/ex-3-2-app:fixed
# Expected: no COPY .ssh lines in history

# Verify the container runs as non-root
nerdctl run --rm localhost:5001/ex-3-2-app:fixed id
# Expected: uid is not 0 (root)
```

---

### Exercise 3.3

**Objective:** The Dockerfile below has one or more security problems. Find and fix all issues so that the image is built from a pinned, specific version tag and uses secure alternatives to any problematic instructions.

**Setup:**

```bash
kubectl create namespace ex-3-3
mkdir -p /tmp/ex-3-3

cat > /tmp/ex-3-3/setup-data.tar.gz.fake << 'EOF'
fake archive placeholder
EOF

cat > /tmp/ex-3-3/Dockerfile << 'EOF'
FROM ubuntu:latest
RUN apt-get update && apt-get install -y python3 python3-pip curl
ADD setup-data.tar.gz.fake /opt/data/
COPY app.py /app/app.py
RUN pip3 install --no-cache-dir flask==3.0.3
EXPOSE 8080
CMD ["python3", "/app/app.py"]
EOF

cat > /tmp/ex-3-3/app.py << 'EOF'
from flask import Flask
app = Flask(__name__)

@app.route("/")
def hello():
    return "ok"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF
```

**Task:** Produce a corrected Dockerfile at `/tmp/ex-3-3/Dockerfile.fixed`. Fix all security issues in the original Dockerfile. Build the image as `localhost:5001/ex-3-3-app:fixed` and push it.

**Verification:**

```bash
# Verify base image is pinned (not :latest)
grep "FROM ubuntu:latest" /tmp/ex-3-3/Dockerfile.fixed
# Expected: no output (line not present)

grep "^FROM " /tmp/ex-3-3/Dockerfile.fixed
# Expected: a line with a specific version tag (e.g., ubuntu:22.04)

# Verify ADD is not used for the archive
grep "^ADD " /tmp/ex-3-3/Dockerfile.fixed
# Expected: no output (ADD is replaced with COPY or removed)

# Build succeeds
nerdctl build -t localhost:5001/ex-3-3-app:fixed -f /tmp/ex-3-3/Dockerfile.fixed /tmp/ex-3-3/
# Expected: exit code 0

nerdctl push --insecure-registry localhost:5001/ex-3-3-app:fixed
# Expected: push succeeds
```

---

## Level 4: Full Security Audit

Level 4 exercises require a complete security analysis of a more complex Dockerfile, producing a corrected version that passes a Trivy scan with no CRITICAL or HIGH misconfiguration findings.

### Exercise 4.1

**Objective:** Perform a complete security audit of the Dockerfile below. Identify all security issues, produce a corrected Dockerfile that addresses every issue, build the corrected image, and scan it.

**Setup:**

```bash
kubectl create namespace ex-4-1
mkdir -p /tmp/ex-4-1

cat > /tmp/ex-4-1/Dockerfile << 'EOF'
FROM python:latest
ARG DEPLOY_TOKEN=ghp_abc123secret456token789
ENV GITHUB_TOKEN=${DEPLOY_TOKEN}
WORKDIR /app
ADD https://bootstrap.pypa.io/get-pip.py /tmp/get-pip.py
RUN python3 /tmp/get-pip.py
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
EXPOSE 8080
CMD ["python", "app.py"]
EOF

cat > /tmp/ex-4-1/requirements.txt << 'EOF'
flask==3.0.3
gunicorn==21.2.0
EOF

cat > /tmp/ex-4-1/app.py << 'EOF'
from flask import Flask
app = Flask(__name__)

@app.route("/health")
def health():
    return "ok"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF
```

**Task:** Produce a corrected Dockerfile at `/tmp/ex-4-1/Dockerfile.fixed` that:
- Pins the base image to a specific version (not `:latest`)
- Removes all embedded credentials from ENV and ARG instructions
- Replaces any ADD with a remote URL with a secure alternative
- Adds a non-root USER instruction with a numeric UID
- Installs only the packages listed in `requirements.txt`

Build the corrected image as `localhost:5001/ex-4-1-app:fixed` and push it.

**Verification:**

```bash
# Verify base image is pinned
grep "FROM python:latest" /tmp/ex-4-1/Dockerfile.fixed
# Expected: no output

# Verify no credentials are in ENV or ARG
grep -E "^(ENV|ARG).*token|^(ENV|ARG).*TOKEN|^(ENV|ARG).*secret|^(ENV|ARG).*SECRET" /tmp/ex-4-1/Dockerfile.fixed
# Expected: no output

# Verify ADD with URL is gone
grep "^ADD http" /tmp/ex-4-1/Dockerfile.fixed
# Expected: no output

# Verify USER instruction is present with non-root UID
grep "^USER " /tmp/ex-4-1/Dockerfile.fixed
# Expected: a USER line with a non-zero UID

# Build and push
nerdctl build -t localhost:5001/ex-4-1-app:fixed -f /tmp/ex-4-1/Dockerfile.fixed /tmp/ex-4-1/
# Expected: exit code 0

nerdctl push --insecure-registry localhost:5001/ex-4-1-app:fixed

# Scan the fixed image
trivy image --insecure --severity CRITICAL --exit-code 1 localhost:5001/ex-4-1-app:fixed
echo "Scan exit code: $?"
# Expected: 0 (no CRITICAL findings in image scan)
```

---

### Exercise 4.2

**Objective:** Build a hardened nginx-based web server image that meets all the security requirements defined in the verification section, then deploy it to a Kubernetes namespace.

**Setup:**

```bash
kubectl create namespace ex-4-2
mkdir -p /tmp/ex-4-2

cat > /tmp/ex-4-2/nginx.conf << 'EOF'
server {
    listen 8080;
    server_name _;

    location / {
        return 200 'ok\n';
        add_header Content-Type text/plain;
    }
}
EOF
```

**Task:** Write a Dockerfile at `/tmp/ex-4-2/Dockerfile` that:
- Uses `nginx:1.25.3` as the base image (exact version tag)
- Copies the provided `nginx.conf` to `/etc/nginx/conf.d/default.conf`
- Configures nginx to run on port 8080 rather than port 80
- Adds a non-root user and runs the process as UID 1001
- Uses `COPY` (not ADD) for all file operations

Build the image as `localhost:5001/ex-4-2-nginx:v1`, push it, and create a Kubernetes Deployment in `ex-4-2` that runs this image. The Deployment should have one replica.

**Verification:**

```bash
# Verify the Deployment is running
kubectl get deployment -n ex-4-2 -o jsonpath='{.items[0].status.readyReplicas}'
# Expected: 1

# Verify the image used
kubectl get deployment -n ex-4-2 -o jsonpath='{.items[0].spec.template.spec.containers[0].image}'
# Expected: localhost:5001/ex-4-2-nginx:v1

# Verify the Dockerfile has no ADD instruction
grep "^ADD " /tmp/ex-4-2/Dockerfile
# Expected: no output

# Verify the Dockerfile has a pinned base image (not :latest)
grep "^FROM nginx:latest" /tmp/ex-4-2/Dockerfile
# Expected: no output

# Scan the image for CRITICAL findings
trivy image --insecure --severity CRITICAL --exit-code 1 localhost:5001/ex-4-2-nginx:v1
echo "Scan exit code: $?"
# Expected: 0 (no CRITICAL findings)
```

---

### Exercise 4.3

**Objective:** Audit a multi-stage Dockerfile, identify all security issues in both the builder and runtime stages, produce a corrected version, and verify the result passes a Trivy scan.

**Setup:**

```bash
kubectl create namespace ex-4-3
mkdir -p /tmp/ex-4-3

cat > /tmp/ex-4-3/Dockerfile << 'EOF'
# Build stage
FROM golang:latest AS builder
WORKDIR /build
ENV GITHUB_TOKEN=ghp_build_token_example_1234567890
COPY . .
RUN go build -o server .

# Runtime stage
FROM ubuntu:20.04
WORKDIR /app
COPY --from=builder /build/server .
COPY config.json .
RUN apt-get update && apt-get install -y curl wget
EXPOSE 8080
CMD ["./server"]
EOF

cat > /tmp/ex-4-3/main.go << 'EOF'
package main

import (
    "fmt"
    "net/http"
)

func main() {
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintln(w, "ok")
    })
    http.ListenAndServe(":8080", nil)
}
EOF

cat > /tmp/ex-4-3/config.json << 'EOF'
{"env": "production", "log_level": "info"}
EOF
```

**Task:** Write a corrected Dockerfile at `/tmp/ex-4-3/Dockerfile.fixed`. The fixed version must:
- Pin both base images to specific version tags (not `:latest`)
- Remove all secret values from ENV instructions in both stages
- Remove unnecessary packages from the runtime stage
- Add a non-root USER instruction in the runtime stage with UID 1001
- Retain the multi-stage structure (keep a builder stage and a minimal runtime stage)

Build the fixed image as `localhost:5001/ex-4-3-server:fixed` and push it.

**Verification:**

```bash
# Verify no :latest tags
grep ":latest" /tmp/ex-4-3/Dockerfile.fixed
# Expected: no output

# Verify no secrets in ENV
grep -E "TOKEN|SECRET|PASSWORD|KEY" /tmp/ex-4-3/Dockerfile.fixed
# Expected: no output (or only comments, not actual values)

# Verify USER instruction in runtime stage
grep "^USER " /tmp/ex-4-3/Dockerfile.fixed
# Expected: a USER line with a non-root UID

# Build succeeds
nerdctl build -t localhost:5001/ex-4-3-server:fixed -f /tmp/ex-4-3/Dockerfile.fixed /tmp/ex-4-3/
# Expected: exit code 0

nerdctl push --insecure-registry localhost:5001/ex-4-3-server:fixed

# Scan runtime image for CRITICAL findings
trivy image --insecure --severity CRITICAL,HIGH --exit-code 1 localhost:5001/ex-4-3-server:fixed
echo "Scan exit code: $?"
# Expected: 0 or 1 depending on base image CVE state; document actual count
```

---

## Level 5: Advanced Debugging

Level 5 exercises involve deployed Kubernetes workloads whose images have security problems. The heading is bare and the objective does not name the problem type or count. Use Trivy, image history, and Kubernetes tools to diagnose the situation before fixing it.

### Exercise 5.1

**Objective:** The Deployment below uses an image that has one or more security problems. Find all issues using Trivy and image inspection tools, then rebuild the image correctly and update the Deployment.

**Setup:**

```bash
kubectl create namespace ex-5-1
mkdir -p /tmp/ex-5-1

cat > /tmp/ex-5-1/Dockerfile << 'EOF'
FROM python:3.9-slim
WORKDIR /app
ENV SECRET_KEY=django-insecure-abc123def456ghi789jkl012mno345
ENV DATABASE_URL=postgresql://admin:password123@db.internal:5432/myapp
COPY app.py .
RUN pip install --no-cache-dir flask==3.0.3
CMD ["python", "app.py"]
EOF

cat > /tmp/ex-5-1/app.py << 'EOF'
from flask import Flask
import os
app = Flask(__name__)

@app.route("/")
def hello():
    return "ok"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF

nerdctl build -t localhost:5001/ex-5-1-webapp:v1 -f /tmp/ex-5-1/Dockerfile /tmp/ex-5-1/
nerdctl push --insecure-registry localhost:5001/ex-5-1-webapp:v1

kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
  namespace: ex-5-1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webapp
  template:
    metadata:
      labels:
        app: webapp
    spec:
      containers:
      - name: webapp
        image: localhost:5001/ex-5-1-webapp:v1
        ports:
        - containerPort: 8080
EOF

kubectl rollout status deployment/webapp -n ex-5-1
```

**Task:** Diagnose the security problems in the deployed image using `trivy image` and `nerdctl image history`. Fix all problems by producing a corrected Dockerfile at `/tmp/ex-5-1/Dockerfile.fixed`, building the image as `localhost:5001/ex-5-1-webapp:v2`, pushing it, and updating the Deployment to use the new image. The corrected image must not expose any credentials in its layer history.

**Verification:**

```bash
# Verify the Deployment uses the corrected image
kubectl get deployment webapp -n ex-5-1 -o jsonpath='{.spec.template.spec.containers[0].image}'
# Expected: localhost:5001/ex-5-1-webapp:v2

# Verify the Deployment is healthy with the new image
kubectl rollout status deployment/webapp -n ex-5-1
# Expected: deployment "webapp" successfully rolled out

# Verify no credentials in image history
nerdctl image history localhost:5001/ex-5-1-webapp:v2
# Expected: no ENV lines containing SECRET_KEY or DATABASE_URL values

# Scan the new image
trivy image --insecure --severity CRITICAL,HIGH localhost:5001/ex-5-1-webapp:v2
# Expected: fewer CRITICAL findings than the original image (base image updated)
```

---

### Exercise 5.2

**Objective:** The Deployment below runs an image with one or more configuration and security problems. Diagnose what is wrong, fix it, rebuild, and redeploy.

**Setup:**

```bash
kubectl create namespace ex-5-2
mkdir -p /tmp/ex-5-2

cat > /tmp/ex-5-2/Dockerfile << 'EOF'
FROM node:14-slim
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY . .
EXPOSE 3000
CMD ["node", "index.js"]
EOF

cat > /tmp/ex-5-2/package.json << 'EOF'
{
  "name": "api-service",
  "version": "1.0.0",
  "scripts": { "start": "node index.js" },
  "dependencies": { "express": "4.19.2" }
}
EOF

cat > /tmp/ex-5-2/index.js << 'EOF'
const express = require('express');
const app = express();
app.get('/', (req, res) => res.send('ok'));
app.listen(3000);
EOF

nerdctl build -t localhost:5001/ex-5-2-api:v1 -f /tmp/ex-5-2/Dockerfile /tmp/ex-5-2/
nerdctl push --insecure-registry localhost:5001/ex-5-2-api:v1

kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-service
  namespace: ex-5-2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api-service
  template:
    metadata:
      labels:
        app: api-service
    spec:
      containers:
      - name: api
        image: localhost:5001/ex-5-2-api:v1
        ports:
        - containerPort: 3000
EOF

kubectl rollout status deployment/api-service -n ex-5-2
```

**Task:** Scan the running image with Trivy. Diagnose all security issues using `trivy image` and `trivy config`. Fix all issues by producing a corrected Dockerfile at `/tmp/ex-5-2/Dockerfile.fixed`, building the image as `localhost:5001/ex-5-2-api:v2`, pushing it, and updating the Deployment to use the new image.

**Verification:**

```bash
# Verify Deployment uses corrected image
kubectl get deployment api-service -n ex-5-2 -o jsonpath='{.spec.template.spec.containers[0].image}'
# Expected: localhost:5001/ex-5-2-api:v2

# Verify Deployment is healthy
kubectl rollout status deployment/api-service -n ex-5-2
# Expected: deployment "api-service" successfully rolled out

# Verify the fixed Dockerfile does not use :latest or old version tags
grep "FROM node:14" /tmp/ex-5-2/Dockerfile.fixed
# Expected: no output (base image has been updated)

# Verify USER instruction is present
grep "^USER " /tmp/ex-5-2/Dockerfile.fixed
# Expected: a USER line with a non-root UID

# Scan the new image
trivy image --insecure --severity CRITICAL --exit-code 1 localhost:5001/ex-5-2-api:v2
echo "Scan exit code: $?"
# Expected: 0 (no CRITICAL findings with updated base image)
```

---

### Exercise 5.3

**Objective:** The Deployment below uses an image that has one or more problems. Use all available diagnostic tools to identify every issue, then fix and redeploy.

**Setup:**

```bash
kubectl create namespace ex-5-3
mkdir -p /tmp/ex-5-3

cat > /tmp/ex-5-3/Dockerfile << 'EOF'
FROM ubuntu:18.04
RUN apt-get update && apt-get install -y python3 python3-pip wget
ARG BUILD_SECRET=super_secret_deploy_key_12345
RUN pip3 install flask==2.0.0
COPY app.py /app/app.py
EXPOSE 8080
CMD ["python3", "/app/app.py"]
EOF

cat > /tmp/ex-5-3/app.py << 'EOF'
from flask import Flask
app = Flask(__name__)

@app.route("/")
def hello():
    return "ok"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF

nerdctl build -t localhost:5001/ex-5-3-svc:v1 \
  --build-arg BUILD_SECRET=super_secret_deploy_key_12345 \
  -f /tmp/ex-5-3/Dockerfile /tmp/ex-5-3/
nerdctl push --insecure-registry localhost:5001/ex-5-3-svc:v1

kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-svc
  namespace: ex-5-3
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend-svc
  template:
    metadata:
      labels:
        app: backend-svc
    spec:
      containers:
      - name: backend
        image: localhost:5001/ex-5-3-svc:v1
        ports:
        - containerPort: 8080
EOF

kubectl rollout status deployment/backend-svc -n ex-5-3
```

**Task:** Use `trivy image`, `nerdctl image history`, and `trivy config` to diagnose all security issues in the image and its Dockerfile. Fix everything by producing a corrected Dockerfile at `/tmp/ex-5-3/Dockerfile.fixed`, building the image as `localhost:5001/ex-5-3-svc:v2`, pushing it, and updating the Deployment.

**Verification:**

```bash
# Verify Deployment uses corrected image
kubectl get deployment backend-svc -n ex-5-3 -o jsonpath='{.spec.template.spec.containers[0].image}'
# Expected: localhost:5001/ex-5-3-svc:v2

# Verify Deployment is healthy
kubectl rollout status deployment/backend-svc -n ex-5-3
# Expected: deployment "backend-svc" successfully rolled out

# Verify no ARG with secret value
grep "BUILD_SECRET" /tmp/ex-5-3/Dockerfile.fixed
# Expected: no output

# Scan image for CRITICAL findings
trivy image --insecure --severity CRITICAL,HIGH --exit-code 1 localhost:5001/ex-5-3-svc:v2
echo "Scan exit code: $?"
# Expected: 0 (base image updated away from ubuntu:18.04)

# Verify container does not run as root
kubectl exec -n ex-5-3 deploy/backend-svc -- id
# Expected: uid is not 0
```

---

## Cleanup

After completing all exercises, remove every exercise namespace and working directory:

```bash
kubectl delete namespace ex-1-1 ex-1-2 ex-1-3 \
  ex-2-1 ex-2-2 ex-2-3 \
  ex-3-1 ex-3-2 ex-3-3 \
  ex-4-1 ex-4-2 ex-4-3 \
  ex-5-1 ex-5-2 ex-5-3

rm -rf /tmp/ex-1-1 /tmp/ex-1-2 /tmp/ex-1-3 \
  /tmp/ex-2-1 /tmp/ex-2-2 /tmp/ex-2-3 \
  /tmp/ex-3-1 /tmp/ex-3-2 /tmp/ex-3-3 \
  /tmp/ex-4-1 /tmp/ex-4-2 /tmp/ex-4-3 \
  /tmp/ex-5-1 /tmp/ex-5-2 /tmp/ex-5-3
```

Remove exercise images from the local registry:

```bash
nerdctl rmi \
  localhost:5001/ex-2-1-app:original localhost:5001/ex-2-1-app:fixed \
  localhost:5001/ex-2-3-alpine:v1 \
  localhost:5001/ex-3-1-app:fixed \
  localhost:5001/ex-3-2-app:fixed \
  localhost:5001/ex-3-3-app:fixed \
  localhost:5001/ex-4-1-app:fixed \
  localhost:5001/ex-4-2-nginx:v1 \
  localhost:5001/ex-4-3-server:fixed \
  localhost:5001/ex-5-1-webapp:v1 localhost:5001/ex-5-1-webapp:v2 \
  localhost:5001/ex-5-2-api:v1 localhost:5001/ex-5-2-api:v2 \
  localhost:5001/ex-5-3-svc:v1 localhost:5001/ex-5-3-svc:v2 \
  2>/dev/null || true
```

---

## Key Takeaways

The exercises in this assignment reinforce five concrete skills. Trivy scanning fluency: you practiced reading CVE output, extracting package names and fixed versions, filtering by severity, and interpreting exit codes as security gates. Remediation by base image upgrade: the most effective CVE remediation action is moving to a newer base image, not patching individual packages; re-scanning confirms the improvement quantitatively. Dockerfile anti-pattern recognition: you identified secrets in ENV and ARG, credential file copies, ADD with remote URLs, root user defaults, and unpinned base tags, and you understand why each is dangerous (layer persistence, cache busting, privilege escalation). SBOM generation: you produced CycloneDX and SPDX-JSON SBOMs and verified their structure, which prepares you for environments where SBOMs are required compliance artifacts. End-to-end workflow: Levels 4 and 5 required you to audit, fix, rebuild, push, and redeploy, connecting the scanning tools to the full Kubernetes delivery pipeline.
