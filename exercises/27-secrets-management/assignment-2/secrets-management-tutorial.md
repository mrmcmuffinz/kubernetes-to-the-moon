# Secrets Management Tutorial: External Secrets Operator and Vault

## Introduction

Kubernetes Secrets solve the problem of how to get sensitive values into pods, but they do not solve the broader problem of where those values should live and how they should be managed over time. In most organizations, secrets are maintained in purpose-built stores, HashiCorp Vault, AWS Secrets Manager, GCP Secret Manager, or Azure Key Vault, with access policies, audit logs, versioning, and automatic rotation that native Kubernetes Secrets cannot provide. The challenge is getting secrets from those stores into pods without copying them manually into Kubernetes Secrets, which creates a second copy that drifts out of sync as the original value rotates.

The External Secrets Operator (ESO) addresses this by running a controller in your cluster that continuously watches ExternalSecret objects and syncs their referenced values from the external store into Kubernetes Secrets. When the external value changes, ESO re-fetches and updates the Kubernetes Secret on the next refresh cycle. Applications read from the Kubernetes Secret as they normally would; the sync is transparent. This architecture separates the concern of secret storage and lifecycle management (handled by the external store) from the concern of secret consumption (handled by the Kubernetes API and the kubelet's volume or environment injection).

This tutorial builds a complete ESO setup on a single-node kind cluster. You will install ESO using Helm, use the fake provider (ESO's built-in testing provider) to explore all the resource types and sync patterns without needing a real external system, deploy HashiCorp Vault in dev mode as a pod in kind, and connect ESO to Vault to sync a secret into a running application pod. The tutorial also covers secret rotation patterns: how refreshInterval drives automatic updates, how to trigger a manual re-sync, and the trade-offs between different Secret update strategies.

## Prerequisites

This tutorial requires a running single-node kind cluster with Helm available. See [docs/cluster-setup.md#single-node-kind-cluster](../../../docs/cluster-setup.md#single-node-kind-cluster) for cluster setup. Helm version 3.x is required for the ESO installation. The tutorial uses `kubectl exec` into the Vault pod to run vault CLI commands; no local vault binary is needed.

## Setup: Installing the External Secrets Operator

ESO is distributed as a Helm chart from its official chart repository. Install it into its own namespace:

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --version 0.9.20 \
  --wait
```

The `--wait` flag causes Helm to block until all ESO components (controller, webhook, and CRD jobs) are Ready. This typically takes thirty to sixty seconds. Verify the installation:

```bash
kubectl get pods -n external-secrets
# Expected: three pods (external-secrets, external-secrets-cert-controller, external-secrets-webhook)
# all in Running state

kubectl get crd | grep external-secrets
# Expected: lines including secretstores.external-secrets.io, clustersecretstores.external-secrets.io,
# externalsecrets.external-secrets.io
```

The three CRDs are the central resources this tutorial teaches:

| CRD | API kind | Scope | Purpose |
|---|---|---|---|
| `secretstores.external-secrets.io` | SecretStore | Namespace | Connection config for an external provider, scoped to one namespace |
| `clustersecretstores.external-secrets.io` | ClusterSecretStore | Cluster | Same as SecretStore but accessible from all namespaces |
| `externalsecrets.external-secrets.io` | ExternalSecret | Namespace | Mapping between external store keys and a target Kubernetes Secret |

Create the tutorial namespace:

```bash
kubectl create namespace tutorial-secrets-management
```

## Section 1: The Fake Provider

ESO ships with a built-in `fake` provider designed for testing and development. The fake provider stores key-value pairs directly in the SecretStore spec; no external system is required. It supports the same SecretStore and ExternalSecret API as real providers, making it the best way to learn ESO's resource model before connecting to a real store.

### Creating a SecretStore with the Fake Provider

The SecretStore defines how ESO connects to an external provider. With the fake provider, the "connection" is just an inline data dictionary:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: fake-store
  namespace: tutorial-secrets-management
spec:
  provider:
    fake:
      data:
        - key: /myapp/db-password
          value: supersecretpassword
        - key: /myapp/api-token
          value: test-api-token-12345
```

Apply this:

```bash
kubectl apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: fake-store
  namespace: tutorial-secrets-management
spec:
  provider:
    fake:
      data:
        - key: /myapp/db-password
          value: supersecretpassword
        - key: /myapp/api-token
          value: test-api-token-12345
EOF
```

Check the SecretStore status:

```bash
kubectl get secretstore fake-store -n tutorial-secrets-management
# Expected:
# NAME         AGE   STATUS   CAPABILITIES   READY
# fake-store   10s   Valid    ReadWrite      True
```

The `READY: True` status means ESO can connect to (or in this case, read from) the provider. For the fake provider this is always valid; for real providers, it verifies connectivity and authentication.

**Spec field documentation for SecretStore:**

| Field | Description | Valid values | Default | Failure when misconfigured |
|---|---|---|---|---|
| `spec.provider` | Specifies the external provider and its connection config | One provider key (fake, vault, aws, gcpsm, etc.) | Required | No provider: validation error on apply |
| `spec.provider.fake.data` | List of key-value pairs the fake provider exposes | Any list of `{key, value}` objects | Required | No data: SecretStore is valid but ExternalSecrets referencing missing keys will fail sync |
| `spec.refreshInterval` | How often ESO re-validates connectivity to the provider | Duration string (1m, 1h, etc.) | 1h | Too long: stale auth errors go undetected; zero: never refreshes |

### Creating an ExternalSecret

The ExternalSecret defines which keys to fetch from the provider and how to map them into a Kubernetes Secret. It references the SecretStore by name:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-external-secret
  namespace: tutorial-secrets-management
spec:
  secretStoreRef:
    name: fake-store
    kind: SecretStore
  target:
    name: app-synced-secret
    creationPolicy: Owner
  refreshInterval: 5m
  data:
    - secretKey: db-password
      remoteRef:
        key: /myapp/db-password
    - secretKey: api-token
      remoteRef:
        key: /myapp/api-token
```

Apply this:

```bash
kubectl apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-external-secret
  namespace: tutorial-secrets-management
spec:
  secretStoreRef:
    name: fake-store
    kind: SecretStore
  target:
    name: app-synced-secret
    creationPolicy: Owner
  refreshInterval: 5m
  data:
    - secretKey: db-password
      remoteRef:
        key: /myapp/db-password
    - secretKey: api-token
      remoteRef:
        key: /myapp/api-token
EOF
```

**Spec field documentation for ExternalSecret:**

| Field | Description | Valid values | Default | Failure when misconfigured |
|---|---|---|---|---|
| `spec.secretStoreRef.name` | Name of the SecretStore or ClusterSecretStore to use | Any existing store name | Required | Store not found: ExternalSecret stays NotReady |
| `spec.secretStoreRef.kind` | Whether the store is namespace or cluster-scoped | `SecretStore` or `ClusterSecretStore` | `SecretStore` | Wrong kind: store lookup fails; ExternalSecret stays NotReady |
| `spec.target.name` | Name of the Kubernetes Secret to create/update | Any valid Secret name | Required | None set: defaults to same name as ExternalSecret |
| `spec.target.creationPolicy` | How ESO manages the lifecycle of the target Secret | `Owner`, `Merge`, `None` | `Owner` | `Merge` when no Secret exists: sync fails because merge requires an existing Secret; `None`: ESO never creates the Secret |
| `spec.refreshInterval` | How often ESO re-fetches from the provider | Duration string | `1h` | `0`: syncs once and never again; very long values cause stale data after rotation |
| `spec.data[].secretKey` | Key name in the resulting Kubernetes Secret | Any valid key name | Required | Duplicate key names silently overwrite each other |
| `spec.data[].remoteRef.key` | Path/key in the external provider | Provider-specific format | Required | Key not found: sync fails; ExternalSecret shows NotReady with a key-not-found message |

After applying, check the ExternalSecret status:

```bash
kubectl get externalsecret app-external-secret -n tutorial-secrets-management
# Expected:
# NAME                   STORE        REFRESH INTERVAL   STATUS   READY
# app-external-secret    fake-store   5m                 Valid    True
```

Check that the Kubernetes Secret was created:

```bash
kubectl get secret app-synced-secret -n tutorial-secrets-management -o yaml
```

The Secret is created and owned by ESO (the ownerReferences field lists the ExternalSecret). Decode the values:

```bash
kubectl get secret app-synced-secret -n tutorial-secrets-management \
  -o jsonpath='{.data.db-password}' | base64 -d
# Expected: supersecretpassword

kubectl get secret app-synced-secret -n tutorial-secrets-management \
  -o jsonpath='{.data.api-token}' | base64 -d
# Expected: test-api-token-12345
```

### Using dataFrom for Bulk Sync

The `spec.dataFrom` field syncs all keys from a provider path into the Kubernetes Secret in one step, without listing each key individually:

```yaml
spec:
  dataFrom:
    - extract:
        key: /myapp
```

With the fake provider, `extract` with a key prefix syncs all fake data entries whose key starts with `/myapp`. Each entry becomes a key in the resulting Kubernetes Secret, using the last path segment as the key name. This is useful when a provider path contains many fields that all belong to the same application.

### Updating the External Value and Triggering a Re-sync

The fake provider values live in the SecretStore spec. Update a value by editing the SecretStore:

```bash
kubectl edit secretstore fake-store -n tutorial-secrets-management
# Change the value for /myapp/db-password from supersecretpassword to rotated-password
```

ESO will pick up the new value on the next refresh cycle (every `refreshInterval`). To trigger an immediate re-sync without waiting:

```bash
kubectl annotate externalsecret app-external-secret \
  force-sync=$(date +%s) \
  -n tutorial-secrets-management \
  --overwrite
```

ESO watches ExternalSecret annotations and triggers a sync when it detects a change. After a moment:

```bash
kubectl get secret app-synced-secret -n tutorial-secrets-management \
  -o jsonpath='{.data.db-password}' | base64 -d
# Expected: rotated-password
```

### ClusterSecretStore

The ClusterSecretStore is cluster-scoped, meaning it can be referenced by ExternalSecrets in any namespace. This is useful when a single Vault instance or secret store should be available cluster-wide without duplicating SecretStore objects in each namespace:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: global-fake-store
spec:
  provider:
    fake:
      data:
        - key: /shared/service-account-key
          value: shared-sa-key-value
```

ExternalSecrets reference it with `kind: ClusterSecretStore` in the `secretStoreRef`:

```yaml
spec:
  secretStoreRef:
    name: global-fake-store
    kind: ClusterSecretStore
```

The distinction matters for the CKA exam: using `kind: SecretStore` when the store is actually a ClusterSecretStore (or vice versa) is one of the most common misconfiguration errors, and ESO will silently fail to find the store if the kind is wrong.

## Section 2: HashiCorp Vault in Dev Mode

Vault is the most widely used self-hosted secrets management system and is specifically mentioned in CKA curriculum coverage of external secrets. Running Vault in dev mode in kind gives you a fully functional KV secrets engine with no persistence requirements and a predictable root token, making it suitable for learning exercises.

### Deploying Vault Dev Mode in Kind

Deploy Vault as a Pod with a matching Service:

```bash
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: vault
  namespace: tutorial-secrets-management
  labels:
    app: vault
spec:
  containers:
    - name: vault
      image: hashicorp/vault:1.17
      command:
        - vault
        - server
        - -dev
        - -dev-root-token-id=root
        - -dev-listen-address=0.0.0.0:8200
      ports:
        - containerPort: 8200
          name: http
      env:
        - name: VAULT_DEV_ROOT_TOKEN_ID
          value: root
EOF

kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: tutorial-secrets-management
spec:
  selector:
    app: vault
  ports:
    - port: 8200
      targetPort: 8200
      protocol: TCP
EOF
```

Wait for the Vault pod to start:

```bash
kubectl wait pod vault -n tutorial-secrets-management --for=condition=Ready --timeout=60s
```

**What dev mode gives you:** Vault starts unsealed with a root token of `root`. It enables a KV v2 secrets engine at the `secret/` path automatically. No configuration is needed to start writing secrets. The storage is in-memory, so all secrets are lost if the pod restarts. This is appropriate for learning and exercises but never for production.

**KV v2 path conventions:** Vault's KV v2 secrets engine uses path conventions that matter for API calls. When you write a secret to `secret/myapp/config`, the Vault API stores it at `secret/data/myapp/config`. The `kv` CLI commands handle this translation transparently, but the ESO provider configuration and direct API calls use the full `data/` path.

### Storing and Reading Secrets in Vault

Write a secret using the vault CLI inside the pod:

```bash
kubectl exec -n tutorial-secrets-management vault -- \
  sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root \
    vault kv put secret/myapp/config \
      db-password=supersecretpassword \
      api-key=test-api-key-value"
```

Read it back:

```bash
kubectl exec -n tutorial-secrets-management vault -- \
  sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root \
    vault kv get secret/myapp/config"
```

The output shows all key-value pairs stored at that path, along with metadata (version, creation time). Read a specific field:

```bash
kubectl exec -n tutorial-secrets-management vault -- \
  sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root \
    vault kv get -field=db-password secret/myapp/config"
# Expected: supersecretpassword
```

### Connecting ESO to Vault

ESO's Vault provider can authenticate using several methods: a static Vault token stored in a Kubernetes Secret, Kubernetes auth (where ESO uses a service account JWT to authenticate), and others. For dev mode with the root token, token authentication is the simplest:

Create a Kubernetes Secret containing the Vault root token:

```bash
kubectl create secret generic vault-token \
  --namespace tutorial-secrets-management \
  --from-literal=token=root
```

Create a SecretStore that uses this token to connect to the Vault pod:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-store
  namespace: tutorial-secrets-management
spec:
  provider:
    vault:
      server: http://vault.tutorial-secrets-management:8200
      path: secret
      version: v2
      auth:
        tokenSecretRef:
          name: vault-token
          key: token
```

Apply this and check the status:

```bash
kubectl apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-store
  namespace: tutorial-secrets-management
spec:
  provider:
    vault:
      server: http://vault.tutorial-secrets-management:8200
      path: secret
      version: v2
      auth:
        tokenSecretRef:
          name: vault-token
          key: token
EOF

kubectl get secretstore vault-store -n tutorial-secrets-management
# Expected: READY True
```

**Spec field documentation for the Vault provider:**

| Field | Description | Valid values | Default | Failure when misconfigured |
|---|---|---|---|---|
| `spec.provider.vault.server` | The Vault server URL | Full URL including scheme and port | Required | Wrong URL: SecretStore goes NotReady with connection refused |
| `spec.provider.vault.path` | The KV mount path | The mount name (e.g., `secret`) | Required | Wrong path: SecretStore is Ready but ExternalSecrets fail with path-not-found |
| `spec.provider.vault.version` | KV engine version | `v1` or `v2` | `v2` | Wrong version: ESO constructs wrong API paths; reads return empty or 404 |
| `spec.provider.vault.auth.tokenSecretRef.name` | Name of the Kubernetes Secret holding the token | Any existing Secret name | Required | Secret not found: SecretStore goes NotReady with auth error |

### Syncing a Vault Secret to a Kubernetes Secret

Create an ExternalSecret that reads from the Vault store:

```bash
kubectl apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: vault-app-secret
  namespace: tutorial-secrets-management
spec:
  secretStoreRef:
    name: vault-store
    kind: SecretStore
  target:
    name: vault-synced-secret
    creationPolicy: Owner
  refreshInterval: 5m
  data:
    - secretKey: db-password
      remoteRef:
        key: myapp/config
        property: db-password
    - secretKey: api-key
      remoteRef:
        key: myapp/config
        property: api-key
EOF
```

The `remoteRef.key` for Vault KV v2 is the path after the mount point (not including `data/`, ESO adds that automatically for v2). The `remoteRef.property` selects one field from that path.

Verify the sync:

```bash
kubectl get externalsecret vault-app-secret -n tutorial-secrets-management
# Expected: READY True

kubectl get secret vault-synced-secret -n tutorial-secrets-management \
  -o jsonpath='{.data.db-password}' | base64 -d
# Expected: supersecretpassword
```

## Section 3: Secret Rotation Patterns

### The refreshInterval and Automatic Re-sync

Once an ExternalSecret is synced, ESO re-fetches the external value on each refresh cycle defined by `spec.refreshInterval`. If the external value changes in Vault or the fake provider, the next refresh will update the Kubernetes Secret. The Kubernetes Secret's `lastUpdateTime` shows when it was last written:

```bash
kubectl get secret vault-synced-secret -n tutorial-secrets-management \
  -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}'
```

Or check the managedFields timestamp:

```bash
kubectl get secret vault-synced-secret -n tutorial-secrets-management \
  -o jsonpath='{.metadata.managedFields[0].time}'
```

For applications using volume-mounted Secrets, kubelet propagates the updated values to the mounted files within one kubelet sync period (typically one minute) after the Kubernetes Secret is updated. Applications using environment variable injection do not see updates until the pod restarts.

### Forcing a Re-sync

Trigger an immediate re-sync without waiting for the refreshInterval:

```bash
kubectl annotate externalsecret vault-app-secret \
  force-sync=$(date +%s) \
  -n tutorial-secrets-management \
  --overwrite
```

Check the ExternalSecret status to confirm the sync completed:

```bash
kubectl describe externalsecret vault-app-secret -n tutorial-secrets-management
```

Look at the `Status` section for `Conditions` with `Ready: True` and a recent `LastTransitionTime`.

### Rolling Pods After Secret Rotation

When a Secret is updated via ESO's re-sync, volume-mounted Secrets are updated automatically by the kubelet. However, environment variable injected Secrets are not updated until the pod restarts. For deployments that use env-var injection and need to pick up rotated secrets, trigger a rollout:

```bash
kubectl rollout restart deployment/<name> -n <namespace>
```

A more automated pattern is to store a hash of the Secret in a pod annotation. Kubernetes rolls out a new ReplicaSet when pod template annotations change, which happens whenever the annotation is updated to reflect a new Secret version:

```bash
# After updating the external secret, update the annotation
SECRET_HASH=$(kubectl get secret vault-synced-secret -n tutorial-secrets-management \
  -o jsonpath='{.data}' | sha256sum | cut -c1-10)
kubectl annotate deployment myapp \
  secret-hash=${SECRET_HASH} \
  -n tutorial-secrets-management \
  --overwrite
```

### Immutable Secrets with Versioned Names

A third rotation pattern avoids updating Secrets in place entirely. Instead of updating `db-secret` when the password rotates, you create `db-secret-v1`, `db-secret-v2`, `db-secret-v3`, and update the Deployment to reference the new versioned name. The old Secret persists until you delete it, providing a rollback path.

With ESO, implement this by naming ExternalSecrets and their targets with version suffixes, or by letting ESO manage a single non-versioned Secret and relying on volume mount auto-update for pods that do not need an immediate restart.

## Cleanup

Delete the tutorial namespace and all resources within it:

```bash
kubectl delete namespace tutorial-secrets-management
```

Remove ESO from the cluster when finished (or leave it running for the exercises, since ESO is required for all homework exercises):

```bash
helm uninstall external-secrets -n external-secrets
kubectl delete namespace external-secrets
kubectl delete crd secretstores.external-secrets.io \
  clustersecretstores.external-secrets.io \
  externalsecrets.external-secrets.io
```

## Reference Commands

### ESO Installation

| Operation | Command |
|---|---|
| Add ESO Helm repo | `helm repo add external-secrets https://charts.external-secrets.io` |
| Install ESO | `helm install external-secrets external-secrets/external-secrets --namespace external-secrets --create-namespace --version 0.9.20 --wait` |
| Check ESO pods | `kubectl get pods -n external-secrets` |
| List ESO CRDs | `kubectl get crd \| grep external-secrets` |

### SecretStore and ExternalSecret Operations

| Operation | Command |
|---|---|
| Check SecretStore status | `kubectl get secretstore <name> -n <ns>` |
| Check ClusterSecretStore status | `kubectl get clustersecretstore <name>` |
| Check ExternalSecret status | `kubectl get externalsecret <name> -n <ns>` |
| Force immediate re-sync | `kubectl annotate externalsecret <name> force-sync=$(date +%s) -n <ns> --overwrite` |
| View ExternalSecret conditions | `kubectl describe externalsecret <name> -n <ns>` |
| Read synced Secret value | `kubectl get secret <target-name> -n <ns> -o jsonpath='{.data.<key>}' \| base64 -d` |

### Vault Dev Mode Operations

| Operation | Command |
|---|---|
| Write a KV secret | `kubectl exec -n <ns> vault -- sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault kv put secret/<path> key=value"` |
| Read a KV secret | `kubectl exec -n <ns> vault -- sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault kv get secret/<path>"` |
| Read a specific field | `kubectl exec -n <ns> vault -- sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault kv get -field=<field> secret/<path>"` |
| List secrets at a path | `kubectl exec -n <ns> vault -- sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault kv list secret/"` |
| Enable auth method | `kubectl exec -n <ns> vault -- sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault auth enable kubernetes"` |
