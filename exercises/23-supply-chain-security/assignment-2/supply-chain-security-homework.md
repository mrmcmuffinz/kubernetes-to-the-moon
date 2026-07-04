# Supply Chain Security Homework: Image Signing and Admission Enforcement

Work through the tutorial file in this directory before starting these exercises. All exercises use the local registry at localhost:5001 and assume Cosign v2.4.0 is installed at `/usr/local/bin/cosign`. Each exercise creates its own namespace and its own key pair in an isolated directory under `/tmp/`. Do not reuse key pairs or image names across exercises.

---

## Level 1: Key Pair Generation, Signing, and Verification

Level 1 exercises give you rapid repetitions on the core Cosign workflow. You will generate key pairs, push images to the local registry, sign them, and verify signatures. You will also observe what failure looks like when you try to verify an unsigned image.

---

### Exercise 1.1

**Objective:** Sign an image in the local registry with a key pair and verify the signature.

**Setup:**

```bash
mkdir -p /tmp/ex-1-1
kubectl create namespace ex-1-1

nerdctl pull nginx:1.27
nerdctl tag nginx:1.27 localhost:5001/level1-webserver:v1.0
nerdctl push localhost:5001/level1-webserver:v1.0
```

**Task:** Change into `/tmp/ex-1-1`. Generate a Cosign key pair using an empty passphrase. Sign `localhost:5001/level1-webserver:v1.0` with the private key. Verify the signature with the public key.

**Verification:**

```bash
cd /tmp/ex-1-1
cosign verify --key cosign.pub localhost:5001/level1-webserver:v1.0
# Expected: output contains "Verification for localhost:5001/level1-webserver:v1.0"
echo $?
# Expected: 0
```

---

### Exercise 1.2

**Objective:** Observe that cosign verify fails on an unsigned image, then sign the image so that verification succeeds.

**Setup:**

```bash
mkdir -p /tmp/ex-1-2
kubectl create namespace ex-1-2

nerdctl pull redis:7.2
nerdctl tag redis:7.2 localhost:5001/level1-cache:v1.0
nerdctl push localhost:5001/level1-cache:v1.0

cd /tmp/ex-1-2
COSIGN_PASSWORD="" cosign generate-key-pair
```

**Task:** In `/tmp/ex-1-2`, first run cosign verify against the unsigned image and confirm it exits non-zero. Then sign `localhost:5001/level1-cache:v1.0` with the generated key pair. Run cosign verify again and confirm it now exits zero.

**Verification:**

```bash
# Before signing -- should fail:
cd /tmp/ex-1-2
cosign verify --key cosign.pub localhost:5001/level1-cache:v1.0
echo $?
# Expected: 1 (non-zero)

# After signing -- should succeed:
cosign verify --key cosign.pub localhost:5001/level1-cache:v1.0
# Expected: output contains "Verification for localhost:5001/level1-cache:v1.0"
echo $?
# Expected: 0
```

---

### Exercise 1.3

**Objective:** Sign two distinct image tags and verify that each signature is valid independently.

**Setup:**

```bash
mkdir -p /tmp/ex-1-3
kubectl create namespace ex-1-3

nerdctl pull httpd:2.4
nerdctl tag httpd:2.4 localhost:5001/level1-server:v2.0
nerdctl tag httpd:2.4 localhost:5001/level1-server:v2.1
nerdctl push localhost:5001/level1-server:v2.0
nerdctl push localhost:5001/level1-server:v2.1

cd /tmp/ex-1-3
COSIGN_PASSWORD="" cosign generate-key-pair
```

**Task:** Sign both `localhost:5001/level1-server:v2.0` and `localhost:5001/level1-server:v2.1` using the key pair in `/tmp/ex-1-3`. Verify both signatures.

**Verification:**

```bash
cd /tmp/ex-1-3
cosign verify --key cosign.pub localhost:5001/level1-server:v2.0
# Expected: output contains "Verification for localhost:5001/level1-server:v2.0"
echo $?
# Expected: 0

cosign verify --key cosign.pub localhost:5001/level1-server:v2.1
# Expected: output contains "Verification for localhost:5001/level1-server:v2.1"
echo $?
# Expected: 0
```

---

## Level 2: Attestations and Admission Policy

Level 2 exercises combine Cosign attestations with Kubernetes admission enforcement. You will attach a signed SBOM attestation to an image and write ValidatingAdmissionPolicy resources that reject pods not meeting registry or tag requirements.

---

### Exercise 2.1

**Objective:** Attach a signed CycloneDX SBOM attestation to an image and verify the attestation.

**Setup:**

```bash
mkdir -p /tmp/ex-2-1
kubectl create namespace ex-2-1

nerdctl pull alpine:3.20
nerdctl tag alpine:3.20 localhost:5001/level2-base:v1.0
nerdctl push localhost:5001/level2-base:v1.0

cd /tmp/ex-2-1
COSIGN_PASSWORD="" cosign generate-key-pair
```

**Task:** In `/tmp/ex-2-1`, create a CycloneDX SBOM JSON file named `sbom.json` that contains at minimum the `bomFormat`, `specVersion`, `version`, and one component. Sign `localhost:5001/level2-base:v1.0`, then attach the SBOM as a signed attestation using `cosign attest --type cyclonedx`. Verify the attestation using `cosign verify-attestation`.

**Verification:**

```bash
cd /tmp/ex-2-1
cosign verify-attestation \
  --key cosign.pub \
  --type cyclonedx \
  localhost:5001/level2-base:v1.0
# Expected: 0 exit code
# Expected: output contains "payloadType" and "cyclonedx"
echo $?
# Expected: 0
```

---

### Exercise 2.2

**Objective:** Create a ValidatingAdmissionPolicy and binding that reject pods using the `:latest` image tag in namespace `ex-2-2`.

**Setup:**

```bash
kubectl create namespace ex-2-2

nerdctl pull nginx:1.27
nerdctl tag nginx:1.27 localhost:5001/level2-nginx:v1.0
nerdctl push localhost:5001/level2-nginx:v1.0
```

**Task:** Create a ValidatingAdmissionPolicy named `deny-latest-ex-2-2` that rejects any pod whose containers (including init containers) use an image ending in `:latest`. The policy must check both regular containers and init containers. Create a ValidatingAdmissionPolicyBinding named `deny-latest-ex-2-2-binding` that applies the policy to namespace `ex-2-2` with validation action `Deny`. Confirm that a pod using `:latest` is rejected and that a pod using `localhost:5001/level2-nginx:v1.0` is admitted.

**Verification:**

```bash
# Rejected pod:
kubectl run test-latest \
  --image=nginx:latest \
  --namespace=ex-2-2 \
  --restart=Never \
  --dry-run=server
# Expected: error containing "Images must not use the :latest tag" (or your custom message)

# Admitted pod:
kubectl run test-versioned \
  --image=localhost:5001/level2-nginx:v1.0 \
  --namespace=ex-2-2 \
  --restart=Never \
  --dry-run=server
# Expected: pod/test-versioned created (server dry run)
```

---

### Exercise 2.3

**Objective:** Create a ValidatingAdmissionPolicy and binding that require all images to use the `localhost:5001/` registry prefix in namespace `ex-2-3`.

**Setup:**

```bash
kubectl create namespace ex-2-3

nerdctl pull alpine:3.20
nerdctl tag alpine:3.20 localhost:5001/level2-app:v1.0
nerdctl push localhost:5001/level2-app:v1.0
```

**Task:** Create a ValidatingAdmissionPolicy named `require-local-registry-ex-2-3` with a CEL expression that checks every container image starts with `localhost:5001/` (include the trailing slash to prevent prefix collisions). The check must cover both regular containers and init containers. Create a ValidatingAdmissionPolicyBinding named `require-local-registry-ex-2-3-binding` targeting namespace `ex-2-3` with validation action `Deny`. Confirm that an image from `docker.io` is rejected and that `localhost:5001/level2-app:v1.0` is admitted.

**Verification:**

```bash
# Rejected pod (docker.io image):
kubectl run test-external \
  --image=nginx:1.27 \
  --namespace=ex-2-3 \
  --restart=Never \
  --dry-run=server
# Expected: error containing "Images must be pulled from localhost:5001/" (or your custom message)

# Admitted pod:
kubectl run test-local \
  --image=localhost:5001/level2-app:v1.0 \
  --namespace=ex-2-3 \
  --restart=Never \
  --dry-run=server
# Expected: pod/test-local created (server dry run)
```

---

## Level 3: Debugging Broken Signing Workflows

Each exercise below sets up a broken Cosign workflow. The setup commands create the broken state; your task is to diagnose the failure and fix it. Headings are bare to avoid telegraphing the problem.

---

### Exercise 3.1

**Objective:** The configuration below has one or more problems. Find and fix whatever is needed so that `cosign verify` succeeds for `localhost:5001/level3-tool:v1.0`.

**Setup:**

```bash
mkdir -p /tmp/ex-3-1
kubectl create namespace ex-3-1

# Push first version of the image and sign it
nerdctl pull busybox:1.36
nerdctl tag busybox:1.36 localhost:5001/level3-tool:v1.0
nerdctl push localhost:5001/level3-tool:v1.0

cd /tmp/ex-3-1
COSIGN_PASSWORD="" cosign generate-key-pair
COSIGN_PASSWORD="" cosign sign --key cosign.key localhost:5001/level3-tool:v1.0

# A second push overwrites the tag with different image content
nerdctl pull alpine:3.20
nerdctl tag alpine:3.20 localhost:5001/level3-tool:v1.0
nerdctl push localhost:5001/level3-tool:v1.0
```

**Task:** Run cosign verify and observe the failure. Diagnose the root cause. Fix the problem so that `localhost:5001/level3-tool:v1.0` verifies successfully.

**Verification:**

```bash
cd /tmp/ex-3-1
cosign verify --key cosign.pub localhost:5001/level3-tool:v1.0
# Expected: output contains "Verification for localhost:5001/level3-tool:v1.0"
echo $?
# Expected: 0
```

---

### Exercise 3.2

**Objective:** The configuration below has one or more problems. Find and fix whatever is needed so that `cosign verify` succeeds for `localhost:5001/level3-service:v1.0`.

**Setup:**

```bash
mkdir -p /tmp/ex-3-2/key-alpha /tmp/ex-3-2/key-beta
kubectl create namespace ex-3-2

nerdctl pull httpd:2.4
nerdctl tag httpd:2.4 localhost:5001/level3-service:v1.0
nerdctl push localhost:5001/level3-service:v1.0

# Generate two separate key pairs
cd /tmp/ex-3-2/key-alpha
COSIGN_PASSWORD="" cosign generate-key-pair

cd /tmp/ex-3-2/key-beta
COSIGN_PASSWORD="" cosign generate-key-pair

# Sign the image with key-alpha
cd /tmp/ex-3-2
COSIGN_PASSWORD="" cosign sign --key /tmp/ex-3-2/key-alpha/cosign.key localhost:5001/level3-service:v1.0

# Verification is being attempted with key-beta -- this will fail:
# cosign verify --key /tmp/ex-3-2/key-beta/cosign.pub localhost:5001/level3-service:v1.0
```

**Task:** Run the broken verification command using `key-beta/cosign.pub` and observe the failure. Diagnose the root cause. Produce a working verify command that exits zero.

**Verification:**

```bash
cosign verify --key /tmp/ex-3-2/key-alpha/cosign.pub localhost:5001/level3-service:v1.0
# Expected: output contains "Verification for localhost:5001/level3-service:v1.0"
echo $?
# Expected: 0
```

---

### Exercise 3.3

**Objective:** The configuration below has one or more problems. Find and fix whatever is needed so that `cosign verify` succeeds for `localhost:5001/level3-frontend:v1.0`.

**Setup:**

```bash
mkdir -p /tmp/ex-3-3
kubectl create namespace ex-3-3

nerdctl pull nginx:1.27
nerdctl tag nginx:1.27 localhost:5001/level3-frontend:v1.0
nerdctl push localhost:5001/level3-frontend:v1.0

cd /tmp/ex-3-3
COSIGN_PASSWORD="" cosign generate-key-pair

# Signing was attempted against the wrong tag (v1.1 was never pushed):
# COSIGN_PASSWORD="" cosign sign --key cosign.key localhost:5001/level3-frontend:v1.1
# That command failed -- level3-frontend:v1.0 is unsigned
```

**Task:** Attempt to verify `localhost:5001/level3-frontend:v1.0` and observe the failure. Diagnose why the image is unsigned despite the apparent signing attempt. Fix the problem so that verification succeeds for `localhost:5001/level3-frontend:v1.0`.

**Verification:**

```bash
cd /tmp/ex-3-3
cosign verify --key cosign.pub localhost:5001/level3-frontend:v1.0
# Expected: output contains "Verification for localhost:5001/level3-frontend:v1.0"
echo $?
# Expected: 0
```

---

## Level 4: Full Supply Chain Workflows

Level 4 exercises combine all previous skills into realistic end-to-end scenarios. Each exercise has multiple steps and requires creating both Kubernetes resources and Cosign artifacts.

---

### Exercise 4.1

**Objective:** Build a container image from a Dockerfile, push it to the local registry, sign it, attach a signed SBOM attestation, verify both the signature and the attestation, and deploy a pod to the cluster using that image.

**Setup:**

```bash
mkdir -p /tmp/ex-4-1
kubectl create namespace ex-4-1

cd /tmp/ex-4-1
COSIGN_PASSWORD="" cosign generate-key-pair

cat > Dockerfile <<'EOF'
FROM nginx:1.27
RUN echo '{"name":"level4-myapp","version":"1.0.0"}' \
    > /usr/share/nginx/html/info.json
EOF
```

**Task:** Build the Dockerfile as `localhost:5001/level4-myapp:v1.0` using nerdctl. Push the image. Sign it with the key pair in `/tmp/ex-4-1`. Create a CycloneDX SBOM JSON file in `/tmp/ex-4-1/sbom.json` that describes the image (at minimum include one component representing nginx:1.27). Attach the SBOM as a signed attestation. Verify the signature. Verify the attestation. Create a Pod named `level4-app` in namespace `ex-4-1` using the image `localhost:5001/level4-myapp:v1.0` with a single container named `app`.

**Verification:**

```bash
# Signature verification:
cd /tmp/ex-4-1
cosign verify --key cosign.pub localhost:5001/level4-myapp:v1.0
echo $?
# Expected: 0

# Attestation verification:
cosign verify-attestation \
  --key cosign.pub \
  --type cyclonedx \
  localhost:5001/level4-myapp:v1.0
echo $?
# Expected: 0

# Pod is running:
kubectl get pod level4-app -n ex-4-1 -o jsonpath='{.spec.containers[0].image}'
# Expected: localhost:5001/level4-myapp:v1.0

kubectl get pod level4-app -n ex-4-1 -o jsonpath='{.status.phase}'
# Expected: Running
```

---

### Exercise 4.2

**Objective:** Set up two complementary admission policies in namespace `ex-4-2` -- one that denies `:latest` tags and one that requires the `localhost:5001/` registry prefix -- then verify they work correctly together against multiple image scenarios.

**Setup:**

```bash
kubectl create namespace ex-4-2

nerdctl pull redis:7.2
nerdctl tag redis:7.2 localhost:5001/level4-backend:v1.0
nerdctl push localhost:5001/level4-backend:v1.0

nerdctl pull alpine:3.20
nerdctl tag alpine:3.20 localhost:5001/level4-proxy:v1.0
nerdctl push localhost:5001/level4-proxy:v1.0
```

**Task:** Create a ValidatingAdmissionPolicy named `deny-latest-ex-4-2` that rejects pods whose containers use `:latest` tags (check both regular containers and init containers). Create a ValidatingAdmissionPolicy named `require-local-registry-ex-4-2` that rejects pods whose containers use images not prefixed with `localhost:5001/`. Create bindings for both policies targeting namespace `ex-4-2` with validation action `Deny`. Verify the following:
- A pod using `nginx:latest` is rejected.
- A pod using `nginx:1.27` (explicit tag but wrong registry) is rejected by the registry policy.
- A pod using `localhost:5001/level4-backend:v1.0` is admitted.
- A pod using `localhost:5001/level4-proxy:v1.0` is admitted.

**Verification:**

```bash
# Rejected -- latest tag:
kubectl run test-latest \
  --image=nginx:latest \
  --namespace=ex-4-2 \
  --restart=Never \
  --dry-run=server
# Expected: error containing "latest" in the message

# Rejected -- wrong registry:
kubectl run test-wrong-registry \
  --image=nginx:1.27 \
  --namespace=ex-4-2 \
  --restart=Never \
  --dry-run=server
# Expected: error containing "localhost:5001" in the message

# Admitted -- correct registry and tag:
kubectl run test-backend \
  --image=localhost:5001/level4-backend:v1.0 \
  --namespace=ex-4-2 \
  --restart=Never \
  --dry-run=server
# Expected: pod/test-backend created (server dry run)

kubectl run test-proxy \
  --image=localhost:5001/level4-proxy:v1.0 \
  --namespace=ex-4-2 \
  --restart=Never \
  --dry-run=server
# Expected: pod/test-proxy created (server dry run)
```

---

### Exercise 4.3

**Objective:** Build and sign a pipeline image, enforce registry admission for namespace `ex-4-3`, deploy a pod using the signed image, and verify the full chain -- signature valid, attestation present, pod running.

**Setup:**

```bash
mkdir -p /tmp/ex-4-3
kubectl create namespace ex-4-3

cd /tmp/ex-4-3
COSIGN_PASSWORD="" cosign generate-key-pair

cat > Dockerfile <<'EOF'
FROM busybox:1.36
CMD ["sh", "-c", "echo 'pipeline-ready'; sleep 3600"]
EOF
```

**Task:** Build the Dockerfile as `localhost:5001/level4-pipeline:v1.0` using nerdctl and push it. Sign the image. Create a minimal SBOM attestation at `/tmp/ex-4-3/pipeline-sbom.json` and attach it. Create a ValidatingAdmissionPolicy named `require-local-registry-ex-4-3` that requires images to start with `localhost:5001/`, and a binding targeting namespace `ex-4-3` with action `Deny`. Create a Pod named `pipeline-runner` in namespace `ex-4-3` using image `localhost:5001/level4-pipeline:v1.0`, container named `runner`. Verify the signature, the attestation, and the running pod.

**Verification:**

```bash
# Policy rejects external image:
kubectl run test-reject \
  --image=busybox:1.36 \
  --namespace=ex-4-3 \
  --restart=Never \
  --dry-run=server
# Expected: error containing "localhost:5001"

# Signature valid:
cd /tmp/ex-4-3
cosign verify --key cosign.pub localhost:5001/level4-pipeline:v1.0
echo $?
# Expected: 0

# Attestation valid:
cosign verify-attestation \
  --key cosign.pub \
  --type cyclonedx \
  localhost:5001/level4-pipeline:v1.0
echo $?
# Expected: 0

# Pod running:
kubectl get pod pipeline-runner -n ex-4-3 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl get pod pipeline-runner -n ex-4-3 -o jsonpath='{.spec.containers[0].name}'
# Expected: runner
```

---

## Level 5: Debugging Admission Policy Problems

Each exercise below sets up a broken or misconfigured admission enforcement setup. Headings are bare to avoid telegraphing the problem. Diagnose what is wrong and fix it.

---

### Exercise 5.1

**Objective:** The configuration below has one or more problems. Find and fix whatever is needed so that the Deployment in namespace `ex-5-1` can be successfully created and the admission policy correctly rejects images not from `localhost:5001/`.

**Setup:**

```bash
kubectl create namespace ex-5-1

nerdctl pull nginx:1.27
nerdctl tag nginx:1.27 localhost:5001/level5-api:v1.0
nerdctl push localhost:5001/level5-api:v1.0

kubectl apply -f - <<'EOF'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: require-local-registry-ex-5-1
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups: [""]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["pods"]
  validations:
  - expression: >
      object.spec.containers.all(c, c.image.startsWith('localhost:5001/')) &&
      (has(object.spec.initContainers) ?
        object.spec.initContainers.all(c, c.image.startsWith('localhost:5001/')) : true)
    message: "Images must come from localhost:5001/"
EOF

kubectl apply -f - <<'EOF'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: require-local-registry-ex-5-1-binding
spec:
  policyName: require-local-registry-ex-5-1
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: ex-5-1
EOF

kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: level5-api
  namespace: ex-5-1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: level5-api
  template:
    metadata:
      labels:
        app: level5-api
    spec:
      containers:
      - name: api
        image: nginx:1.27
EOF
```

**Task:** Observe that the Deployment is created but pods are rejected by the admission policy (check pod events and the replicaset events). Diagnose the root cause. Fix the Deployment so that its pods are admitted by the policy and the Deployment reaches 1/1 ready.

**Verification:**

```bash
kubectl get deployment level5-api -n ex-5-1 -o jsonpath='{.status.readyReplicas}'
# Expected: 1

kubectl get pods -n ex-5-1 -l app=level5-api -o jsonpath='{.items[0].spec.containers[0].image}'
# Expected: localhost:5001/level5-api:v1.0

# External image still rejected:
kubectl run test-reject \
  --image=nginx:1.27 \
  --namespace=ex-5-1 \
  --restart=Never \
  --dry-run=server
# Expected: error containing "Images must come from localhost:5001/"
```

---

### Exercise 5.2

**Objective:** The configuration below has one or more problems. Find and fix whatever is needed so that pods using `:latest` tags are rejected in namespace `ex-5-2` and pods using `localhost:5001/level5-svc:v1.0` are admitted.

**Setup:**

```bash
kubectl create namespace ex-5-2

nerdctl pull alpine:3.20
nerdctl tag alpine:3.20 localhost:5001/level5-svc:v1.0
nerdctl push localhost:5001/level5-svc:v1.0

kubectl apply -f - <<'EOF'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: deny-latest-ex-5-2
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups: [""]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["pods"]
  validations:
  - expression: >
      object.spec.containers.all(c, !c.image.endsWith(':latest')) &&
      (has(object.spec.initContainers) ?
        object.spec.initContainers.all(c, !c.image.endsWith(':latest')) : true)
    message: "Images must not use the :latest tag"
EOF

kubectl apply -f - <<'EOF'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: deny-latest-ex-5-2-binding
spec:
  policyName: deny-latest-ex-5-2
  validationActions: [Warn]
  matchResources:
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: ex-5-2
EOF
```

**Task:** Try to create a pod with `:latest` in namespace `ex-5-2` and observe that it is NOT rejected (only warned). Diagnose all problems in the configuration. Fix whatever is needed so that `:latest` images are actually denied and `localhost:5001/level5-svc:v1.0` is admitted.

**Verification:**

```bash
# latest is now rejected:
kubectl run test-latest \
  --image=nginx:latest \
  --namespace=ex-5-2 \
  --restart=Never \
  --dry-run=server
# Expected: error containing "Images must not use the :latest tag"

# Explicit tag is admitted:
kubectl run test-versioned \
  --image=localhost:5001/level5-svc:v1.0 \
  --namespace=ex-5-2 \
  --restart=Never \
  --dry-run=server
# Expected: pod/test-versioned created (server dry run)
```

---

### Exercise 5.3

**Objective:** The configuration below has one or more problems. Find and fix whatever is needed so that the admission policy correctly rejects images not from `localhost:5001/` in namespace `ex-5-3`, and so that the Deployment in that namespace is admitted and reaches 1/1 ready.

**Setup:**

```bash
kubectl create namespace ex-5-3

nerdctl pull busybox:1.36
nerdctl tag busybox:1.36 localhost:5001/level5-worker:v1.0
nerdctl push localhost:5001/level5-worker:v1.0

kubectl apply -f - <<'EOF'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: require-local-registry-ex-5-3
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups: [""]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["pods"]
  validations:
  - expression: >
      object.spec.containers.all(c, c.image.contains('localhost:5001')) &&
      (has(object.spec.initContainers) ?
        object.spec.initContainers.all(c, c.image.contains('localhost:5001')) : true)
    message: "Images must come from localhost:5001/"
EOF

kubectl apply -f - <<'EOF'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: require-local-registry-ex-5-3-binding
spec:
  policyName: require-local-registry-ex-5-3
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: ex-5-3
EOF

kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: level5-worker
  namespace: ex-5-3
spec:
  replicas: 1
  selector:
    matchLabels:
      app: level5-worker
  template:
    metadata:
      labels:
        app: level5-worker
    spec:
      containers:
      - name: worker
        image: localhost:50011/level5-worker:v1.0
        command: ["sh", "-c", "sleep 3600"]
EOF
```

**Task:** Observe that the Deployment pods fail to be admitted. Diagnose all problems in this setup (there is more than one). Fix everything so that `localhost:5001/level5-worker:v1.0` images are admitted, images from other registries are rejected, and the Deployment reaches 1/1 ready.

**Verification:**

```bash
kubectl get deployment level5-worker -n ex-5-3 -o jsonpath='{.status.readyReplicas}'
# Expected: 1

kubectl get pods -n ex-5-3 -l app=level5-worker -o jsonpath='{.items[0].spec.containers[0].image}'
# Expected: localhost:5001/level5-worker:v1.0

# Verify policy still rejects docker.io images:
kubectl run test-reject \
  --image=nginx:1.27 \
  --namespace=ex-5-3 \
  --restart=Never \
  --dry-run=server
# Expected: error containing "localhost:5001"

# Verify localhost:50011 (wrong port) is also rejected:
kubectl run test-wrong-port \
  --image=localhost:50011/level5-worker:v1.0 \
  --namespace=ex-5-3 \
  --restart=Never \
  --dry-run=server
# Expected: error containing "localhost:5001"
```

---

## Cleanup

Delete all exercise namespaces and cluster-scoped admission resources created during these exercises:

```bash
# Delete namespaces
kubectl delete namespace ex-1-1 ex-1-2 ex-1-3 \
  ex-2-1 ex-2-2 ex-2-3 \
  ex-3-1 ex-3-2 ex-3-3 \
  ex-4-1 ex-4-2 ex-4-3 \
  ex-5-1 ex-5-2 ex-5-3 \
  --ignore-not-found

# Delete ValidatingAdmissionPolicies
kubectl delete validatingadmissionpolicy \
  deny-latest-ex-2-2 \
  require-local-registry-ex-2-3 \
  deny-latest-ex-4-2 \
  require-local-registry-ex-4-2 \
  require-local-registry-ex-4-3 \
  require-local-registry-ex-5-1 \
  deny-latest-ex-5-2 \
  require-local-registry-ex-5-3 \
  --ignore-not-found

# Delete ValidatingAdmissionPolicyBindings
kubectl delete validatingadmissionpolicybinding \
  deny-latest-ex-2-2-binding \
  require-local-registry-ex-2-3-binding \
  deny-latest-ex-4-2-binding \
  require-local-registry-ex-4-2-binding \
  require-local-registry-ex-4-3-binding \
  require-local-registry-ex-5-1-binding \
  deny-latest-ex-5-2-binding \
  require-local-registry-ex-5-3-binding \
  --ignore-not-found

# Remove exercise working directories
rm -rf /tmp/ex-1-1 /tmp/ex-1-2 /tmp/ex-1-3 \
  /tmp/ex-2-1 \
  /tmp/ex-3-1 /tmp/ex-3-2 /tmp/ex-3-3 \
  /tmp/ex-4-1 /tmp/ex-4-3
```

---

## Key Takeaways

After completing these exercises you have practiced the following skills that appear in CKA and CKS exam scenarios:

- Generating a Cosign key pair and using it to sign and verify OCI images in a local registry. You have seen firsthand that the signature is stored as a separate OCI artifact keyed to the image digest, and you know that pushing a new image to the same tag silently invalidates the signature.
- Attaching a signed SBOM attestation to an image and verifying it independently of the image signature. Attestations extend the supply chain model from "was this image approved" to "what does it contain."
- Writing ValidatingAdmissionPolicy resources with CEL expressions that check container image properties. You practiced both the `:latest` rejection pattern and the registry prefix allowlist pattern, and you know to guard `initContainers` access with `has()` to avoid CEL type errors.
- Diagnosing and repairing broken admission policies. The most common real-world issues -- `validationActions: [Warn]` instead of `[Deny]`, a namespace selector that does not match, a CEL expression using `contains` instead of `startsWith`, and a Deployment referencing the wrong image -- all appeared in the Level 3 and Level 5 exercises.
