# Secrets Management Tutorial: etcd Encryption at Rest

## Introduction

Every Kubernetes cluster stores its state in etcd, and that state includes every Secret object you have ever created. When you run `kubectl create secret generic db-password --from-literal=password=supersecretpassword`, Kubernetes encodes the value in base64 and writes it to etcd. That base64 encoding is not encryption. It is a text-safe representation of binary data, and any person or process with direct etcd access can decode it trivially using `echo <value> | base64 -d`. The Kubernetes RBAC system, which governs who can call the API server, has no say in what etcd itself contains. A stolen etcd backup, an exposed etcd endpoint, or a compromised node with access to the etcd data directory bypasses every RBAC policy you have written.

Kubernetes solves this with the EncryptionConfiguration mechanism, which instructs the kube-apiserver to encrypt Secret objects before writing them to etcd and to decrypt them transparently when reading them back. From the perspective of any application or operator using the Kubernetes API, nothing changes. From the perspective of anyone who reads etcd directly, Secret values become opaque ciphertext rather than readable base64 strings. This tutorial walks through the complete lifecycle: demonstrating the plaintext problem, writing and applying an EncryptionConfiguration, verifying the change in etcd, performing a key rotation, and understanding the implications for how you expose Secrets to pods.

This tutorial builds a working encryption setup on a single-node kind cluster from scratch. You will use etcdctl inside the etcd pod to inspect raw storage before and after enabling encryption, edit the kube-apiserver static pod manifest to add the `--encryption-provider-config` flag, and perform a full key rotation. By the end, you will have seen the complete lifecycle of Secret encryption and will understand exactly what the CKA exam expects you to do when asked to enable or rotate encryption at rest.

## Prerequisites

This tutorial requires a running single-node kind cluster. See [docs/cluster-setup.md#single-node-kind-cluster](../../../docs/cluster-setup.md#single-node-kind-cluster) for the creation command. You will need kubectl configured for the cluster and nerdctl available for exec into the kind-control-plane container. No additional components or operators are needed; the etcd pod in kind has etcdctl pre-installed and the required certificates mounted at the standard paths.

## Setup

Create the tutorial namespace:

```bash
kubectl create namespace tutorial-secrets-management
```

Verify the namespace is ready:

```bash
kubectl get namespace tutorial-secrets-management
# Expected output:
# NAME                           STATUS   AGE
# tutorial-secrets-management   Active   5s
```

## Section 1: The Plaintext Problem

### Creating a Secret

Start by creating a simple Secret that simulates a database password. The value `supersecretpassword` will be encoded in base64 by kubectl before being sent to the API server:

```bash
kubectl create secret generic app-credentials \
  --namespace tutorial-secrets-management \
  --from-literal=password=supersecretpassword
```

Confirm the Secret exists and inspect what kubectl shows you:

```bash
kubectl get secret app-credentials \
  --namespace tutorial-secrets-management \
  -o yaml
```

The output will show something similar to:

```yaml
apiVersion: v1
data:
  password: c3VwZXJzZWNyZXRwYXNzd29yZA==
kind: Secret
metadata:
  name: app-credentials
  namespace: tutorial-secrets-management
type: Opaque
```

The value `c3VwZXJzZWNyZXRwYXNzd29yZA==` is base64 for "supersecretpassword". Decode it:

```bash
echo "c3VwZXJzZWNyZXRwYXNzd29yZA==" | base64 -d
# Output: supersecretpassword
```

That confirms what the API server stores. Now let us look at what etcd stores.

### Reading the Secret Directly from etcd

The etcd pod in kind is named `etcd-kind-control-plane` and is in the `kube-system` namespace. It has etcdctl pre-installed and the required TLS certificates mounted at `/etc/kubernetes/pki/etcd/`. Kubernetes stores Secret objects under the key path `/registry/secrets/<namespace>/<name>`.

Run etcdctl inside the etcd pod to read the Secret directly:

```bash
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/tutorial-secrets-management/app-credentials"
```

The output is binary protobuf data, but the base64-encoded values are stored as readable ASCII strings embedded within it. You will see the string `c3VwZXJzZWNyZXRwYXNzd29yZA==` somewhere in the output, the exact same value kubectl showed you, and decodable to "supersecretpassword" by anyone reading etcd. There is no encryption layer between etcd and that string. This is the security problem EncryptionConfiguration addresses.

Note the four flags required for every etcdctl command against a kind cluster:

| Flag | Value in kind | Purpose |
|---|---|---|
| `--endpoints` | `https://127.0.0.1:2379` | etcd listen address inside the pod |
| `--cacert` | `/etc/kubernetes/pki/etcd/ca.crt` | CA certificate for TLS verification |
| `--cert` | `/etc/kubernetes/pki/etcd/server.crt` | Client certificate (server cert acts as client cert in kind) |
| `--key` | `/etc/kubernetes/pki/etcd/server.key` | Private key for the client certificate |

All four flags are required. Omitting any one of them will result in a TLS handshake failure or connection refused error. The `ETCDCTL_API=3` environment variable is also required; without it, etcdctl defaults to API version 2, which uses a different command syntax and cannot reach the v3 endpoints.

## Section 2: EncryptionConfiguration

### File Structure

The EncryptionConfiguration is a Kubernetes API object written as a YAML file on the file system of the control plane node (not applied with kubectl). Its full structure is:

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: <base64-encoded-32-byte-key>
      - identity: {}
```

Each field in this structure has specific behavior that matters for correctness:

**`resources`** is a list of resource type groups to which the providers apply. Each entry has:
- `resources`: the list of Kubernetes resource types (for example, `secrets`, `configmaps`). Use the plural, lowercase resource name.
- `providers`: the ordered list of providers for those resources.

**`providers`** is an ordered list of encryption providers. The order matters in two ways: the first provider in the list is used for all new writes, and all providers are tried in sequence when reading an existing object. If the first provider cannot decrypt a value (because it was written with a different provider), the next provider is tried, and so on.

**Provider types** and their key requirements:

| Provider | Algorithm | Key size (bytes) | Notes |
|---|---|---|---|
| `identity` | None (plaintext) | No key | Values stored as-is; used for reads of pre-existing unencrypted objects |
| `aescbc` | AES-CBC with PKCS7 padding | Exactly 32 bytes | Recommended for CKA exam scenarios; key stored base64-encoded in the YAML |
| `secretbox` | XSalsa20 + Poly1305 | Exactly 32 bytes | Faster than aescbc on modern CPUs; same key size requirement |
| `kms` | External KMS (AWS, GCP, Azure) | Managed externally | Conceptual for CKA; requires a running KMS plugin |

**Failure modes when misconfigured:**

- Supplying a key that decodes to the wrong byte length (for example, 16 bytes instead of 32 for aescbc) causes the kube-apiserver to refuse to start. The kubelet log will show: `invalid encryption provider configuration: aescbc: invalid key size 16`.
- Listing `identity` as the first provider means all new Secrets are written as plaintext (identity is a "no-op" encryption provider). This is the valid configuration for transitioning out of encryption, but if it is the first provider when you intend to encrypt, Secrets are not being protected.
- Omitting `identity` entirely means the kube-apiserver cannot read any Secrets that were written in plaintext before encryption was enabled. Reads of those Secrets will fail with a decryption error. The `identity` provider must remain in the list (typically last) until all existing plaintext Secrets have been re-encrypted.
- Referencing an EncryptionConfiguration file at a path that does not exist inside the kube-apiserver container causes the API server to refuse to start with a file-not-found error.

### Generating a Key

The aescbc provider requires a key that is exactly 32 bytes long, provided as a base64-encoded string. Generate one:

```bash
TUTORIAL_KEY=$(head -c 32 /dev/urandom | base64)
echo "Tutorial key (save this): $TUTORIAL_KEY"
```

The command reads exactly 32 bytes from the kernel's cryptographically secure random source and encodes them as base64. The result will be a 44-character base64 string (32 bytes at 4/3 ratio, rounded up to the next multiple of 4). The key name (`key1` in the example) is an arbitrary label; it appears in the ciphertext prefix stored in etcd and is used during key rotation to identify which key encrypted a given value.

## Section 3: Enabling Encryption on the API Server

### Writing the EncryptionConfiguration to the Kind Node

The kube-apiserver reads the EncryptionConfiguration from the local file system of the control plane node. In kind, the control plane node is a container named `kind-control-plane`. You will write the file to `/etc/kubernetes/enc/enc-config.yaml` on that container.

First, create the EncryptionConfiguration file locally using the key generated above:

```bash
cat > /tmp/tutorial-enc-config.yaml << EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${TUTORIAL_KEY}
      - identity: {}
EOF
```

Create the directory on the kind node and copy the file:

```bash
nerdctl exec kind-control-plane mkdir -p /etc/kubernetes/enc
nerdctl cp /tmp/tutorial-enc-config.yaml kind-control-plane:/etc/kubernetes/enc/enc-config.yaml
```

Verify the file is in place:

```bash
nerdctl exec kind-control-plane cat /etc/kubernetes/enc/enc-config.yaml
```

The output should show your EncryptionConfiguration with the key value you generated.

### Editing the kube-apiserver Static Pod Manifest

The kube-apiserver in kind is a static pod managed by the kubelet. Its manifest lives at `/etc/kubernetes/manifests/kube-apiserver.yaml` on the kind-control-plane node. When you edit this file, the kubelet detects the change and restarts the kube-apiserver pod automatically within a few seconds.

Copy the current manifest to your local machine for editing:

```bash
nerdctl cp kind-control-plane:/etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml
```

Open `/tmp/kube-apiserver.yaml` in an editor. You need to make three additions:

**1. Add the flag to the command list.** Find the section that looks like:

```yaml
    - command:
      - kube-apiserver
      - --advertise-address=...
      - --allow-privileged=true
      - --authorization-mode=...
```

Add the following line anywhere in that list (the order of flags does not matter):

```yaml
      - --encryption-provider-config=/etc/kubernetes/enc/enc-config.yaml
```

**2. Add a volumeMount for the enc directory.** Find the `volumeMounts` section of the kube-apiserver container and add:

```yaml
        - mountPath: /etc/kubernetes/enc
          name: enc
          readOnly: true
```

**3. Add a volume for the enc directory.** Find the `volumes` section (at the Pod level, not inside the container) and add:

```yaml
      - hostPath:
          path: /etc/kubernetes/enc
          type: DirectoryOrCreate
        name: enc
```

After making all three edits, copy the manifest back to the kind node:

```bash
nerdctl cp /tmp/kube-apiserver.yaml kind-control-plane:/etc/kubernetes/manifests/kube-apiserver.yaml
```

### Waiting for the API Server to Restart

After you copy the edited manifest back, the kubelet detects the change and kills the current kube-apiserver pod. It then starts a new pod using the updated manifest. This process takes between ten and thirty seconds. The API server will be briefly unreachable during the restart.

Wait for it to come back:

```bash
until kubectl cluster-info 2>/dev/null | grep -q "Kubernetes control plane"; do
  echo "Waiting for API server..."
  sleep 5
done
echo "API server is ready"
```

Confirm the kube-apiserver pod is running with the new flag:

```bash
kubectl get pod kube-apiserver-kind-control-plane -n kube-system -o yaml | grep encryption
# Expected output contains:
# - --encryption-provider-config=/etc/kubernetes/enc/enc-config.yaml
```

## Section 4: Verifying Encryption is Working

### Creating a New Secret

Now that the API server is configured to use EncryptionConfiguration, any new Secret you create will be encrypted before being written to etcd. Create a new Secret:

```bash
kubectl create secret generic encrypted-credentials \
  --namespace tutorial-secrets-management \
  --from-literal=api-key=test-secret
```

### Comparing etcd Storage for Old and New Secrets

Read the old Secret (created before encryption was enabled) from etcd:

```bash
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/tutorial-secrets-management/app-credentials"
```

You will still see the base64-encoded plaintext. The old Secret was written to etcd before encryption was enabled; the kube-apiserver does not automatically re-encrypt existing Secrets when the EncryptionConfiguration is first applied.

Now read the new Secret:

```bash
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/tutorial-secrets-management/encrypted-credentials"
```

The output for the new Secret starts with `k8s:enc:aescbc:v1:key1:` followed by binary ciphertext. The prefix encodes the encryption mechanism (`aescbc`), the API version (`v1`), and the key name (`key1`). After the prefix there are no readable ASCII strings containing the secret value. The encryption is working.

### Verifying kubectl Still Decrypts Correctly

The encryption and decryption happen transparently in the kube-apiserver. Applications and operators using the Kubernetes API see no difference:

```bash
kubectl get secret encrypted-credentials \
  --namespace tutorial-secrets-management \
  -o jsonpath='{.data.api-key}' | base64 -d
# Expected output: test-secret
```

The kube-apiserver decrypts the value from etcd using the key from the EncryptionConfiguration before returning it through the API.

## Section 5: Key Rotation

Key rotation is the process of replacing the encryption key used to protect Secrets with a new key. This is necessary when a key may have been exposed, when compliance requirements mandate periodic rotation, or when moving from one encryption algorithm to another.

The rotation process has a specific ordering requirement: the old key must remain in the providers list until all Secrets have been re-encrypted with the new key, because the kube-apiserver uses the providers list to decrypt existing Secrets during reads. Removing the old key before re-encrypting all Secrets with the new key will cause decryption failures for any Secret that was encrypted with the old key.

### Step 1: Add the New Key

Generate a new key:

```bash
TUTORIAL_KEY_2=$(head -c 32 /dev/urandom | base64)
echo "New key (save this): $TUTORIAL_KEY_2"
```

Update the EncryptionConfiguration to list the new key first and keep the old key second. Create an updated file (replace `<OLD_KEY>` with the value of `$TUTORIAL_KEY` you saved earlier):

```bash
cat > /tmp/tutorial-enc-config-v2.yaml << EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key2
              secret: ${TUTORIAL_KEY_2}
            - name: key1
              secret: <OLD_KEY>
      - identity: {}
EOF
```

Copy the updated file to the kind node:

```bash
nerdctl cp /tmp/tutorial-enc-config-v2.yaml kind-control-plane:/etc/kubernetes/enc/enc-config.yaml
```

The kubelet detects the changed file through the volume mount and the kube-apiserver re-reads it without a full restart (EncryptionConfiguration changes are hot-reloaded). Wait a few seconds and verify the API server is still healthy:

```bash
kubectl cluster-info
```

### Step 2: Re-encrypt Existing Secrets

With key2 now listed first, new Secrets will be encrypted with key2. Existing Secrets encrypted with key1 (or stored in plaintext) are still readable, the providers list includes key1 for decryption, but they are not yet protected by key2. Re-encrypt all Secrets in all namespaces by reading them and writing them back:

```bash
kubectl get secrets --all-namespaces -o json | kubectl replace -f -
```

This command reads all Secrets through the Kubernetes API (which decrypts them) and writes them back (which encrypts them using the first provider, key2). The `kubectl replace` path forces an update even if the object data has not changed.

### Step 3: Verify the New Ciphertext

Read the previously-unencrypted Secret from etcd:

```bash
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/tutorial-secrets-management/app-credentials"
```

The output should now start with `k8s:enc:aescbc:v1:key2:`, the Secret has been re-encrypted with key2. The `app-credentials` Secret, which was written in plaintext before encryption was enabled, is now protected.

### Step 4: Remove the Old Key

Once all Secrets show the key2 prefix, remove key1 from the EncryptionConfiguration:

```bash
cat > /tmp/tutorial-enc-config-v3.yaml << EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key2
              secret: ${TUTORIAL_KEY_2}
      - identity: {}
EOF

nerdctl cp /tmp/tutorial-enc-config-v3.yaml kind-control-plane:/etc/kubernetes/enc/enc-config.yaml
```

Wait a moment and confirm the API server is still serving:

```bash
kubectl get secret encrypted-credentials \
  --namespace tutorial-secrets-management \
  -o jsonpath='{.data.api-key}' | base64 -d
# Expected output: test-secret
```

The rotation is complete. The old key no longer exists in the EncryptionConfiguration, so even if it were leaked, it cannot be used to decrypt any currently stored Secret.

## Section 6: Secret Exposure Patterns

Protecting Secrets in etcd is only one side of the security picture. Once a Secret is stored, how a pod accesses it determines whether that Secret can be accidentally exposed through application logs, crash dumps, process inspection tools, or over-broad environment variable inheritance.

### Environment Variable Exposure

Mounting a Secret as an environment variable is the most common exposure pattern and the one most likely to lead to accidental leaks. When you create a pod that reads a Secret via `env.valueFrom.secretKeyRef`, the value is loaded into the container's process environment at startup. Three things make this risky.

First, the value appears in `kubectl describe pod <name>` output under the environment section (though kubectl shows the variable name and source Secret reference, not the decoded value, the variable name can reveal what the pod is accessing). Second, anyone with exec access to the container can read the environment by inspecting `/proc/1/environ` or running `printenv`. Third, if the application logs its entire environment for debugging, the Secret value appears in log aggregation systems where access controls may be weaker than in etcd.

```yaml
# Environment variable exposure pattern (use with caution)
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: db-credentials
        key: password
```

The `secretKeyRef` field references a single key from the Secret. The `envFrom.secretRef` variant mounts all keys from a Secret as environment variables, which is convenient but increases the blast radius if any single key is leaked.

### Volume Mount Exposure (Preferred)

Mounting a Secret as a volume writes each key as a separate file inside a directory in the container's file system. The values are not in the environment, so they do not appear in process listings, are not captured by environment-variable logging, and do not propagate to child processes via `exec`. An application reads the file on demand rather than receiving the value as a string at startup.

```yaml
# Volume mount pattern (preferred for sensitive values)
volumes:
  - name: secret-vol
    secret:
      secretName: db-credentials
spec:
  containers:
    - volumeMounts:
        - name: secret-vol
          mountPath: /etc/secrets
          readOnly: true
```

With this configuration, the Secret key `password` becomes readable at `/etc/secrets/password`. The `readOnly: true` mount option prevents the application from writing to the secrets directory, which is a defense-in-depth measure.

One limitation of volume-mounted Secrets worth knowing: if the Secret is updated (via `kubectl edit secret` or `kubectl apply`), the file on disk is updated automatically (within the kubelet's sync period, typically one minute). Environment variable Secrets, by contrast, are only read at pod startup and are not updated when the Secret changes. This difference matters for secret rotation strategies.

### Projected Volumes

A projected volume allows you to combine multiple sources, Secrets, ConfigMaps, service account tokens, and downward API data, into a single directory mount. This is useful when an application expects its configuration and credentials in the same directory:

```yaml
volumes:
  - name: combined-config
    projected:
      sources:
        - secret:
            name: db-credentials
        - configMap:
            name: app-config
        - serviceAccountToken:
            path: token
            expirationSeconds: 3600
```

With this configuration, both the Secret keys and the ConfigMap keys appear as files in the same directory inside the container. The `serviceAccountToken` source generates a bound service account token with a configurable expiration, which is more secure than the long-lived token the kube-controller-manager creates for service accounts by default.

### Disabling Service Account Token Automount

Every pod is automatically assigned the default service account in its namespace, and the kubelet automatically mounts that service account's token at `/var/run/secrets/kubernetes.io/serviceaccount/token`. This token can authenticate to the Kubernetes API server with the permissions of the default service account. For pods that do not need to call the Kubernetes API, this automatic mount is an unnecessary credential.

Set `automountServiceAccountToken: false` on the pod spec to suppress the mount:

```yaml
spec:
  automountServiceAccountToken: false
  containers:
    - name: app
      image: nginx:1.27
```

You can also set this field to `false` on the ServiceAccount resource itself to disable auto-mounting cluster-wide for all pods using that service account:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: restricted-app
  namespace: tutorial-secrets-management
automountServiceAccountToken: false
```

When `automountServiceAccountToken: false` is set on the ServiceAccount, it applies to all pods using that account unless the pod spec overrides it by setting `automountServiceAccountToken: true` explicitly.

## Cleanup

Remove all tutorial resources, including the tutorial namespace and all Secrets within it:

```bash
kubectl delete namespace tutorial-secrets-management
```

Restore the kube-apiserver to its original state by removing the EncryptionConfiguration flag and volume. Copy the original manifest back (or edit the current one to remove the three additions you made), then copy it back to the kind node:

```bash
# Remove the enc-config from the kind node
nerdctl exec kind-control-plane rm -rf /etc/kubernetes/enc

# Edit /tmp/kube-apiserver.yaml to remove:
# 1. The --encryption-provider-config flag
# 2. The enc volumeMount
# 3. The enc volume
# Then copy back:
nerdctl cp /tmp/kube-apiserver.yaml kind-control-plane:/etc/kubernetes/manifests/kube-apiserver.yaml
```

Wait for the API server to restart without the encryption flag:

```bash
until kubectl cluster-info 2>/dev/null | grep -q "Kubernetes control plane"; do
  sleep 5
done
echo "API server restored"
```

Existing Secrets that were encrypted with aescbc can no longer be decrypted by the API server because the EncryptionConfiguration has been removed. If you need the cluster in a clean state for the exercises, it is easier to delete and recreate the kind cluster entirely:

```bash
kind delete cluster
kind create cluster
```

## Reference Commands

### etcdctl Commands for Kind

| Operation | Command |
|---|---|
| List all secrets in etcd | `kubectl exec -n kube-system etcd-kind-control-plane -- sh -c "ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key get /registry/secrets --prefix --keys-only"` |
| Read a specific secret | `kubectl exec -n kube-system etcd-kind-control-plane -- sh -c "ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key get /registry/secrets/<namespace>/<name>"` |

### Key Generation

| Operation | Command |
|---|---|
| Generate 32-byte aescbc/secretbox key | `head -c 32 /dev/urandom \| base64` |
| Verify key length (should be 32) | `echo "<key>" \| base64 -d \| wc -c` |

### Encryption Configuration Operations

| Operation | Command |
|---|---|
| Copy file to kind node | `nerdctl cp <local-file> kind-control-plane:<remote-path>` |
| Copy file from kind node | `nerdctl cp kind-control-plane:<remote-path> <local-file>` |
| Exec into kind node | `nerdctl exec -it kind-control-plane bash` |
| Re-encrypt all Secrets | `kubectl get secrets --all-namespaces -o json \| kubectl replace -f -` |
| Check API server flags | `kubectl get pod kube-apiserver-kind-control-plane -n kube-system -o yaml \| grep encryption` |

### Secret Exposure Operations

| Operation | Command |
|---|---|
| Decode a Secret value | `kubectl get secret <name> -o jsonpath='{.data.<key>}' \| base64 -d` |
| Check env var in running pod | `kubectl exec <pod> -- printenv <VAR_NAME>` |
| Check volume-mounted secret file | `kubectl exec <pod> -- cat /etc/secrets/<key>` |
| Verify no SA token mounted | `kubectl exec <pod> -- ls /var/run/secrets/kubernetes.io/serviceaccount/ 2>&1` |
