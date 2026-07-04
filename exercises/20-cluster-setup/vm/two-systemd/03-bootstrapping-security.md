# Bootstrapping Kubernetes Security (Two Nodes)

**Based on:** [02-bootstrapping-security.md](../../single-systemd/02-bootstrapping-security.md) of the single-node guide.

**Adapted for:** A two-node cluster where each node generates its own certificates. The CA is generated on `controlplane-1` first and copied to `nodes-1` over scp, after which each node generates its own component certificates. The apiserver certificate's SAN list includes both VMs' IPs.

---

## What This Chapter Does

The single-node guide generated all certificates inside one VM. With two nodes, we need a per-node identity for kubelet (`system:node:controlplane-1` vs `system:node:nodes-1`) and an apiserver certificate that both nodes can validate. The cleanest workflow is:

1. Generate the CA and shared kubeconfigs on `controlplane-1`.
2. Copy the CA cert and key to `nodes-1` via scp.
3. On each node, generate that node's own kubelet/kube-proxy certificate.
4. Copy each node's kube-proxy kubeconfig from `controlplane-1` (or generate per-node, your choice).

The certs that need to be on both nodes are:

| File | Why on Both |
|------|-------------|
| `ca.pem` | Trust anchor; every component verifies against it |
| `kube-proxy.kubeconfig` | kube-proxy on each node uses it to talk to the apiserver |

The certs that are per-node:

| Node | File | Identity |
|------|------|----------|
| `controlplane-1` | `controlplane-1.pem`, `controlplane-1-key.pem`, `controlplane-1.kubeconfig` | `CN=system:node:controlplane-1`, `O=system:nodes` |
| `nodes-1` | `nodes-1.pem`, `nodes-1-key.pem`, `nodes-1.kubeconfig` | `CN=system:node:nodes-1`, `O=system:nodes` |

The certs that only `controlplane-1` needs (because only `controlplane-1` runs the control plane):

| File | Used By |
|------|---------|
| `kubernetes.pem`, `kubernetes-key.pem` | apiserver TLS |
| `service-account.pem`, `service-account-key.pem` | apiserver and controller-manager (token signing) |
| `kube-controller-manager.pem`, `kube-controller-manager.kubeconfig` | controller-manager |
| `kube-scheduler.pem`, `kube-scheduler.kubeconfig` | scheduler |
| `admin.pem`, `admin.kubeconfig` | Admin user / your kubectl access |

## What Is Different from the Single-Node Guide

- Apiserver cert SAN list now includes `192.168.122.10`, `192.168.122.11`, and the bridge gateway `192.168.122.1` (in case you ever talk to the apiserver from the host).
- Two `system:node:nodeN` certificates instead of one.
- CA distribution step (scp from `controlplane-1` to `nodes-1`).
- Each node's kubeconfig server URL points to `https://192.168.122.10:6443` (the apiserver's bridge IP), not `127.0.0.1`.

## Prerequisites

Document 02 complete. SSH from the host to both nodes works. Both VMs are running.

---

## Part 1: Install cfssl and kubectl on Both Nodes

cfssl generates certificates. kubectl writes kubeconfig files. Both must be installed on each node before starting.

Run on **both `controlplane-1` and `nodes-1`:**

```bash
# Install cfssl
sudo apt update
sudo apt install -y golang-cfssl

# Install kubectl
k8s_version=1.35.3
wget -q --show-progress --https-only --timestamping \
  "https://dl.k8s.io/release/v${k8s_version}/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Verify
cfssl version
kubectl version --client
```

---

## Part 2: Generate the CA on controlplane-1

The CA is the trust anchor. It is generated once on `controlplane-1` and copied to `nodes-1`. After this point, every certificate in the cluster will be signed by this CA.

```bash
ssh controlplane-1
mkdir -p ~/auth && cd ~/auth
```

### Step 1: CA CSR

```bash
cat > ca-csr.json <<'EOF'
{
  "CN": "Kubernetes",
  "key": { "algo": "rsa", "size": 2048 },
  "names": [{
    "C": "US", "L": "Austin", "O": "Kubernetes",
    "OU": "CKA Lab", "ST": "Texas"
  }]
}
EOF
```

### Step 2: Generate the CA

```bash
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
```

Produces `ca.pem` and `ca-key.pem`.

### Step 3: CA Signing Configuration

```bash
cat > ca-config.json <<'EOF'
{
  "signing": {
    "default": { "expiry": "87600h" },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "87600h"
      }
    }
  }
}
EOF
```

---

## Part 3: Generate Control-Plane Certificates on controlplane-1

These certificates are only needed on the control plane node. The apiserver cert in particular has a SAN list that needs both VMs' IPs.

### Step 1: API Server Certificate

The SAN list now includes both VMs. The single-node guide had `controlplane-1` and `10.0.2.15` (QEMU NAT IP). The two-node guide has `controlplane-1`, `nodes-1`, both bridge IPs, and the bridge gateway.

```bash
cat > kubernetes-csr.json <<'EOF'
{
  "CN": "kubernetes",
  "key": { "algo": "rsa", "size": 2048 },
  "names": [{
    "C": "US", "L": "Austin", "O": "Kubernetes",
    "OU": "CKA Lab", "ST": "Texas"
  }],
  "hosts": [
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local",
    "10.96.0.1",
    "controlplane-1",
    "nodes-1",
    "192.168.122.10",
    "192.168.122.11",
    "192.168.122.1",
    "127.0.0.1"
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem -ca-key=ca-key.pem \
  -config=ca-config.json -profile=kubernetes \
  kubernetes-csr.json | cfssljson -bare kubernetes
```

### Step 2: Admin User Certificate

```bash
cat > admin-csr.json <<'EOF'
{
  "CN": "admin",
  "key": { "algo": "rsa", "size": 2048 },
  "names": [{
    "C": "US", "L": "Austin", "O": "system:masters",
    "OU": "CKA Lab", "ST": "Texas"
  }]
}
EOF

cfssl gencert \
  -ca=ca.pem -ca-key=ca-key.pem \
  -config=ca-config.json -profile=kubernetes \
  admin-csr.json | cfssljson -bare admin
```

### Step 3: kube-controller-manager Certificate

```bash
cat > kube-controller-manager-csr.json <<'EOF'
{
  "CN": "system:kube-controller-manager",
  "key": { "algo": "rsa", "size": 2048 },
  "names": [{
    "C": "US", "L": "Austin", "O": "system:kube-controller-manager",
    "OU": "CKA Lab", "ST": "Texas"
  }]
}
EOF

cfssl gencert \
  -ca=ca.pem -ca-key=ca-key.pem \
  -config=ca-config.json -profile=kubernetes \
  kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager
```

### Step 4: kube-scheduler Certificate

```bash
cat > kube-scheduler-csr.json <<'EOF'
{
  "CN": "system:kube-scheduler",
  "key": { "algo": "rsa", "size": 2048 },
  "names": [{
    "C": "US", "L": "Austin", "O": "system:kube-scheduler",
    "OU": "CKA Lab", "ST": "Texas"
  }]
}
EOF

cfssl gencert \
  -ca=ca.pem -ca-key=ca-key.pem \
  -config=ca-config.json -profile=kubernetes \
  kube-scheduler-csr.json | cfssljson -bare kube-scheduler
```

### Step 5: kube-proxy Certificate

kube-proxy runs on both nodes. Same identity on both, so this is a shared cert.

```bash
cat > kube-proxy-csr.json <<'EOF'
{
  "CN": "system:kube-proxy",
  "key": { "algo": "rsa", "size": 2048 },
  "names": [{
    "C": "US", "L": "Austin", "O": "system:node-proxier",
    "OU": "CKA Lab", "ST": "Texas"
  }]
}
EOF

cfssl gencert \
  -ca=ca.pem -ca-key=ca-key.pem \
  -config=ca-config.json -profile=kubernetes \
  kube-proxy-csr.json | cfssljson -bare kube-proxy
```

### Step 6: Service Account Token Signing Key Pair

```bash
cat > service-account-csr.json <<'EOF'
{
  "CN": "service-accounts",
  "key": { "algo": "rsa", "size": 2048 },
  "names": [{
    "C": "US", "L": "Austin", "O": "Kubernetes",
    "OU": "CKA Lab", "ST": "Texas"
  }]
}
EOF

cfssl gencert \
  -ca=ca.pem -ca-key=ca-key.pem \
  -config=ca-config.json -profile=kubernetes \
  service-account-csr.json | cfssljson -bare service-account
```

### Step 7: controlplane-1's Own Node Certificate

```bash
cat > controlplane-1-csr.json <<'EOF'
{
  "CN": "system:node:controlplane-1",
  "key": { "algo": "rsa", "size": 2048 },
  "names": [{
    "C": "US", "L": "Austin", "O": "system:nodes",
    "OU": "CKA Lab", "ST": "Texas"
  }],
  "hosts": [
    "controlplane-1",
    "192.168.122.10",
    "127.0.0.1"
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem -ca-key=ca-key.pem \
  -config=ca-config.json -profile=kubernetes \
  controlplane-1-csr.json | cfssljson -bare controlplane-1
```

---

## Part 4: Distribute the CA to nodes-1

`nodes-1` needs the CA cert (`ca.pem`) and the CA key (`ca-key.pem`) so it can sign its own kubelet certificate. It also needs the kube-proxy certs and kubeconfig (which are not per-node).

From `controlplane-1`:

```bash
# Copy CA cert and key, kube-proxy bundle, and ca-config to nodes-1
scp ~/auth/ca.pem ~/auth/ca-key.pem ~/auth/ca-config.json \
    ~/auth/kube-proxy.pem ~/auth/kube-proxy-key.pem \
    nodes-1:/tmp/auth-bootstrap/

# Move into place on nodes-1
ssh nodes-1 'mkdir -p ~/auth && mv /tmp/auth-bootstrap/* ~/auth/'
```

If the scp fails because `/tmp/auth-bootstrap` does not exist:

```bash
ssh nodes-1 'mkdir -p /tmp/auth-bootstrap'
# Then re-run the scp
```

---

## Part 5: Generate nodes-1's Node Certificate (on nodes-1)

`nodes-1` now has the CA. Generate its own kubelet identity:

```bash
ssh nodes-1
cd ~/auth

cat > nodes-1-csr.json <<'EOF'
{
  "CN": "system:node:nodes-1",
  "key": { "algo": "rsa", "size": 2048 },
  "names": [{
    "C": "US", "L": "Austin", "O": "system:nodes",
    "OU": "CKA Lab", "ST": "Texas"
  }],
  "hosts": [
    "nodes-1",
    "192.168.122.11",
    "127.0.0.1"
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem -ca-key=ca-key.pem \
  -config=ca-config.json -profile=kubernetes \
  nodes-1-csr.json | cfssljson -bare nodes-1
```

After this, `nodes-1:~/auth/` contains its own certs plus the shared CA and kube-proxy material.

---

## Part 6: Generate Kubeconfigs

Each kubeconfig bundles the CA, a client cert, and a client key, plus the API server URL. With two nodes, all kubeconfigs point at `https://192.168.122.10:6443` because that is where the apiserver listens.

### Step 1: Helper Function

Same helper as the single-node guide, but with the bridge IP. Run on **controlplane-1**:

```bash
ssh controlplane-1
cd ~/auth

genkubeconfig() {
  cert=$1
  user=$2
  kubeconfig="${cert}.kubeconfig"

  kubectl config set-cluster cka-twonode \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://192.168.122.10:6443 \
    --kubeconfig="$kubeconfig"

  kubectl config set-credentials "$user" \
    --client-certificate="${cert}.pem" \
    --client-key="${cert}-key.pem" \
    --embed-certs=true \
    --kubeconfig="$kubeconfig"

  kubectl config set-context default \
    --cluster=cka-twonode \
    --user="$user" \
    --kubeconfig="$kubeconfig"

  kubectl config use-context default \
    --kubeconfig="$kubeconfig"
}
```

### Step 2: Generate kubeconfigs on controlplane-1

```bash
genkubeconfig admin admin
genkubeconfig controlplane-1 system:node:controlplane-1
genkubeconfig kube-scheduler system:kube-scheduler
genkubeconfig kube-controller-manager system:kube-controller-manager
genkubeconfig kube-proxy system:kube-proxy
```

### Step 3: Copy Shared kubeconfig (kube-proxy) and Generate nodes-1's Own

`kube-proxy.kubeconfig` is identical on both nodes (same kube-proxy identity). Copy it:

```bash
scp ~/auth/kube-proxy.kubeconfig nodes-1:~/auth/
```

`nodes-1.kubeconfig` is unique to `nodes-1` and uses `nodes-1`'s certificate. Generate it on `nodes-1`:

```bash
ssh nodes-1
cd ~/auth

genkubeconfig() {
  cert=$1
  user=$2
  kubeconfig="${cert}.kubeconfig"

  kubectl config set-cluster cka-twonode \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://192.168.122.10:6443 \
    --kubeconfig="$kubeconfig"

  kubectl config set-credentials "$user" \
    --client-certificate="${cert}.pem" \
    --client-key="${cert}-key.pem" \
    --embed-certs=true \
    --kubeconfig="$kubeconfig"

  kubectl config set-context default \
    --cluster=cka-twonode \
    --user="$user" \
    --kubeconfig="$kubeconfig"

  kubectl config use-context default \
    --kubeconfig="$kubeconfig"
}

genkubeconfig nodes-1 system:node:nodes-1
```

---

## Part 7: Generate the Encryption Config (on controlplane-1)

```bash
ssh controlplane-1
cd ~/auth

key=$(head -c 32 /dev/urandom | base64)

cat > encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: $key
      - identity: {}
EOF
```

This file is only used by the apiserver, which only runs on `controlplane-1`. No copy to `nodes-1` needed.

---

## Part 8: Optional - Host-Side admin.kubeconfig

For running `kubectl` from the host machine, copy the admin kubeconfig out of `controlplane-1`:

```bash
# From the host
mkdir -p ~/cka-lab/two-systemd
scp controlplane-1:~/auth/admin.kubeconfig ~/cka-lab/two-systemd/admin.conf
scp controlplane-1:~/auth/ca.pem ~/cka-lab/two-systemd/ca.pem

# The admin kubeconfig already references https://192.168.122.10:6443, which
# is reachable from the host through the bridge. Test:
KUBECONFIG=~/cka-lab/two-systemd/admin.conf kubectl version --client
```

Once the apiserver is up (next document) you will be able to run `kubectl get nodes` from the host using this kubeconfig.

---

## Summary

After this chapter, the auth state on each node is:

**controlplane-1 `~/auth/`:**

| File | Purpose |
|------|---------|
| `ca.pem`, `ca-key.pem`, `ca-config.json` | Cluster CA |
| `kubernetes.pem`, `kubernetes-key.pem` | apiserver TLS cert (with both VMs in SAN) |
| `admin.pem`, `admin-key.pem` | Admin user client cert |
| `controlplane-1.pem`, `controlplane-1-key.pem` | controlplane-1's kubelet cert |
| `kube-controller-manager.pem`, `kube-controller-manager-key.pem` | Controller-manager client cert |
| `kube-scheduler.pem`, `kube-scheduler-key.pem` | Scheduler client cert |
| `kube-proxy.pem`, `kube-proxy-key.pem` | kube-proxy client cert |
| `service-account.pem`, `service-account-key.pem` | ServiceAccount token signing key pair |
| `admin.kubeconfig` | Admin kubeconfig |
| `controlplane-1.kubeconfig` | controlplane-1's kubelet kubeconfig |
| `kube-controller-manager.kubeconfig` | Controller-manager kubeconfig |
| `kube-scheduler.kubeconfig` | Scheduler kubeconfig |
| `kube-proxy.kubeconfig` | Shared kube-proxy kubeconfig |
| `encryption-config.yaml` | Encryption key for Secrets at rest |

**nodes-1 `~/auth/`:**

| File | Purpose |
|------|---------|
| `ca.pem`, `ca-key.pem`, `ca-config.json` | Cluster CA (copied from controlplane-1) |
| `nodes-1.pem`, `nodes-1-key.pem` | nodes-1's kubelet cert (generated locally) |
| `nodes-1.kubeconfig` | nodes-1's kubelet kubeconfig (generated locally) |
| `kube-proxy.pem`, `kube-proxy-key.pem` | kube-proxy client cert (copied from controlplane-1) |
| `kube-proxy.kubeconfig` | Shared kube-proxy kubeconfig (copied from controlplane-1) |

The next document brings up the control plane on `controlplane-1`.
