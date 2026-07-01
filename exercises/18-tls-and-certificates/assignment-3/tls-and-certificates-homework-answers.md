# TLS and Certificates Homework Answers: Certificate Troubleshooting

Complete solutions for all 15 exercises.

---

## Exercise 1.1 Solution

```bash
nerdctl exec kind-control-plane kubeadm certs check-expiration
```

Shows expiration for:
- admin.conf
- apiserver
- apiserver-etcd-client
- apiserver-kubelet-client
- controller-manager.conf
- etcd-healthcheck-client
- etcd-peer
- etcd-server
- front-proxy-client
- scheduler.conf

---

## Exercise 1.2 Solution

```bash
nerdctl exec kind-control-plane /bin/bash -c '
WARN_DAYS=30
NOW=$(date +%s)
for cert in /etc/kubernetes/pki/*.crt; do
  EXPIRY=$(openssl x509 -in $cert -noout -enddate | cut -d= -f2)
  EXPIRY_SEC=$(date -d "$EXPIRY" +%s)
  DAYS_LEFT=$(( (EXPIRY_SEC - NOW) / 86400 ))
  if [ $DAYS_LEFT -lt $WARN_DAYS ]; then
    echo "WARNING: $cert expires in $DAYS_LEFT days"
  else
    echo "OK: $cert expires in $DAYS_LEFT days"
  fi
done
'
```

---

## Exercise 1.3 Solution

```bash
nerdctl exec kind-control-plane openssl verify -CAfile /etc/kubernetes/pki/ca.crt /etc/kubernetes/pki/apiserver.crt
```

Output: `apiserver.crt: OK`

---

## Exercise 2.1 Solution

```bash
nerdctl exec kind-control-plane openssl x509 -in /etc/kubernetes/pki/etcd/server.crt -noout -issuer
```

Output shows `CN = etcd-ca`, not `CN = kubernetes`.

etcd certificates are signed by the etcd CA, which is separate from the cluster CA.

---

## Exercise 2.2 Solution

```bash
nerdctl exec kind-control-plane openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text | grep -E "DNS:|IP:"
```

Shows all SANs including kubernetes.default.svc.

---

## Exercise 2.3 Solution

```bash
nerdctl exec kind-control-plane ls -la /etc/kubernetes/pki/
```

**Expected permissions:**
- .crt files: 644 (readable by all)
- .key files: 600 (readable only by owner)

Key files with broader permissions are a security issue.

---

## Exercise 3.1 Solution

```bash
openssl x509 -in expired.crt -noout -dates
```

Check NotAfter against current date. If NotAfter is in the past, certificate is expired.

---

## Exercise 3.2 Solution

```bash
# Verify against wrong CA
openssl verify -CAfile ca2.crt test.crt
# Error: unable to verify the first certificate

# Verify against correct CA
openssl verify -CAfile ca1.crt test.crt
# test.crt: OK
```

**Diagnosis:** Check issuer and compare to expected CA:
```bash
openssl x509 -in test.crt -noout -issuer
# Shows CA1
```

---

## Exercise 3.3 Solution

```bash
openssl x509 -in noSAN.crt -noout -text | grep -A2 "Subject Alternative Name"
```

No output means no SANs. Server certificates need SANs for:
- All DNS names the server will be accessed by
- All IP addresses

Without SANs, TLS verification fails for any name other than CN.

---

## Exercise 4.1 Solution

**User Certificate Renewal Process:**

```bash
# 1. Generate new key and CSR
openssl genrsa -out user-new.key 2048
openssl req -new -key user-new.key -out user-new.csr -subj "/CN=user/O=group"

# 2. Submit CSR
CSR=$(cat user-new.csr | base64 -w0)
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: user-renewal
spec:
  request: $CSR
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
EOF

# 3. Approve
kubectl certificate approve user-renewal

# 4. Extract certificate
kubectl get csr user-renewal -o jsonpath='{.status.certificate}' | base64 -d > user-new.crt

# 5. Update kubeconfig
kubectl config set-credentials user --client-certificate=user-new.crt --client-key=user-new.key --embed-certs=true
```

---

## Exercise 4.2 Solution

**kubeadm Certificate Renewal:**

```bash
# Check current expiration
kubeadm certs check-expiration

# Renew all certificates
kubeadm certs renew all

# Or renew specific certificate
kubeadm certs renew apiserver

# Restart control plane (for static pods)
# Option 1: Restart kubelet
systemctl restart kubelet

# Option 2: Move and restore manifests
mv /etc/kubernetes/manifests/*.yaml /tmp/
sleep 10
mv /tmp/*.yaml /etc/kubernetes/manifests/

# Verify
kubectl get nodes
kubeadm certs check-expiration
```

---

## Exercise 4.3 Solution

**Update kubeconfig after renewal:**

```bash
# Option 1: kubectl config command
kubectl config set-credentials <user> \
  --client-certificate=new.crt \
  --client-key=new.key \
  --embed-certs=true

# Option 2: Edit kubeconfig directly
# Replace client-certificate-data with:
cat new.crt | base64 -w0

# Replace client-key-data with:
cat new.key | base64 -w0
```

---

## Exercise 4.4 Solution

### Diagnosis

On a kind cluster, worker nodes are accessible via `nerdctl exec` into the node container. First, identify a worker node:

```bash
kubectl get nodes
# Pick a worker node (e.g., kind-worker)
```

Access the node and locate the kubelet PKI directory:

```bash
nerdctl exec kind-worker find /var/lib/kubelet/pki
```

Output typically shows:
- `/var/lib/kubelet/pki/kubelet-client-current.pem` (client certificate)
- `/var/lib/kubelet/pki/kubelet.crt` (server certificate)
- `/var/lib/kubelet/pki/kubelet.key` (server private key)

The client certificate is used when the kubelet connects to the API server (outbound authentication). The server certificate is used when the API server connects to the kubelet for operations like `kubectl exec`, `kubectl logs`, or metrics scraping (inbound authentication).

### Extracting Certificate Information

For the **client certificate**, extract Issuer and Extended Key Usage:

```bash
nerdctl exec kind-worker openssl x509 -in /var/lib/kubelet/pki/kubelet-client-current.pem -noout -issuer
# Output: issuer=CN = kubernetes

nerdctl exec kind-worker openssl x509 -in /var/lib/kubelet/pki/kubelet-client-current.pem -noout -text | grep "Extended Key Usage" -A1
# Output:
#     X509v3 Extended Key Usage:
#         TLS Web Client Authentication
```

The client certificate is issued by the cluster CA (`CN = kubernetes`) and has Extended Key Usage set to TLS Web Client Authentication, confirming its role as an authentication credential for outbound connections.

For the **server certificate**, extract the same information:

```bash
nerdctl exec kind-worker openssl x509 -in /var/lib/kubelet/pki/kubelet.crt -noout -issuer
# Output: issuer=CN = kind-worker-ca@<timestamp>

nerdctl exec kind-worker openssl x509 -in /var/lib/kubelet/pki/kubelet.crt -noout -text | grep "Extended Key Usage" -A1
# Output:
#     X509v3 Extended Key Usage:
#         TLS Web Server Authentication
```

The server certificate is issued by a node-local CA (the Issuer CN includes the node hostname plus a timestamp, not `kubernetes`), and its Extended Key Usage is TLS Web Server Authentication, confirming its role as the certificate presented to incoming connections.

### The Fix

Write the information to `/tmp/kubelet-cert-info.txt`:

```bash
cat > /tmp/kubelet-cert-info.txt <<EOF
Client Certificate:
  Path: /var/lib/kubelet/pki/kubelet-client-current.pem
  Issuer: CN = kubernetes
  Extended Key Usage: TLS Web Client Authentication

Server Certificate:
  Path: /var/lib/kubelet/pki/kubelet.crt
  Issuer: CN = kind-worker-ca@<timestamp>
  Extended Key Usage: TLS Web Server Authentication
EOF
```

Replace `<timestamp>` with the actual timestamp from the server certificate's Issuer field. The key distinction is:
- **Client cert**: Cluster CA issuer, client authentication usage (kubelet → API server)
- **Server cert**: Node-local CA issuer, server authentication usage (API server → kubelet)

This two-certificate setup is how the kubelet authenticates both outbound (as a client to the API server) and inbound (as a server for kubectl operations).

---

## Exercise 5.1 Solution

**Certificate Audit Script:**

```bash
nerdctl exec kind-control-plane /bin/bash -c '
echo "======================================"
echo "Kubernetes Certificate Audit Report"
echo "======================================"
echo ""

for cert in /etc/kubernetes/pki/*.crt /etc/kubernetes/pki/etcd/*.crt; do
  [ -f "$cert" ] || continue
  echo "Certificate: $cert"
  echo "---"
  openssl x509 -in $cert -noout -subject 2>/dev/null | sed "s/^/  /"
  openssl x509 -in $cert -noout -issuer 2>/dev/null | sed "s/^/  /"
  openssl x509 -in $cert -noout -enddate 2>/dev/null | sed "s/^/  /"
  
  # Determine correct CA
  if [[ $cert == *"/etcd/"* ]]; then
    CA="/etc/kubernetes/pki/etcd/ca.crt"
  else
    CA="/etc/kubernetes/pki/ca.crt"
  fi
  
  # Verify
  if openssl verify -CAfile $CA $cert 2>/dev/null | grep -q "OK"; then
    echo "  Status: Valid"
  else
    echo "  Status: INVALID"
  fi
  echo ""
done
'
```

---

## Exercise 5.2 Solution

**Systematic Diagnostic Approach:**

```markdown
# Certificate Failure Diagnostic Procedure

## 1. Initial Assessment
kubeadm certs check-expiration
kubectl cluster-info

## 2. Check Control Plane Logs
# API server
kubectl logs -n kube-system kube-apiserver-<node> 2>/dev/null || \
  crictl logs $(crictl ps | grep apiserver | awk '{print $1}')

# Controller manager, scheduler
kubectl logs -n kube-system kube-controller-manager-<node>
kubectl logs -n kube-system kube-scheduler-<node>

## 3. Check etcd
kubectl logs -n kube-system etcd-<node> 2>/dev/null || \
  crictl logs $(crictl ps | grep etcd | awk '{print $1}')

## 4. Verify Certificate Chains
# API server
openssl verify -CAfile /etc/kubernetes/pki/ca.crt /etc/kubernetes/pki/apiserver.crt

# etcd
openssl verify -CAfile /etc/kubernetes/pki/etcd/ca.crt /etc/kubernetes/pki/etcd/server.crt

## 5. Check kubelet
journalctl -u kubelet -n 100 | grep -i cert

## 6. Resolution
# Renew expired: kubeadm certs renew <name>
# Wrong CA: Regenerate with correct CA
# Missing SAN: Regenerate with SANs
```

---

## Exercise 5.3 Solution

**Certificate Monitoring Strategy:**

```markdown
# Certificate Monitoring Strategy

## Automated Checks
Daily cron job:
```
0 0 * * * /usr/local/bin/check-k8s-certs.sh | mail -s "K8s Cert Report" admin@example.com
```

## Alert Thresholds
- Warning: 30 days before expiry
- Critical: 7 days before expiry

## Monitoring Script
```bash
#!/bin/bash
WARN_DAYS=30
CRIT_DAYS=7

for cert in /etc/kubernetes/pki/*.crt; do
  DAYS=$(cert-days-remaining $cert)
  if [ $DAYS -lt $CRIT_DAYS ]; then
    echo "CRITICAL: $cert expires in $DAYS days"
    # Send alert
  elif [ $DAYS -lt $WARN_DAYS ]; then
    echo "WARNING: $cert expires in $DAYS days"
    # Send alert
  fi
done
```

## Renewal Runbook
1. Schedule maintenance window
2. Backup etcd
3. Run kubeadm certs renew all
4. Restart control plane
5. Verify cluster health
6. Update documentation

## Verification After Renewal
- kubeadm certs check-expiration
- kubectl get nodes
- kubectl get pods --all-namespaces
- Test workload deployment
```

---

## Common Mistakes

1. **Checking wrong certificate:** API errors may be caused by different cert than expected
2. **Confusing CN with SAN:** Server certs need SANs, CN alone is insufficient
3. **Not restarting after renewal:** Components use cached certificates
4. **Renewing but not updating kubeconfig:** User certs need kubeconfig update
5. **Wrong CA for verification:** etcd certs use etcd CA, not cluster CA
6. **Permission issues after renewal:** New files may have wrong permissions

---

## Diagnostic Commands Cheat Sheet

| Task | Command |
|------|---------|
| Check all expiration | `kubeadm certs check-expiration` |
| Check one cert dates | `openssl x509 -in cert -noout -dates` |
| Check subject | `openssl x509 -in cert -noout -subject` |
| Check issuer | `openssl x509 -in cert -noout -issuer` |
| Check SANs | `openssl x509 -in cert -noout -text \| grep -A1 "Subject Alternative"` |
| Verify against CA | `openssl verify -CAfile ca.crt cert.crt` |
| Full cert dump | `openssl x509 -in cert -text -noout` |
| Check permissions | `ls -la /etc/kubernetes/pki/` |
| Renew all | `kubeadm certs renew all` |
| Renew specific | `kubeadm certs renew <name>` |
