# Secrets Management Homework Answers: etcd Encryption at Rest

---

## Exercise 1.1 Solution

Create the Secret with the literal base64-encoded value. Note that `--from-literal` encodes the value in base64 automatically, so to store the base64 string `dGVzdC1zZWNyZXQ=` as the literal value, you must decode it back to `test-secret` first and let kubectl re-encode it:

```bash
kubectl create secret generic vault-token \
  --namespace ex-1-1 \
  --from-literal=token=test-secret
```

This stores `dGVzdC1zZWNyZXQ=` (base64 of "test-secret") in the Secret's data field. Read from etcd:

```bash
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-1-1/vault-token"
```

The output is binary protobuf but the string `dGVzdC1zZWNyZXQ=` is visible embedded in it. Decode to confirm:

```bash
kubectl get secret vault-token -n ex-1-1 -o jsonpath='{.data.token}' | base64 -d
# Output: test-secret
```

The value `dGVzdC1zZWNyZXQ=` in etcd is not protected in any way. Any process reading etcd directly can decode it with a single `base64 -d` call.

---

## Exercise 1.2 Solution

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-creds
  namespace: ex-1-2
type: Opaque
stringData:
  db-password: supersecretpassword
---
apiVersion: v1
kind: Pod
metadata:
  name: env-reader
  namespace: ex-1-2
spec:
  containers:
    - name: reader
      image: busybox:1.36
      command: ["sleep", "3600"]
      env:
        - name: DATABASE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-creds
              key: db-password
```

Apply with `kubectl apply -f -`. Once the pod is Running:

```bash
kubectl exec env-reader -n ex-1-2 -- printenv DATABASE_PASSWORD
# Output: supersecretpassword
```

The `stringData` field in the Secret spec accepts plain strings; kubectl encodes them to base64 before submitting to the API server.

---

## Exercise 1.3 Solution

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: tls-secrets
  namespace: ex-1-3
type: Opaque
stringData:
  cert: "BEGIN CERTIFICATE"
  key: "BEGIN PRIVATE KEY"
---
apiVersion: v1
kind: Pod
metadata:
  name: file-reader
  namespace: ex-1-3
spec:
  containers:
    - name: reader
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: tls-vol
          mountPath: /etc/tls
          readOnly: true
  volumes:
    - name: tls-vol
      secret:
        secretName: tls-secrets
```

Verify:

```bash
kubectl exec file-reader -n ex-1-3 -- ls /etc/tls
# Output: cert  key

kubectl exec file-reader -n ex-1-3 -- cat /etc/tls/cert
# Output: BEGIN CERTIFICATE
```

Each key in the Secret becomes a file in the mount directory. The `readOnly: true` mount option prevents the application from modifying the mounted files.

---

## Exercise 2.1 Solution

**Step 1, Generate a 32-byte key:**

```bash
ENC_KEY=$(head -c 32 /dev/urandom | base64)
echo "Key: $ENC_KEY"
```

**Step 2, Write the EncryptionConfiguration:**

```bash
cat > /tmp/enc-config.yaml << EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENC_KEY}
      - identity: {}
EOF

nerdctl exec kind-control-plane mkdir -p /etc/kubernetes/enc
nerdctl cp /tmp/enc-config.yaml kind-control-plane:/etc/kubernetes/enc/enc-config.yaml
```

**Step 3, Edit the kube-apiserver manifest:**

```bash
nerdctl cp kind-control-plane:/etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml
```

Add to `/tmp/kube-apiserver.yaml`:
- In `command`: `- --encryption-provider-config=/etc/kubernetes/enc/enc-config.yaml`
- In `volumeMounts`: `- mountPath: /etc/kubernetes/enc`, `  name: enc`, `  readOnly: true`
- In `volumes`: `- hostPath:`, `    path: /etc/kubernetes/enc`, `    type: DirectoryOrCreate`, `  name: enc`

```bash
nerdctl cp /tmp/kube-apiserver.yaml kind-control-plane:/etc/kubernetes/manifests/kube-apiserver.yaml
```

**Step 4, Wait for restart:**

```bash
until kubectl cluster-info 2>/dev/null | grep -q "Kubernetes control plane"; do
  sleep 5
done
```

**Step 5, Create the post-encryption Secret:**

```bash
kubectl create secret generic post-encryption \
  --namespace ex-2-1 \
  --from-literal=value=encrypted-value
```

The pre-encryption Secret was written before the EncryptionConfiguration was applied. Reading it from etcd shows the base64 value in plaintext. The post-encryption Secret shows `k8s:enc:aescbc:v1:key1:` in etcd. Both are fully readable through the Kubernetes API because the identity provider (listed second) handles reading plaintext-stored Secrets.

---

## Exercise 2.2 Solution

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: token-denied
  namespace: ex-2-2
spec:
  automountServiceAccountToken: false
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
```

The key field is `automountServiceAccountToken: false` on the pod spec (not on the container). Without this field, the kubelet mounts the default service account token at `/var/run/secrets/kubernetes.io/serviceaccount/token` for every pod automatically. Setting it to false suppresses that mount entirely.

---

## Exercise 2.3 Solution

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: projected-reader
  namespace: ex-2-3
spec:
  containers:
    - name: reader
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: combined
          mountPath: /etc/app-config
  volumes:
    - name: combined
      projected:
        sources:
          - secret:
              name: app-secrets
          - configMap:
              name: app-config
```

The projected volume merges both sources into the same directory. The Secret key `db-url` becomes `/etc/app-config/db-url`, and the ConfigMap keys `log-level` and `environment` become `/etc/app-config/log-level` and `/etc/app-config/environment`. If the same key name exists in both the Secret and the ConfigMap, the ConfigMap value takes precedence when both are listed in the same projected volume (the last source in the list wins for name collisions).

---

## Exercise 3.1 Solution

### Diagnosis

Examine the EncryptionConfiguration:

```bash
nerdctl exec kind-control-plane cat /etc/kubernetes/enc/enc-config.yaml
```

Look at the `secret` field under the aescbc key:

```
secret: dGhpc2lzYWJhZGtleXRlc3Q=
```

Decode this value to check its byte length:

```bash
echo "dGhpc2lzYWJhZGtleXRlc3Q=" | base64 -d | wc -c
# Output: 16
```

The aescbc provider requires exactly 32 bytes. This key is only 16 bytes. If this configuration were applied to the kube-apiserver, the API server would refuse to start. Check the kubelet logs or the kube-apiserver container logs after applying a bad config to see the error:

```bash
# After applying (if you tried it), check journald on the kind node:
nerdctl exec kind-control-plane journalctl -u kubelet --no-pager -n 50 | grep -i "invalid"
# Or check the static pod container state:
nerdctl exec kind-control-plane crictl logs $(nerdctl exec kind-control-plane crictl ps -a --name kube-apiserver -q | head -1)
```

The error message contains: `invalid encryption provider configuration: aescbc: invalid key size 16`

### What the Bug Is and Why It Happens

The aescbc provider implements AES-256-CBC, which requires a 256-bit (32-byte) key. The secret field in the EncryptionConfiguration must be the base64 encoding of exactly 32 raw bytes. The broken configuration used a key that decodes to only 16 bytes (128-bit AES is not supported by this provider). This is a common mistake when someone generates a key from a short passphrase or uses `head -c 16` instead of `head -c 32`.

### The Fix

Generate a correct 32-byte key and write a corrected EncryptionConfiguration:

```bash
FIXED_KEY=$(head -c 32 /dev/urandom | base64)

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
              secret: ${FIXED_KEY}
      - identity: {}
EOF"
```

Now add the `--encryption-provider-config` flag and volume to the kube-apiserver manifest (per the tutorial steps), copy it back, and wait for the API server to restart cleanly:

```bash
until kubectl cluster-info 2>/dev/null | grep -q "Kubernetes control plane"; do sleep 5; done

kubectl create secret generic probe-secret \
  --namespace ex-3-1 \
  --from-literal=value=probe-value
```

---

## Exercise 3.2 Solution

### Diagnosis

Read the EncryptionConfiguration from the kind node:

```bash
nerdctl exec kind-control-plane cat /etc/kubernetes/enc/enc-config.yaml
```

The providers list shows:

```yaml
providers:
  - identity: {}
  - aescbc:
      keys:
        - name: key1
          secret: <key>
```

Now create a Secret and read it from etcd:

```bash
kubectl create secret generic test-secret -n ex-3-2 --from-literal=x=y

kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-3-2/test-secret" | cat
```

The output does NOT start with `k8s:enc:aescbc:v1:`. The Secret is stored in plaintext. The API server is running and accepting the configuration, so there is no startup error, the problem is silent incorrect behavior.

### What the Bug Is and Why It Happens

The providers list controls which provider is used for writes by position: the first provider in the list is always used for new writes. With `identity` listed first, every new Secret is written using the identity provider, which stores data as-is (plaintext base64 in etcd). The `aescbc` provider is listed second, so it is never used for writes, it is only tried as a fallback when reading existing values. The result is that the operator believes encryption is active (the configuration is accepted, no errors appear) but all new Secrets are stored in plaintext.

### The Fix

Swap the provider order so `aescbc` is first and `identity` is last:

```bash
ENC_KEY_3_2_FIXED=$(head -c 32 /dev/urandom | base64)
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
              secret: ${ENC_KEY_3_2_FIXED}
      - identity: {}
EOF"
```

After the kube-apiserver hot-reloads the configuration, create the verified Secret:

```bash
kubectl create secret generic verified-secret \
  --namespace ex-3-2 \
  --from-literal=data=secured-value
```

Read it from etcd to confirm the ciphertext prefix is present.

---

## Exercise 3.3 Solution

### Diagnosis

Try to read the `legacy-secret`:

```bash
kubectl get secret legacy-secret -n ex-3-3-legacy -o yaml
```

The output may show an error like `Internal error occurred: unable to transform key "/registry/secrets/ex-3-3-legacy/legacy-secret": no matching provider` or the data field may be missing, indicating a decryption failure.

Examine the EncryptionConfiguration:

```bash
nerdctl exec kind-control-plane cat /etc/kubernetes/enc/enc-config.yaml
```

The providers list contains only `aescbc`. There is no `identity` provider. Check the etcd value for the legacy Secret:

```bash
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-3-3-legacy/legacy-secret" | cat
```

The output does NOT start with `k8s:enc:aescbc:v1:`, it is plaintext. The kube-apiserver tries each provider in order when reading: it tries aescbc first, which cannot decrypt a plaintext value, and since there is no identity provider as a fallback, it returns an error. The `encrypted-app-secret` (written with aescbc) is still readable because aescbc is in the list.

### What the Bug Is and Why It Happens

The `identity` provider must remain in the providers list whenever there are Secrets in etcd that were written in plaintext (without encryption). When the identity provider is present, the API server can decrypt plaintext Secrets using identity as a fallback after the aescbc attempt fails. Without identity, any Secret written before encryption was enabled, or written with a different provider, cannot be read. This is why the transition to encryption requires two phases: first add aescbc with identity still present (reads work for all Secrets, new writes use aescbc), then re-encrypt all existing Secrets, then only after all Secrets are re-encrypted can identity be removed.

### The Fix

Add `identity` back as the last provider in the EncryptionConfiguration. The aescbc key value must match the one used to encrypt the existing `encrypted-app-secret`:

```bash
# The ENC_KEY_3_3 variable from the setup holds the original key value.
# Replace <ORIGINAL_KEY> with the value of ENC_KEY_3_3 from the setup commands.
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
              secret: <ORIGINAL_KEY>
      - identity: {}
EOF"
```

After the kube-apiserver re-reads the configuration, both Secrets should be readable.

---

## Exercise 4.1 Solution

**Step 1, Enable encryption (same as exercise 2.1, generating a fresh key):**

```bash
ENC_KEY=$(head -c 32 /dev/urandom | base64)
cat > /tmp/enc-config.yaml << EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENC_KEY}
      - identity: {}
EOF
nerdctl exec kind-control-plane mkdir -p /etc/kubernetes/enc
nerdctl cp /tmp/enc-config.yaml kind-control-plane:/etc/kubernetes/enc/enc-config.yaml
# Edit kube-apiserver manifest to add flag + volume + volumeMount, then copy back
# Wait for API server to restart
```

**Step 2, Re-encrypt all existing Secrets:**

```bash
kubectl get secrets --all-namespaces -o json | kubectl replace -f -
```

This command reads every Secret through the Kubernetes API (which decrypts them transparently) and writes them back (which re-encrypts each one using the first provider, aescbc with key1). The command will output a line for each Secret it replaces.

**Step 3, Verify the pre-existing Secrets are now encrypted:**

```bash
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-4-1/legacy-db" | cat
# Expected: starts with k8s:enc:aescbc:v1:key1:
```

All pre-existing Secrets, including the kube-system Secrets, are now protected by aescbc.

---

## Exercise 4.2 Solution

**Step 1, Generate key2:**

```bash
KEY2=$(head -c 32 /dev/urandom | base64)
```

**Step 2, Update EncryptionConfiguration with key2 first, key1 second:**

The key1 value must be the same key used in exercise 4.1. Replace `<KEY1_VALUE>` with the value of the key used in 4.1:

```bash
cat > /tmp/enc-config-v2.yaml << EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key2
              secret: ${KEY2}
            - name: key1
              secret: <KEY1_VALUE>
      - identity: {}
EOF
nerdctl cp /tmp/enc-config-v2.yaml kind-control-plane:/etc/kubernetes/enc/enc-config.yaml
sleep 5
```

**Step 3, Re-encrypt all Secrets:**

```bash
kubectl get secrets --all-namespaces -o json | kubectl replace -f -
```

**Step 4, Remove key1:**

```bash
cat > /tmp/enc-config-v3.yaml << EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key2
              secret: ${KEY2}
      - identity: {}
EOF
nerdctl cp /tmp/enc-config-v3.yaml kind-control-plane:/etc/kubernetes/enc/enc-config.yaml
```

After the hot-reload, all Secrets are encrypted with key2. key1 is no longer in the configuration and cannot decrypt anything, but since all Secrets have been re-encrypted with key2, no decryption failures occur.

---

## Exercise 4.3 Solution

Update the EncryptionConfiguration to add a second resource group for configmaps. Both Secrets and ConfigMaps use the same key:

```bash
cat > /tmp/enc-config-cm.yaml << EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENC_KEY}
      - identity: {}
  - resources:
      - configmaps
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENC_KEY}
      - identity: {}
EOF
nerdctl cp /tmp/enc-config-cm.yaml kind-control-plane:/etc/kubernetes/enc/enc-config.yaml
sleep 5

kubectl create configmap post-enc-config \
  --namespace ex-4-3 \
  --from-literal=setting=post-encryption-value
```

The pre-existing `pre-enc-config` ConfigMap is still in plaintext in etcd (readable by the API via identity). The `post-enc-config` ConfigMap is stored as ciphertext. To protect both, run the same re-encrypt command for ConfigMaps:

```bash
kubectl get configmaps --all-namespaces -o json | kubectl replace -f -
```

---

## Exercise 5.1 Solution

### Diagnosis

The security audit has found that encryption is enabled (confirmed by the `--encryption-provider-config` flag and new Secrets showing the `k8s:enc:` prefix). Use etcdctl to scan Secrets and find those NOT starting with `k8s:enc:`:

```bash
# List all secret keys in etcd
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets --prefix --keys-only"
```

This lists every Secret key path. Check several known Secrets:

```bash
# Check service-a-creds (created BEFORE encryption was enabled)
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-5-1/service-a-creds" | cat
# Output: plaintext (no k8s:enc: prefix)

# Check service-d-creds (created AFTER encryption was enabled)
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-5-1/service-d-creds" | cat
# Output: starts with k8s:enc:aescbc:v1:
```

The pattern is clear: Secrets created before encryption was enabled are stored in plaintext. Secrets created after are encrypted. The EncryptionConfiguration with aescbc as the first provider encrypts new writes but does not automatically re-encrypt existing Secrets.

### What the Bug Is and Why It Happens

Enabling EncryptionConfiguration changes how new Secrets are written to etcd. It does not retroactively change any existing Secret in etcd. Each existing Secret will remain in its original storage format (plaintext base64 for the identity provider) until it is explicitly re-written through the Kubernetes API. The API server re-encrypts a Secret when it is updated, because every write goes through the first provider in the current EncryptionConfiguration. The three Secrets (`service-a-creds`, `service-b-creds`, `service-c-creds`) were written before encryption was enabled, so their etcd values are still plaintext.

### The Fix

Re-encrypt all existing Secrets by reading and re-writing them:

```bash
kubectl get secrets --all-namespaces -o json | kubectl replace -f -
```

After this command completes, verify the previously plaintext Secrets now show the aescbc ciphertext prefix in etcd:

```bash
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-5-1/service-a-creds" | cat
# Expected: starts with k8s:enc:aescbc:v1:
```

---

## Exercise 5.2 Solution

### Diagnosis

Examine the EncryptionConfiguration before applying it:

```bash
nerdctl exec kind-control-plane cat /etc/kubernetes/enc/enc-config.yaml
```

Check the two key values:

```bash
# Check the primary key (aescbc)
echo "c2hvcnRrZXk=" | base64 -d | wc -c
# Output: 8

# Check the fallback key (secretbox)
echo "YWxzb3Nob3J0" | base64 -d | wc -c
# Output: 9
```

Both keys decode to fewer than 32 bytes. The aescbc provider decodes `c2hvcnRrZXk=` to `shortkey` (8 bytes). The secretbox provider decodes `YWxzb3Nob3J0` to `alsoshort` (9 bytes). Both providers require exactly 32 bytes.

The symptoms if applied: the kube-apiserver would refuse to start, logging errors for both providers indicating invalid key sizes.

### What the Bug Is and Why It Happens

The `c2hvcnRrZXk=` value is base64 of the string "shortkey", which is 8 bytes. The `YWxzb3Nob3J0` value is base64 of "alsoshort", which is 9 bytes. Both aescbc and secretbox require exactly 32-byte keys. Keys derived from short strings (passphrases, names) nearly always fail this requirement unless they are properly stretched with a KDF. The correct approach is always `head -c 32 /dev/urandom | base64`.

### The Fix

Generate correct 32-byte keys for both providers:

```bash
PRIMARY_KEY=$(head -c 32 /dev/urandom | base64)
FALLBACK_KEY=$(head -c 32 /dev/urandom | base64)

nerdctl exec kind-control-plane sh -c "cat > /etc/kubernetes/enc/enc-config.yaml << EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: primary
              secret: ${PRIMARY_KEY}
      - secretbox:
          keys:
            - name: fallback
              secret: ${FALLBACK_KEY}
      - identity: {}
EOF"
```

Add the `--encryption-provider-config` flag and volume to the kube-apiserver manifest, copy it back, and wait for the restart. Then create the health-check Secret:

```bash
kubectl create secret generic health-check \
  --namespace ex-5-2 \
  --from-literal=value=system-ok
```

---

## Exercise 5.3 Solution

### Diagnosis

Attempt to read a Secret that was encrypted with key1:

```bash
kubectl get secret payment-creds -n ex-5-3 -o yaml
```

The output shows an error like `Internal error occurred: unable to transform key "/registry/secrets/ex-5-3/payment-creds": no matching provider` or the data field is missing.

Check the current EncryptionConfiguration:

```bash
nerdctl exec kind-control-plane cat /etc/kubernetes/enc/enc-config.yaml
```

The configuration only contains key2. key1 has been removed.

Check the etcd value for the affected Secret:

```bash
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-5-3/payment-creds" | cat
```

The output starts with `k8s:enc:aescbc:v1:key1:`, the Secret was encrypted with key1, which is no longer in the providers list. The kube-apiserver cannot find a matching decryption key.

### What the Bug Is and Why It Happens

The key rotation was performed out of order. The correct sequence is: (1) add key2 as the first provider while keeping key1 in the list, (2) re-encrypt all Secrets so they are stored with key2, (3) verify that all Secrets show the key2 prefix in etcd, and only then (4) remove key1. In this exercise, key1 was removed before step 2 (the re-encryption) was completed, leaving Secrets in etcd that reference key1 but have no key1 available to decrypt them.

### The Fix

Restore key1 to the EncryptionConfiguration temporarily. Both keys must be present to decrypt existing Secrets. The `ENC_KEY_5_3_1` variable from the setup holds the original key1 value; replace `<KEY1_VALUE>` with it, and `<KEY2_VALUE>` with the value of `ENC_KEY_5_3_2`:

```bash
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
              secret: <KEY2_VALUE>
            - name: key1
              secret: <KEY1_VALUE>
      - identity: {}
EOF"
sleep 5
```

Verify Secrets are readable again:

```bash
kubectl get secret payment-creds -n ex-5-3 -o jsonpath='{.data.stripe-key}' | base64 -d
# Expected: sk-test-payment-key
```

Now re-encrypt all Secrets with key2 as the active provider:

```bash
kubectl get secrets --all-namespaces -o json | kubectl replace -f -
```

Verify the key2 prefix is present:

```bash
kubectl exec -n kube-system etcd-kind-control-plane -- \
  sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/secrets/ex-5-3/payment-creds" | cat
# Expected: starts with k8s:enc:aescbc:v1:key2:
```

Remove key1:

```bash
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
              secret: <KEY2_VALUE>
      - identity: {}
EOF"
```

---

## Common Mistakes

**Mistake 1: Generating keys from short strings instead of /dev/urandom.**

The aescbc and secretbox providers require exactly 32 raw bytes. Running `echo -n "my-secret-key" | base64` produces a short key that will cause the kube-apiserver to refuse to start with an "invalid key size" error. The only correct way to generate an encryption key is `head -c 32 /dev/urandom | base64`, which reads 32 cryptographically random bytes from the kernel entropy pool. Shorter keys fail the size check; longer keys (from `head -c 64`) also fail because the base64-decoded length would be 64 bytes. The key validation checks the decoded length, not the base64 string length.

**Mistake 2: Placing identity first in the providers list and believing encryption is active.**

When `identity: {}` is the first provider, all new Secrets are written to etcd in plaintext. No error occurs; the API server starts cleanly and the configuration is accepted. The only way to detect this mistake is to create a Secret and read it from etcd, the absence of the `k8s:enc:` prefix reveals that identity is being used for writes. On the exam, after enabling EncryptionConfiguration, always verify by creating a new Secret and reading its etcd value to confirm the expected ciphertext prefix.

**Mistake 3: Removing the old key before re-encrypting all Secrets, breaking reads.**

After a key rotation, the impulse is to immediately clean up the old key once the new key is configured. But any Secret still encrypted with the old key becomes unreadable the moment the old key is removed from the providers list. The kube-apiserver tries each provider in order when reading; if none can decrypt the value, it returns an error. The fix is to restore the old key, re-encrypt all Secrets, verify the new key prefix, and only then remove the old key. This ordering is the critical sequence the CKA exam tests under the "key rotation" competency.

**Mistake 4: Forgetting to mount the EncryptionConfiguration file into the kube-apiserver container.**

The `--encryption-provider-config` flag specifies a path inside the kube-apiserver container's file system, not on the host node. Without a hostPath volume and corresponding volumeMount in the static pod manifest, the path does not exist inside the container and the API server refuses to start with a file-not-found error. Both the volume (at the Pod spec level) and the volumeMount (inside the container spec) are required. A common variant of this mistake is specifying the correct host path in the volume definition but a different path in the flag, for example, the volume mounts `/etc/kubernetes/enc` but the flag references `/etc/kubernetes/encryption`, causing a mismatch.

**Mistake 5: Skipping the re-encrypt step after enabling EncryptionConfiguration.**

After enabling encryption and confirming new Secrets show the `k8s:enc:` prefix in etcd, many operators consider the work done. But all Secrets that existed before encryption was enabled remain in plaintext in etcd. A security audit inspecting etcd directly will find them. The re-encrypt step (`kubectl get secrets --all-namespaces -o json | kubectl replace -f -`) is required to protect existing Secrets and is explicitly tested on the CKA exam under the encryption at rest competency.

---

## Verification Commands Cheat Sheet

| Use Case | Command |
|---|---|
| Read a Secret from etcd | `kubectl exec -n kube-system etcd-kind-control-plane -- sh -c "ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key get /registry/secrets/<ns>/<name>"` |
| List all etcd secret key paths | `kubectl exec -n kube-system etcd-kind-control-plane -- sh -c "ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key get /registry/secrets --prefix --keys-only"` |
| Decode a Secret value | `kubectl get secret <name> -n <ns> -o jsonpath='{.data.<key>}' \| base64 -d` |
| Generate a 32-byte aescbc key | `head -c 32 /dev/urandom \| base64` |
| Verify key byte length | `echo "<key>" \| base64 -d \| wc -c` |
| Copy file to kind node | `nerdctl cp <local> kind-control-plane:<remote>` |
| Copy file from kind node | `nerdctl cp kind-control-plane:<remote> <local>` |
| Exec into kind node | `nerdctl exec -it kind-control-plane bash` |
| Re-encrypt all Secrets | `kubectl get secrets --all-namespaces -o json \| kubectl replace -f -` |
| Re-encrypt all ConfigMaps | `kubectl get configmaps --all-namespaces -o json \| kubectl replace -f -` |
| Check API server encryption flag | `kubectl get pod kube-apiserver-kind-control-plane -n kube-system -o jsonpath='{.spec.containers[0].command}' \| tr ',' '\n' \| grep encryption` |
| Wait for API server to restart | `until kubectl cluster-info 2>/dev/null \| grep -q "Kubernetes control plane"; do sleep 5; done` |
| Check if SA token is mounted | `kubectl exec <pod> -n <ns> -- ls /var/run/secrets/kubernetes.io/serviceaccount/ 2>&1` |
| Read env var in container | `kubectl exec <pod> -n <ns> -- printenv <VAR>` |
| Read volume-mounted secret file | `kubectl exec <pod> -n <ns> -- cat /etc/secrets/<key>` |
