# CoreDNS Homework Answers: Advanced DNS Patterns

This document provides complete solutions for all 15 exercises. Debugging exercises (Levels 3 and 5) include diagnostic steps, bug explanation, and the fix. Study the diagnostic reasoning, not just the final solution, as the CKA exam tests your ability to identify problems from symptoms.

---

## Exercise 1.1 Solution

Create the headless service by exposing the deployment with `--cluster-ip=None`:

```bash
kubectl -n ex-1-1 expose deployment app --name=app-headless --port=80 --cluster-ip=None
```

Declarative form:

```bash
kubectl -n ex-1-1 apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: app-headless
spec:
  clusterIP: None
  selector:
    app: app
  ports:
  - port: 80
    targetPort: 80
EOF
```

The key is `clusterIP: None`, which makes this a headless service. DNS queries for the service return all pod IPs instead of a single virtual IP.

---

## Exercise 1.2 Solution

Create the ExternalName service:

```bash
kubectl -n ex-1-2 create service externalname external-api --external-name=api.github.com
```

Declarative form:

```bash
kubectl -n ex-1-2 apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: external-api
spec:
  type: ExternalName
  externalName: api.github.com
EOF
```

ExternalName services have no ClusterIP, no selector, and no endpoints. They exist purely as DNS aliases, creating a CNAME record from the service name to the external domain.

---

## Exercise 1.3 Solution

Create both services:

```bash
kubectl -n ex-1-3 expose deployment backend --name=backend-headless --port=80 --cluster-ip=None
kubectl -n ex-1-3 expose deployment backend --name=backend-clusterip --port=80
```

Declarative form:

```bash
kubectl -n ex-1-3 apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: backend-headless
spec:
  clusterIP: None
  selector:
    app: backend
  ports:
  - port: 80
---
apiVersion: v1
kind: Service
metadata:
  name: backend-clusterip
spec:
  selector:
    app: backend
  ports:
  - port: 80
    targetPort: 80
EOF
```

The headless service DNS returns multiple A records (one per pod), while the ClusterIP service DNS returns a single A record (the service virtual IP). Both services select the same pods, but DNS behavior is fundamentally different.

---

## Exercise 2.1 Solution

Create the headless service and pod:

```bash
kubectl -n ex-2-1 apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: db-cluster
spec:
  clusterIP: None
  selector:
    app: database
  ports:
  - port: 5432
---
apiVersion: v1
kind: Pod
metadata:
  name: db-primary
  labels:
    app: database
spec:
  hostname: db-primary
  subdomain: db-cluster
  containers:
  - name: postgres
    image: postgres:16-alpine
    env:
    - name: POSTGRES_PASSWORD
      value: example
    ports:
    - containerPort: 5432
EOF
```

The pod's `hostname: db-primary` and `subdomain: db-cluster` fields combine to create the stable DNS name `db-primary.db-cluster.ex-2-1.svc.cluster.local`. The headless service `db-cluster` must exist for this DNS record to be created.

---

## Exercise 2.2 Solution

Query the original IP:

```bash
kubectl -n ex-2-2 exec dns-test -- nslookup replica-1.replica-svc.ex-2-2.svc.cluster.local | grep Address | tail -1
```

Delete and recreate the pod:

```bash
kubectl -n ex-2-2 delete pod replica-1
kubectl -n ex-2-2 apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: replica-1
  labels:
    app: replica
spec:
  hostname: replica-1
  subdomain: replica-svc
  containers:
  - name: nginx
    image: nginx:1.27
    ports:
    - containerPort: 80
EOF
kubectl -n ex-2-2 wait --for=condition=ready pod/replica-1 --timeout=60s
```

Query the DNS name again:

```bash
kubectl -n ex-2-2 exec dns-test -- nslookup replica-1.replica-svc.ex-2-2.svc.cluster.local | grep Address | tail -1
```

The IP will be different (the pod got a new IP from the pod CIDR), but the DNS name `replica-1.replica-svc.ex-2-2.svc.cluster.local` still resolves. This demonstrates that hostname/subdomain-based DNS survives IP changes, unlike IP-based pod DNS which breaks when the IP changes.

---

## Exercise 2.3 Solution

Get the pod IP and construct the IP-based DNS name:

```bash
POD_IP=$(kubectl -n ex-2-3 get pod worker-a -o jsonpath='{.status.podIP}')
IP_DNS=$(echo $POD_IP | tr '.' '-')
echo "IP-based DNS: ${IP_DNS}.ex-2-3.pod.cluster.local"
echo "Subdomain-based DNS: worker-a.worker-svc.ex-2-3.svc.cluster.local"
```

Both DNS names resolve to the same IP:

```bash
kubectl -n ex-2-3 exec dns-test -- nslookup ${IP_DNS}.ex-2-3.pod.cluster.local
kubectl -n ex-2-3 exec dns-test -- nslookup worker-a.worker-svc.ex-2-3.svc.cluster.local
```

The IP-based format uses the pod's namespace (`pod.cluster.local` domain), while the subdomain-based format uses the service namespace (`svc.cluster.local` domain) and requires both the pod's subdomain field and a matching headless service to exist.

---

## Exercise 3.1 Solution

### Diagnosis

Check the headless service configuration:

```bash
kubectl -n ex-3-1 get svc cache-headless -o yaml
```

The service exists and has `clusterIP: None`. Check the endpoints:

```bash
kubectl -n ex-3-1 get endpoints cache-headless
```

Output shows `<none>` under ENDPOINTS. This means no pods match the service selector. Check what pods exist in the namespace:

```bash
kubectl -n ex-3-1 get pods --show-labels
```

Only the dns-test pod exists, with no `app: cache-server` label.

### What the bug is and why it happens

The headless service selector is `app: cache-server`, but no pods with that label exist. DNS for a headless service returns A records based on the service's endpoints, and endpoints are populated by pods matching the selector. Without matching pods, the service has no endpoints, so DNS returns NXDOMAIN or an empty result. This is a common mistake when creating headless services: forgetting to actually create the backend pods.

### The fix

Create at least one pod with the correct label:

```bash
kubectl -n ex-3-1 run cache-1 --image=redis:7.2 --labels="app=cache-server"
kubectl -n ex-3-1 wait --for=condition=ready pod/cache-1 --timeout=60s
```

Verify the endpoints now exist:

```bash
kubectl -n ex-3-1 get endpoints cache-headless
```

DNS queries now return the pod IP:

```bash
kubectl -n ex-3-1 exec dns-test -- nslookup cache-headless.ex-3-1.svc.cluster.local
```

---

## Exercise 3.2 Solution

### Diagnosis

Check the pod configuration:

```bash
kubectl -n ex-3-2 get pod api-server -o yaml | grep -A2 "hostname:\|subdomain:"
```

The pod has `hostname: api-server` and `subdomain: api-service`. The DNS name should be `api-server.api-service.ex-3-2.svc.cluster.local`. Check if a headless service exists matching the subdomain:

```bash
kubectl -n ex-3-2 get svc
```

Only the dns-test pod's implicit service (if any) exists. No service named `api-service` is present. Check if there are any services at all:

```bash
kubectl -n ex-3-2 get svc
```

Output shows `No resources found in ex-3-2 namespace`.

### What the bug is and why it happens

Pod subdomain/hostname DNS only works when a headless service with the same name as the pod's subdomain field exists. Kubernetes does not create this service automatically. The pod's `subdomain: api-service` requires a headless service named `api-service` to exist, otherwise the DNS record is never created. This is the most common mistake when using pod subdomain/hostname: creating the pod but forgetting the matching service.

### The fix

Create the missing headless service:

```bash
kubectl -n ex-3-2 apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: api-service
spec:
  clusterIP: None
  selector:
    app: api
  ports:
  - port: 80
EOF
```

The service selector `app: api` matches the pod's label. DNS queries now work:

```bash
kubectl -n ex-3-2 exec dns-test -- nslookup api-server.api-service.ex-3-2.svc.cluster.local
```

---

## Exercise 3.3 Solution

### Diagnosis

Check the current externalName value:

```bash
kubectl -n ex-3-3 get svc external-svc -o jsonpath='{.spec.externalName}'
```

Output shows `invalid..domain..name`, which is not a valid DNS name (multiple consecutive dots are illegal). Try querying it:

```bash
kubectl -n ex-3-3 exec dns-test -- dig external-svc.ex-3-3.svc.cluster.local
```

The dig output shows a CNAME record pointing to the invalid domain, but no subsequent A record resolution because the domain is malformed.

### What the bug is and why it happens

ExternalName services create CNAME records pointing to whatever domain is specified in `spec.externalName`. Kubernetes does not validate whether the external domain is a real, resolvable domain. If the domain is invalid or does not exist, the CNAME is still created but DNS resolution fails at the next step (looking up the external domain itself). This is a configuration error, not a Kubernetes behavior issue.

### The fix

Edit the service to use a valid external domain:

```bash
kubectl -n ex-3-3 patch svc external-svc -p '{"spec":{"externalName":"www.kubernetes.io"}}'
```

Verify the new externalName:

```bash
kubectl -n ex-3-3 get svc external-svc -o jsonpath='{.spec.externalName}'
```

DNS queries now return a valid CNAME:

```bash
kubectl -n ex-3-3 exec dns-test -- dig external-svc.ex-3-3.svc.cluster.local | grep CNAME
```

---

## Exercise 4.1 Solution

Back up the CoreDNS ConfigMap (already done in setup):

```bash
kubectl -n kube-system get configmap coredns -o yaml > /tmp/ex-4-1-coredns-backup.yaml
```

Edit the CoreDNS ConfigMap:

```bash
kubectl -n kube-system edit configmap coredns
```

Find the line `kubernetes cluster.local in-addr.arpa ip6.arpa {` and change it to:

```
kubernetes cluster.local internal.local in-addr.arpa ip6.arpa {
```

This adds `internal.local` as a second cluster domain. Save and exit the editor. Wait for CoreDNS to reload:

```bash
sleep 15
```

Verify services resolve in both domains:

```bash
kubectl -n ex-4-1 exec dns-test -- nslookup web-svc.ex-4-1.svc.cluster.local
kubectl -n ex-4-1 exec dns-test -- nslookup web-svc.ex-4-1.svc.internal.local
```

Both queries should return the same ClusterIP. After verifying, restore the original configuration:

```bash
kubectl apply -f /tmp/ex-4-1-coredns-backup.yaml
sleep 15
```

---

## Exercise 4.2 Solution

Back up the CoreDNS ConfigMap (already done in setup):

```bash
kubectl -n kube-system get configmap coredns -o yaml > /tmp/ex-4-2-coredns-backup.yaml
```

Edit the CoreDNS ConfigMap:

```bash
kubectl -n kube-system edit configmap coredns
```

Find the line `forward . /etc/resolv.conf` (or similar) and change it to:

```
forward . 8.8.8.8 1.1.1.1
```

Save and exit. Wait for CoreDNS to reload:

```bash
sleep 15
```

Verify external DNS resolution works:

```bash
kubectl -n ex-4-2 exec dns-test -- nslookup kubernetes.io
```

The query should resolve successfully using the custom upstream servers. Restore the original configuration:

```bash
kubectl apply -f /tmp/ex-4-2-coredns-backup.yaml
sleep 15
```

---

## Exercise 4.3 Solution

Verify CoreDNS has two replicas (setup already scaled to 2):

```bash
kubectl -n kube-system get deployment coredns
```

Delete one CoreDNS pod and immediately test DNS:

```bash
COREDNS_POD=$(kubectl -n kube-system get pods -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}')
kubectl -n kube-system delete pod $COREDNS_POD &
sleep 1
kubectl -n ex-4-3 exec dns-test -- nslookup app-svc.ex-4-3.svc.cluster.local
```

The DNS query succeeds because the kube-dns service load balances requests across all healthy CoreDNS pods, and at least one pod is still running. Wait a few seconds and verify the Deployment recreated the deleted pod:

```bash
sleep 5
kubectl -n kube-system get pods -l k8s-app=kube-dns
```

You should see two CoreDNS pods, one with a recent creation timestamp. This demonstrates CoreDNS high availability through multiple replicas.

---

## Exercise 5.1 Solution

### Diagnosis

Verify the kube-dns service is missing:

```bash
kubectl -n kube-system get svc kube-dns
```

Output shows `Error from server (NotFound): services "kube-dns" not found`. Check the dns-test pod's resolv.conf:

```bash
kubectl -n ex-5-1 exec dns-test -- cat /etc/resolv.conf
```

The `nameserver` line still shows the old kube-dns ClusterIP (typically 10.96.0.10). This IP is hardcoded into the pod's resolv.conf at pod creation time and does not update when the service is deleted. Try a DNS query:

```bash
kubectl -n ex-5-1 exec dns-test -- nslookup web-svc.ex-5-1.svc.cluster.local
```

The query times out or fails because the nameserver IP no longer routes to any CoreDNS pods.

### What the bug is and why it happens

The kube-dns service provides the ClusterIP that all pods use as their DNS nameserver. When the service is deleted, the ClusterIP is released and no longer routes traffic to CoreDNS pods, breaking DNS for all pods. Existing pods' `/etc/resolv.conf` files retain the old IP because resolv.conf is written at pod creation time and is not dynamically updated. New pods created after the service is deleted would get no nameserver at all (or a placeholder). This is a critical operational failure scenario: deleting kube-dns breaks DNS cluster-wide.

### The fix

Recreate the kube-dns service from the backup:

```bash
kubectl apply -f /tmp/ex-5-1-kube-dns-backup.yaml
```

Verify the service is restored with the same ClusterIP:

```bash
kubectl -n kube-system get svc kube-dns
```

The ClusterIP should match what was shown in /etc/resolv.conf. DNS queries now work:

```bash
kubectl -n ex-5-1 exec dns-test -- nslookup web-svc.ex-5-1.svc.cluster.local
```

---

## Exercise 5.2 Solution

Create the headless service and three pods:

```bash
kubectl -n ex-5-2 apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: database
spec:
  clusterIP: None
  selector:
    app: db
  ports:
  - port: 5432
---
apiVersion: v1
kind: Pod
metadata:
  name: db-0
  labels:
    app: db
spec:
  hostname: db-0
  subdomain: database
  containers:
  - name: postgres
    image: postgres:16-alpine
    env:
    - name: POSTGRES_PASSWORD
      value: example
    ports:
    - containerPort: 5432
---
apiVersion: v1
kind: Pod
metadata:
  name: db-1
  labels:
    app: db
spec:
  hostname: db-1
  subdomain: database
  containers:
  - name: postgres
    image: postgres:16-alpine
    env:
    - name: POSTGRES_PASSWORD
      value: example
    ports:
    - containerPort: 5432
---
apiVersion: v1
kind: Pod
metadata:
  name: db-2
  labels:
    app: db
spec:
  hostname: db-2
  subdomain: database
  containers:
  - name: postgres
    image: postgres:16-alpine
    env:
    - name: POSTGRES_PASSWORD
      value: example
    ports:
    - containerPort: 5432
EOF
```

Wait for all pods to be ready:

```bash
kubectl -n ex-5-2 wait --for=condition=ready pod/db-0 pod/db-1 pod/db-2 --timeout=60s
```

Each pod gets a stable DNS name based on its hostname and the shared subdomain. This is the pattern StatefulSets use, where each pod is individually addressable at `<pod-name>.<service-name>.<namespace>.svc.cluster.local`.

---

## Exercise 5.3 Solution

### Diagnosis

Check the headless service and its endpoints:

```bash
kubectl -n ex-5-3 get svc internal-api -o yaml
```

The service selector is `tier: api`. Check the pod's labels:

```bash
kubectl -n ex-5-3 get pod api-1 --show-labels
```

The pod has label `app: api-pod`, not `tier: api`. The selector does not match, so the service has no endpoints:

```bash
kubectl -n ex-5-3 get endpoints internal-api
```

Output shows `<none>`. Check if the pod's stable DNS works:

```bash
kubectl -n ex-5-3 exec dns-test -- nslookup api-1.internal-api.ex-5-3.svc.cluster.local
```

The query fails. The pod has `hostname: api-1` and `subdomain: internal-api`, but the headless service `internal-api` exists, so why doesn't the DNS work? The issue is that pod subdomain DNS only resolves when the pod is actually selected by the headless service (appears in the service's endpoints). Since the selector does not match, the pod is not an endpoint, and its stable DNS name is not created.

### What the bugs are and why they happen

First bug: the headless service selector `tier: api` does not match the pod's label `app: api-pod`. This causes the service to have no endpoints, so headless service DNS returns nothing. Second bug: because the pod is not selected by the service, its stable DNS name (`api-1.internal-api...`) is never created, even though the pod has the correct hostname and subdomain fields. Kubernetes only creates the stable DNS record when the pod is both (a) configured with hostname and subdomain, and (b) actually selected by a headless service matching the subdomain name. This is a subtle interaction: the service's role is not just DNS namespace but also endpoint selection.

### The fix

Fix the pod's label to match the service selector. Delete and recreate the pod:

```bash
kubectl -n ex-5-3 delete pod api-1
kubectl -n ex-5-3 apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: api-1
  labels:
    tier: api
spec:
  hostname: api-1
  subdomain: internal-api
  containers:
  - name: app
    image: nginx:1.27
    ports:
    - containerPort: 8080
EOF
kubectl -n ex-5-3 wait --for=condition=ready pod/api-1 --timeout=60s
```

Verify the service endpoints now include the pod:

```bash
kubectl -n ex-5-3 get endpoints internal-api
```

Both DNS queries now work:

```bash
kubectl -n ex-5-3 exec dns-test -- nslookup internal-api.ex-5-3.svc.cluster.local
kubectl -n ex-5-3 exec dns-test -- nslookup api-1.internal-api.ex-5-3.svc.cluster.local
```

---

## Common Mistakes

### Forgetting backend pods for headless services

A headless service with no matching pods has no endpoints, so DNS queries return NXDOMAIN or an empty result instead of pod IPs. This is different from a ClusterIP service, which still has a ClusterIP even with no endpoints. Headless services depend entirely on endpoints for their DNS behavior. Always verify `kubectl get endpoints <svc>` shows the expected pod IPs after creating a headless service.

### Creating pod subdomain/hostname without matching headless service

Setting `hostname` and `subdomain` fields on a pod does not automatically create DNS records. A headless service with the same name as the subdomain must exist, and the pod must match the service's selector. If either is missing, the stable DNS name does not resolve. This is a common mistake when learning StatefulSets, where the governing service is a separate required object.

### Not waiting for CoreDNS reload after ConfigMap edits

CoreDNS watches the ConfigMap and reloads automatically, but the reload is not instant. Changes typically take effect within 15 seconds. Testing DNS immediately after editing the ConfigMap may show the old behavior because the reload has not completed. Always `sleep 15` after applying ConfigMap changes before verifying DNS behavior.

### Assuming ExternalName services route traffic

ExternalName services are purely DNS aliases. They do not have ClusterIP, they do not route traffic, and they do not have endpoints. Applications using an ExternalName service perform DNS resolution to get the external domain's IP, then connect directly to that IP. The service object itself is not in the traffic path. This is different from ClusterIP services, which do route traffic through kube-proxy or iptables rules.

### Confusing IP-based pod DNS with subdomain-based pod DNS

IP-based pod DNS (`<IP-with-dashes>.<namespace>.pod.cluster.local`) is always available for any pod and requires no extra configuration, but it breaks when the pod's IP changes. Subdomain-based pod DNS (`<hostname>.<subdomain>.<namespace>.svc.cluster.local`) survives IP changes but requires both the pod's hostname/subdomain fields and a matching headless service. The two formats are not interchangeable and serve different use cases (ephemeral vs stable identity).

### Deleting kube-dns service without backup

Deleting the kube-dns service breaks DNS cluster-wide immediately. Existing pods retain the old service IP in their `/etc/resolv.conf` but it no longer routes anywhere. Recreating the service without specifying the exact same ClusterIP (via the backup YAML) gives the new service a different IP, which does not help existing pods. Always back up the kube-dns service YAML before any maintenance that might involve deleting it, and restore from the backup to preserve the ClusterIP.

### Not scaling CoreDNS for high availability

A single-replica CoreDNS deployment is a single point of failure. If the CoreDNS pod crashes, restarts, or is evicted, DNS stops working until the pod comes back. Production clusters should run at least two CoreDNS replicas so DNS remains available during pod failures or rolling updates. The kube-dns service load balances requests across all replicas automatically.

---

## Verification Commands Cheat Sheet

### Headless Service Verification

| Task | Command |
|---|---|
| Verify service is headless | `kubectl get svc <name> -o jsonpath='{.spec.clusterIP}'` (expect: None) |
| Check endpoints | `kubectl get endpoints <name>` (expect: pod IPs listed) |
| Query DNS for multiple A records | `nslookup <svc>.<ns>.svc.cluster.local` (returns multiple Address lines) |
| Count A records | `nslookup <svc>.<ns>.svc.cluster.local \| grep Address \| wc -l` (expect: 1 + pod count) |
| Query SRV records | `dig SRV <svc>.<ns>.svc.cluster.local` |

### ExternalName Service Verification

| Task | Command |
|---|---|
| Verify service type | `kubectl get svc <name> -o jsonpath='{.spec.type}'` (expect: ExternalName) |
| Check external domain | `kubectl get svc <name> -o jsonpath='{.spec.externalName}'` |
| Query CNAME record | `dig <svc>.<ns>.svc.cluster.local \| grep CNAME` |
| Query with nslookup | `nslookup <svc>.<ns>.svc.cluster.local` (shows canonical name) |

### Pod Subdomain/Hostname Verification

| Task | Command |
|---|---|
| Check pod hostname | `kubectl get pod <name> -o jsonpath='{.spec.hostname}'` |
| Check pod subdomain | `kubectl get pod <name> -o jsonpath='{.spec.subdomain}'` |
| Query stable DNS name | `nslookup <hostname>.<subdomain>.<ns>.svc.cluster.local` |
| Verify requires headless service | `kubectl get svc <subdomain>` (must exist and be headless) |
| Compare to IP-based DNS | `nslookup <IP-with-dashes>.<ns>.pod.cluster.local` |

### CoreDNS Configuration Verification

| Task | Command |
|---|---|
| Check kubernetes plugin domains | `kubectl -n kube-system get cm coredns -o yaml \| grep kubernetes` |
| Check forward plugin upstreams | `kubectl -n kube-system get cm coredns -o yaml \| grep forward` |
| Verify service resolves in custom domain | `nslookup <svc>.<ns>.svc.<custom-domain>` |
| Check CoreDNS pod logs | `kubectl -n kube-system logs -l k8s-app=kube-dns --tail=20` |

### CoreDNS High Availability Verification

| Task | Command |
|---|---|
| Check CoreDNS replica count | `kubectl -n kube-system get deployment coredns` |
| List CoreDNS pods | `kubectl -n kube-system get pods -l k8s-app=kube-dns` |
| Verify kube-dns service exists | `kubectl -n kube-system get svc kube-dns` |
| Check kube-dns endpoints | `kubectl -n kube-system get endpoints kube-dns` (should list all CoreDNS pod IPs) |
| Test DNS during pod deletion | Delete a CoreDNS pod and immediately query DNS |

### General DNS Troubleshooting

| Task | Command |
|---|---|
| Check pod resolv.conf | `kubectl exec <pod> -- cat /etc/resolv.conf` |
| Verify kube-dns ClusterIP | `kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}'` |
| Test external DNS resolution | `nslookup kubernetes.io` (verifies forward plugin works) |
| Test cluster DNS resolution | `nslookup kubernetes.default.svc.cluster.local` |
| Query with short name | `nslookup <svc>` (uses search domains from resolv.conf) |
| Query with FQDN | `nslookup <svc>.<ns>.svc.cluster.local` (fully qualified) |
