# Supply Chain Security Tutorial: Image Signing and Admission Enforcement

## Introduction

Container images travel a long path before they run in a cluster: a developer writes a Dockerfile, a CI system builds it, a registry stores it, and eventually a scheduler pulls it onto a node. Any of those handoffs is an opportunity for tampering. Vulnerability scanning (covered in assignment 1) tells you what is inside an image, but it says nothing about whether the image you scanned is the same image that ends up running in production. Image signing closes that gap. A cryptographic signature, stored alongside the image in the registry, lets anyone with the public key verify that the image was approved by a specific party and that its bits have not changed since signing.

Cosign is the signing tool from the Sigstore project that has become the de facto standard for OCI image signing. It integrates tightly with OCI registries: signatures are stored as OCI artifacts in the same registry namespace as the images they protect, which means no additional infrastructure is needed beyond your existing registry. Key-based signing, which this tutorial covers hands-on, uses a traditional public/private key pair. Keyless signing, covered conceptually below, replaces the key pair with a short-lived certificate issued by the Fulcio certificate authority using an OIDC token from a provider like GitHub Actions, which eliminates long-lived key management at the cost of requiring an OIDC provider in your environment.

By the end of this tutorial you will have installed Cosign, generated a key pair, signed a tutorial image pushed to the local registry, verified the signature, attached a signed SBOM attestation, and created a ValidatingAdmissionPolicy that enforces registry and tag requirements at pod admission time. All of this happens in the `tutorial-supply-chain` namespace for resources that live inside the cluster; the Cosign operations happen on the host against the local registry at localhost:5001.

## Prerequisites

This tutorial requires the single-node kind cluster described in [docs/cluster-setup.md#single-node-kind-cluster](../../../docs/cluster-setup.md#single-node-kind-cluster). The local OCI registry at localhost:5001 must be running; it was configured in the 21-container-images assignment. Cosign is not installed by default; the first section of this tutorial installs it. You should have nerdctl available on the host for building and pushing images.

## Setup

Create the tutorial namespace and pull the base image you will use for the tutorial workflow.

```bash
kubectl create namespace tutorial-supply-chain
```

Pull nginx:1.27 to the host so that subsequent nerdctl tag and push commands work without waiting on a remote download.

```bash
nerdctl pull nginx:1.27
```

## Installing Cosign

Cosign is a single statically compiled binary distributed through GitHub Releases. Pinning to a specific release version is important in a lab environment because the CLI flags and environment variable names have changed across major versions. This tutorial uses v2.4.0.

```bash
curl -LO https://github.com/sigstore/cosign/releases/download/v2.4.0/cosign-linux-amd64
chmod +x cosign-linux-amd64
sudo mv cosign-linux-amd64 /usr/local/bin/cosign
```

Verify the installation:

```bash
cosign version
```

You should see output that begins with `GitVersion: v2.4.0`.

## Building and Pushing a Tutorial Image

Create a minimal Dockerfile for the tutorial image. This image adds a JSON metadata file to nginx so that you have something identifiable to sign.

```bash
mkdir -p /tmp/tutorial-scs
cd /tmp/tutorial-scs

cat > Dockerfile <<'EOF'
FROM nginx:1.27
RUN echo '{"service":"supply-chain-tutorial","version":"1.0.0"}' \
    > /usr/share/nginx/html/app-info.json
EOF
```

Build and push the image to the local registry:

```bash
nerdctl build -t localhost:5001/tutorial-scs-app:v1.0 /tmp/tutorial-scs
nerdctl push localhost:5001/tutorial-scs-app:v1.0
```

The push step is critical. Cosign signs an image by its content-addressable digest. When you run `cosign sign`, Cosign contacts the registry to resolve the tag to its current digest, creates a signature for that digest, and pushes the signature artifact back to the registry. If the image has not been pushed, Cosign has nothing to resolve and the sign command fails. The image must always be in the registry before you attempt to sign it.

## Generating a Key Pair

Change into your tutorial working directory and generate the key pair there so that the key files are isolated from other directories.

```bash
cd /tmp/tutorial-scs
COSIGN_PASSWORD="" cosign generate-key-pair
```

Setting `COSIGN_PASSWORD=""` before the command tells Cosign to use an empty passphrase for the private key, which is convenient for lab exercises. In production you would use a non-empty passphrase or a key management service such as AWS KMS or HashiCorp Vault. The command produces two files:

- `cosign.key` -- the private key, used for signing. This file is encrypted with the passphrase even when the passphrase is empty; protect it as you would any private key.
- `cosign.pub` -- the public key, used for verification. This file can be freely distributed to anyone who needs to verify signatures made with the corresponding private key.

## Signing an Image

Sign the tutorial image. You must use the full image reference including the registry host:

```bash
cd /tmp/tutorial-scs
COSIGN_PASSWORD="" cosign sign --key cosign.key localhost:5001/tutorial-scs-app:v1.0
```

Cosign performs several steps during signing. It resolves the tag `v1.0` to its current digest (a sha256 hash of the image manifest). It creates a signature payload that includes the digest, signs the payload with `cosign.key`, and then pushes the resulting signature as a new OCI artifact to the registry. The signature is stored at a tag derived from the digest: if the image digest is `sha256:abc123...`, the signature is stored at `localhost:5001/tutorial-scs-app:sha256-abc123....sig`.

You can inspect the registry to confirm the signature artifact is present:

```bash
nerdctl images | grep tutorial-scs-app
```

You should see both the `v1.0` tag and a tag that begins with `sha256-`. The `.sig` artifact is a small JSON document; the signature lives inside it.

## Verifying a Signature

Verification uses the public key and the same image reference:

```bash
cd /tmp/tutorial-scs
cosign verify --key cosign.pub localhost:5001/tutorial-scs-app:v1.0
```

Successful output looks like:

```text
Verification for localhost:5001/tutorial-scs-app:v1.0 --
The following checks were performed on each of these signatures:
  - The cosign claims were validated
  - The signatures were verified against the specified public key

[{"critical":{"identity":{"docker-reference":"localhost:5001/tutorial-scs-app:v1.0"},
"image":{"docker-manifest-digest":"sha256:<digest>"},
"type":"cosign container image signature"},"optional":null}]
```

The JSON payload confirms the image reference that was signed and the digest that was covered by the signature. If the image at `v1.0` has been replaced since signing (pushing a new image to the same tag changes the digest), verification fails because the stored `.sig` artifact references the old digest.

## What Happens When Verification Fails

Push an unsigned image to the same registry under a different tag:

```bash
nerdctl pull redis:7.2
nerdctl tag redis:7.2 localhost:5001/tutorial-unsigned:v1.0
nerdctl push localhost:5001/tutorial-unsigned:v1.0
```

Now attempt verification. Cosign will look for a `.sig` artifact matching the digest of this image and find nothing:

```bash
cosign verify --key cosign.pub localhost:5001/tutorial-unsigned:v1.0
```

```text
Error: no matching signatures:
...
```

The exit code is non-zero. This is the behavior your admission enforcement relies on: a webhook or policy check that calls `cosign verify` will receive a non-zero exit code for unsigned images and can deny the pod accordingly.

## Keyless Signing (Conceptual)

Key-based signing works well in environments where you can manage and protect a private key. Keyless signing removes the key management burden by replacing the long-lived private key with a workflow identity. When you run `cosign sign` in a GitHub Actions workflow (or any OIDC-capable CI environment), Cosign requests an OIDC token from the provider, presents that token to the Fulcio certificate authority, and receives a short-lived signing certificate. Cosign uses the certificate to sign the image and then immediately records the signature in Rekor, an append-only transparency log. Verifiers check both the signature and the Rekor entry to confirm authenticity.

The trade-off is clear: keyless signing requires an OIDC provider in your environment. In a local kind cluster with no external OIDC provider, keyless signing is not practical. For production systems running CI in GitHub Actions, Google Cloud Build, or similar environments, keyless is often preferred because there is no private key to rotate or leak.

The keyless signing command looks like this (shown for reference; it requires an OIDC provider to be configured):

```bash
# Shown for reference -- requires OIDC provider, not functional in a local lab
cosign sign localhost:5001/tutorial-scs-app:v1.0
```

Without a `--key` flag, Cosign attempts to obtain an OIDC token from the ambient environment. In a local lab you would see an error about no identity token. All hands-on exercises in this assignment use key-based signing.

## Attestations: Signed Statements About Your Images

A signature answers the question "was this image approved?" An attestation answers a richer question: "what is this image's provenance, what does it contain, and does it pass our quality checks?" Attestations are signed statements that attach structured metadata to an image. Common attestation types include SBOM (Software Bill of Materials), SLSA provenance (describing the build environment), and Trivy scan results.

Cosign stores attestations in the same OCI registry as the image, using a tag pattern similar to signatures (`.att` suffix). Create a minimal CycloneDX SBOM JSON file to use as the attestation predicate:

```bash
cd /tmp/tutorial-scs
cat > sbom.json <<'EOF'
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.4",
  "version": 1,
  "metadata": {
    "timestamp": "2026-07-04T00:00:00Z",
    "component": {
      "type": "container",
      "name": "tutorial-scs-app",
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
```

Attach the SBOM as a signed attestation:

```bash
cd /tmp/tutorial-scs
COSIGN_PASSWORD="" cosign attest \
  --key cosign.key \
  --predicate sbom.json \
  --type cyclonedx \
  localhost:5001/tutorial-scs-app:v1.0
```

The `--type cyclonedx` flag tells Cosign the format of the predicate so it can embed the correct media type in the attestation envelope. Valid built-in types include `cyclonedx`, `spdxjson`, `slsaprovenance`, and `vuln`. You can also pass a custom URI as the type for proprietary attestation formats.

Verify the attestation:

```bash
cd /tmp/tutorial-scs
cosign verify-attestation \
  --key cosign.pub \
  --type cyclonedx \
  localhost:5001/tutorial-scs-app:v1.0
```

The output includes the verified attestation payload as base64-encoded JSON. A non-zero exit code means either no attestation was found or the signature did not verify.

## Enforcing Image Policy with ValidatingAdmissionPolicy

ValidatingAdmissionPolicy is a Kubernetes admission mechanism introduced in 1.26 and promoted to GA in 1.30. It uses CEL (Common Expression Language) to evaluate pod (or other resource) fields at admission time without requiring an external webhook server. For supply chain security, this lets you reject pods that use images from unapproved registries or with disallowed tags directly in the API server, with no additional process to run.

A ValidatingAdmissionPolicy works in combination with a ValidatingAdmissionPolicyBinding. The policy defines what to check (CEL expressions and which resource types to validate); the binding ties the policy to specific namespaces or objects and specifies the enforcement action.

### ValidatingAdmissionPolicy Spec Fields

The spec of a ValidatingAdmissionPolicy has the following fields:

**`spec.failurePolicy`**
What it does: controls what happens if a CEL expression encounters an error during evaluation (not a policy denial, but an actual runtime error). Valid values: `Fail` causes the request to be rejected when any expression errors; `Ignore` allows the request through when expressions error. Default when omitted: `Fail`. Failure mode when misconfigured: setting `Ignore` in a policy intended as a hard gate means that if someone passes an object with an unexpected shape (for example, a pod with a null container list), the policy silently passes rather than blocking, creating a potential bypass.

**`spec.matchConstraints`**
What it does: defines which API resources this policy evaluates. The `resourceRules` list inside it specifies which API groups, versions, operations, and resource types trigger evaluation. Default when omitted: the field is required; the API server rejects the policy without it. Failure mode when misconfigured: if `operations` does not include `CREATE`, newly created pods will not be evaluated. If it includes only `UPDATE`, the policy has no effect on pod creation.

**`spec.matchConstraints.resourceRules`**
What it does: a list of `NamedRuleWithOperations` objects, each describing a set of resources to match. Required sub-fields: `apiGroups` (use `[""]` for core resources), `apiVersions` (typically `["v1"]` for pods), `operations` (typically `["CREATE", "UPDATE"]`), `resources` (for example `["pods"]`). Default when omitted: the list is required. Failure mode: missing `UPDATE` means policy is not evaluated when pods are updated in place (rare for pods, but matters for Deployments and other controllers that create pods).

**`spec.validations`**
What it does: a list of CEL expression objects, each evaluated against the request object. If any expression evaluates to `false`, the request is denied with the associated message. Default when omitted: the field is required; no validations means the policy matches everything and allows everything. Failure mode: an expression that always returns `true` (for example `1 == 1`) makes the policy a no-op.

**`spec.validations[].expression`**
What it does: a CEL expression evaluated against `object` (the resource being admitted). Must evaluate to a boolean. The `object` variable for a pod gives access to `object.spec.containers`, `object.spec.initContainers`, `object.metadata`, and so on. Default: required, no default. Failure mode: a CEL type error (for example accessing a field that does not exist on the object) causes an evaluation error, and the `failurePolicy` determines what happens next.

**`spec.validations[].message`**
What it does: the human-readable message returned to the client when the expression evaluates to `false`. Default when omitted: Kubernetes uses the expression string itself as the message, which is usually not helpful to end users. Best practice: always provide a clear message. Failure mode: omitting the message makes admission errors confusing, but does not affect enforcement.

**`spec.validations[].reason`**
What it does: a machine-readable reason code appended to the HTTP response. Valid values: `Forbidden`, `Invalid`, `RequestEntityTooLarge`, `BadRequest`, `InternalError`. Default when omitted: `Forbidden`. Failure mode: choosing an incorrect reason code may confuse tooling that parses admission error reasons programmatically but does not affect enforcement.

**`spec.auditAnnotations`**
What it does: CEL expressions whose results are added as audit log annotations when the request passes. Useful for recording which policy was applied without denying the request. Default when omitted: no annotations added. Failure mode: an error in an audit expression with `failurePolicy: Fail` will deny the request even if all `validations` passed.

**`spec.variables`**
What it does: named CEL expressions you can reuse across validations. Useful when a complex sub-expression appears in multiple validation rules. Default when omitted: no variables defined. Failure mode: a variable that shadows a built-in CEL variable name may produce unexpected results.

### ValidatingAdmissionPolicyBinding Spec Fields

**`spec.policyName`**
What it does: the name of the ValidatingAdmissionPolicy this binding activates. Default: required, no default. Failure mode: if the named policy does not exist, the binding has no effect (Kubernetes does not error on a binding referencing a non-existent policy; the binding simply becomes dormant).

**`spec.validationActions`**
What it does: controls what happens when a validation expression returns `false`. Valid values: `Deny` (reject the request with a 403), `Warn` (allow the request but return a warning header), `Audit` (allow the request but emit an audit event). Multiple values can be combined, for example `[Deny, Audit]`. Default when omitted: the field is required; the binding is rejected without it. Failure mode: using `Warn` instead of `Deny` is a common mistake when testing policies; it makes the policy appear to be enforcing (you see a warning message) but requests are not actually blocked.

**`spec.matchResources`**
What it does: limits which resources and namespaces this binding's enforcement applies to. Contains `namespaceSelector` (a label selector over namespace labels), `objectSelector` (a label selector over the object being created), and `resourceRules` (further restricts resource types beyond what the policy's matchConstraints already defines). Default when omitted: the binding applies to all namespaces for all resources matched by the policy's matchConstraints. Failure mode: an overly restrictive `namespaceSelector` that does not match any namespaces makes the binding dormant; the policy exists but enforces nothing.

**`spec.paramRef`**
What it does: references a parameter resource object (ConfigMap, CRD instance) that the policy's CEL expressions can access through the `params` variable. Default when omitted: no parameter object, `params` variable is not available in expressions. Failure mode: if the policy's expressions reference `params` but no `paramRef` is set, evaluation errors occur, and `failurePolicy` determines the outcome.

### Creating a Policy That Rejects :latest Tags

Here is a complete example that rejects pods using `:latest` image tags:

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: deny-latest-tutorial
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
    message: "All container images must use an explicit version tag, not :latest"
```

The CEL expression uses `.all()` to check every container in the pod. The `initContainers` check uses `has()` first because `initContainers` is optional and accessing an absent field in CEL causes a type error. This is a common source of policy expression bugs.

Apply the policy:

```bash
kubectl apply -f - <<'EOF'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: deny-latest-tutorial
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
    message: "All container images must use an explicit version tag, not :latest"
EOF
```

The policy alone does nothing. You must create a binding to activate it:

```bash
kubectl apply -f - <<'EOF'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: deny-latest-tutorial-binding
spec:
  policyName: deny-latest-tutorial
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: tutorial-supply-chain
EOF
```

The `namespaceSelector` uses the automatic `kubernetes.io/metadata.name` label that Kubernetes adds to every namespace, which lets you target a specific namespace by name without adding custom labels.

### Testing the Policy

Attempt to create a pod with `:latest`:

```bash
kubectl run test-latest \
  --image=nginx:latest \
  --namespace=tutorial-supply-chain \
  --restart=Never
```

You should see:

```text
Error from server (Forbidden): pods "test-latest" is forbidden: ValidatingAdmissionPolicy 'deny-latest-tutorial' with binding 'deny-latest-tutorial-binding' denied request: All container images must use an explicit version tag, not :latest
```

Create a pod with an explicit tag to confirm it is admitted:

```bash
kubectl run test-versioned \
  --image=localhost:5001/tutorial-scs-app:v1.0 \
  --namespace=tutorial-supply-chain \
  --restart=Never
```

This pod should be created without error. Verify it exists:

```bash
kubectl get pod test-versioned -n tutorial-supply-chain
```

### Registry Allowlist Policy

A second common enforcement pattern requires all images to come from an approved registry. The CEL expression checks whether the image string starts with the approved prefix:

```yaml
validations:
- expression: >
    object.spec.containers.all(c, c.image.startsWith('localhost:5001/')) &&
    (has(object.spec.initContainers) ?
      object.spec.initContainers.all(c, c.image.startsWith('localhost:5001/')) : true)
  message: "All images must be pulled from localhost:5001/"
```

Notice the trailing slash in `localhost:5001/`. Without it, a crafted image name like `localhost:50011/malicious:v1.0` would satisfy a check against `localhost:5001` (because it starts with those characters). The trailing slash ensures only images from exactly the `localhost:5001` registry pass.

## Connecting Cosign Verification to Admission (Conceptual)

ValidatingAdmissionPolicy with CEL can enforce tag and registry requirements because those are properties of the image reference string itself. Verifying a Cosign signature, however, requires contacting the registry, fetching the `.sig` artifact, and running cryptographic verification. That computation cannot be expressed in CEL.

The standard pattern for signature verification at admission time is a ValidatingWebhook backed by a webhook server that runs `cosign verify` or calls the Cosign library before admitting the pod. Policy Controller (from the Sigstore project) is the reference implementation: it is a webhook server that accepts configuration about which keys or keyless identities are trusted, and it verifies image signatures on every pod create or update. Configuring Policy Controller is outside the scope of this assignment (it requires deploying a running webhook server), but understanding the pattern -- admission webhook calls cosign, non-zero exit blocks admission -- is the conceptual bridge between the hands-on signing work and production enforcement.

## Cleanup

Delete all resources created during the tutorial, including the tutorial namespace and the cluster-scoped admission policy and binding:

```bash
kubectl delete namespace tutorial-supply-chain
kubectl delete validatingadmissionpolicy deny-latest-tutorial
kubectl delete validatingadmissionpolicybinding deny-latest-tutorial-binding
```

Remove the tutorial working directory:

```bash
rm -rf /tmp/tutorial-scs
```

## Reference Commands

| Task | Command |
|------|---------|
| Install Cosign v2.4.0 | `curl -LO https://github.com/sigstore/cosign/releases/download/v2.4.0/cosign-linux-amd64 && chmod +x cosign-linux-amd64 && sudo mv cosign-linux-amd64 /usr/local/bin/cosign` |
| Generate key pair (no password) | `COSIGN_PASSWORD="" cosign generate-key-pair` |
| Sign an image | `COSIGN_PASSWORD="" cosign sign --key cosign.key localhost:5001/myapp:v1.0` |
| Verify a signature | `cosign verify --key cosign.pub localhost:5001/myapp:v1.0` |
| Attach SBOM attestation | `COSIGN_PASSWORD="" cosign attest --key cosign.key --predicate sbom.json --type cyclonedx localhost:5001/myapp:v1.0` |
| Verify attestation | `cosign verify-attestation --key cosign.pub --type cyclonedx localhost:5001/myapp:v1.0` |
| Apply admission policy | `kubectl apply -f policy.yaml` |
| List admission policies | `kubectl get validatingadmissionpolicy` |
| List bindings | `kubectl get validatingadmissionpolicybinding` |
| Test admission (dry run) | `kubectl run test --image=nginx:latest --restart=Never --dry-run=server` |
| Push image to local registry | `nerdctl push localhost:5001/myapp:v1.0` |
| Tag for local registry | `nerdctl tag nginx:1.27 localhost:5001/myapp:v1.0` |
| Check cosign version | `cosign version` |
