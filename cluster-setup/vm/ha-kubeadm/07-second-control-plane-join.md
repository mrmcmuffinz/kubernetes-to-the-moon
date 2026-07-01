# Second Control Plane Join

**Purpose:** Join `controlplane-2` as a second control plane node. This is the step
unique to HA setups: `kubeadm join --control-plane` copies the certificates from the
cluster's kubeadm-managed Secret, starts a second etcd instance on the node, and
configures the API server to advertise `controlplane-2`'s own IP while connecting to
the HAProxy VIP.

---

## Prerequisites

- `controlplane-1` is `Ready` with Calico installed (document 06).
- `controlplane-2` has containerd and kubeadm installed (document 03).
- The certificate key from `kubeadm init --upload-certs` is still valid (2-hour TTL).

If the certificate key has expired, generate a new one on `controlplane-1`:

```bash
ssh controlplane-1 'sudo kubeadm init phase upload-certs --upload-certs'
```

This prints a new certificate key. Use it in the join command below.

## Part 1: Preflight Check on controlplane-2

```bash
ssh controlplane-2 '
  sudo crictl info 2>/dev/null | grep -q runtimeHandlers && echo "containerd: OK"
  free -h | grep Swap
  curl -sk https://192.168.100.100:6443/healthz && echo " (VIP reachable)"
'
```

## Part 2: Construct the Control Plane Join Command

The control plane join command differs from the worker join command in two ways:
- `--control-plane` flag: tells kubeadm to install etcd and the full control plane
- `--certificate-key`: decrypts the certificates uploaded to the cluster Secret

From the kubeadm init output (document 05), your command looks like:

```bash
sudo kubeadm join 192.168.100.100:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane \
  --certificate-key <cert-key> \
  --apiserver-advertise-address 192.168.100.21
```

The `--apiserver-advertise-address 192.168.100.21` is critical: it tells `controlplane-2`
to advertise its own IP (not the VIP) as the address of its local API server. The VIP
is what clients use, but each API server must advertise its own IP to etcd peers.

If you no longer have the original join command, retrieve the token and hash on
`controlplane-1`:

```bash
ssh controlplane-1 '
  # Get current token (or create new)
  TOKEN=$(kubeadm token list -o jsonpath="{.items[0].token}" 2>/dev/null || \
          kubeadm token create)
  echo "Token: $TOKEN"

  # Get CA cert hash
  openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
    openssl rsa -pubin -outform der 2>/dev/null | \
    openssl dgst -sha256 -hex | sed "s/^.* //"
  echo "(prefix sha256: to the hash above)"

  # Upload certs and get new key
  sudo kubeadm init phase upload-certs --upload-certs
  echo "(use the last line as --certificate-key)"
'
```

## Part 3: Run the Join Command

On `controlplane-2`:

**Single-NIC setup (default):** use the inline command:

```bash
ssh controlplane-2

sudo kubeadm join 192.168.100.100:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane \
  --certificate-key <cert-key> \
  --apiserver-advertise-address 192.168.100.21
```

**Dual-NIC callout:** If you used Option C from document 02, pass a config file instead
so kubeadm can pin `--node-ip` to the cluster NIC. On `controlplane-2`:

```bash
ssh controlplane-2

cat > ~/kubeadm-join-cp2.yaml <<'EOF'
apiVersion: kubeadm.k8s.io/v1beta4
kind: JoinConfiguration
discovery:
  bootstrapToken:
    apiServerEndpoint: "192.168.100.100:6443"
    token: <token>
    caCertHashes:
      - sha256:<hash>
controlPlane:
  localAPIEndpoint:
    advertiseAddress: "192.168.100.21"
    bindPort: 6443
  certificateKey: <cert-key>
nodeRegistration:
  kubeletExtraArgs:
    - name: "node-ip"
      value: "192.168.100.21"
EOF

sudo kubeadm join --config ~/kubeadm-join-cp2.yaml
```

This takes 1-2 minutes. kubeadm will:
1. Download and unpack the certificates from the cluster Secret.
2. Generate a kubelet certificate for `controlplane-2`.
3. Start the etcd member process and join the existing etcd cluster.
4. Start the kube-apiserver configured to advertise `192.168.100.21`.
5. Start kube-controller-manager and kube-scheduler (active/standby -- only one runs
   leader election at a time).

## Part 4: Set Up kubectl on controlplane-2

```bash
mkdir -p ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
```

## Part 5: Verify Both Control Planes

From `controlplane-1` or the host:

```bash
kubectl get nodes -o wide
# Both control planes should show Ready (after Calico schedules calico-node on controlplane-2)
```

Wait up to 90 seconds for Calico on `controlplane-2`.

## Part 6: Verify etcd Has Two Members

```bash
ssh controlplane-1 '
  sudo ETCDCTL_API=3 etcdctl member list \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key
'
```

Expected output: two members, both showing `started`:

```
<id>, started, controlplane-1, https://192.168.100.20:2380, https://192.168.100.20:2379
<id>, started, controlplane-2, https://192.168.100.21:2380, https://192.168.100.21:2379
```

## Part 7: Verify controlplane-2 API Server is Reachable via VIP

HAProxy should now have both backends `UP`. The stats page at
`http://192.168.100.1:9000/stats` should show both servers active.

Test direct connectivity:

```bash
# Direct to controlplane-2
curl -sk https://192.168.100.21:6443/healthz
# Expected: ok

# Via VIP (may route to either control plane)
curl -sk https://192.168.100.100:6443/healthz
# Expected: ok
```

## Part 8: Optional -- Remove controlplane-2 Taint

If you want workloads to schedule on `controlplane-2`:

```bash
kubectl taint nodes controlplane-2 node-role.kubernetes.io/control-plane:NoSchedule-
```

This is optional. With three worker nodes, leaving the control planes tainted keeps
the control plane clean and is closer to production behavior.

**Result:** Both control planes `Ready`, etcd has two members, HAProxy routes to both
API servers, and the VIP continues to serve traffic when either control plane is down.

---

← [Previous: CNI Installation: Calico](06-cni-installation.md) | [Next: Worker Join: nodes-1, nodes-2, nodes-3 →](08-worker-join.md)
