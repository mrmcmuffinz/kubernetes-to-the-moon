# Secrets Management Homework: External Secrets Operator and Vault

Work through the tutorial in `secrets-management-tutorial.md` before attempting these exercises. The tutorial installs the External Secrets Operator, explains the SecretStore and ExternalSecret resource model, and shows how to connect to both the fake provider and a Vault dev-mode pod. The exercises assume ESO is already installed in the `external-secrets` namespace. Install it once before starting:

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --version 0.9.20 \
  --wait
```

Exercises that require a Vault pod document the Vault setup in their own setup sections.

---

## Level 1: Basic SecretStore and ExternalSecret Patterns

### Exercise 1.1

**Objective:** Create a namespace-scoped SecretStore using the fake provider, create an ExternalSecret that syncs two keys from the store, and verify the target Kubernetes Secret is created with the correct values.

**Setup:**

```bash
kubectl create namespace ex-1-1
```

**Task:**

Create a SecretStore named `demo-store` in the `ex-1-1` namespace using the fake provider. The store should expose two keys: `/demo/username` with value `admin-user` and `/demo/password` with value `supersecretpassword`. Create an ExternalSecret named `demo-external-secret` in the same namespace that references `demo-store`, targets a Kubernetes Secret named `demo-credentials`, sets `creationPolicy: Owner`, sets `refreshInterval: 1h`, and maps both keys (`username` and `password`) into the target Secret using the key names `username` and `password` respectively.

**Verification:**

```bash
# Confirm the SecretStore is Ready
kubectl get secretstore demo-store -n ex-1-1 -o jsonpath='{.status.conditions[0].status}'
# Expected: True

# Confirm the ExternalSecret is Ready
kubectl get externalsecret demo-external-secret -n ex-1-1 -o jsonpath='{.status.conditions[0].status}'
# Expected: True

# Confirm the target Kubernetes Secret was created
kubectl get secret demo-credentials -n ex-1-1
# Expected: demo-credentials   Opaque   2   ...

# Verify the username value
kubectl get secret demo-credentials -n ex-1-1 -o jsonpath='{.data.username}' | base64 -d
# Expected: admin-user

# Verify the password value
kubectl get secret demo-credentials -n ex-1-1 -o jsonpath='{.data.password}' | base64 -d
# Expected: supersecretpassword

# Confirm ESO owns the Secret (ownerReferences should reference the ExternalSecret)
kubectl get secret demo-credentials -n ex-1-1 \
  -o jsonpath='{.metadata.ownerReferences[0].kind}'
# Expected: ExternalSecret
```

---

### Exercise 1.2

**Objective:** Create a ClusterSecretStore using the fake provider and an ExternalSecret in a different namespace that references it using `kind: ClusterSecretStore`.

**Setup:**

```bash
kubectl create namespace ex-1-2
```

**Task:**

Create a ClusterSecretStore named `cluster-fake-store` (note: ClusterSecretStore has no namespace) using the fake provider with one key: `/shared/service-token` with value `shared-token-value`. Create an ExternalSecret named `cluster-store-consumer` in the `ex-1-2` namespace that references `cluster-fake-store` with `kind: ClusterSecretStore`, targets a Kubernetes Secret named `shared-credentials`, and maps the `/shared/service-token` key to a Secret key named `service-token`. Verify the Secret is created with the correct value.

**Verification:**

```bash
# Confirm the ClusterSecretStore is Ready
kubectl get clustersecretstore cluster-fake-store \
  -o jsonpath='{.status.conditions[0].status}'
# Expected: True

# Confirm the ExternalSecret is Ready
kubectl get externalsecret cluster-store-consumer -n ex-1-2 \
  -o jsonpath='{.status.conditions[0].status}'
# Expected: True

# Confirm the target Secret was created in ex-1-2
kubectl get secret shared-credentials -n ex-1-2
# Expected: shared-credentials   Opaque   1   ...

# Verify the service-token value
kubectl get secret shared-credentials -n ex-1-2 \
  -o jsonpath='{.data.service-token}' | base64 -d
# Expected: shared-token-value
```

---

### Exercise 1.3

**Objective:** Create a SecretStore with multiple fake provider keys under a common path prefix and use `spec.dataFrom` with `extract` in an ExternalSecret to sync all keys at once into a Kubernetes Secret.

**Setup:**

```bash
kubectl create namespace ex-1-3
```

**Task:**

Create a SecretStore named `bulk-store` in the `ex-1-3` namespace using the fake provider with three keys: `/app/config/db-host` with value `postgres.default.svc`, `/app/config/db-port` with value `5432`, and `/app/config/db-name` with value `appdb`. Create an ExternalSecret named `bulk-external-secret` in the same namespace that references `bulk-store`, targets a Kubernetes Secret named `app-config-secret`, and uses `spec.dataFrom` with `extract` referencing the key `/app/config` to sync all three keys at once.

**Note:** With the fake provider's `extract`, keys are matched by prefix and the last path segment becomes the Kubernetes Secret key name. The keys `/app/config/db-host`, `/app/config/db-port`, and `/app/config/db-name` become `db-host`, `db-port`, and `db-name` in the resulting Secret.

**Verification:**

```bash
# Confirm the ExternalSecret is Ready
kubectl get externalsecret bulk-external-secret -n ex-1-3 \
  -o jsonpath='{.status.conditions[0].status}'
# Expected: True

# Confirm the target Secret was created with three keys
kubectl get secret app-config-secret -n ex-1-3 \
  -o jsonpath='{.data}' | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))"
# Expected: 3

# Verify each value
kubectl get secret app-config-secret -n ex-1-3 -o jsonpath='{.data.db-host}' | base64 -d
# Expected: postgres.default.svc

kubectl get secret app-config-secret -n ex-1-3 -o jsonpath='{.data.db-port}' | base64 -d
# Expected: 5432

kubectl get secret app-config-secret -n ex-1-3 -o jsonpath='{.data.db-name}' | base64 -d
# Expected: appdb
```

---

## Level 2: Re-sync, Vault Integration, and ESO Status

### Exercise 2.1

**Objective:** Update a fake provider's value in the SecretStore, trigger an immediate ESO re-sync using the force-sync annotation, and verify the Kubernetes Secret reflects the new value.

**Setup:**

```bash
kubectl create namespace ex-2-1

kubectl apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: rotation-store
  namespace: ex-2-1
spec:
  provider:
    fake:
      data:
        - key: /app/api-key
          value: initial-api-key-value
EOF

kubectl apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: rotation-external-secret
  namespace: ex-2-1
spec:
  secretStoreRef:
    name: rotation-store
    kind: SecretStore
  target:
    name: rotated-secret
    creationPolicy: Owner
  refreshInterval: 24h
  data:
    - secretKey: api-key
      remoteRef:
        key: /app/api-key
EOF
```

Wait for the initial sync to complete:

```bash
kubectl wait externalsecret rotation-external-secret -n ex-2-1 \
  --for=condition=Ready --timeout=30s
```

**Task:**

The initial sync creates the Kubernetes Secret with value `initial-api-key-value`. Simulate a secret rotation by patching the SecretStore to change the value of `/app/api-key` to `rotated-api-key-value`. The `refreshInterval` is `24h`, so a normal re-sync will not happen for many hours. Trigger an immediate re-sync using the `force-sync` annotation on the ExternalSecret. Verify the Kubernetes Secret is updated to the new value.

**Verification:**

```bash
# After applying the patch and forcing re-sync:
kubectl get secret rotated-secret -n ex-2-1 -o jsonpath='{.data.api-key}' | base64 -d
# Expected: rotated-api-key-value

# Confirm the ExternalSecret is still Ready after the re-sync
kubectl get externalsecret rotation-external-secret -n ex-2-1 \
  -o jsonpath='{.status.conditions[0].status}'
# Expected: True
```

---

### Exercise 2.2

**Objective:** Deploy Vault in dev mode as a pod in a namespace, store a secret in Vault using the vault CLI, and verify it is accessible by reading a specific field.

**Setup:**

```bash
kubectl create namespace ex-2-2
```

**Task:**

Create a Pod named `vault` in the `ex-2-2` namespace using the image `hashicorp/vault:1.17` with command `["vault", "server", "-dev", "-dev-root-token-id=root", "-dev-listen-address=0.0.0.0:8200"]` and a Service named `vault` in the same namespace exposing port 8200. Wait for the pod to become Ready. Then exec into the vault pod and write a KV secret at path `secret/payments/config` with two fields: `merchant-id` with value `merchant-12345` and `api-secret` with value `supersecretpaymentkey`. Read the secret back to confirm both fields are stored.

**Verification:**

```bash
# Confirm the vault pod is running
kubectl get pod vault -n ex-2-2
# Expected: vault   1/1   Running   ...

# Read the merchant-id field
kubectl exec -n ex-2-2 vault -- \
  sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root \
    vault kv get -field=merchant-id secret/payments/config"
# Expected: merchant-12345

# Read the api-secret field
kubectl exec -n ex-2-2 vault -- \
  sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root \
    vault kv get -field=api-secret secret/payments/config"
# Expected: supersecretpaymentkey
```

---

### Exercise 2.3

**Objective:** Create a Kubernetes Secret containing a Vault root token, create a SecretStore pointing to the Vault pod in the same namespace using token authentication, and create an ExternalSecret that syncs a Vault KV secret to a Kubernetes Secret.

**Setup:**

```bash
kubectl create namespace ex-2-3

# Deploy Vault dev mode (same pattern as exercise 2.2)
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: vault
  namespace: ex-2-3
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
EOF

kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: ex-2-3
spec:
  selector:
    app: vault
  ports:
    - port: 8200
      targetPort: 8200
EOF

kubectl wait pod vault -n ex-2-3 --for=condition=Ready --timeout=60s

# Store a secret in Vault
kubectl exec -n ex-2-3 vault -- \
  sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root \
    vault kv put secret/myservice/credentials \
      db-password=supersecretpassword \
      service-key=test-service-key"
```

**Task:**

Create a Kubernetes Secret named `vault-token` in the `ex-2-3` namespace with a key `token` and literal value `root`. Create a SecretStore named `vault-backend` in the `ex-2-3` namespace using the Vault provider, pointing to `http://vault.ex-2-3:8200`, with KV path `secret`, version `v2`, and token authentication referencing the `vault-token` Secret. Create an ExternalSecret named `service-external-secret` that syncs the `db-password` field from `myservice/credentials` in Vault to a Kubernetes Secret named `service-credentials`, with `refreshInterval: 5m`. Verify the sync.

**Verification:**

```bash
# Confirm the SecretStore is Ready
kubectl get secretstore vault-backend -n ex-2-3 \
  -o jsonpath='{.status.conditions[0].status}'
# Expected: True

# Confirm the ExternalSecret is Ready
kubectl get externalsecret service-external-secret -n ex-2-3 \
  -o jsonpath='{.status.conditions[0].status}'
# Expected: True

# Verify the synced Secret value
kubectl get secret service-credentials -n ex-2-3 \
  -o jsonpath='{.data.db-password}' | base64 -d
# Expected: supersecretpassword
```

---

## Level 3: Debugging Broken ESO Configurations

The exercises in this level present broken ESO configurations. Headings are bare. Read the ExternalSecret status and ESO controller logs to identify the root cause before attempting a fix.

### Exercise 3.1

**Objective:** The ExternalSecret below has a problem that prevents it from syncing. Diagnose the sync failure and fix the configuration so the target Secret is created with the correct values.

**Setup:**

```bash
kubectl create namespace ex-3-1

kubectl apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: app-store
  namespace: ex-3-1
spec:
  provider:
    fake:
      data:
        - key: /production/db-password
          value: prod-db-password-value
        - key: /production/api-key
          value: prod-api-key-value
EOF

kubectl apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-external-secret
  namespace: ex-3-1
spec:
  secretStoreRef:
    name: app-store
    kind: SecretStore
  target:
    name: app-credentials
    creationPolicy: Owner
  refreshInterval: 1h
  data:
    - secretKey: db-password
      remoteRef:
        key: /production/database/password
    - secretKey: api-key
      remoteRef:
        key: /production/api-key
EOF
```

**Task:**

The ExternalSecret above has a problem that prevents the target Secret from being created. Diagnose the sync failure by checking the ExternalSecret status and identifying which specific configuration is wrong. Fix the problem and verify the `app-credentials` Secret is created with both keys populated correctly.

**Verification:**

```bash
# After your fix, the ExternalSecret should be Ready
kubectl get externalsecret app-external-secret -n ex-3-1 \
  -o jsonpath='{.status.conditions[0].status}'
# Expected: True

# Both keys should be present in the synced Secret
kubectl get secret app-credentials -n ex-3-1 -o jsonpath='{.data.db-password}' | base64 -d
# Expected: prod-db-password-value

kubectl get secret app-credentials -n ex-3-1 -o jsonpath='{.data.api-key}' | base64 -d
# Expected: prod-api-key-value
```

---

### Exercise 3.2

**Objective:** The ExternalSecret below has a problem related to how it references the secret store. Diagnose the failure and fix it so the target Secret is created.

**Setup:**

```bash
kubectl create namespace ex-3-2

kubectl apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: cluster-app-store
spec:
  provider:
    fake:
      data:
        - key: /global/shared-secret
          value: cluster-wide-secret-value
EOF

kubectl apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: global-external-secret
  namespace: ex-3-2
spec:
  secretStoreRef:
    name: cluster-app-store
    kind: SecretStore
  target:
    name: global-credentials
    creationPolicy: Owner
  refreshInterval: 1h
  data:
    - secretKey: shared-secret
      remoteRef:
        key: /global/shared-secret
EOF
```

**Task:**

The ExternalSecret above has a problem that prevents it from finding the secret store. Diagnose the failure by examining the ExternalSecret status conditions, identify the root cause, fix the ExternalSecret, and verify the target Secret is created with the correct value.

**Verification:**

```bash
# After your fix, the ExternalSecret should be Ready
kubectl get externalsecret global-external-secret -n ex-3-2 \
  -o jsonpath='{.status.conditions[0].status}'
# Expected: True

# Verify the synced value
kubectl get secret global-credentials -n ex-3-2 \
  -o jsonpath='{.data.shared-secret}' | base64 -d
# Expected: cluster-wide-secret-value
```

---

### Exercise 3.3

**Objective:** The ExternalSecret below is configured and the SecretStore is Ready, but the target Kubernetes Secret is never created. Diagnose the problem and fix it so the Secret is created with the correct value.

**Setup:**

```bash
kubectl create namespace ex-3-3

kubectl apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: merge-store
  namespace: ex-3-3
spec:
  provider:
    fake:
      data:
        - key: /config/service-url
          value: http://internal-service:8080
EOF

kubectl apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: merge-external-secret
  namespace: ex-3-3
spec:
  secretStoreRef:
    name: merge-store
    kind: SecretStore
  target:
    name: config-secret
    creationPolicy: Merge
  refreshInterval: 1h
  data:
    - secretKey: service-url
      remoteRef:
        key: /config/service-url
EOF
```

**Task:**

The ExternalSecret above has a configuration problem that prevents the target Secret from being created even though the SecretStore is valid and the key exists. Diagnose why the Secret is not being created, fix the configuration, and verify the `config-secret` Secret exists with the correct value.

**Verification:**

```bash
# After your fix, the ExternalSecret should be Ready
kubectl get externalsecret merge-external-secret -n ex-3-3 \
  -o jsonpath='{.status.conditions[0].status}'
# Expected: True

# Verify the target Secret exists
kubectl get secret config-secret -n ex-3-3
# Expected: config-secret   Opaque   1   ...

# Verify the value
kubectl get secret config-secret -n ex-3-3 \
  -o jsonpath='{.data.service-url}' | base64 -d
# Expected: http://internal-service:8080
```

---

## Level 4: Vault Integration with Kubernetes Auth

**Note:** These exercises require a Vault pod in each exercise namespace. The setup sections document all Vault installation and configuration steps.

### Exercise 4.1

**Objective:** Deploy Vault dev mode, write multiple secrets to Vault, create a SecretStore pointing to Vault with token authentication, and sync all fields from one Vault KV path into a Kubernetes Secret using `dataFrom`.

**Setup:**

```bash
kubectl create namespace ex-4-1

kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: vault
  namespace: ex-4-1
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
EOF

kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: ex-4-1
spec:
  selector:
    app: vault
  ports:
    - port: 8200
      targetPort: 8200
EOF

kubectl wait pod vault -n ex-4-1 --for=condition=Ready --timeout=60s
```

**Task:**

Write a Vault KV secret at path `secret/webapp/full-config` with three fields: `db-url` with value `postgresql://db.internal:5432/webapp`, `redis-url` with value `redis://cache.internal:6379`, and `jwt-signing-key` with value `supersecretjwtsigningkey`. Create a Kubernetes Secret named `vault-root-token` in the `ex-4-1` namespace with key `token` and value `root`. Create a SecretStore named `vault-store` pointing to `http://vault.ex-4-1:8200` with KV path `secret`, version `v2`, and token auth. Create an ExternalSecret named `webapp-full-config` that syncs all three fields from `webapp/full-config` using `dataFrom` with `extract`, targeting a Kubernetes Secret named `webapp-config-secret`. Verify all three fields appear in the resulting Secret.

**Verification:**

```bash
# Confirm SecretStore is Ready
kubectl get secretstore vault-store -n ex-4-1 \
  -o jsonpath='{.status.conditions[0].status}'
# Expected: True

# Confirm ExternalSecret is Ready
kubectl get externalsecret webapp-full-config -n ex-4-1 \
  -o jsonpath='{.status.conditions[0].status}'
# Expected: True

kubectl get secret webapp-config-secret -n ex-4-1 -o jsonpath='{.data.db-url}' | base64 -d
# Expected: postgresql://db.internal:5432/webapp

kubectl get secret webapp-config-secret -n ex-4-1 -o jsonpath='{.data.redis-url}' | base64 -d
# Expected: redis://cache.internal:6379

kubectl get secret webapp-config-secret -n ex-4-1 -o jsonpath='{.data.jwt-signing-key}' | base64 -d
# Expected: supersecretjwtsigningkey
```

---

### Exercise 4.2

**Objective:** Sync a Vault secret into a Kubernetes Secret and mount it in a running pod as a volume. Verify the pod can read the secret value from the mounted file.

**Setup:**

```bash
kubectl create namespace ex-4-2

kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: vault
  namespace: ex-4-2
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
EOF

kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: ex-4-2
spec:
  selector:
    app: vault
  ports:
    - port: 8200
      targetPort: 8200
EOF

kubectl wait pod vault -n ex-4-2 --for=condition=Ready --timeout=60s

kubectl exec -n ex-4-2 vault -- \
  sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root \
    vault kv put secret/database/primary password=supersecretdbpassword"

kubectl create secret generic vault-token \
  --namespace ex-4-2 \
  --from-literal=token=root
```

**Task:**

Create a SecretStore named `db-vault-store` in the `ex-4-2` namespace pointing to `http://vault.ex-4-2:8200` with version `v2` and token auth using the `vault-token` Secret. Create an ExternalSecret named `db-external-secret` with `refreshInterval: 5m` that syncs the `password` field from `database/primary` in Vault to a Kubernetes Secret named `db-secret` with key `password`. Create a Pod named `db-client` in the `ex-4-2` namespace using the image `busybox:1.36` (with `command: ["sleep", "3600"]`) that mounts the `db-secret` Secret as a read-only volume at `/etc/db`. Verify the pod can read the database password from the mounted file.

**Verification:**

```bash
# Confirm ExternalSecret is Ready
kubectl get externalsecret db-external-secret -n ex-4-2 \
  -o jsonpath='{.status.conditions[0].status}'
# Expected: True

# Confirm the pod is Running
kubectl get pod db-client -n ex-4-2
# Expected: db-client   1/1   Running   ...

# Read the password from the mounted volume
kubectl exec db-client -n ex-4-2 -- cat /etc/db/password
# Expected: supersecretdbpassword
```

---

### Exercise 4.3

**Objective:** Update a Vault secret value, trigger an ESO re-sync, and verify a pod with a volume-mounted Secret picks up the new value from the updated file.

**Setup:**

```bash
kubectl create namespace ex-4-3

kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: vault
  namespace: ex-4-3
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
EOF

kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: ex-4-3
spec:
  selector:
    app: vault
  ports:
    - port: 8200
      targetPort: 8200
EOF

kubectl wait pod vault -n ex-4-3 --for=condition=Ready --timeout=60s

kubectl exec -n ex-4-3 vault -- \
  sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root \
    vault kv put secret/app/token value=initial-token-value"

kubectl create secret generic vault-token \
  --namespace ex-4-3 \
  --from-literal=token=root

kubectl apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: app-vault-store
  namespace: ex-4-3
spec:
  provider:
    vault:
      server: http://vault.ex-4-3:8200
      path: secret
      version: v2
      auth:
        tokenSecretRef:
          name: vault-token
          key: token
EOF

kubectl apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: token-external-secret
  namespace: ex-4-3
spec:
  secretStoreRef:
    name: app-vault-store
    kind: SecretStore
  target:
    name: app-token-secret
    creationPolicy: Owner
  refreshInterval: 5m
  data:
    - secretKey: token
      remoteRef:
        key: app/token
        property: value
EOF

kubectl wait externalsecret token-external-secret -n ex-4-3 \
  --for=condition=Ready --timeout=30s
```

Create the consumer pod:

```bash
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: token-reader
  namespace: ex-4-3
spec:
  containers:
    - name: reader
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: token-vol
          mountPath: /etc/tokens
          readOnly: true
  volumes:
    - name: token-vol
      secret:
        secretName: app-token-secret
EOF

kubectl wait pod token-reader -n ex-4-3 --for=condition=Ready --timeout=60s
```

**Task:**

The pod currently reads `initial-token-value` from the mounted file at `/etc/tokens/token`. Update the Vault secret at `secret/app/token` to change the `value` field to `rotated-token-value`. Trigger an immediate ESO re-sync using the force-sync annotation. After the Kubernetes Secret is updated, wait up to two minutes for the kubelet to propagate the change to the mounted file, then verify the pod reads the new value from `/etc/tokens/token` without a pod restart.

**Verification:**

```bash
# Before rotation: confirm initial value
kubectl exec token-reader -n ex-4-3 -- cat /etc/tokens/token
# Expected: initial-token-value

# After updating Vault and forcing re-sync: wait for kubelet propagation (up to 60s)
# Then verify the updated value is visible without restarting the pod
kubectl exec token-reader -n ex-4-3 -- cat /etc/tokens/token
# Expected: rotated-token-value

# Confirm the pod was never restarted
kubectl get pod token-reader -n ex-4-3 -o jsonpath='{.status.containerStatuses[0].restartCount}'
# Expected: 0
```

---

## Level 5: Debugging Stale Secrets and Rotation Failures

### Exercise 5.1

**Objective:** An application pod is reading a stale secret value. The external value has changed, but the Kubernetes Secret was not updated because of an ESO configuration problem. Diagnose the issue and fix it so the pod reads the current value.

**Setup:**

```bash
kubectl create namespace ex-5-1

kubectl apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: stale-store
  namespace: ex-5-1
spec:
  provider:
    fake:
      data:
        - key: /app/auth-token
          value: old-auth-token-value
EOF

kubectl apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: stale-external-secret
  namespace: ex-5-1
spec:
  secretStoreRef:
    name: stale-store
    kind: SecretStore
  target:
    name: auth-token-secret
    creationPolicy: Owner
  refreshInterval: 0
  data:
    - secretKey: auth-token
      remoteRef:
        key: /app/auth-token
EOF

kubectl wait externalsecret stale-external-secret -n ex-5-1 \
  --for=condition=Ready --timeout=30s

# Create a pod that reads the secret from a volume
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: auth-client
  namespace: ex-5-1
spec:
  containers:
    - name: client
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: auth-vol
          mountPath: /etc/auth
          readOnly: true
  volumes:
    - name: auth-vol
      secret:
        secretName: auth-token-secret
EOF

kubectl wait pod auth-client -n ex-5-1 --for=condition=Ready --timeout=60s

# The external value has "rotated" -- update the SecretStore to reflect the new value
kubectl patch secretstore stale-store -n ex-5-1 --type=merge -p '
{
  "spec": {
    "provider": {
      "fake": {
        "data": [
          {"key": "/app/auth-token", "value": "new-auth-token-value"}
        ]
      }
    }
  }
}'
```

**Task:**

The external value has been updated to `new-auth-token-value`, but the pod at `/etc/auth/auth-token` still reads `old-auth-token-value`. The setup above has a configuration problem that explains why the Kubernetes Secret was not updated after the external value changed. Diagnose the root cause by examining the ExternalSecret configuration and status, fix the problem, trigger a re-sync, and verify the pod reads the new value.

**Verification:**

```bash
# After your fix and re-sync, the pod should read the new value
kubectl exec auth-client -n ex-5-1 -- cat /etc/auth/auth-token
# Expected: new-auth-token-value

# The ExternalSecret should be Ready
kubectl get externalsecret stale-external-secret -n ex-5-1 \
  -o jsonpath='{.status.conditions[0].status}'
# Expected: True
```

---

### Exercise 5.2

**Objective:** Multiple configuration problems in an ESO setup prevent the target Secret from being created. Diagnose all issues and fix them so the ExternalSecret syncs successfully.

**Setup:**

```bash
kubectl create namespace ex-5-2

kubectl apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: multi-issue-store
  namespace: ex-5-2
spec:
  provider:
    fake:
      data:
        - key: /backend/db-password
          value: supersecretbackendpassword
        - key: /backend/cache-key
          value: supersecretcachekey
EOF

kubectl apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: multi-issue-external-secret
  namespace: ex-5-2
spec:
  secretStoreRef:
    name: multi-issue-store
    kind: ClusterSecretStore
  target:
    name: backend-credentials
    creationPolicy: Merge
  refreshInterval: 0
  data:
    - secretKey: db-password
      remoteRef:
        key: /backend/database/password
    - secretKey: cache-key
      remoteRef:
        key: /backend/cache-key
EOF
```

**Task:**

The ExternalSecret above has one or more problems that prevent the `backend-credentials` Secret from being created. Diagnose all problems by examining the ExternalSecret status conditions, identify the root cause of each issue, and apply the minimum set of fixes needed to make the ExternalSecret sync successfully and create the `backend-credentials` Secret with both keys populated.

**Verification:**

```bash
# After all fixes, the ExternalSecret should be Ready
kubectl get externalsecret multi-issue-external-secret -n ex-5-2 \
  -o jsonpath='{.status.conditions[0].status}'
# Expected: True

# Both values should be present
kubectl get secret backend-credentials -n ex-5-2 \
  -o jsonpath='{.data.db-password}' | base64 -d
# Expected: supersecretbackendpassword

kubectl get secret backend-credentials -n ex-5-2 \
  -o jsonpath='{.data.cache-key}' | base64 -d
# Expected: supersecretcachekey
```

---

### Exercise 5.3

**Objective:** An application Deployment references a Kubernetes Secret that was synced by ESO from Vault. The Vault value has been rotated but the application is still reading the old value despite ESO showing the ExternalSecret as Ready. Diagnose why the pod is not seeing the updated value and fix the configuration to ensure the application picks up the new secret.

**Setup:**

```bash
kubectl create namespace ex-5-3

kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: vault
  namespace: ex-5-3
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
EOF

kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: ex-5-3
spec:
  selector:
    app: vault
  ports:
    - port: 8200
      targetPort: 8200
EOF

kubectl wait pod vault -n ex-5-3 --for=condition=Ready --timeout=60s

kubectl exec -n ex-5-3 vault -- \
  sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root \
    vault kv put secret/app/signing-key value=original-signing-key"

kubectl create secret generic vault-token \
  --namespace ex-5-3 \
  --from-literal=token=root

kubectl apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: signing-vault-store
  namespace: ex-5-3
spec:
  provider:
    vault:
      server: http://vault.ex-5-3:8200
      path: secret
      version: v2
      auth:
        tokenSecretRef:
          name: vault-token
          key: token
EOF

kubectl apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: signing-key-external-secret
  namespace: ex-5-3
spec:
  secretStoreRef:
    name: signing-vault-store
    kind: SecretStore
  target:
    name: signing-key-secret
    creationPolicy: Owner
  refreshInterval: 5m
  data:
    - secretKey: signing-key
      remoteRef:
        key: app/signing-key
        property: value
EOF

kubectl wait externalsecret signing-key-external-secret -n ex-5-3 \
  --for=condition=Ready --timeout=30s

# Create a Deployment that reads the signing key as an env var
kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: signing-service
  namespace: ex-5-3
spec:
  replicas: 1
  selector:
    matchLabels:
      app: signing-service
  template:
    metadata:
      labels:
        app: signing-service
    spec:
      containers:
        - name: service
          image: busybox:1.36
          command: ["sleep", "3600"]
          env:
            - name: SIGNING_KEY
              valueFrom:
                secretKeyRef:
                  name: signing-key-secret
                  key: signing-key
EOF

kubectl wait deployment signing-service -n ex-5-3 \
  --for=condition=Available --timeout=60s

# Rotate the Vault secret
kubectl exec -n ex-5-3 vault -- \
  sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root \
    vault kv put secret/app/signing-key value=rotated-signing-key"

# Force ESO to re-sync immediately
kubectl annotate externalsecret signing-key-external-secret \
  force-sync=$(date +%s) \
  -n ex-5-3 \
  --overwrite

sleep 10
```

**Task:**

The Vault secret has been rotated and ESO has re-synced the Kubernetes Secret successfully. However, the application pod still reads the old value `original-signing-key` from the `SIGNING_KEY` environment variable. Diagnose why the pod is not seeing the updated value and fix the configuration so the application reads `rotated-signing-key`. The pod must reflect the new value after your fix.

**Verification:**

```bash
# After your fix, the pod should read the new signing key
POD=$(kubectl get pods -n ex-5-3 -l app=signing-service -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -n ex-5-3 -- printenv SIGNING_KEY
# Expected: rotated-signing-key

# Confirm the Kubernetes Secret is up to date
kubectl get secret signing-key-secret -n ex-5-3 \
  -o jsonpath='{.data.signing-key}' | base64 -d
# Expected: rotated-signing-key
```

---

## Cleanup

Delete all exercise namespaces when finished:

```bash
kubectl delete namespace ex-1-1 ex-1-2 ex-1-3
kubectl delete namespace ex-2-1 ex-2-2 ex-2-3
kubectl delete namespace ex-3-1 ex-3-2 ex-3-3
kubectl delete namespace ex-4-1 ex-4-2 ex-4-3
kubectl delete namespace ex-5-1 ex-5-2 ex-5-3

# Remove the ClusterSecretStore created in exercise 1.2
kubectl delete clustersecretstore cluster-fake-store --ignore-not-found

# Remove the ClusterSecretStore created in exercise 3.2 if it still exists
kubectl delete clustersecretstore cluster-app-store --ignore-not-found
```

Uninstall ESO if you are done with all secrets-management exercises:

```bash
helm uninstall external-secrets -n external-secrets
kubectl delete namespace external-secrets
```

## Key Takeaways

These exercises reinforce four ESO skills. First, the three-object pattern: SecretStore (or ClusterSecretStore) defines the connection, ExternalSecret defines the mapping, and ESO creates the Kubernetes Secret. Second, the SecretStore kind matters: using `SecretStore` when the store is a `ClusterSecretStore` is a silent failure that takes time to diagnose from the status conditions. Third, `creationPolicy` determines lifecycle behavior: `Owner` lets ESO create and own the Secret, `Merge` requires the Secret to pre-exist, and `None` means ESO never writes the Secret. Fourth, `refreshInterval: 0` disables automatic re-syncing entirely, which is appropriate only when a force-sync annotation workflow is used explicitly.
