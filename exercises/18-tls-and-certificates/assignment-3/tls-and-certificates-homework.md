# TLS and Certificates Homework: Certificate Troubleshooting

This homework contains 15 exercises covering certificate troubleshooting.

---

## Level 1: Certificate Health Checks

### Exercise 1.1

**Objective:** Check expiration dates for all cluster certificates.

**Setup:**
```bash
kubectl create namespace ex-1-1
```

**Task:** Use kubeadm to check expiration dates for all cluster certificates.

**Verification:**
```bash
nerdctl exec kind-control-plane kubeadm certs check-expiration && echo "SUCCESS"
```

---

### Exercise 1.2

**Objective:** Identify certificates expiring within 30 days.

**Setup:**
```bash
kubectl create namespace ex-1-2
```

**Task:** Check each certificate in /etc/kubernetes/pki/ and identify any expiring within 30 days.

**Verification:**
```bash
nerdctl exec kind-control-plane /bin/bash -c '
for cert in /etc/kubernetes/pki/*.crt; do
  echo "=== $cert ==="
  openssl x509 -in $cert -noout -enddate
done
' && echo "SUCCESS"
```

---

### Exercise 1.3

**Objective:** Verify the certificate chain for a component.

**Setup:**
```bash
kubectl create namespace ex-1-3
```

**Task:** Verify that the API server certificate was signed by the cluster CA.

**Verification:**
```bash
nerdctl exec kind-control-plane openssl verify -CAfile /etc/kubernetes/pki/ca.crt /etc/kubernetes/pki/apiserver.crt && echo "SUCCESS"
```

---

## Level 2: Diagnosing Issues

### Exercise 2.1

**Objective:** Identify the CA that signed a given certificate.

**Setup:**
```bash
kubectl create namespace ex-2-1
```

**Task:** Determine which CA signed the etcd server certificate.

**Verification:**
```bash
nerdctl exec kind-control-plane openssl x509 -in /etc/kubernetes/pki/etcd/server.crt -noout -issuer && echo "SUCCESS"
# Should show etcd-ca, not kubernetes CA
```

---

### Exercise 2.2

**Objective:** Verify a certificate is valid for a specific hostname.

**Setup:**
```bash
kubectl create namespace ex-2-2
```

**Task:** Check if the API server certificate is valid for "kubernetes.default.svc".

**Verification:**
```bash
nerdctl exec kind-control-plane openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text | grep -q "kubernetes.default.svc" && echo "SUCCESS"
```

---

### Exercise 2.3

**Objective:** Check file permissions on certificate files.

**Setup:**
```bash
kubectl create namespace ex-2-3
```

**Task:** Check the permissions on certificate and key files in /etc/kubernetes/pki/. Identify any permission issues.

**Verification:**
```bash
nerdctl exec kind-control-plane ls -la /etc/kubernetes/pki/*.key | head -5 && echo "SUCCESS"
# Keys should be 600 or more restrictive
```

---

## Level 3: Debugging Broken Certificates

### Exercise 3.1

**Objective:** Diagnose the certificate issue.

**Setup:**
```bash
kubectl create namespace ex-3-1
mkdir -p /tmp/ex-3-1 && cd /tmp/ex-3-1
# Create an expired certificate for testing
openssl genrsa -out expired.key 2048
openssl req -new -key expired.key -out expired.csr -subj "/CN=expired"
# Sign with past dates
openssl x509 -req -in expired.csr -signkey expired.key -out expired.crt -days -1 2>/dev/null || \
  openssl x509 -req -in expired.csr -signkey expired.key -out expired.crt -days 1
```

**Task:** Check if expired.crt is valid by examining its dates.

**Verification:**
```bash
openssl x509 -in expired.crt -noout -dates && echo "SUCCESS"
echo "Check if NotAfter is in the past"
```

---

### Exercise 3.2

**Objective:** Diagnose a certificate signed by wrong CA.

**Setup:**
```bash
kubectl create namespace ex-3-2
mkdir -p /tmp/ex-3-2 && cd /tmp/ex-3-2
# Create two CAs
openssl genrsa -out ca1.key 2048
openssl req -x509 -new -key ca1.key -out ca1.crt -subj "/CN=CA1"
openssl genrsa -out ca2.key 2048
openssl req -x509 -new -key ca2.key -out ca2.crt -subj "/CN=CA2"
# Sign cert with CA1
openssl genrsa -out test.key 2048
openssl req -new -key test.key -out test.csr -subj "/CN=test"
openssl x509 -req -in test.csr -CA ca1.crt -CAkey ca1.key -CAcreateserial -out test.crt
```

**Task:** Verify test.crt against ca2.crt and observe the error.

**Verification:**
```bash
openssl verify -CAfile ca2.crt test.crt || echo "Verification failed as expected"
echo "Certificate was signed by CA1, not CA2" && echo "SUCCESS"
```

---

### Exercise 3.3

**Objective:** Diagnose a missing SAN issue.

**Setup:**
```bash
kubectl create namespace ex-3-3
mkdir -p /tmp/ex-3-3 && cd /tmp/ex-3-3
openssl genrsa -out noSAN.key 2048
openssl req -new -key noSAN.key -out noSAN.csr -subj "/CN=myserver"
openssl genrsa -out ca.key 2048
openssl req -x509 -new -key ca.key -out ca.crt -subj "/CN=TestCA"
openssl x509 -req -in noSAN.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out noSAN.crt
```

**Task:** Check if noSAN.crt has any Subject Alternative Names.

**Verification:**
```bash
openssl x509 -in noSAN.crt -noout -text | grep "Subject Alternative Name" || echo "No SANs found"
echo "Server certificates should have SANs for all hostnames they serve" && echo "SUCCESS"
```

---

## Level 4: Certificate Renewal

### Exercise 4.1

**Objective:** Document the user certificate renewal process.

**Setup:**
```bash
kubectl create namespace ex-4-1
```

**Task:** Document the steps to renew a user certificate that is about to expire.

**Verification:**
```bash
echo "Steps: 1) Generate new key/CSR, 2) Submit CSR, 3) Approve, 4) Extract cert, 5) Update kubeconfig"
echo "SUCCESS"
```

---

### Exercise 4.2

**Objective:** Document the kubeadm certificate renewal process.

**Setup:**
```bash
kubectl create namespace ex-4-2
```

**Task:** Document the commands to renew cluster certificates with kubeadm.

**Verification:**
```bash
echo "Commands: kubeadm certs check-expiration, kubeadm certs renew all"
echo "After renewal: restart control plane components"
echo "SUCCESS"
```

---

### Exercise 4.3

**Objective:** Update kubeconfig after certificate renewal.

**Setup:**
```bash
kubectl create namespace ex-4-3
```

**Task:** Document how to update a kubeconfig file after renewing its certificate.

**Verification:**
```bash
echo "Steps: 1) kubectl config set-credentials <user> --client-certificate=new.crt --client-key=new.key --embed-certs=true"
echo "Or: Edit kubeconfig directly, replacing certificate-data"
echo "SUCCESS"
```

---

### Exercise 4.4

**Objective:** Inspect kubelet client and server certificates and document their distinct roles.

**Setup:**
```bash
kubectl create namespace ex-4-4
```

**Task:** The kubelet on a worker node uses two distinct certificates: a client certificate for outbound connections to the API server, and a server certificate for inbound connections (kubectl exec, kubectl logs). On a kind cluster worker node, locate both certificates in `/var/lib/kubelet/pki/`, extract the Issuer and Extended Key Usage for each, and write the information to `/tmp/kubelet-cert-info.txt` in the format:

```
Client Certificate:
  Path: <path>
  Issuer: <issuer>
  Extended Key Usage: <usage>

Server Certificate:
  Path: <path>
  Issuer: <issuer>
  Extended Key Usage: <usage>
```

**Verification:**
```bash
# Check that both certificates were inspected
grep -q "Client Certificate" /tmp/kubelet-cert-info.txt
# Expected: exit 0

grep -q "Server Certificate" /tmp/kubelet-cert-info.txt
# Expected: exit 0

grep -q "/var/lib/kubelet/pki/kubelet-client-current.pem" /tmp/kubelet-cert-info.txt
# Expected: exit 0 (client cert path)

grep -q "/var/lib/kubelet/pki/kubelet.crt" /tmp/kubelet-cert-info.txt
# Expected: exit 0 (server cert path)

grep -q "CN.*kubernetes" /tmp/kubelet-cert-info.txt
# Expected: exit 0 (client cert issued by cluster CA)

grep -i "TLS Web Client Authentication" /tmp/kubelet-cert-info.txt
# Expected: exit 0 (client cert usage)

grep -i "TLS Web Server Authentication" /tmp/kubelet-cert-info.txt
# Expected: exit 0 (server cert usage)

# Verify understanding: Client cert Issuer should be cluster CA (CN=kubernetes)
# Server cert Issuer should be node-local CA (CN contains node hostname)
cat /tmp/kubelet-cert-info.txt
```

---

## Level 5: Complex Scenarios

### Exercise 5.1

**Objective:** Create a full cluster certificate audit.

**Setup:**
```bash
kubectl create namespace ex-5-1
```

**Task:** Create a report showing for each certificate in /etc/kubernetes/pki/:
- Certificate name
- Subject
- Issuer
- Expiration date
- Whether it is valid

**Verification:**
```bash
nerdctl exec kind-control-plane /bin/bash -c '
echo "Certificate Audit Report"
echo "========================"
for cert in /etc/kubernetes/pki/*.crt /etc/kubernetes/pki/etcd/*.crt; do
  [ -f "$cert" ] || continue
  echo ""
  echo "=== $cert ==="
  openssl x509 -in $cert -noout -subject -issuer -enddate 2>/dev/null
done
' && echo "SUCCESS"
```

---

### Exercise 5.2

**Objective:** Diagnose a multi-certificate failure scenario.

**Setup:**
```bash
kubectl create namespace ex-5-2
```

**Task:** A cluster is failing with certificate errors. Document a systematic approach to diagnose which certificate(s) are problematic.

**Verification:**
```bash
echo "Diagnostic approach:"
echo "1. Check kubeadm certs check-expiration"
echo "2. Check API server logs for cert errors"
echo "3. Verify each cert against its CA"
echo "4. Check kubelet logs"
echo "5. Check etcd logs"
echo "SUCCESS"
```

---

### Exercise 5.3

**Objective:** Create a certificate monitoring strategy.

**Setup:**
```bash
kubectl create namespace ex-5-3
```

**Task:** Design a monitoring and alerting strategy for certificate expiration.

**Verification:**
```bash
echo "Strategy should include:"
echo "1. Regular expiration checks (daily cron)"
echo "2. Alert when <30 days to expiry"
echo "3. Automated renewal or runbook"
echo "4. Verification after renewal"
echo "SUCCESS"
```

---

## Cleanup

```bash
kubectl delete namespace ex-1-1 ex-1-2 ex-1-3 ex-2-1 ex-2-2 ex-2-3 ex-3-1 ex-3-2 ex-3-3 ex-4-1 ex-4-2 ex-4-3 ex-5-1 ex-5-2 ex-5-3
rm -rf /tmp/ex-3-1 /tmp/ex-3-2 /tmp/ex-3-3
```

---

## Key Takeaways

1. **Proactive checking:** Check expiration before problems occur
2. **Certificate chain:** Always verify cert was signed by expected CA
3. **SANs required:** Server certs need SANs for hostnames
4. **Permission issues:** Keys should have restrictive permissions
5. **Restart after renewal:** Components must restart to use new certs
6. **Update kubeconfig:** After user cert renewal, update kubeconfig
