# Secrets Management Homework Answers: External Secrets Operator and Vault

---

## Exercise 1.1 Solution

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: demo-store
  namespace: ex-1-1
spec:
  provider:
    fake:
      data:
        - key: /demo/username
          value: admin-user
        - key: /demo/password
          value: supersecretpassword
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: demo-external-secret
  namespace: ex-1-1
spec:
  secretStoreRef:
    name: demo-store
    kind: SecretStore
  target:
    name: demo-credentials
    creationPolicy: Owner
  refreshInterval: 1h
  data:
    - secretKey: username
      remoteRef:
        key: /demo/username
    - secretKey: password
      remoteRef:
        key: /demo/password
```

Apply with `kubectl apply -f -`. ESO creates the Kubernetes Secret within a few seconds of the ExternalSecret being processed. The Secret's `ownerReferences` field is set to the ExternalSecret, which means deleting the ExternalSecret will also delete the Secret (since ESO is the owner).

---

## Exercise 1.2 Solution

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: cluster-fake-store
spec:
  provider:
    fake:
      data:
        - key: /shared/service-token
          value: shared-token-value
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: cluster-store-consumer
  namespace: ex-1-2
spec:
  secretStoreRef:
    name: cluster-fake-store
    kind: ClusterSecretStore
  target:
    name: shared-credentials
    creationPolicy: Owner
  refreshInterval: 1h
  data:
    - secretKey: service-token
      remoteRef:
        key: /shared/service-token
```

The critical difference from exercise 1.1 is `kind: ClusterSecretStore` in the `secretStoreRef`. The ClusterSecretStore has no `metadata.namespace` because it is cluster-scoped. An ExternalSecret in any namespace can reference it using `kind: ClusterSecretStore`.

---

## Exercise 1.3 Solution

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: bulk-store
  namespace: ex-1-3
spec:
  provider:
    fake:
      data:
        - key: /app/config/db-host
          value: postgres.default.svc
        - key: /app/config/db-port
          value: "5432"
        - key: /app/config/db-name
          value: appdb
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: bulk-external-secret
  namespace: ex-1-3
spec:
  secretStoreRef:
    name: bulk-store
    kind: SecretStore
  target:
    name: app-config-secret
    creationPolicy: Owner
  refreshInterval: 1h
  dataFrom:
    - extract:
        key: /app/config
```

With `dataFrom.extract`, ESO fetches all keys in the fake provider that share the specified prefix and maps each key's last path segment to a key in the resulting Secret. The key `/app/config/db-host` becomes the Secret key `db-host`, `/app/config/db-port` becomes `db-port`, and so on. This is more concise than listing each key in `spec.data` when an application has many configuration values stored at the same path.

---

## Exercise 2.1 Solution

The secret rotation requires two steps: updating the external value and triggering an immediate re-sync.

**Step 1, Patch the SecretStore to update the value:**

```bash
kubectl patch secretstore rotation-store -n ex-2-1 --type=merge -p '
{
  "spec": {
    "provider": {
      "fake": {
        "data": [
          {"key": "/app/api-key", "value": "rotated-api-key-value"}
        ]
      }
    }
  }
}'
```

**Step 2, Force an immediate re-sync:**

```bash
kubectl annotate externalsecret rotation-external-secret \
  force-sync=$(date +%s) \
  -n ex-2-1 \
  --overwrite
```

**Step 3, Wait briefly and verify:**

```bash
sleep 5
kubectl get secret rotated-secret -n ex-2-1 -o jsonpath='{.data.api-key}' | base64 -d
# Expected: rotated-api-key-value
```

Without the force-sync annotation, the next re-sync would not occur for 24 hours (the configured refreshInterval). The `force-sync` annotation value must change each time (using `$(date +%s)` provides a unique timestamp) to trigger a new reconcile. Setting it to the same value twice does not trigger a second sync.

---

## Exercise 2.2 Solution

**Create the Vault pod and Service:**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: vault
  namespace: ex-2-2
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
---
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: ex-2-2
spec:
  selector:
    app: vault
  ports:
    - port: 8200
      targetPort: 8200
```

**Store the secret:**

```bash
kubectl wait pod vault -n ex-2-2 --for=condition=Ready --timeout=60s

kubectl exec -n ex-2-2 vault -- \
  sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root \
    vault kv put secret/payments/config \
      merchant-id=merchant-12345 \
      api-secret=supersecretpaymentkey"
```

**Verify:**

```bash
kubectl exec -n ex-2-2 vault -- \
  sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root \
    vault kv get -field=merchant-id secret/payments/config"
# Output: merchant-12345
```

Vault dev mode starts with a KV v2 engine at the `secret/` mount automatically. The `vault kv put` command writes to this engine. In KV v2, each write creates a new version; `vault kv get` returns the latest version by default.

---

## Exercise 2.3 Solution

```bash
kubectl create secret generic vault-token \
  --namespace ex-2-3 \
  --from-literal=token=root
```

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: ex-2-3
spec:
  provider:
    vault:
      server: http://vault.ex-2-3:8200
      path: secret
      version: v2
      auth:
        tokenSecretRef:
          name: vault-token
          key: token
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: service-external-secret
  namespace: ex-2-3
spec:
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: service-credentials
    creationPolicy: Owner
  refreshInterval: 5m
  data:
    - secretKey: db-password
      remoteRef:
        key: myservice/credentials
        property: db-password
```

The `remoteRef.key` is `myservice/credentials` (the path after the mount point, without `data/`). The `remoteRef.property` is `db-password` (one field within the KV secret at that path). ESO automatically constructs the full Vault API path `secret/data/myservice/credentials` for KV v2 reads.

---

## Exercise 3.1 Solution

### Diagnosis

Check the ExternalSecret status:

```bash
kubectl describe externalsecret app-external-secret -n ex-3-1
```

Look at the `Status` section. The `Conditions` will show `Ready: False` with a message like `key /production/database/password does not exist` or a similar key-not-found error.

Compare the remoteRef key in the ExternalSecret to the keys defined in the SecretStore:

```bash
kubectl get secretstore app-store -n ex-3-1 -o yaml
```

The SecretStore defines `/production/db-password`. The ExternalSecret references `/production/database/password`. These do not match: `db-password` vs `database/password`.

### What the Bug Is and Why It Happens

The `remoteRef.key` in the ExternalSecret must exactly match a key in the fake provider's `data` list. The ExternalSecret used the path `/production/database/password`, which is a non-existent key (the store has `/production/db-password`). This is a common mistake when the external store has a flat key naming convention but the ExternalSecret was written expecting a hierarchical path. ESO reports a sync failure in the ExternalSecret status with a message indicating the key was not found in the provider.

### The Fix

Edit the ExternalSecret to use the correct key path:

```bash
kubectl edit externalsecret app-external-secret -n ex-3-1
```

Change:

```yaml
      remoteRef:
        key: /production/database/password
```

To:

```yaml
      remoteRef:
        key: /production/db-password
```

Or apply a patch:

```bash
kubectl patch externalsecret app-external-secret -n ex-3-1 --type=json \
  -p '[{"op": "replace", "path": "/spec/data/0/remoteRef/key", "value": "/production/db-password"}]'
```

After the fix, trigger a re-sync:

```bash
kubectl annotate externalsecret app-external-secret \
  force-sync=$(date +%s) -n ex-3-1 --overwrite
```

---

## Exercise 3.2 Solution

### Diagnosis

Check the ExternalSecret status:

```bash
kubectl describe externalsecret global-external-secret -n ex-3-2
```

The `Conditions` will show `Ready: False` with a message like `SecretStore "cluster-app-store" not found in namespace "ex-3-2"`. ESO looks for a namespace-scoped SecretStore named `cluster-app-store` in the `ex-3-2` namespace, but no such resource exists, the resource that exists is a ClusterSecretStore (cluster-scoped).

Verify which resource type was created:

```bash
kubectl get secretstore -n ex-3-2
# Expected: No resources found

kubectl get clustersecretstore cluster-app-store
# Expected: cluster-app-store   ...   Ready
```

### What the Bug Is and Why It Happens

The `secretStoreRef.kind` field tells ESO which API type to look up. With `kind: SecretStore`, ESO looks for a namespace-scoped SecretStore in the same namespace as the ExternalSecret. With `kind: ClusterSecretStore`, ESO looks for a cluster-scoped ClusterSecretStore by name, without regard to namespace. Using the wrong `kind` causes a silent lookup failure: no error is reported at apply time, but the ExternalSecret goes NotReady with a "not found" message that requires reading the status to diagnose.

### The Fix

Patch the ExternalSecret to use `kind: ClusterSecretStore`:

```bash
kubectl patch externalsecret global-external-secret -n ex-3-2 --type=merge \
  -p '{"spec": {"secretStoreRef": {"kind": "ClusterSecretStore"}}}'

kubectl annotate externalsecret global-external-secret \
  force-sync=$(date +%s) -n ex-3-2 --overwrite
```

---

## Exercise 3.3 Solution

### Diagnosis

Check the ExternalSecret status:

```bash
kubectl describe externalsecret merge-external-secret -n ex-3-3
```

The `Conditions` will show `Ready: False` with a message such as `secret config-secret not found` or `target secret does not exist for Merge policy`. The SecretStore is valid (confirmed by `kubectl get secretstore merge-store -n ex-3-3` showing `READY: True`), and the remote key exists, so the problem is in the target configuration.

Look at the ExternalSecret spec:

```bash
kubectl get externalsecret merge-external-secret -n ex-3-3 \
  -o jsonpath='{.spec.target.creationPolicy}'
# Output: Merge
```

Check whether the target Secret exists:

```bash
kubectl get secret config-secret -n ex-3-3
# Expected: Error from server (NotFound): ...
```

### What the Bug Is and Why It Happens

`creationPolicy: Merge` tells ESO to merge the synced keys into an already-existing Kubernetes Secret. It will not create the Secret from scratch. If the target Secret does not exist, ESO cannot proceed and reports a sync failure. The `Merge` policy is used when the target Secret contains keys from multiple ExternalSecrets or has some keys managed manually; it requires the Secret to be pre-created (usually with only the externally unmanaged keys). Using `Merge` when you actually want ESO to own and create the Secret is a common first-time ESO mistake because `Merge` sounds like it might be more flexible than `Owner`, when in practice `Owner` is the correct default for most use cases.

### The Fix

Change `creationPolicy` from `Merge` to `Owner`:

```bash
kubectl patch externalsecret merge-external-secret -n ex-3-3 --type=merge \
  -p '{"spec": {"target": {"creationPolicy": "Owner"}}}'

kubectl annotate externalsecret merge-external-secret \
  force-sync=$(date +%s) -n ex-3-3 --overwrite
```

Alternatively, if the intent was truly to use `Merge` (for example, to merge into a pre-existing Secret), create the target Secret first:

```bash
kubectl create secret generic config-secret --namespace ex-3-3 --from-literal=placeholder=x
```

But for this exercise, changing to `Owner` is the correct fix.

---

## Exercise 4.1 Solution

**Write the Vault secrets:**

```bash
kubectl exec -n ex-4-1 vault -- \
  sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root \
    vault kv put secret/webapp/full-config \
      db-url='postgresql://db.internal:5432/webapp' \
      redis-url='redis://cache.internal:6379' \
      jwt-signing-key=supersecretjwtsigningkey"
```

**Create the token Secret, SecretStore, and ExternalSecret:**

```bash
kubectl create secret generic vault-root-token \
  --namespace ex-4-1 \
  --from-literal=token=root
```

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-store
  namespace: ex-4-1
spec:
  provider:
    vault:
      server: http://vault.ex-4-1:8200
      path: secret
      version: v2
      auth:
        tokenSecretRef:
          name: vault-root-token
          key: token
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: webapp-full-config
  namespace: ex-4-1
spec:
  secretStoreRef:
    name: vault-store
    kind: SecretStore
  target:
    name: webapp-config-secret
    creationPolicy: Owner
  refreshInterval: 5m
  dataFrom:
    - extract:
        key: webapp/full-config
```

With `dataFrom.extract` and Vault KV v2, the `key` is the path after the mount point (`webapp/full-config`). ESO fetches all fields at `secret/data/webapp/full-config` and maps each field name directly as a Secret key. The resulting Secret has keys `db-url`, `redis-url`, and `jwt-signing-key`.

---

## Exercise 4.2 Solution

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: db-vault-store
  namespace: ex-4-2
spec:
  provider:
    vault:
      server: http://vault.ex-4-2:8200
      path: secret
      version: v2
      auth:
        tokenSecretRef:
          name: vault-token
          key: token
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-external-secret
  namespace: ex-4-2
spec:
  secretStoreRef:
    name: db-vault-store
    kind: SecretStore
  target:
    name: db-secret
    creationPolicy: Owner
  refreshInterval: 5m
  data:
    - secretKey: password
      remoteRef:
        key: database/primary
        property: password
---
apiVersion: v1
kind: Pod
metadata:
  name: db-client
  namespace: ex-4-2
spec:
  containers:
    - name: client
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: db-vol
          mountPath: /etc/db
          readOnly: true
  volumes:
    - name: db-vol
      secret:
        secretName: db-secret
```

Wait for the ExternalSecret to sync before applying the pod manifest, so the Secret exists when the pod starts. Alternatively, if the pod starts before the Secret exists, it will be stuck in Pending with a "secret not found" event. The fix in that case is to wait for the Secret and then allow the pod to start.

---

## Exercise 4.3 Solution

**Update the Vault secret:**

```bash
kubectl exec -n ex-4-3 vault -- \
  sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root \
    vault kv put secret/app/token value=rotated-token-value"
```

**Trigger an immediate ESO re-sync:**

```bash
kubectl annotate externalsecret token-external-secret \
  force-sync=$(date +%s) \
  -n ex-4-3 \
  --overwrite
```

**Wait for the Kubernetes Secret to be updated and the kubelet to propagate the change:**

```bash
sleep 15

kubectl get secret app-token-secret -n ex-4-3 \
  -o jsonpath='{.data.token}' | base64 -d
# Expected: rotated-token-value
```

**Wait for the kubelet to propagate to the mounted file (up to 60s):**

```bash
for i in $(seq 1 12); do
  VALUE=$(kubectl exec token-reader -n ex-4-3 -- cat /etc/tokens/token 2>/dev/null)
  if [ "$VALUE" = "rotated-token-value" ]; then
    echo "Updated: $VALUE"
    break
  fi
  echo "Still old value: $VALUE, waiting..."
  sleep 5
done
```

The kubelet syncs volume-mounted Secrets periodically (default sync period is configurable, typically around 60 seconds in kind). The update does not require a pod restart. This is the key operational advantage of volume-mounted Secrets over environment variable injection for secret rotation.

---

## Exercise 5.1 Solution

### Diagnosis

Check the ExternalSecret configuration:

```bash
kubectl get externalsecret stale-external-secret -n ex-5-1 \
  -o jsonpath='{.spec.refreshInterval}'
# Output: 0
```

The `refreshInterval` is `0`. In ESO, a `refreshInterval` of `0` means the ExternalSecret syncs exactly once at creation time and then never re-syncs. This is distinct from not setting a refreshInterval (which defaults to `1h`) or setting it to a very long value. With `refreshInterval: 0`, the ExternalSecret will show as `Ready: True` (the initial sync succeeded), but the Kubernetes Secret will never be updated when the external value changes, regardless of what changes are made to the SecretStore.

### What the Bug Is and Why It Happens

The `refreshInterval: 0` setting disables automatic re-syncing. It is useful in scenarios where the external value should only be fetched once (for example, during cluster bootstrap) or where re-syncs are triggered entirely via the force-sync annotation. In this exercise, the intent was for the Secret to be updated when the external value rotates, which requires a non-zero refreshInterval. The `0` value is easy to mistake for "no interval configured" when it actually means "never re-sync."

### The Fix

Change the `refreshInterval` to a reasonable value:

```bash
kubectl patch externalsecret stale-external-secret -n ex-5-1 --type=merge \
  -p '{"spec": {"refreshInterval": "5m"}}'
```

Trigger an immediate re-sync to pick up the already-changed value:

```bash
kubectl annotate externalsecret stale-external-secret \
  force-sync=$(date +%s) -n ex-5-1 --overwrite

sleep 10
```

Wait for the kubelet to propagate the updated Kubernetes Secret to the mounted volume:

```bash
for i in $(seq 1 12); do
  VALUE=$(kubectl exec auth-client -n ex-5-1 -- cat /etc/auth/auth-token 2>/dev/null)
  if [ "$VALUE" = "new-auth-token-value" ]; then
    echo "Updated"
    break
  fi
  sleep 5
done
```

---

## Exercise 5.2 Solution

### Diagnosis

Check the ExternalSecret status conditions:

```bash
kubectl describe externalsecret multi-issue-external-secret -n ex-5-2
```

The status will show multiple problems:

1. `SecretStore "multi-issue-store" not found` (or similar), the ExternalSecret uses `kind: ClusterSecretStore` but the store is a namespace-scoped SecretStore.
2. Even if the store were found, `refreshInterval: 0` disables automatic re-syncing.
3. `creationPolicy: Merge` with no pre-existing target Secret would cause a sync failure once connectivity is established.
4. The key `/backend/database/password` does not exist in the SecretStore (the store has `/backend/db-password`).

### What the Bug Is and Why It Happens

There are four distinct problems in this ExternalSecret:
- Wrong `secretStoreRef.kind`: the store is a `SecretStore`, not a `ClusterSecretStore`.
- Wrong `remoteRef.key` for db-password: the store has `/backend/db-password`, not `/backend/database/password`.
- `creationPolicy: Merge` with no pre-existing Secret.
- `refreshInterval: 0` disabling future re-syncs.

### The Fix

Apply a corrected ExternalSecret (using `kubectl apply` to replace the existing one):

```bash
kubectl apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: multi-issue-external-secret
  namespace: ex-5-2
spec:
  secretStoreRef:
    name: multi-issue-store
    kind: SecretStore
  target:
    name: backend-credentials
    creationPolicy: Owner
  refreshInterval: 5m
  data:
    - secretKey: db-password
      remoteRef:
        key: /backend/db-password
    - secretKey: cache-key
      remoteRef:
        key: /backend/cache-key
EOF

kubectl annotate externalsecret multi-issue-external-secret \
  force-sync=$(date +%s) -n ex-5-2 --overwrite
```

---

## Exercise 5.3 Solution

### Diagnosis

Confirm the Kubernetes Secret is up to date:

```bash
kubectl get secret signing-key-secret -n ex-5-3 \
  -o jsonpath='{.data.signing-key}' | base64 -d
# Output: rotated-signing-key
```

The Secret has the new value. Now check the running pod:

```bash
POD=$(kubectl get pods -n ex-5-3 -l app=signing-service -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -n ex-5-3 -- printenv SIGNING_KEY
# Output: original-signing-key
```

The pod still shows the old value despite the Secret being updated. The Deployment uses the Secret as an environment variable (`env.valueFrom.secretKeyRef`). Environment variables in a running container are set once at pod startup from the Secret's value at that moment. When the Kubernetes Secret is updated, the running pod's environment variables are NOT updated. Only a pod restart causes the container to re-read the Secret for environment variable injection.

### What the Bug Is and Why It Happens

This is the fundamental limitation of environment variable injection for secrets: the value is baked into the container process's environment at startup and does not change while the pod is running, even if the source Secret changes. Volume-mounted Secrets, by contrast, are synced by the kubelet and update the files on disk within the kubelet's sync period without a pod restart. For applications that must pick up rotated secrets promptly, volume mounts are strongly preferred. For environment-variable-based injection, the application must be restarted to pick up the new value.

### The Fix

Trigger a rolling restart of the Deployment to force the pods to re-read the updated Secret:

```bash
kubectl rollout restart deployment/signing-service -n ex-5-3
kubectl rollout status deployment/signing-service -n ex-5-3
```

After the rollout completes, the new pod starts with the current value of the Secret:

```bash
POD=$(kubectl get pods -n ex-5-3 -l app=signing-service -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -n ex-5-3 -- printenv SIGNING_KEY
# Expected: rotated-signing-key
```

To prevent this scenario in the future, switch the Deployment to use a volume-mounted Secret instead of an environment variable, so future rotations propagate automatically.

---

## Common Mistakes

**Mistake 1: Using the wrong secretStoreRef.kind and missing the silent failure.**

Setting `kind: SecretStore` when the store is a `ClusterSecretStore` (or vice versa) causes ESO to look in the wrong scope and return a "not found" error in the ExternalSecret status. No error is reported at `kubectl apply` time, the object is accepted by the API server and the failure only appears when checking `kubectl describe externalsecret`. On the exam, always verify the ExternalSecret is `Ready: True` after applying; a "not found" status message on the store is usually a kind mismatch.

**Mistake 2: Using creationPolicy: Merge when no target Secret pre-exists.**

The `Merge` creation policy is for merging synced keys into a Secret that already exists and is partially managed outside ESO. With `Merge`, ESO will never create the Secret from scratch; if the target does not exist, the ExternalSecret reports a sync failure indefinitely. The correct default for most use cases is `Owner`, where ESO creates, owns, and manages the full lifecycle of the target Secret. Use `Merge` only when you explicitly need to combine externally synced keys with keys that are managed separately.

**Mistake 3: Setting refreshInterval: 0 and expecting automatic re-syncs.**

`refreshInterval: 0` means "sync once and never again." This is distinct from not specifying the field (which defaults to `1h`) or from setting a very large value like `24h`. When the external value rotates and the Kubernetes Secret does not update, `refreshInterval: 0` is the most common silent culprit. The ExternalSecret shows `Ready: True` (the original sync succeeded) and no error is visible, making the problem hard to spot without specifically checking the refreshInterval value. Set an explicit refreshInterval appropriate to the rotation frequency of your external store.

**Mistake 4: Expecting environment variable injection to update without a pod restart.**

Volume-mounted Secrets are updated by the kubelet when the Kubernetes Secret changes, within the kubelet sync period (typically one minute). Environment variable injection is not. An application that reads a Secret via `env.valueFrom.secretKeyRef` will continue reading the value that was in the Secret when the pod started, regardless of how many times the Secret is updated. On the exam, questions about secret rotation and whether pods need restarting are specifically testing this distinction. Volume mounts are always the right choice when the application must pick up rotated values without downtime.

**Mistake 5: Wrong remoteRef.key format for Vault KV v2.**

With Vault KV v2 and the ESO Vault provider, the `remoteRef.key` is the path after the mount point, without a leading `data/` segment. ESO adds `data/` internally when constructing the Vault API path for KV v2. If you set `remoteRef.key: secret/data/myapp/config` instead of `remoteRef.key: myapp/config` (with `spec.provider.vault.path: secret`), ESO constructs the wrong API path and the read fails with a 404 or path-not-found error. A related mistake is setting `version: v1` when the Vault mount is KV v2, which causes ESO to omit `data/` in the path and read from the wrong endpoint.

---

## Verification Commands Cheat Sheet

### ESO Status

| Use Case | Command |
|---|---|
| Check SecretStore status | `kubectl get secretstore <name> -n <ns>` |
| Check ClusterSecretStore status | `kubectl get clustersecretstore <name>` |
| Check ExternalSecret ready status | `kubectl get externalsecret <name> -n <ns>` |
| View ExternalSecret conditions | `kubectl describe externalsecret <name> -n <ns>` |
| View ExternalSecret refresh time | `kubectl get externalsecret <name> -n <ns> -o jsonpath='{.status.refreshTime}'` |
| Force immediate re-sync | `kubectl annotate externalsecret <name> force-sync=$(date +%s) -n <ns> --overwrite` |

### Synced Secrets

| Use Case | Command |
|---|---|
| Check if target Secret exists | `kubectl get secret <target-name> -n <ns>` |
| Decode a synced Secret value | `kubectl get secret <target-name> -n <ns> -o jsonpath='{.data.<key>}' \| base64 -d` |
| Count keys in a Secret | `kubectl get secret <target-name> -n <ns> -o jsonpath='{.data}' \| python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))"` |
| Check who owns the Secret | `kubectl get secret <target-name> -n <ns> -o jsonpath='{.metadata.ownerReferences[0].kind}'` |

### Vault Dev Mode

| Use Case | Command |
|---|---|
| Write a KV secret | `kubectl exec -n <ns> vault -- sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault kv put secret/<path> key=value"` |
| Read a KV secret (all fields) | `kubectl exec -n <ns> vault -- sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault kv get secret/<path>"` |
| Read one field | `kubectl exec -n <ns> vault -- sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault kv get -field=<field> secret/<path>"` |
| Update a KV secret | `kubectl exec -n <ns> vault -- sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault kv put secret/<path> key=new-value"` |

### Pod and Deployment Operations

| Use Case | Command |
|---|---|
| Read env var in running pod | `kubectl exec <pod> -n <ns> -- printenv <VAR>` |
| Read volume-mounted secret file | `kubectl exec <pod> -n <ns> -- cat /etc/secrets/<key>` |
| Trigger deployment rollout | `kubectl rollout restart deployment/<name> -n <ns>` |
| Wait for rollout to complete | `kubectl rollout status deployment/<name> -n <ns>` |
| Check pod restart count | `kubectl get pod <name> -n <ns> -o jsonpath='{.status.containerStatuses[0].restartCount}'` |
