# CoreDNS Homework: Advanced DNS Patterns

This homework contains 15 progressive exercises testing headless service DNS, ExternalName services, pod subdomain and hostname for stable DNS, multiple cluster domains, custom upstream DNS configuration, and CoreDNS high availability. Work through the tutorial file first to understand each pattern, then attempt these exercises. Consult the answer key only after attempting each exercise.

---

## Exercise Setup

Before starting the exercises, ensure you have a multi-node kind cluster running with CoreDNS. Verify CoreDNS is healthy:

```bash
kubectl -n kube-system get deployment coredns
kubectl -n kube-system get svc kube-dns
```

You should see at least one CoreDNS replica running and the kube-dns service with a ClusterIP.

---

## Level 1: Headless and ExternalName Service DNS

### Exercise 1.1

**Objective:** Create a headless service and verify DNS returns multiple A records instead of a single ClusterIP.

**Setup:**

```bash
kubectl create namespace ex-1-1
kubectl -n ex-1-1 create deployment app --image=nginx:1.27 --replicas=4
kubectl -n ex-1-1 run dns-test --image=busybox:1.36 --command -- sleep 3600
kubectl -n ex-1-1 wait --for=condition=ready pod/dns-test --timeout=60s
```

**Task:** Create a headless service named `app-headless` exposing port 80 for the app deployment. Verify that DNS queries for the service return four A records, one for each pod.

**Verify:**

```bash
kubectl -n ex-1-1 get svc app-headless
# Expected: CLUSTER-IP shows None

kubectl -n ex-1-1 get endpoints app-headless
# Expected: Four IP addresses listed

kubectl -n ex-1-1 exec dns-test -- nslookup app-headless.ex-1-1.svc.cluster.local
# Expected: Four Address lines (after server info), one per pod

kubectl -n ex-1-1 exec dns-test -- sh -c "nslookup app-headless.ex-1-1.svc.cluster.local | grep Address | wc -l"
# Expected: 5 (1 for nameserver + 4 for pods)
```

### Exercise 1.2

**Objective:** Create an ExternalName service that aliases an external domain and verify CNAME behavior.

**Setup:**

```bash
kubectl create namespace ex-1-2
kubectl -n ex-1-2 run dns-test --image=alpine:3.20 --command -- sleep 3600
kubectl -n ex-1-2 wait --for=condition=ready pod/dns-test --timeout=60s
kubectl -n ex-1-2 exec dns-test -- apk add --no-cache bind-tools
```

**Task:** Create an ExternalName service named `external-api` that points to `api.github.com`. Verify the service has no ClusterIP and DNS queries return a CNAME record.

**Verify:**

```bash
kubectl -n ex-1-2 get svc external-api -o jsonpath='{.spec.type}'
# Expected: ExternalName

kubectl -n ex-1-2 get svc external-api -o jsonpath='{.spec.externalName}'
# Expected: api.github.com

kubectl -n ex-1-2 get svc external-api -o jsonpath='{.spec.clusterIP}'
# Expected: empty or None

kubectl -n ex-1-2 exec dns-test -- dig external-api.ex-1-2.svc.cluster.local | grep CNAME
# Expected: Line showing external-api CNAME to api.github.com
```

### Exercise 1.3

**Objective:** Compare headless service DNS behavior to ClusterIP service DNS for the same deployment.

**Setup:**

```bash
kubectl create namespace ex-1-3
kubectl -n ex-1-3 create deployment backend --image=httpd:2.4 --replicas=3
kubectl -n ex-1-3 run dns-test --image=busybox:1.36 --command -- sleep 3600
kubectl -n ex-1-3 wait --for=condition=ready pod/dns-test --timeout=60s
```

**Task:** Create two services for the backend deployment: a headless service named `backend-headless` and a ClusterIP service named `backend-clusterip`, both exposing port 80. Verify that nslookup for the headless service returns three addresses while nslookup for the ClusterIP service returns one address.

**Verify:**

```bash
kubectl -n ex-1-3 get svc backend-headless -o jsonpath='{.spec.clusterIP}'
# Expected: None

kubectl -n ex-1-3 get svc backend-clusterip -o jsonpath='{.spec.clusterIP}' | grep -E '^[0-9]+\.'
# Expected: Non-empty IP address (e.g., 10.96.x.x)

kubectl -n ex-1-3 exec dns-test -- sh -c "nslookup backend-headless.ex-1-3.svc.cluster.local | grep Address | wc -l"
# Expected: 4 (1 nameserver + 3 pods)

kubectl -n ex-1-3 exec dns-test -- sh -c "nslookup backend-clusterip.ex-1-3.svc.cluster.local | grep Address | wc -l"
# Expected: 2 (1 nameserver + 1 ClusterIP)
```

---

## Level 2: Pod Subdomain and Hostname

### Exercise 2.1

**Objective:** Create a pod with custom hostname and subdomain fields and verify it gets a stable DNS name.

**Setup:**

```bash
kubectl create namespace ex-2-1
kubectl -n ex-2-1 run dns-test --image=busybox:1.36 --command -- sleep 3600
kubectl -n ex-2-1 wait --for=condition=ready pod/dns-test --timeout=60s
```

**Task:** Create a headless service named `db-cluster` exposing port 5432. Create a pod named `db-primary` with `hostname: db-primary`, `subdomain: db-cluster`, image `postgres:16-alpine`, and label `app: database`. Verify the pod resolves at `db-primary.db-cluster.ex-2-1.svc.cluster.local`.

**Verify:**

```bash
kubectl -n ex-2-1 get pod db-primary -o jsonpath='{.spec.hostname}'
# Expected: db-primary

kubectl -n ex-2-1 get pod db-primary -o jsonpath='{.spec.subdomain}'
# Expected: db-cluster

kubectl -n ex-2-1 wait --for=condition=ready pod/db-primary --timeout=60s
# Expected: pod/db-primary condition met

kubectl -n ex-2-1 exec dns-test -- nslookup db-primary.db-cluster.ex-2-1.svc.cluster.local
# Expected: Resolves to db-primary pod IP

kubectl -n ex-2-1 exec dns-test -- nslookup db-primary.db-cluster.ex-2-1.svc.cluster.local | grep Address | tail -1 | awk '{print $2}'
# Expected: Same IP as kubectl -n ex-2-1 get pod db-primary -o jsonpath='{.status.podIP}'
```

### Exercise 2.2

**Objective:** Verify that pod subdomain DNS survives pod IP changes.

**Setup:**

```bash
kubectl create namespace ex-2-2
kubectl -n ex-2-2 apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: replica-svc
spec:
  clusterIP: None
  selector:
    app: replica
  ports:
  - port: 80
---
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
kubectl -n ex-2-2 run dns-test --image=busybox:1.36 --command -- sleep 3600
kubectl -n ex-2-2 wait --for=condition=ready pod/replica-1 --timeout=60s
kubectl -n ex-2-2 wait --for=condition=ready pod/dns-test --timeout=60s
```

**Task:** Query DNS for `replica-1.replica-svc.ex-2-2.svc.cluster.local` and record the IP. Delete the pod `replica-1`, recreate it with the same manifest, wait for it to be ready, then query the same DNS name again and verify it resolves to a new IP (proving the DNS name is stable but tracks the new pod IP).

**Verify:**

```bash
ORIGINAL_IP=$(kubectl -n ex-2-2 exec dns-test -- nslookup replica-1.replica-svc.ex-2-2.svc.cluster.local | grep Address | tail -1 | awk '{print $2}')
echo "Original IP: $ORIGINAL_IP"

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

NEW_IP=$(kubectl -n ex-2-2 exec dns-test -- nslookup replica-1.replica-svc.ex-2-2.svc.cluster.local | grep Address | tail -1 | awk '{print $2}')
echo "New IP: $NEW_IP"

test "$ORIGINAL_IP" != "$NEW_IP" && echo "IPs are different (expected)" || echo "IPs are the same (unexpected)"
# Expected: IPs are different (pod got new IP, DNS name still works)
```

### Exercise 2.3

**Objective:** Compare IP-based pod DNS to subdomain-based pod DNS.

**Setup:**

```bash
kubectl create namespace ex-2-3
kubectl -n ex-2-3 apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: worker-svc
spec:
  clusterIP: None
  selector:
    app: worker
  ports:
  - port: 8080
---
apiVersion: v1
kind: Pod
metadata:
  name: worker-a
  labels:
    app: worker
spec:
  hostname: worker-a
  subdomain: worker-svc
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF
kubectl -n ex-2-3 run dns-test --image=busybox:1.36 --command -- sleep 3600
kubectl -n ex-2-3 wait --for=condition=ready pod/worker-a --timeout=60s
kubectl -n ex-2-3 wait --for=condition=ready pod/dns-test --timeout=60s
```

**Task:** Get the IP of pod `worker-a` and construct its IP-based DNS name (format: `<IP-with-dashes>.ex-2-3.pod.cluster.local`). Verify both the IP-based DNS name and the subdomain-based DNS name (`worker-a.worker-svc.ex-2-3.svc.cluster.local`) resolve to the same IP.

**Verify:**

```bash
POD_IP=$(kubectl -n ex-2-3 get pod worker-a -o jsonpath='{.status.podIP}')
IP_DNS=$(echo $POD_IP | tr '.' '-')
echo "IP-based DNS: ${IP_DNS}.ex-2-3.pod.cluster.local"

kubectl -n ex-2-3 exec dns-test -- nslookup ${IP_DNS}.ex-2-3.pod.cluster.local
# Expected: Resolves to $POD_IP

kubectl -n ex-2-3 exec dns-test -- nslookup worker-a.worker-svc.ex-2-3.svc.cluster.local
# Expected: Resolves to $POD_IP (same IP)

kubectl -n ex-2-3 exec dns-test -- nslookup worker-a.worker-svc.ex-2-3.svc.cluster.local | grep Address | tail -1 | awk '{print $2}'
# Expected: Same as $POD_IP
```

---

## Level 3: Debugging DNS Configurations

### Exercise 3.1

**Objective:** Diagnose why a headless service DNS query returns no pod IPs.

**Setup:**

```bash
kubectl create namespace ex-3-1
kubectl -n ex-3-1 apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: cache-headless
spec:
  clusterIP: None
  selector:
    app: cache-server
  ports:
  - port: 6379
EOF
kubectl -n ex-3-1 run dns-test --image=busybox:1.36 --command -- sleep 3600
kubectl -n ex-3-1 wait --for=condition=ready pod/dns-test --timeout=60s
```

**Task:** The setup creates a headless service but DNS queries for `cache-headless.ex-3-1.svc.cluster.local` return no pod addresses (or NXDOMAIN). Find and fix the issue so that DNS returns at least one pod IP.

**Verify:**

```bash
kubectl -n ex-3-1 exec dns-test -- nslookup cache-headless.ex-3-1.svc.cluster.local
# Expected: After fix, returns at least one Address (pod IP)

kubectl -n ex-3-1 get endpoints cache-headless
# Expected: At least one IP address listed
```

### Exercise 3.2

**Objective:** Fix a pod that does not resolve via its intended stable DNS name.

**Setup:**

```bash
kubectl create namespace ex-3-2
kubectl -n ex-3-2 apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: api-server
  labels:
    app: api
spec:
  hostname: api-server
  subdomain: api-service
  containers:
  - name: nginx
    image: nginx:1.27
    ports:
    - containerPort: 80
EOF
kubectl -n ex-3-2 run dns-test --image=busybox:1.36 --command -- sleep 3600
kubectl -n ex-3-2 wait --for=condition=ready pod/api-server --timeout=60s
kubectl -n ex-3-2 wait --for=condition=ready pod/dns-test --timeout=60s
```

**Task:** The pod has hostname and subdomain set, but querying `api-server.api-service.ex-3-2.svc.cluster.local` fails. Find and fix the issue.

**Verify:**

```bash
kubectl -n ex-3-2 exec dns-test -- nslookup api-server.api-service.ex-3-2.svc.cluster.local
# Expected: After fix, resolves to api-server pod IP

kubectl -n ex-3-2 get pod api-server -o jsonpath='{.status.podIP}'
# Expected: Same IP as DNS query result
```

### Exercise 3.3

**Objective:** Diagnose and fix an ExternalName service that is not resolving.

**Setup:**

```bash
kubectl create namespace ex-3-3
kubectl -n ex-3-3 apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: external-svc
spec:
  type: ExternalName
  externalName: invalid..domain..name
  ports:
  - port: 443
EOF
kubectl -n ex-3-3 run dns-test --image=alpine:3.20 --command -- sleep 3600
kubectl -n ex-3-3 wait --for=condition=ready pod/dns-test --timeout=60s
kubectl -n ex-3-3 exec dns-test -- apk add --no-cache bind-tools
```

**Task:** The ExternalName service was configured incorrectly. Change the externalName to a valid external domain (such as `www.kubernetes.io`) and verify DNS returns a CNAME record.

**Verify:**

```bash
kubectl -n ex-3-3 get svc external-svc -o jsonpath='{.spec.externalName}'
# Expected: A valid domain name (e.g., www.kubernetes.io)

kubectl -n ex-3-3 exec dns-test -- dig external-svc.ex-3-3.svc.cluster.local | grep CNAME
# Expected: CNAME line pointing to the valid external domain
```

---

## Level 4: CoreDNS Configuration and High Availability

### Exercise 4.1

**Objective:** Configure CoreDNS to serve a second cluster domain and verify services resolve in both domains.

**Setup:**

```bash
kubectl create namespace ex-4-1
kubectl -n ex-4-1 create deployment web --image=nginx:1.27
kubectl -n ex-4-1 expose deployment web --name=web-svc --port=80
kubectl -n ex-4-1 run dns-test --image=busybox:1.36 --command -- sleep 3600
kubectl -n ex-4-1 wait --for=condition=ready pod/dns-test --timeout=60s
kubectl -n kube-system get configmap coredns -o yaml > /tmp/ex-4-1-coredns-backup.yaml
```

**Task:** Edit the CoreDNS ConfigMap to add a second cluster domain `internal.local` alongside the existing `cluster.local` domain. Verify the web-svc service resolves under both domains.

**Verify:**

```bash
sleep 15
kubectl -n ex-4-1 exec dns-test -- nslookup web-svc.ex-4-1.svc.cluster.local
# Expected: Resolves to web-svc ClusterIP

kubectl -n ex-4-1 exec dns-test -- nslookup web-svc.ex-4-1.svc.internal.local
# Expected: Resolves to the same ClusterIP

kubectl -n kube-system get configmap coredns -o yaml | grep "kubernetes cluster.local internal.local"
# Expected: Line showing both domains configured

kubectl apply -f /tmp/ex-4-1-coredns-backup.yaml
sleep 15
```

### Exercise 4.2

**Objective:** Configure CoreDNS to use custom upstream DNS servers instead of /etc/resolv.conf.

**Setup:**

```bash
kubectl create namespace ex-4-2
kubectl -n ex-4-2 run dns-test --image=busybox:1.36 --command -- sleep 3600
kubectl -n ex-4-2 wait --for=condition=ready pod/dns-test --timeout=60s
kubectl -n kube-system get configmap coredns -o yaml > /tmp/ex-4-2-coredns-backup.yaml
```

**Task:** Edit the CoreDNS ConfigMap to forward external DNS queries to `8.8.8.8` and `1.1.1.1` instead of using `/etc/resolv.conf`. Verify external domain resolution still works.

**Verify:**

```bash
sleep 15
kubectl -n ex-4-2 exec dns-test -- nslookup kubernetes.io
# Expected: Resolves successfully (using custom upstreams)

kubectl -n kube-system get configmap coredns -o yaml | grep "forward . 8.8.8.8 1.1.1.1"
# Expected: Line showing custom upstream servers

kubectl apply -f /tmp/ex-4-2-coredns-backup.yaml
sleep 15
```

### Exercise 4.3

**Objective:** Test CoreDNS high availability by deleting a CoreDNS pod and verifying DNS continues to work.

**Setup:**

```bash
kubectl create namespace ex-4-3
kubectl -n ex-4-3 create deployment app --image=httpd:2.4
kubectl -n ex-4-3 expose deployment app --name=app-svc --port=80
kubectl -n ex-4-3 run dns-test --image=busybox:1.36 --command -- sleep 3600
kubectl -n ex-4-3 wait --for=condition=ready pod/dns-test --timeout=60s
kubectl -n kube-system scale deployment coredns --replicas=2
kubectl -n kube-system wait --for=condition=available deployment/coredns --timeout=60s
```

**Task:** Delete one CoreDNS pod and immediately verify that DNS queries still succeed (routed to the remaining CoreDNS pod). Confirm the Deployment recreates the deleted pod.

**Verify:**

```bash
COREDNS_POD=$(kubectl -n kube-system get pods -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}')
kubectl -n kube-system delete pod $COREDNS_POD &
sleep 1
kubectl -n ex-4-3 exec dns-test -- nslookup app-svc.ex-4-3.svc.cluster.local
# Expected: Resolves successfully even during pod deletion

sleep 5
kubectl -n kube-system get pods -l k8s-app=kube-dns
# Expected: Two CoreDNS pods (one new pod with recent age)

kubectl -n kube-system scale deployment coredns --replicas=1
```

---

## Level 5: Advanced Scenarios and Integration

### Exercise 5.1

**Objective:** Recover DNS functionality after the kube-dns service is accidentally deleted.

**Setup:**

```bash
kubectl create namespace ex-5-1
kubectl -n ex-5-1 create deployment web --image=nginx:1.27
kubectl -n ex-5-1 expose deployment web --name=web-svc --port=80
kubectl -n ex-5-1 run dns-test --image=busybox:1.36 --command -- sleep 3600
kubectl -n ex-5-1 wait --for=condition=ready pod/dns-test --timeout=60s
kubectl -n kube-system get svc kube-dns -o yaml > /tmp/ex-5-1-kube-dns-backup.yaml
kubectl -n kube-system delete svc kube-dns
```

**Task:** DNS queries from the dns-test pod now fail because the kube-dns service is missing. Verify the service is deleted, check that /etc/resolv.conf still references the old service IP, then recreate the kube-dns service from the backup and verify DNS works again.

**Verify:**

```bash
kubectl -n kube-system get svc kube-dns
# Expected before fix: Error from server (NotFound)

kubectl -n ex-5-1 exec dns-test -- cat /etc/resolv.conf | grep nameserver
# Expected: Shows old kube-dns ClusterIP (no longer routes anywhere)

# After recreating kube-dns service:
kubectl -n ex-5-1 exec dns-test -- nslookup web-svc.ex-5-1.svc.cluster.local
# Expected: Resolves successfully

kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}'
# Expected: Same IP as shown in /etc/resolv.conf
```

### Exercise 5.2

**Objective:** Build a complete stable-DNS setup for a multi-pod application using headless service and pod subdomain/hostname.

**Setup:**

```bash
kubectl create namespace ex-5-2
kubectl -n ex-5-2 run dns-test --image=busybox:1.36 --command -- sleep 3600
kubectl -n ex-5-2 wait --for=condition=ready pod/dns-test --timeout=60s
```

**Task:** Create a headless service named `database` exposing port 5432. Create three pods named `db-0`, `db-1`, and `db-2`, each with the appropriate hostname (matching the pod name) and subdomain `database`, using image `postgres:16-alpine`, label `app: db`, and environment variable `POSTGRES_PASSWORD=example`. Verify all three pods resolve at their stable DNS names and the headless service DNS returns all three pod IPs.

**Verify:**

```bash
kubectl -n ex-5-2 get svc database -o jsonpath='{.spec.clusterIP}'
# Expected: None

kubectl -n ex-5-2 get pods -l app=db
# Expected: Three pods (db-0, db-1, db-2) all Running

kubectl -n ex-5-2 exec dns-test -- nslookup db-0.database.ex-5-2.svc.cluster.local
# Expected: Resolves to db-0 pod IP

kubectl -n ex-5-2 exec dns-test -- nslookup db-1.database.ex-5-2.svc.cluster.local
# Expected: Resolves to db-1 pod IP

kubectl -n ex-5-2 exec dns-test -- nslookup db-2.database.ex-5-2.svc.cluster.local
# Expected: Resolves to db-2 pod IP

kubectl -n ex-5-2 exec dns-test -- sh -c "nslookup database.ex-5-2.svc.cluster.local | grep Address | wc -l"
# Expected: 4 (1 nameserver + 3 pods)
```

### Exercise 5.3

**Objective:** Troubleshoot a complex DNS scenario involving headless service, ExternalName service, and custom pod DNS.

**Setup:**

```bash
kubectl create namespace ex-5-3
kubectl -n ex-5-3 apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: internal-api
spec:
  clusterIP: None
  selector:
    tier: api
  ports:
  - port: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: external-db
spec:
  type: ExternalName
  externalName: db.example.local
---
apiVersion: v1
kind: Pod
metadata:
  name: api-1
  labels:
    app: api-pod
spec:
  hostname: api-1
  subdomain: internal-api
  containers:
  - name: app
    image: nginx:1.27
    ports:
    - containerPort: 8080
EOF
kubectl -n ex-5-3 run dns-test --image=alpine:3.20 --command -- sleep 3600
kubectl -n ex-5-3 wait --for=condition=ready pod/dns-test --timeout=60s
kubectl -n ex-5-3 exec dns-test -- apk add --no-cache bind-tools
```

**Task:** This configuration has multiple issues. The headless service `internal-api` returns no pod IPs. The pod `api-1` does not resolve at its stable DNS name. Fix both issues so that the headless service DNS returns the api-1 pod IP and the stable DNS name `api-1.internal-api.ex-5-3.svc.cluster.local` resolves correctly. (The external-db ExternalName service is already correct, no changes needed.)

**Verify:**

```bash
kubectl -n ex-5-3 exec dns-test -- nslookup internal-api.ex-5-3.svc.cluster.local
# Expected after fix: Returns api-1 pod IP

kubectl -n ex-5-3 exec dns-test -- nslookup api-1.internal-api.ex-5-3.svc.cluster.local
# Expected after fix: Resolves to api-1 pod IP

kubectl -n ex-5-3 get endpoints internal-api
# Expected: One IP address (api-1 pod)

kubectl -n ex-5-3 exec dns-test -- dig external-db.ex-5-3.svc.cluster.local | grep CNAME
# Expected: CNAME to db.example.local (already working)
```

---

## Cleanup

Delete all exercise namespaces:

```bash
kubectl delete namespace ex-1-1 ex-1-2 ex-1-3 ex-2-1 ex-2-2 ex-2-3 ex-3-1 ex-3-2 ex-3-3 ex-4-1 ex-4-2 ex-4-3 ex-5-1 ex-5-2 ex-5-3
```

Remove backup files if they still exist:

```bash
rm -f /tmp/ex-4-1-coredns-backup.yaml /tmp/ex-4-2-coredns-backup.yaml /tmp/ex-5-1-kube-dns-backup.yaml
```

---

## Key Takeaways

After completing these exercises, you should be able to create and verify headless services that return multiple A records for client-side service discovery, create ExternalName services that alias external domains into cluster DNS using CNAME records, configure pod subdomain and hostname fields to create stable DNS names that survive pod IP changes, edit the CoreDNS ConfigMap to add multiple cluster domains and verify services resolve in all configured domains, configure custom upstream DNS servers in the forward plugin for external DNS resolution, test CoreDNS high availability by deleting pods and confirming DNS continues working through remaining replicas, and recover from missing kube-dns service by understanding the service's role and recreating it from backup. These patterns cover the advanced DNS scenarios tested in CKA exam simulations (Simulator A Q16 multiple domains, Simulator B Q1 pod subdomain DNS) and production troubleshooting contexts.
