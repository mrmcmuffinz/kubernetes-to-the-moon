# Secrets Management Homework: etcd Encryption at Rest

Work through the tutorial in `secrets-management-tutorial.md` before attempting these exercises. The tutorial explains etcdctl access patterns, EncryptionConfiguration file structure, and kube-apiserver manifest editing, all of which are required for the exercises below. Each exercise creates its own namespace and is designed to be self-contained, but exercises in Level 2 and Level 4 that involve the kube-apiserver manifest must be attempted on a clean cluster (or after reverting the manifest to its original state from the previous exercise).

## Global Setup

Confirm your kind cluster is running and kubectl is configured:

```bash
kubectl cluster-info
# Expected: "Kubernetes control plane is running at https://127.0.0.1:..."

kubectl get nodes
# Expected: kind-control-plane   Ready   control-plane   ...
```

If any Level 2 or Level 4 exercise requires a fresh cluster state, recreate the cluster:

```bash
kind delete cluster && kind create cluster
```

---

## Level 1: Reading Secrets from etcd and Basic Exposure Patterns

### Exercise 1.1

**Objective:** Create a Secret in the cluster, then use etcdctl to read its value directly from etcd and confirm the value is stored as base64-encoded plaintext with no encryption.

**Setup:**

```bash
kubectl create namespace ex-1-1
```

**Task:**

Create a Secret named `vault-token` in the `ex-1-1` namespace with a single key `token` and value `dGVzdC1zZWNyZXQ=` as the literal base64-encoded value. Then use etcdctl (exec into the etcd pod) to read the Secret directly from etcd at the path `/registry/secrets/ex-1-1/vault-token`. Confirm the base64 string is visible in the etcd output. Finally, decode the value using `base64 -d` and show that it recovers the original string.

**Verification:**

```bash
# Confirm the Secret exists via the API
kubectl get secret vault-token -n ex-1-1
# Expected: vault-token   Opaque   1   ...

# Read the Secret value through the API (shows base64)
kubectl get secret vault-token -n ex-1-1 -o jsonpath='{.data.token}'
# Expected: dGVzdC1zZWNyZXQ=

# Decode the API-returned value
kubectl get secret vault-token -n ex-1-1 -o jsonpath='{.data.token}' | base64 -d
# Expected: test-secret

# Read the Secret directly from etcd (confirms it is plaintext in storage)
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-1-1/vault-token" | cat
# Expected: output contains the string dGVzdC1zZWNyZXQ= (NOT prefixed with k8s:enc:)
```

---

### Exercise 1.2

**Objective:** Create a Secret and a pod that reads the Secret as an environment variable, then inspect the environment variable inside the running container.

**Setup:**

```bash
kubectl create namespace ex-1-2
```

**Task:**

Create a Secret named `db-creds` in the `ex-1-2` namespace with a single key `db-password` and literal value `supersecretpassword`. Create a Pod named `env-reader` in the same namespace using the image `busybox:1.36` that keeps running with `command: ["sleep", "3600"]` and reads the Secret key `db-password` into an environment variable named `DATABASE_PASSWORD` using `env.valueFrom.secretKeyRef`. Once the pod is running, exec into it and print the environment variable.

**Verification:**

```bash
# Confirm the pod is running
kubectl get pod env-reader -n ex-1-2
# Expected: env-reader   1/1   Running   ...

# Print the environment variable inside the container
kubectl exec env-reader -n ex-1-2 -- printenv DATABASE_PASSWORD
# Expected: supersecretpassword

# Confirm the Secret exists
kubectl get secret db-creds -n ex-1-2 -o jsonpath='{.data.db-password}' | base64 -d
# Expected: supersecretpassword
```

---

### Exercise 1.3

**Objective:** Create a Secret and a pod that mounts the Secret as a volume, then read the Secret value from the mounted file inside the container.

**Setup:**

```bash
kubectl create namespace ex-1-3
```

**Task:**

Create a Secret named `tls-secrets` in the `ex-1-3` namespace with two keys: `cert` with literal value `BEGIN CERTIFICATE` and `key` with literal value `BEGIN PRIVATE KEY`. Create a Pod named `file-reader` in the same namespace using the image `busybox:1.36` that sleeps indefinitely (`command: ["sleep", "3600"]`) and mounts the `tls-secrets` Secret as a read-only volume at `/etc/tls`. Once running, exec into the pod and list the files in `/etc/tls`, then read the content of each file.

**Verification:**

```bash
# Confirm the pod is running
kubectl get pod file-reader -n ex-1-3
# Expected: file-reader   1/1   Running   ...

# List the mounted files
kubectl exec file-reader -n ex-1-3 -- ls /etc/tls
# Expected:
# cert
# key

# Read the cert file
kubectl exec file-reader -n ex-1-3 -- cat /etc/tls/cert
# Expected: BEGIN CERTIFICATE

# Read the key file
kubectl exec file-reader -n ex-1-3 -- cat /etc/tls/key
# Expected: BEGIN PRIVATE KEY
```

---

## Level 2: Enabling Encryption and Safe Exposure Patterns

**Note:** Exercise 2.1 requires modifying the kube-apiserver manifest. Start with a clean cluster state. After completing 2.1, the cluster will have encryption enabled; exercises 2.2 and 2.3 do not depend on this state and can be done on a separate clean cluster.

### Exercise 2.1

**Objective:** Enable EncryptionConfiguration on the kube-apiserver, create a new Secret, and verify it appears as ciphertext in etcd. Also read a Secret created before enabling encryption and confirm it remains as plaintext in etcd but is still readable through the Kubernetes API.

**Setup:**

```bash
kubectl create namespace ex-2-1

# Create a Secret BEFORE enabling encryption
kubectl create secret generic pre-encryption \
  --namespace ex-2-1 \
  --from-literal=value=plaintext-value
```

**Task:**

Generate a 32-byte aescbc encryption key. Write an EncryptionConfiguration file specifying aescbc as the first provider (with your generated key) and identity as the second provider. Copy the file to `/etc/kubernetes/enc/enc-config.yaml` on the kind-control-plane node. Edit the kube-apiserver static pod manifest at `/etc/kubernetes/manifests/kube-apiserver.yaml` to add the `--encryption-provider-config=/etc/kubernetes/enc/enc-config.yaml` flag, a volume mounting `/etc/kubernetes/enc` as `DirectoryOrCreate`, and a volumeMount for that volume. Wait for the API server to restart. Then create a new Secret named `post-encryption` with literal value `encrypted-value` in the `ex-2-1` namespace. Read both Secrets from etcd using etcdctl and compare their storage format.

**Verification:**

```bash
# Confirm the API server has the encryption flag
kubectl get pod kube-apiserver-kind-control-plane -n kube-system \
  -o jsonpath='{.spec.containers[0].command}' | tr ',' '\n' | grep encryption
# Expected: --encryption-provider-config=/etc/kubernetes/enc/enc-config.yaml

# Read the pre-encryption Secret from etcd (should still be plaintext)
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-2-1/pre-encryption" | cat
# Expected: output contains plaintext (no k8s:enc: prefix)

# Read the post-encryption Secret from etcd (should be ciphertext)
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-2-1/post-encryption" | cat
# Expected: output starts with k8s:enc:aescbc:v1:

# Confirm both Secrets are readable through the API (decryption is transparent)
kubectl get secret pre-encryption -n ex-2-1 -o jsonpath='{.data.value}' | base64 -d
# Expected: plaintext-value

kubectl get secret post-encryption -n ex-2-1 -o jsonpath='{.data.value}' | base64 -d
# Expected: encrypted-value
```

---

### Exercise 2.2

**Objective:** Create a pod with `automountServiceAccountToken: false` and verify that the service account token is not present inside the container.

**Setup:**

```bash
kubectl create namespace ex-2-2
```

**Task:**

Create a Pod named `token-denied` in the `ex-2-2` namespace using the image `busybox:1.36` with `command: ["sleep", "3600"]` and `automountServiceAccountToken: false` on the pod spec. Once running, exec into the pod and attempt to list the files at `/var/run/secrets/kubernetes.io/serviceaccount/`. The directory should not exist or should be empty.

**Verification:**

```bash
# Confirm the pod is running
kubectl get pod token-denied -n ex-2-2
# Expected: token-denied   1/1   Running   ...

# Verify automountServiceAccountToken is false
kubectl get pod token-denied -n ex-2-2 -o jsonpath='{.spec.automountServiceAccountToken}'
# Expected: false

# Verify the SA token directory is not present
kubectl exec token-denied -n ex-2-2 -- \
  ls /var/run/secrets/kubernetes.io/serviceaccount/ 2>&1
# Expected: ls: /var/run/secrets/kubernetes.io/serviceaccount/: No such file or directory
```

---

### Exercise 2.3

**Objective:** Create a projected volume in a pod that combines a Secret and a ConfigMap into a single directory mount.

**Setup:**

```bash
kubectl create namespace ex-2-3

kubectl create secret generic app-secrets \
  --namespace ex-2-3 \
  --from-literal=db-url=postgres://db:5432/myapp

kubectl create configmap app-config \
  --namespace ex-2-3 \
  --from-literal=log-level=info \
  --from-literal=environment=staging
```

**Task:**

Create a Pod named `projected-reader` in the `ex-2-3` namespace using the image `busybox:1.36` that sleeps indefinitely. Mount a projected volume named `combined` at `/etc/app-config` that includes both the `app-secrets` Secret and the `app-config` ConfigMap as sources. All keys from both sources should appear as files in `/etc/app-config`.

**Verification:**

```bash
# Confirm the pod is running
kubectl get pod projected-reader -n ex-2-3
# Expected: projected-reader   1/1   Running   ...

# List all files in the projected volume directory
kubectl exec projected-reader -n ex-2-3 -- ls /etc/app-config
# Expected (in any order):
# db-url
# environment
# log-level

# Read the Secret key from the projected mount
kubectl exec projected-reader -n ex-2-3 -- cat /etc/app-config/db-url
# Expected: postgres://db:5432/myapp

# Read a ConfigMap key from the projected mount
kubectl exec projected-reader -n ex-2-3 -- cat /etc/app-config/log-level
# Expected: info
```

---

## Level 3: Debugging Broken Encryption Configurations

The exercises in this level present broken encryption configurations. Each exercise heading is intentionally bare. Read the error symptoms carefully and diagnose the root cause before attempting a fix.

### Exercise 3.1

**Objective:** The EncryptionConfiguration file below cannot be applied to the kube-apiserver successfully. Identify the problem, produce a corrected configuration, and apply it to the cluster so the API server starts with encryption enabled.

**Setup:**

```bash
kubectl create namespace ex-3-1

# Create this broken EncryptionConfiguration on the kind node
nerdctl exec kind-control-plane mkdir -p /etc/kubernetes/enc

nerdctl exec kind-control-plane sh -c "cat > /etc/kubernetes/enc/enc-config.yaml << 'EOF'
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: dGhpc2lzYWJhZGtleXRlc3Q=
      - identity: {}
EOF"

# Copy the kube-apiserver manifest locally for editing
nerdctl cp kind-control-plane:/etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver-3-1.yaml

# Apply the broken configuration (the API server will fail to restart)
# Add --encryption-provider-config flag plus volume/volumeMount to /tmp/kube-apiserver-3-1.yaml
# then copy back:
# nerdctl cp /tmp/kube-apiserver-3-1.yaml kind-control-plane:/etc/kubernetes/manifests/kube-apiserver.yaml
```

**Note:** Before applying the configuration to the live cluster, examine the EncryptionConfiguration and identify the problem. Produce a corrected EncryptionConfiguration file and then apply the manifest change. After applying, confirm the kube-apiserver starts cleanly.

**Task:**

The configuration above has a problem that will prevent the kube-apiserver from starting with encryption enabled. Find and fix whatever is needed so that the API server starts with a working EncryptionConfiguration, then create a Secret named `probe-secret` in the `ex-3-1` namespace with literal value `probe-value` and verify it is stored as ciphertext in etcd.

**Verification:**

```bash
# Confirm the API server is running with the encryption flag
kubectl get pod kube-apiserver-kind-control-plane -n kube-system \
  -o jsonpath='{.spec.containers[0].command}' | tr ',' '\n' | grep encryption
# Expected: --encryption-provider-config=/etc/kubernetes/enc/enc-config.yaml

# Confirm the probe Secret was created
kubectl get secret probe-secret -n ex-3-1
# Expected: probe-secret   Opaque   1   ...

# Confirm the probe Secret is encrypted in etcd
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-3-1/probe-secret" | cat
# Expected: output starts with k8s:enc:aescbc:v1:
```

---

### Exercise 3.2

**Objective:** A cluster has EncryptionConfiguration enabled, but after reviewing the setup you find that Secrets created after enabling encryption are not actually protected. Diagnose the problem and fix it so that new Secrets are correctly encrypted in etcd.

**Setup:**

```bash
# Start with a clean cluster (recreate if needed: kind delete cluster && kind create cluster)
kubectl create namespace ex-3-2

# Create a "before" Secret
kubectl create secret generic before-secret \
  --namespace ex-3-2 \
  --from-literal=data=original-value

# Write a broken EncryptionConfiguration where identity is FIRST
nerdctl exec kind-control-plane mkdir -p /etc/kubernetes/enc

ENC_KEY_3_2=$(head -c 32 /dev/urandom | base64)

nerdctl exec kind-control-plane sh -c "cat > /etc/kubernetes/enc/enc-config.yaml << EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - identity: {}
      - aescbc:
          keys:
            - name: key1
              secret: ${ENC_KEY_3_2}
EOF"

# Copy manifest, add the encryption flag and volume/volumeMount, copy back
# (Follow the same steps as in exercise 2.1 to add the flag to the kube-apiserver manifest)
# After the API server restarts, create an "after" Secret:
kubectl create secret generic after-secret \
  --namespace ex-3-2 \
  --from-literal=data=new-value
```

**Task:**

The configuration above has a problem that causes new Secrets to be stored without the intended encryption protection. Diagnose what is wrong, fix the EncryptionConfiguration, apply the corrected version, and create a Secret named `verified-secret` in the `ex-3-2` namespace with literal value `secured-value`. Verify it is stored as ciphertext in etcd.

**Verification:**

```bash
# Confirm the after-secret is encrypted in etcd after your fix
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-3-2/verified-secret" | cat
# Expected: output starts with k8s:enc:aescbc:v1:

# Confirm kubectl can still read all Secrets
kubectl get secret before-secret -n ex-3-2 -o jsonpath='{.data.data}' | base64 -d
# Expected: original-value

kubectl get secret verified-secret -n ex-3-2 -o jsonpath='{.data.data}' | base64 -d
# Expected: secured-value
```

---

### Exercise 3.3

**Objective:** A cluster has encryption enabled, but some Secrets cannot be read through the Kubernetes API. Diagnose the failure and fix the configuration to restore access to all existing Secrets.

**Setup:**

```bash
# Start with a clean cluster
kubectl create namespace ex-3-3

# Generate a key and write EncryptionConfiguration with ONLY aescbc (no identity provider)
nerdctl exec kind-control-plane mkdir -p /etc/kubernetes/enc

ENC_KEY_3_3=$(head -c 32 /dev/urandom | base64)

# First, write a GOOD config and enable it so some Secrets get encrypted
nerdctl exec kind-control-plane sh -c "cat > /etc/kubernetes/enc/enc-config.yaml << EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENC_KEY_3_3}
      - identity: {}
EOF"

# Add the encryption flag to kube-apiserver (see tutorial for steps), then wait for restart

# Create a Secret AFTER encryption is enabled (this one is encrypted with aescbc)
kubectl create secret generic encrypted-app-secret \
  --namespace ex-3-3 \
  --from-literal=api-key=secret-api-key-value

# Now simulate the bad configuration: remove identity from the providers list
nerdctl exec kind-control-plane sh -c "cat > /etc/kubernetes/enc/enc-config.yaml << EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENC_KEY_3_3}
EOF"

# Also create a Secret BEFORE the initial encryption was enabled in another namespace
# (to simulate a plaintext Secret that exists in etcd)
kubectl create namespace ex-3-3-legacy
kubectl create secret generic legacy-secret \
  --namespace ex-3-3-legacy \
  --from-literal=old-data=legacy-value
# At this point: attempting to read legacy-secret through the API will fail
# because the identity provider is missing
```

**Task:**

The configuration above has one or more problems that cause certain Secrets to become unreadable through the Kubernetes API. Diagnose which Secrets are affected, identify the root cause, and fix the EncryptionConfiguration so that all Secrets (both encrypted and plaintext) are readable again. Do not lose any Secret data in the process.

**Verification:**

```bash
# After your fix, both Secrets should be readable
kubectl get secret encrypted-app-secret -n ex-3-3 -o jsonpath='{.data.api-key}' | base64 -d
# Expected: secret-api-key-value

kubectl get secret legacy-secret -n ex-3-3-legacy -o jsonpath='{.data.old-data}' | base64 -d
# Expected: legacy-value
```

---

## Level 4: Key Rotation and Extended Encryption Scope

**Note:** These exercises require modifying the kube-apiserver manifest. Start each exercise with a clean cluster state unless the exercise setup explicitly builds on a previous state.

### Exercise 4.1

**Objective:** Enable encryption from scratch, then perform a full re-encryption of all existing Secrets in the cluster to protect Secrets that were written before encryption was enabled.

**Setup:**

```bash
# Start with a clean cluster (no encryption configured)
kubectl create namespace ex-4-1
kubectl create namespace ex-4-1-b

# Create Secrets in multiple namespaces BEFORE enabling encryption
kubectl create secret generic legacy-db \
  --namespace ex-4-1 \
  --from-literal=password=legacy-password

kubectl create secret generic legacy-api \
  --namespace ex-4-1-b \
  --from-literal=token=legacy-token

kubectl create secret generic kube-system-test \
  --namespace kube-system \
  --from-literal=data=kube-system-value
```

**Task:**

Enable EncryptionConfiguration with aescbc on the kube-apiserver (follow the same procedure as exercise 2.1). After the API server restarts and confirms encryption is active for new writes, re-encrypt all existing Secrets in all namespaces using `kubectl get secrets --all-namespaces -o json | kubectl replace -f -`. Verify that all three pre-existing Secrets are now stored as ciphertext in etcd.

**Verification:**

```bash
# Confirm the API server has the encryption flag
kubectl get pod kube-apiserver-kind-control-plane -n kube-system \
  -o jsonpath='{.spec.containers[0].command}' | tr ',' '\n' | grep encryption
# Expected: --encryption-provider-config=/etc/kubernetes/enc/enc-config.yaml

# Verify legacy-db is now encrypted in etcd
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-4-1/legacy-db" | cat
# Expected: output starts with k8s:enc:aescbc:v1:

# Verify legacy-api is now encrypted in etcd
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-4-1-b/legacy-api" | cat
# Expected: output starts with k8s:enc:aescbc:v1:

# Confirm all Secrets are still readable through the API
kubectl get secret legacy-db -n ex-4-1 -o jsonpath='{.data.password}' | base64 -d
# Expected: legacy-password

kubectl get secret legacy-api -n ex-4-1-b -o jsonpath='{.data.token}' | base64 -d
# Expected: legacy-token
```

---

### Exercise 4.2

**Objective:** Perform a complete key rotation on a cluster where encryption is already enabled: add a new key as the first provider, re-encrypt all Secrets, verify the new key is used in etcd storage, and remove the old key from the configuration.

**Setup:**

```bash
# This exercise assumes Exercise 4.1 is complete and encryption is enabled with key1.
# If starting fresh, enable encryption first per the tutorial steps.
kubectl create namespace ex-4-2

# Create a Secret to track across the rotation
kubectl create secret generic rotation-probe \
  --namespace ex-4-2 \
  --from-literal=tracking=before-rotation
```

**Task:**

Generate a new 32-byte aescbc key (key2). Update the EncryptionConfiguration on the kind node to list key2 first and keep key1 second. Re-read the EncryptionConfiguration to confirm both keys are present. Re-encrypt all Secrets using `kubectl get secrets --all-namespaces -o json | kubectl replace -f -`. Verify that the `rotation-probe` Secret and the Secrets from exercise 4.1 now show the `key2` prefix in etcd. Then update the EncryptionConfiguration to remove key1 entirely. Verify that all Secrets are still readable through the Kubernetes API.

**Verification:**

```bash
# After rotation: rotation-probe should show key2 prefix
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-4-2/rotation-probe" | cat
# Expected: output starts with k8s:enc:aescbc:v1:key2:

# After removing key1: all Secrets remain readable
kubectl get secret rotation-probe -n ex-4-2 -o jsonpath='{.data.tracking}' | base64 -d
# Expected: before-rotation

kubectl get secret legacy-db -n ex-4-1 -o jsonpath='{.data.password}' | base64 -d
# Expected: legacy-password
```

---

### Exercise 4.3

**Objective:** Extend the EncryptionConfiguration to cover ConfigMaps in addition to Secrets. Verify that a new ConfigMap is stored as ciphertext in etcd while existing ConfigMaps remain readable.

**Setup:**

```bash
kubectl create namespace ex-4-3

# Create a ConfigMap BEFORE extending encryption to configmaps
kubectl create configmap pre-enc-config \
  --namespace ex-4-3 \
  --from-literal=setting=pre-encryption-value
```

**Task:**

Update the EncryptionConfiguration (already in place from earlier exercises, or enable it fresh per the tutorial) to add a second resource entry that covers `configmaps` using the same aescbc provider and key. Apply the change by copying the updated file to the kind node. Wait for the configuration to be re-read. Create a new ConfigMap named `post-enc-config` in the `ex-4-3` namespace with literal value `post-encryption-value`. Read both ConfigMaps from etcd using etcdctl and confirm that the newly created one is stored as ciphertext while the pre-existing one is still readable through the API.

**Verification:**

```bash
# Verify the new ConfigMap is encrypted in etcd
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/configmaps/ex-4-3/post-enc-config" | cat
# Expected: output starts with k8s:enc:aescbc:v1:

# Verify both ConfigMaps are readable through the API
kubectl get configmap pre-enc-config -n ex-4-3 -o jsonpath='{.data.setting}'
# Expected: pre-encryption-value

kubectl get configmap post-enc-config -n ex-4-3 -o jsonpath='{.data.setting}'
# Expected: post-encryption-value
```

---

## Level 5: Advanced Debugging Scenarios

### Exercise 5.1

**Objective:** A security audit of the cluster finds that encryption is enabled but some Secrets in etcd are still stored as plaintext. Diagnose the cause, enumerate the affected Secrets, and remediate so all Secrets are protected.

**Setup:**

```bash
# Start with a clean cluster
kubectl create namespace ex-5-1
kubectl create namespace ex-5-1-b
kubectl create namespace ex-5-1-c

# Create Secrets in three namespaces BEFORE enabling encryption
kubectl create secret generic service-a-creds \
  --namespace ex-5-1 \
  --from-literal=api-key=service-a-key

kubectl create secret generic service-b-creds \
  --namespace ex-5-1-b \
  --from-literal=api-key=service-b-key

kubectl create secret generic service-c-creds \
  --namespace ex-5-1-c \
  --from-literal=api-key=service-c-key

# Now enable encryption (creates the EncryptionConfiguration and adds the flag to the API server)
# Follow the same steps as the tutorial: generate key, write config, edit manifest, wait for restart

ENC_KEY_5_1=$(head -c 32 /dev/urandom | base64)
nerdctl exec kind-control-plane mkdir -p /etc/kubernetes/enc
nerdctl exec kind-control-plane sh -c "cat > /etc/kubernetes/enc/enc-config.yaml << EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENC_KEY_5_1}
      - identity: {}
EOF"

# Add the flag and volume to the kube-apiserver manifest (see tutorial steps) then wait for restart

# Create ONE new Secret AFTER encryption is enabled
kubectl create secret generic service-d-creds \
  --namespace ex-5-1 \
  --from-literal=api-key=service-d-key
```

**Task:**

The configuration above has a problem. The security audit confirms that encryption is enabled (new Secrets are being written as ciphertext), but some Secrets in the cluster are still stored in plaintext in etcd. Diagnose which Secrets are affected and why, then remediate so that all Secrets in all namespaces are stored as ciphertext in etcd. Verify the remediation by checking several Secrets in etcd directly.

**Verification:**

```bash
# After remediation: all four service Secrets should be encrypted in etcd
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-5-1/service-a-creds" | cat
# Expected: output starts with k8s:enc:aescbc:v1:

kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-5-1-b/service-b-creds" | cat
# Expected: output starts with k8s:enc:aescbc:v1:

kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-5-1/service-d-creds" | cat
# Expected: output starts with k8s:enc:aescbc:v1:

# Confirm all Secrets are still readable through the API
kubectl get secret service-a-creds -n ex-5-1 -o jsonpath='{.data.api-key}' | base64 -d
# Expected: service-a-key

kubectl get secret service-c-creds -n ex-5-1-c -o jsonpath='{.data.api-key}' | base64 -d
# Expected: service-c-key
```

---

### Exercise 5.2

**Objective:** The kube-apiserver is failing to start due to one or more problems in the encryption setup. Diagnose all issues and fix them so the cluster returns to a healthy state with encryption working correctly.

**Setup:**

```bash
# Start with a clean cluster
kubectl create namespace ex-5-2

# Write a broken EncryptionConfiguration with two separate problems
nerdctl exec kind-control-plane mkdir -p /etc/kubernetes/enc

nerdctl exec kind-control-plane sh -c "cat > /etc/kubernetes/enc/enc-config.yaml << 'EOF'
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: primary
              secret: c2hvcnRrZXk=
      - secretbox:
          keys:
            - name: fallback
              secret: YWxzb3Nob3J0
      - identity: {}
EOF"

# Copy the manifest, add --encryption-provider-config plus volume/volumeMount,
# then copy back to trigger the (failing) restart:
# nerdctl cp /tmp/kube-apiserver-5-2.yaml kind-control-plane:/etc/kubernetes/manifests/kube-apiserver.yaml
```

**Note:** The EncryptionConfiguration above has one or more problems. Do NOT apply the manifest until you have identified and fixed all problems in the configuration file. Then apply the corrected configuration and confirm the API server starts cleanly.

**Task:**

The configuration above has one or more problems that would prevent the kube-apiserver from starting. Find and fix all problems, apply the corrected EncryptionConfiguration, add the required manifest flags, and verify the API server starts with encryption working. Create a Secret named `health-check` in the `ex-5-2` namespace with literal value `system-ok` and confirm it is stored as ciphertext in etcd.

**Verification:**

```bash
# Confirm the API server is running
kubectl cluster-info
# Expected: Kubernetes control plane is running at https://127.0.0.1:...

# Confirm the encryption flag is set
kubectl get pod kube-apiserver-kind-control-plane -n kube-system \
  -o jsonpath='{.spec.containers[0].command}' | tr ',' '\n' | grep encryption
# Expected: --encryption-provider-config=/etc/kubernetes/enc/enc-config.yaml

# Confirm the health-check Secret is encrypted in etcd
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-5-2/health-check" | cat
# Expected: output starts with k8s:enc:aescbc:v1: or k8s:enc:secretbox:v1:

kubectl get secret health-check -n ex-5-2 -o jsonpath='{.data.value}' | base64 -d
# Expected: system-ok
```

---

### Exercise 5.3

**Objective:** A key rotation was performed, but afterward some application Secret reads began failing. Diagnose the cause and restore access to all Secrets while keeping the cluster in a correctly configured encrypted state.

**Setup:**

```bash
# Start with encryption already enabled (key1 active)
kubectl create namespace ex-5-3

ENC_KEY_5_3_1=$(head -c 32 /dev/urandom | base64)
nerdctl exec kind-control-plane mkdir -p /etc/kubernetes/enc
nerdctl exec kind-control-plane sh -c "cat > /etc/kubernetes/enc/enc-config.yaml << EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENC_KEY_5_3_1}
      - identity: {}
EOF"

# Add encryption to kube-apiserver (see tutorial steps), wait for restart

# Create Secrets encrypted with key1
kubectl create secret generic payment-creds \
  --namespace ex-5-3 \
  --from-literal=stripe-key=sk-test-payment-key

kubectl create secret generic auth-creds \
  --namespace ex-5-3 \
  --from-literal=jwt-secret=super-secret-jwt

# Simulate a botched rotation: rotate to key2 but immediately remove key1
# WITHOUT re-encrypting the existing Secrets first
ENC_KEY_5_3_2=$(head -c 32 /dev/urandom | base64)
nerdctl exec kind-control-plane sh -c "cat > /etc/kubernetes/enc/enc-config.yaml << EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key2
              secret: ${ENC_KEY_5_3_2}
      - identity: {}
EOF"
# Wait a few seconds for the hot-reload

# At this point: existing Secrets (encrypted with key1) cannot be decrypted
# because key1 is no longer in the providers list
```

**Task:**

The configuration above has one or more problems that cause existing Secrets to be unreadable. Diagnose which Secrets are affected and why, then fix the EncryptionConfiguration to restore access to all Secrets. After restoring access, complete the rotation correctly: re-encrypt all Secrets with key2, verify the new key prefix in etcd, then remove key1 from the configuration. Leave the cluster in a state where all Secrets are encrypted with key2 and key1 is no longer present in the EncryptionConfiguration.

**Verification:**

```bash
# After restoring access and completing rotation: both Secrets should be readable
kubectl get secret payment-creds -n ex-5-3 -o jsonpath='{.data.stripe-key}' | base64 -d
# Expected: sk-test-payment-key

kubectl get secret auth-creds -n ex-5-3 -o jsonpath='{.data.jwt-secret}' | base64 -d
# Expected: super-secret-jwt

# Both Secrets should be stored with the key2 prefix in etcd
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-5-3/payment-creds" | cat
# Expected: output starts with k8s:enc:aescbc:v1:key2:

kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-5-3/auth-creds" | cat
# Expected: output starts with k8s:enc:aescbc:v1:key2:

# Confirm key1 is no longer in the EncryptionConfiguration
nerdctl exec kind-control-plane grep "key1" /etc/kubernetes/enc/enc-config.yaml
# Expected: no output (key1 has been removed)
```

---

## Cleanup

Delete all exercise namespaces when you are finished:

```bash
kubectl delete namespace ex-1-1 ex-1-2 ex-1-3
kubectl delete namespace ex-2-1 ex-2-2 ex-2-3
kubectl delete namespace ex-3-1 ex-3-2 ex-3-3 ex-3-3-legacy
kubectl delete namespace ex-4-1 ex-4-1-b ex-4-2 ex-4-3
kubectl delete namespace ex-5-1 ex-5-1-b ex-5-1-c ex-5-2 ex-5-3
kubectl delete secret kube-system-test -n kube-system --ignore-not-found
```

If you modified the kube-apiserver manifest during the exercises and want to restore the cluster to its original unencrypted state, the cleanest approach is:

```bash
kind delete cluster && kind create cluster
```

## Key Takeaways

The exercises in this assignment reinforce four skills that the CKA exam tests directly. First, etcdctl inspection: the ability to read raw etcd values and interpret whether a Secret is stored as plaintext or ciphertext. Second, EncryptionConfiguration: the ability to write a valid configuration file with correct key size, correct provider ordering (encryption provider first, identity last), and the ability to recognize common misconfigurations from their symptoms. Third, API server manifest editing: adding the `--encryption-provider-config` flag and the required volume plus volumeMount to a static pod manifest, and waiting for the kubelet to restart the pod. Fourth, key rotation: the ordered sequence of add new key first, re-encrypt all Secrets, then remove old key, and the failure mode when this order is violated.
