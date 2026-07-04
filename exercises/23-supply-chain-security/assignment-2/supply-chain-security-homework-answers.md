# Supply Chain Security Homework Answers: Image Signing and Admission Enforcement

---

## Exercise 1.1 Solution

Generate the key pair in `/tmp/ex-1-1` with an empty passphrase, sign the image, and verify:

```bash
cd /tmp/ex-1-1
COSIGN_PASSWORD="" cosign generate-key-pair
COSIGN_PASSWORD="" cosign sign --key cosign.key localhost:5001/level1-webserver:v1.0
cosign verify --key cosign.pub localhost:5001/level1-webserver:v1.0
```

The `generate-key-pair` command creates `cosign.key` (encrypted private key) and `cosign.pub` (plain-text public key) in the current directory. The `sign` command resolves the tag to its digest and pushes the signature artifact to `localhost:5001/level1-webserver:sha256-<digest>.sig`. The `verify` command fetches that artifact and confirms the cryptographic signature matches the public key.

Expected output from verify:

```text
Verification for localhost:5001/level1-webserver:v1.0 --
The following checks were performed on each of these signatures:
  - The cosign claims were validated
  - The signatures were verified against the specified public key

[{"critical":{"identity":{"docker-reference":"localhost:5001/level1-webserver:v1.0"},...}}]
```

---

## Exercise 1.2 Solution

First observe the failure on the unsigned image, then sign and verify:

```bash
cd /tmp/ex-1-2

# Observe failure:
cosign verify --key cosign.pub localhost:5001/level1-cache:v1.0
# Exit code 1, error: "no matching signatures"

# Sign:
COSIGN_PASSWORD="" cosign sign --key cosign.key localhost:5001/level1-cache:v1.0

# Verify success:
cosign verify --key cosign.pub localhost:5001/level1-cache:v1.0
echo $?
# 0
```

The key pair was already created by the setup commands. The initial verify attempt is educational: the error message "no matching signatures" means Cosign looked for a `.sig` OCI artifact corresponding to the image's current digest and found nothing. This is the exact failure mode that admission enforcement relies on when checking whether an image has been signed.

---

## Exercise 1.3 Solution

Sign both tags separately and verify each:

```bash
cd /tmp/ex-1-3
COSIGN_PASSWORD="" cosign sign --key cosign.key localhost:5001/level1-server:v2.0
COSIGN_PASSWORD="" cosign sign --key cosign.key localhost:5001/level1-server:v2.1

cosign verify --key cosign.pub localhost:5001/level1-server:v2.0
echo $?
# 0

cosign verify --key cosign.pub localhost:5001/level1-server:v2.1
echo $?
# 0
```

Even though both tags point to the same underlying image (they were tagged from the same `httpd:2.4` pull), Cosign stores a separate `.sig` artifact for each tag reference. Signing `v2.0` does not automatically make `v2.1` verified, because each sign command resolves the tag to a digest at signing time and creates a separate signature record. In this exercise both tags resolve to the same digest (same image content), so both signatures reference the same digest, but the signature artifacts are stored independently under each tag's derived reference.

---

## Exercise 2.1 Solution

Create the SBOM file, sign the image, attach the attestation, and verify:

```bash
cd /tmp/ex-2-1

# Sign the image first:
COSIGN_PASSWORD="" cosign sign --key cosign.key localhost:5001/level2-base:v1.0

# Create the SBOM predicate:
cat > sbom.json <<'EOF'
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.4",
  "version": 1,
  "metadata": {
    "component": {
      "type": "container",
      "name": "level2-base",
      "version": "1.0.0"
    }
  },
  "components": [
    {
      "type": "library",
      "name": "alpine",
      "version": "3.20"
    }
  ]
}
EOF

# Attach attestation:
COSIGN_PASSWORD="" cosign attest \
  --key cosign.key \
  --predicate sbom.json \
  --type cyclonedx \
  localhost:5001/level2-base:v1.0

# Verify attestation:
cosign verify-attestation \
  --key cosign.pub \
  --type cyclonedx \
  localhost:5001/level2-base:v1.0
echo $?
# 0
```

Note that signing the image (`cosign sign`) and attaching the attestation (`cosign attest`) are separate operations. It is valid to attach an attestation to an unsigned image, though in practice you would typically do both. The `verify-attestation` command checks that the attestation envelope was signed by the key, not that the image itself was signed. Always run both `verify` and `verify-attestation` when you need to confirm the full chain.

---

## Exercise 2.2 Solution

```bash
kubectl apply -f - <<'EOF'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: deny-latest-ex-2-2
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
  name: deny-latest-ex-2-2-binding
spec:
  policyName: deny-latest-ex-2-2
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: ex-2-2
EOF
```

Test the policy:

```bash
kubectl run test-latest \
  --image=nginx:latest \
  --namespace=ex-2-2 \
  --restart=Never \
  --dry-run=server
# Expected: error containing "Images must not use the :latest tag"

kubectl run test-versioned \
  --image=localhost:5001/level2-nginx:v1.0 \
  --namespace=ex-2-2 \
  --restart=Never \
  --dry-run=server
# Expected: pod/test-versioned created (server dry run)
```

The `has(object.spec.initContainers)` guard is required because `initContainers` is an optional field. In CEL, accessing a list field that is absent on the object causes a type error. Without the `has()` check, any pod that has no init containers would trigger a CEL evaluation error, and with `failurePolicy: Fail`, those pods would be rejected even though they have no `:latest` init containers.

---

## Exercise 2.3 Solution

```bash
kubectl apply -f - <<'EOF'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: require-local-registry-ex-2-3
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
    message: "Images must be pulled from localhost:5001/"
EOF

kubectl apply -f - <<'EOF'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: require-local-registry-ex-2-3-binding
spec:
  policyName: require-local-registry-ex-2-3
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: ex-2-3
EOF
```

Test:

```bash
kubectl run test-external \
  --image=nginx:1.27 \
  --namespace=ex-2-3 \
  --restart=Never \
  --dry-run=server
# Expected: error containing "localhost:5001/"

kubectl run test-local \
  --image=localhost:5001/level2-app:v1.0 \
  --namespace=ex-2-3 \
  --restart=Never \
  --dry-run=server
# Expected: pod/test-local created (server dry run)
```

The trailing slash in `startsWith('localhost:5001/')` is essential. Without it, an image named `localhost:50011/attacker:v1.0` would pass the check because its name starts with the string `localhost:5001`. With the trailing slash, only images whose registry host is exactly `localhost:5001` (followed by a `/`) pass.

---

## Exercise 3.1 Solution

### Diagnosis

Run cosign verify and observe the error:

```bash
cd /tmp/ex-3-1
cosign verify --key cosign.pub localhost:5001/level3-tool:v1.0
```

The output will look like:

```text
Error: no matching signatures:
  ...
  failed to verify signature for sha256:<new-digest>
```

The digest shown in the error is different from the one signed. To confirm, inspect the current digest of the tag:

```bash
nerdctl inspect localhost:5001/level3-tool:v1.0 | grep -i digest
```

Compare this digest against the signature artifact tag in the registry. You can list registry tags for the image namespace to see what `.sig` artifacts exist. The `.sig` artifact tag encodes the digest it was created for. If the current image digest does not match any `.sig` artifact, the tag has been overwritten.

### What the Bug Is and Why It Happens

The setup pushed `busybox:1.36` as `localhost:5001/level3-tool:v1.0`, signed it (creating a `.sig` artifact for the busybox digest), and then pushed `alpine:3.20` to the same tag. The `v1.0` tag now resolves to the alpine digest, but the `.sig` artifact still references the busybox digest. Cosign looks for a signature matching the current tag's digest and finds none because the signature was created for a now-orphaned digest.

This is the most dangerous real-world supply chain failure mode. An attacker (or a careless rebuild) can overwrite a signed tag with different image content. The signature appears to exist in the registry (the `.sig` artifact is still there) but it no longer corresponds to the image the tag resolves to. Any verification that resolves the tag first and then checks for a matching signature will fail, which is the correct behavior: the verification failure is the signal that the image content has changed since signing.

### The Fix

Re-sign the current content of the tag (which is now alpine):

```bash
cd /tmp/ex-3-1
COSIGN_PASSWORD="" cosign sign --key cosign.key localhost:5001/level3-tool:v1.0
cosign verify --key cosign.pub localhost:5001/level3-tool:v1.0
echo $?
# 0
```

In a production workflow, you would investigate why the tag was overwritten before re-signing. Re-signing without investigation just authenticates whatever the current image content is, which may not be what was originally intended. The correct process is: rebuild from source, scan for vulnerabilities, then re-sign the new image.

---

## Exercise 3.2 Solution

### Diagnosis

Run the failing verification command:

```bash
cosign verify --key /tmp/ex-3-2/key-beta/cosign.pub localhost:5001/level3-service:v1.0
```

Output:

```text
Error: no matching signatures:
  ...
  verifying sig: crypto/rsa: verification error
```

The error message "verification error" at the cryptographic layer (not "no matching signatures") indicates a signature was found but it does not verify against the provided public key. This distinguishes a key mismatch from a completely unsigned image (which produces "no matching signatures" with no cryptographic error).

To confirm which key was used for signing, list the available key pairs:

```bash
ls /tmp/ex-3-2/key-alpha/
# cosign.key  cosign.pub

ls /tmp/ex-3-2/key-beta/
# cosign.key  cosign.pub
```

The setup comments make clear that signing was done with `key-alpha/cosign.key`. The verification was attempted with `key-beta/cosign.pub`.

### What the Bug Is and Why It Happens

Cosign's public-key verification requires the public key that corresponds to the specific private key used for signing. The public key from `key-alpha` and the public key from `key-beta` are mathematically unrelated; a signature created with `key-alpha/cosign.key` can only be verified with `key-alpha/cosign.pub`. Using any other public key results in a cryptographic verification failure.

This error is common in teams that maintain multiple key pairs for different environments (prod, staging, dev). The image might be correctly signed for production, but when a developer tries to verify it using their staging key, they receive a confusing "verification error" rather than a clear "wrong key" message. The diagnostic approach is always: confirm which key was used for signing, then use the matching public key for verification.

### The Fix

Use the correct public key for verification:

```bash
cosign verify --key /tmp/ex-3-2/key-alpha/cosign.pub localhost:5001/level3-service:v1.0
echo $?
# 0
```

No re-signing is needed; the image is correctly signed. Only the verification command was using the wrong key.

---

## Exercise 3.3 Solution

### Diagnosis

Attempt to verify the image:

```bash
cd /tmp/ex-3-3
cosign verify --key cosign.pub localhost:5001/level3-frontend:v1.0
```

Output:

```text
Error: no matching signatures:
  ...
```

There are no `.sig` artifacts at all for this image. Examine the setup comments: the sign command was run against `localhost:5001/level3-frontend:v1.1`, which was never pushed to the registry. When Cosign tries to sign an image that does not exist in the registry, it cannot resolve the tag to a digest and the sign command fails with a "manifest unknown" or "not found" error. The sign command in the setup was silently commented out (shown as a failed attempt), meaning `v1.0` was pushed but never signed.

To confirm the current state, check whether any `.sig` artifacts exist:

```bash
nerdctl images | grep level3-frontend
```

You should see `level3-frontend:v1.0` but no `.sig` tag, confirming the image is unsigned.

### What the Bug Is and Why It Happens

The sign command was run against `v1.1` (which does not exist) instead of `v1.0` (which was pushed). This is a tag mismatch during signing. It is a common mistake when images are versioned by automated scripts that sometimes get the version number wrong, or when an operator copies a sign command from a previous release and forgets to update the tag. The result is a pushed, unsigned image that the team believes is signed.

The correct process is to always verify the sign step immediately after running it (as part of the same pipeline step), rather than relying on a later verification step to catch a failed sign.

### The Fix

Sign the correct tag:

```bash
cd /tmp/ex-3-3
COSIGN_PASSWORD="" cosign sign --key cosign.key localhost:5001/level3-frontend:v1.0
cosign verify --key cosign.pub localhost:5001/level3-frontend:v1.0
echo $?
# 0
```

---

## Exercise 4.1 Solution

```bash
cd /tmp/ex-4-1

# Build and push:
nerdctl build -t localhost:5001/level4-myapp:v1.0 /tmp/ex-4-1
nerdctl push localhost:5001/level4-myapp:v1.0

# Sign:
COSIGN_PASSWORD="" cosign sign --key cosign.key localhost:5001/level4-myapp:v1.0

# Create SBOM:
cat > sbom.json <<'EOF'
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.4",
  "version": 1,
  "metadata": {
    "component": {
      "type": "container",
      "name": "level4-myapp",
      "version": "1.0.0"
    }
  },
  "components": [
    {
      "type": "library",
      "name": "nginx",
      "version": "1.27"
    }
  ]
}
EOF

# Attach attestation:
COSIGN_PASSWORD="" cosign attest \
  --key cosign.key \
  --predicate sbom.json \
  --type cyclonedx \
  localhost:5001/level4-myapp:v1.0

# Verify signature:
cosign verify --key cosign.pub localhost:5001/level4-myapp:v1.0

# Verify attestation:
cosign verify-attestation \
  --key cosign.pub \
  --type cyclonedx \
  localhost:5001/level4-myapp:v1.0
```

Create and deploy the pod:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: level4-app
  namespace: ex-4-1
spec:
  containers:
  - name: app
    image: localhost:5001/level4-myapp:v1.0
EOF
```

Wait for the pod to start:

```bash
kubectl wait pod level4-app -n ex-4-1 --for=condition=Ready --timeout=60s
kubectl get pod level4-app -n ex-4-1
```

---

## Exercise 4.2 Solution

Create both policies and their bindings:

```bash
kubectl apply -f - <<'EOF'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: deny-latest-ex-4-2
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
  name: deny-latest-ex-4-2-binding
spec:
  policyName: deny-latest-ex-4-2
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: ex-4-2
EOF

kubectl apply -f - <<'EOF'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: require-local-registry-ex-4-2
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
  name: require-local-registry-ex-4-2-binding
spec:
  policyName: require-local-registry-ex-4-2
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: ex-4-2
EOF
```

Both policies are active. `nginx:latest` fails the `:latest` check first (the deny-latest policy is evaluated independently and either policy can reject the request). `nginx:1.27` passes the tag check but fails the registry check. `localhost:5001/level4-backend:v1.0` and `localhost:5001/level4-proxy:v1.0` pass both checks.

---

## Exercise 4.3 Solution

```bash
cd /tmp/ex-4-3

# Build and push:
nerdctl build -t localhost:5001/level4-pipeline:v1.0 /tmp/ex-4-3
nerdctl push localhost:5001/level4-pipeline:v1.0

# Sign:
COSIGN_PASSWORD="" cosign sign --key cosign.key localhost:5001/level4-pipeline:v1.0

# Create and attach SBOM:
cat > pipeline-sbom.json <<'EOF'
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.4",
  "version": 1,
  "metadata": {
    "component": {
      "type": "container",
      "name": "level4-pipeline",
      "version": "1.0.0"
    }
  },
  "components": [
    {
      "type": "library",
      "name": "busybox",
      "version": "1.36"
    }
  ]
}
EOF

COSIGN_PASSWORD="" cosign attest \
  --key cosign.key \
  --predicate pipeline-sbom.json \
  --type cyclonedx \
  localhost:5001/level4-pipeline:v1.0
```

Create the admission policy and binding:

```bash
kubectl apply -f - <<'EOF'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: require-local-registry-ex-4-3
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
  name: require-local-registry-ex-4-3-binding
spec:
  policyName: require-local-registry-ex-4-3
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: ex-4-3
EOF
```

Deploy the pod:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: pipeline-runner
  namespace: ex-4-3
spec:
  containers:
  - name: runner
    image: localhost:5001/level4-pipeline:v1.0
    command: ["sh", "-c", "sleep 3600"]
EOF

kubectl wait pod pipeline-runner -n ex-4-3 --for=condition=Ready --timeout=60s
```

---

## Exercise 5.1 Solution

### Diagnosis

Check why the Deployment is not reaching ready state:

```bash
kubectl get deployment level5-api -n ex-5-1
# READY column shows 0/1
```

Describe the ReplicaSet to find why pods are not being created:

```bash
kubectl describe replicaset -n ex-5-1
```

In the Events section you will see something like:

```text
Warning  FailedCreate  ...  Error creating: pods "level5-api-..." is forbidden:
ValidatingAdmissionPolicy 'require-local-registry-ex-5-1' with binding
'require-local-registry-ex-5-1-binding' denied request: Images must come from localhost:5001/
```

The pod template in the Deployment uses `image: nginx:1.27`, which does not start with `localhost:5001/`. The admission policy `require-local-registry-ex-5-1` rejects every pod creation attempt.

Confirm the policy and binding are correctly configured:

```bash
kubectl get validatingadmissionpolicy require-local-registry-ex-5-1 -o yaml
kubectl get validatingadmissionpolicybinding require-local-registry-ex-5-1-binding -o yaml
```

Both look correct. The problem is in the Deployment's pod template image reference.

### What the Bug Is and Why It Happens

The Deployment specifies `image: nginx:1.27`, which references an image from the implicit Docker Hub registry (`docker.io`). The admission policy requires images to start with `localhost:5001/`. The ReplicaSet controller repeatedly tries to create pods from the Deployment's pod template, and each attempt is rejected at admission. The Deployment resource itself is admitted (the policy matches `pods`, not `deployments`), which is why `kubectl apply` succeeds but the pods never appear.

This is a common source of confusion: a Deployment can be created successfully while its pods are silently rejected. The ReplicaSet events are the right place to look; `kubectl describe deployment` also surfaces these events in its Events section.

### The Fix

Patch the Deployment to use the local registry image:

```bash
kubectl patch deployment level5-api -n ex-5-1 \
  --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"localhost:5001/level5-api:v1.0"}]'
```

Wait for the rollout:

```bash
kubectl rollout status deployment/level5-api -n ex-5-1
kubectl get deployment level5-api -n ex-5-1
# READY: 1/1
```

---

## Exercise 5.2 Solution

### Diagnosis

Attempt to create a pod with `:latest` in `ex-5-2`:

```bash
kubectl run test-latest \
  --image=nginx:latest \
  --namespace=ex-5-2 \
  --restart=Never \
  --dry-run=server
```

Instead of an error, you receive:

```text
Warning: ...: Images must not use the :latest tag
pod/test-latest created (server dry run)
```

The pod is admitted (server dry run returns success) but a warning is printed. The policy is running but not blocking. Describe the binding to find the cause:

```bash
kubectl describe validatingadmissionpolicybinding deny-latest-ex-5-2-binding
```

In the spec you will see:

```yaml
validationActions:
- Warn
```

`Warn` causes the API server to emit a warning header without rejecting the request. Only `Deny` causes rejection.

### What the Bug Is and Why It Happens

The ValidatingAdmissionPolicyBinding uses `validationActions: [Warn]` instead of `validationActions: [Deny]`. This is the single most common misconfiguration when first testing admission policies: the warning output looks like enforcement is working (you see the message), but the request is not actually blocked. Operators often start with `Warn` during testing to see which requests would be affected, then forget to switch to `Deny` before enabling the policy in production.

The CEL expression in the policy itself is correct. The namespace selector matches `ex-5-2` correctly. The only issue is the validation action.

### The Fix

Update the binding's validation action to `Deny`:

```bash
kubectl patch validatingadmissionpolicybinding deny-latest-ex-5-2-binding \
  --type=json \
  -p='[{"op":"replace","path":"/spec/validationActions","value":["Deny"]}]'
```

Confirm enforcement:

```bash
kubectl run test-latest \
  --image=nginx:latest \
  --namespace=ex-5-2 \
  --restart=Never \
  --dry-run=server
# Expected: error containing "Images must not use the :latest tag"

kubectl run test-versioned \
  --image=localhost:5001/level5-svc:v1.0 \
  --namespace=ex-5-2 \
  --restart=Never \
  --dry-run=server
# Expected: pod/test-versioned created (server dry run)
```

---

## Exercise 5.3 Solution

### Diagnosis

Check the Deployment:

```bash
kubectl get deployment level5-worker -n ex-5-3
# READY: 0/1
```

Describe the ReplicaSet:

```bash
kubectl describe replicaset -n ex-5-3
```

Events show the pod is rejected by the admission policy with the message "Images must come from localhost:5001/". Look at the pod template image:

```bash
kubectl get deployment level5-worker -n ex-5-3 -o jsonpath='{.spec.template.spec.containers[0].image}'
# localhost:50011/level5-worker:v1.0
```

The image is `localhost:50011/level5-worker:v1.0` -- port `50011` instead of `5001`. Now examine whether the policy CEL expression correctly rejects this image:

```bash
kubectl get validatingadmissionpolicy require-local-registry-ex-5-3 -o jsonpath='{.spec.validations[0].expression}'
```

The expression is:

```text
object.spec.containers.all(c, c.image.contains('localhost:5001')) && ...
```

The expression uses `contains('localhost:5001')` (not `startsWith`). The string `localhost:50011/level5-worker:v1.0` does contain the substring `localhost:5001` (the first 14 characters match). This means the current policy expression ALLOWS images from `localhost:50011` because it only checks for substring presence, not prefix anchoring. There are two problems:

1. The Deployment image uses port `50011` instead of `5001` (wrong port, wrong registry).
2. The policy CEL expression uses `contains` instead of `startsWith`, which is too permissive and would allow images from `localhost:50011` or any host whose name contains the substring `localhost:5001`.

### What the Bug Is and Why It Happens

The CEL `contains()` method checks for substring presence anywhere in the string. An image from `registry.localhost:5001.attacker.io/evil:v1.0` would satisfy `c.image.contains('localhost:5001')` because the attacker's registry hostname contains the substring. Using `startsWith('localhost:5001/')` anchors the check to the beginning of the string and requires the trailing slash, ensuring the registry hostname is exactly `localhost:5001`.

The Deployment image port typo (`50011` vs `5001`) is a separate issue: the image reference is simply wrong and points to a registry that does not exist.

Interestingly, the current broken combination means: the CEL expression is too permissive (allows `localhost:50011`), but the Deployment's image is still being rejected. Why? Because the image `localhost:50011/level5-worker:v1.0` contains `localhost:5001` as a substring (positions 0-13), so the `contains` check passes. The rejection must be coming from somewhere else, or the expression actually fails for a different reason.

Wait -- let's recheck: `localhost:50011` contains `localhost:5001` (it starts with `localhost:5001` and then has a `1`). So `'localhost:50011/level5-worker:v1.0'.contains('localhost:5001')` is `true`. This means the policy expression ALLOWS the image. So why is the Deployment failing?

The pod is being rejected by the policy. But if the CEL expression allows `localhost:50011`... check whether the ReplicaSet events show a different error:

```bash
kubectl get events -n ex-5-3 --sort-by='.lastTimestamp'
```

Actually, re-reading the policy: the message says "Images must come from localhost:5001/" but the expression would allow `localhost:50011`. This means the Deployment might actually be getting admitted but the pods are failing for an image pull reason (registry at port 50011 does not exist). In that case:

Check pod status:

```bash
kubectl get pods -n ex-5-3
kubectl describe pod -n ex-5-3 -l app=level5-worker
```

If the policy is letting the pod through but it fails to pull, the events will show `ImagePullBackOff` and the image pull error: "registry at localhost:50011 not found" or similar.

### The Fix

Fix both issues:

1. Correct the policy CEL expression to use `startsWith` with the trailing slash:

```bash
kubectl patch validatingadmissionpolicy require-local-registry-ex-5-3 \
  --type=json \
  -p='[
    {"op":"replace","path":"/spec/validations/0/expression","value":"object.spec.containers.all(c, c.image.startsWith(\"localhost:5001/\")) && (has(object.spec.initContainers) ? object.spec.initContainers.all(c, c.image.startsWith(\"localhost:5001/\")) : true)"}
  ]'
```

2. Fix the Deployment image to use the correct registry port:

```bash
kubectl patch deployment level5-worker -n ex-5-3 \
  --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"localhost:5001/level5-worker:v1.0"}]'
```

Wait for rollout:

```bash
kubectl rollout status deployment/level5-worker -n ex-5-3
kubectl get deployment level5-worker -n ex-5-3
# READY: 1/1
```

Verify the policy now correctly rejects external images:

```bash
kubectl run test-reject \
  --image=nginx:1.27 \
  --namespace=ex-5-3 \
  --restart=Never \
  --dry-run=server
# Expected: error containing "localhost:5001/"

kubectl run test-wrong-port \
  --image=localhost:50011/level5-worker:v1.0 \
  --namespace=ex-5-3 \
  --restart=Never \
  --dry-run=server
# Expected: error containing "localhost:5001/"
```

After fixing the policy expression to use `startsWith('localhost:5001/')`, the `localhost:50011` image is now rejected because `startsWith` anchors to the exact beginning and the trailing slash prevents substring matches.

---

## Common Mistakes

**Signing a tag that has not been pushed, then believing the image is signed.** Cosign cannot sign an image that is not in the registry; it resolves the tag to a digest by contacting the registry. If the image was not pushed before signing, the sign command fails. The failure output is easy to miss in a pipeline, especially if the exit code is not checked. The symptom is: no `.sig` artifact exists in the registry, and subsequent verify calls fail with "no matching signatures." Always run `cosign verify` immediately after `cosign sign` in the same pipeline step and fail the pipeline if verify exits non-zero.

**Pushing a new image to an existing signed tag without re-signing.** This is the most dangerous silent failure in the Cosign workflow. The `.sig` artifact still exists in the registry (it is not automatically deleted when the tag is overwritten), but it references the digest of the old image. Verify calls for the new tag content will fail. Pipelines that push a tag and then check for a `.sig` artifact's existence (rather than running verify) will not catch this. Always run `cosign verify` as the final validation step, after any push operation.

**Using `validationActions: [Warn]` instead of `[Deny]` in a ValidatingAdmissionPolicyBinding.** When testing a new admission policy it is common to start with `Warn` to preview which requests would be denied. The mistake is leaving `Warn` in place when you intend to enforce. Warn sends a warning header with the policy message but does NOT reject the request. The policy looks like it is working (you see the message) but pods with forbidden images still get admitted. Always switch to `Deny` (or `[Deny, Audit]` for auditability) before enabling a policy in an environment where enforcement matters.

**Using `contains()` instead of `startsWith()` for registry prefix checks in CEL.** The `contains` method checks for substring presence anywhere in the string. An image from a registry whose hostname contains your approved registry name as a substring (for example `registry.example-localhost:5001.attacker.io`) would pass a `contains('localhost:5001')` check. Use `startsWith('localhost:5001/')` with a trailing slash to anchor the check to the beginning of the string and require the registry port boundary.

**Forgetting the `has(object.spec.initContainers)` guard in CEL expressions.** When a pod has no init containers, `object.spec.initContainers` may be absent or null. Accessing an absent field in CEL causes a type error, not a false result. Without the `has()` guard, any pod without init containers triggers a CEL evaluation error, and with `failurePolicy: Fail`, those pods are rejected even though they have no policy violations. Always guard optional list fields with `has()` before accessing them in a CEL expression.

**Verifying with the wrong public key and concluding the image is unsigned.** When you verify with a public key that does not correspond to the signing key, Cosign reports "no matching signatures" or a cryptographic verification error. This can look like the image was never signed. Before concluding an image is unsigned, confirm which public key corresponds to the private key used for signing and re-run verify with the correct key. In multi-team environments, document which key pair is authoritative for each image or image namespace.

---

## Verification Commands Cheat Sheet

| Task | Command |
|------|---------|
| Generate key pair (no password) | `COSIGN_PASSWORD="" cosign generate-key-pair` |
| Sign an image | `COSIGN_PASSWORD="" cosign sign --key cosign.key localhost:5001/img:tag` |
| Verify a signature | `cosign verify --key cosign.pub localhost:5001/img:tag` |
| Attach SBOM attestation | `COSIGN_PASSWORD="" cosign attest --key cosign.key --predicate sbom.json --type cyclonedx localhost:5001/img:tag` |
| Verify attestation | `cosign verify-attestation --key cosign.pub --type cyclonedx localhost:5001/img:tag` |
| Test admission (dry run) | `kubectl run test --image=... --restart=Never --dry-run=server` |
| List ValidatingAdmissionPolicies | `kubectl get validatingadmissionpolicy` |
| List bindings | `kubectl get validatingadmissionpolicybinding` |
| Describe policy | `kubectl describe validatingadmissionpolicy <name>` |
| Describe binding | `kubectl describe validatingadmissionpolicybinding <name>` |
| Get policy CEL expression | `kubectl get validatingadmissionpolicy <name> -o jsonpath='{.spec.validations[0].expression}'` |
| Check binding actions | `kubectl get validatingadmissionpolicybinding <name> -o jsonpath='{.spec.validationActions}'` |
| View replicaset events (pod rejections) | `kubectl describe replicaset -n <ns>` |
| View all events sorted by time | `kubectl get events -n <ns> --sort-by='.lastTimestamp'` |
| Check pod image | `kubectl get pod <name> -n <ns> -o jsonpath='{.spec.containers[0].image}'` |
| Check deployment ready replicas | `kubectl get deployment <name> -n <ns> -o jsonpath='{.status.readyReplicas}'` |
| Rollout status | `kubectl rollout status deployment/<name> -n <ns>` |
| Patch deployment image | `kubectl patch deployment <name> -n <ns> --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"<image>"}]'` |
