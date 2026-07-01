# CoreDNS Tutorial: Advanced DNS Patterns

## Introduction

This tutorial covers specialized DNS patterns that appear in CKA exam simulations and production Kubernetes clusters. Headless services change DNS behavior fundamentally, returning multiple A records (one per pod) instead of a single virtual IP, enabling client-side load balancing and service discovery patterns that StatefulSets depend on. ExternalName services alias external domains into the cluster DNS namespace, letting applications reference external databases or APIs using consistent service names. Pod subdomain and hostname fields create stable DNS names that survive pod IP changes, the foundation StatefulSets use for predictable network identities. Multiple cluster domains let services resolve under different DNS suffixes simultaneously, useful in migration scenarios or when integrating with legacy systems. Custom upstream DNS configuration lets CoreDNS forward external queries to specific resolvers instead of the node's default nameservers. CoreDNS high availability through multiple replicas behind the kube-dns service ensures DNS continues working even when individual CoreDNS pods fail.

This tutorial builds one complete workflow demonstrating headless service DNS, ExternalName CNAME behavior, pod subdomain/hostname DNS, multiple cluster domains, custom upstream DNS configuration, and CoreDNS resilience testing. By the end, you will understand how these patterns work together and how to verify each one using nslookup and dig. The CKA exam tests these patterns in questions like Simulator A Q16 (multiple cluster domains) and Simulator B Q1 (pod subdomain DNS), so mastering them directly improves exam readiness.

The tutorial assumes you have completed CoreDNS assignments 1, 2, and 3, and Services assignment 2. You should be comfortable with service DNS lookup patterns, CoreDNS Corefile editing and backup/restore workflow, and DNS troubleshooting techniques. The complete worked example below takes 45-60 minutes to build and verify from a clean cluster.

## Prerequisites

You need a multi-node kind cluster with CoreDNS running (the default kind setup). Follow the [Multi-Node Kind Cluster](../../../docs/cluster-setup.md#multi-node-kind-cluster) section in the cluster setup document to create the cluster. Verify CoreDNS is running:

```bash
kubectl -n kube-system get deployment coredns
kubectl -n kube-system get svc kube-dns
```

You should see the CoreDNS deployment with at least one ready replica and the kube-dns service with a ClusterIP (typically 10.96.0.10 in kind clusters). This service is how pods reach CoreDNS for DNS resolution.

## Setup

Create the tutorial namespace and a pod we will use for all DNS queries:

```bash
kubectl create namespace tutorial-coredns-advanced
kubectl -n tutorial-coredns-advanced run dns-client --image=busybox:1.36 --command -- sleep 3600
kubectl -n tutorial-coredns-advanced wait --for=condition=ready pod/dns-client --timeout=60s
```

The dns-client pod gives us a stable environment for running nslookup and dig commands throughout the tutorial.

## Headless Service DNS Behavior

A headless service is created by setting `spec.clusterIP: None`. Unlike a normal ClusterIP service, which gets a virtual IP that DNS resolves to a single address, a headless service has no ClusterIP at all. Instead, DNS returns multiple A records, one for each pod that matches the service's selector. This lets clients discover all backend pods directly and implement their own load balancing or connection pooling strategies.

Create a headless service and three backend pods:

```bash
kubectl -n tutorial-coredns-advanced create deployment web --image=nginx:1.27 --replicas=3
kubectl -n tutorial-coredns-advanced expose deployment web --name=web-headless --port=80 --cluster-ip=None
```

The `--cluster-ip=None` flag creates the headless service. Verify the service has no ClusterIP:

```bash
kubectl -n tutorial-coredns-advanced get svc web-headless
```

Output shows `CLUSTER-IP` as `None`. Check the endpoints:

```bash
kubectl -n tutorial-coredns-advanced get endpoints web-headless
```

You should see three IP addresses, one for each pod in the deployment. Now query DNS for the headless service:

```bash
kubectl -n tutorial-coredns-advanced exec dns-client -- nslookup web-headless.tutorial-coredns-advanced.svc.cluster.local
```

The output shows multiple `Address` lines (after the server information), one for each pod. This is fundamentally different from a normal ClusterIP service, which would return a single address. If you create a regular ClusterIP service for comparison:

```bash
kubectl -n tutorial-coredns-advanced expose deployment web --name=web-clusterip --port=80
kubectl -n tutorial-coredns-advanced exec dns-client -- nslookup web-clusterip.tutorial-coredns-advanced.svc.cluster.local
```

The ClusterIP service returns exactly one address, the service's virtual IP. Headless services also support SRV records, which include port and priority information. To query SRV records, you need `dig` instead of `nslookup`. Install `dig` in the dns-client pod:

```bash
kubectl -n tutorial-coredns-advanced exec dns-client -- sh -c "apk add --no-cache bind-tools"
kubectl -n tutorial-coredns-advanced exec dns-client -- dig SRV web-headless.tutorial-coredns-advanced.svc.cluster.local
```

The SRV record output includes fields like priority, weight, port, and target (the pod's own DNS name). StatefulSets use headless services specifically because each pod gets its own stable DNS name through this mechanism, letting other pods address individual StatefulSet members directly.

## ExternalName Service DNS

An ExternalName service creates a DNS alias (CNAME record) from a service name inside the cluster to an external domain name. This lets applications reference external databases or APIs using consistent service names without hardcoding external domains in application configuration. If you later migrate that external service into the cluster, you change the ExternalName service to a ClusterIP service and applications do not need to change their DNS lookups.

Create an ExternalName service aliasing to an external domain:

```bash
kubectl -n tutorial-coredns-advanced create service externalname external-db --external-name=db.example.com
```

Verify the service has no ClusterIP and shows the external name:

```bash
kubectl -n tutorial-coredns-advanced get svc external-db -o yaml | grep -A2 spec:
```

Output shows `type: ExternalName` and `externalName: db.example.com`. Query DNS for this service:

```bash
kubectl -n tutorial-coredns-advanced exec dns-client -- nslookup external-db.tutorial-coredns-advanced.svc.cluster.local
```

The nslookup output shows `external-db.tutorial-coredns-advanced.svc.cluster.local` as a canonical name (alias) for `db.example.com`. To see the CNAME record explicitly, use dig:

```bash
kubectl -n tutorial-coredns-advanced exec dns-client -- dig external-db.tutorial-coredns-advanced.svc.cluster.local
```

The `ANSWER SECTION` includes a CNAME record pointing to `db.example.com`. If `db.example.com` itself resolved (it does not in this example because it is not a real domain), dig would also show the final A record after following the CNAME chain. ExternalName services have no selectors, no endpoints, and no ClusterIP. They exist purely as DNS aliases and do not route traffic themselves.

## Pod Subdomain and Hostname for Stable DNS

Normally, a pod's DNS name is based on its IP address in the format `<IP-with-dashes>.<namespace>.pod.cluster.local`. This DNS name changes whenever the pod's IP changes (pod restart, rescheduling to a different node). For workloads that need stable DNS names that survive IP changes, Kubernetes lets you specify `spec.hostname` and `spec.subdomain` fields in the pod spec. When both are set, the pod gets a DNS name in the format `<hostname>.<subdomain>.<namespace>.svc.cluster.local`, and this name resolves correctly as long as a headless service with the same name as the subdomain exists.

Create a headless service and a pod with custom hostname and subdomain:

```bash
kubectl -n tutorial-coredns-advanced apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: stable-svc
spec:
  clusterIP: None
  selector:
    app: stable-pod
  ports:
  - port: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: web-0
  labels:
    app: stable-pod
spec:
  hostname: web-0
  subdomain: stable-svc
  containers:
  - name: nginx
    image: nginx:1.27
    ports:
    - containerPort: 80
EOF
```

The pod's `hostname` is `web-0` and its `subdomain` is `stable-svc`, matching the headless service name. Verify the pod is running, then query its stable DNS name:

```bash
kubectl -n tutorial-coredns-advanced wait --for=condition=ready pod/web-0 --timeout=60s
kubectl -n tutorial-coredns-advanced exec dns-client -- nslookup web-0.stable-svc.tutorial-coredns-advanced.svc.cluster.local
```

The query returns the pod's current IP. Now delete and recreate the pod to get a different IP:

```bash
kubectl -n tutorial-coredns-advanced delete pod web-0
kubectl -n tutorial-coredns-advanced apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: web-0
  labels:
    app: stable-pod
spec:
  hostname: web-0
  subdomain: stable-svc
  containers:
  - name: nginx
    image: nginx:1.27
    ports:
    - containerPort: 80
EOF
kubectl -n tutorial-coredns-advanced wait --for=condition=ready pod/web-0 --timeout=60s
```

Query the same DNS name again:

```bash
kubectl -n tutorial-coredns-advanced exec dns-client -- nslookup web-0.stable-svc.tutorial-coredns-advanced.svc.cluster.local
```

The DNS name still resolves, now to the pod's new IP. This is the mechanism StatefulSets use. A StatefulSet automatically sets `hostname` to the pod's ordinal name (like `web-0`, `web-1`) and `subdomain` to the governing service name, giving each StatefulSet pod a stable DNS name that persists across restarts and rescheduling. Without the headless service, the DNS query would fail with NXDOMAIN, because Kubernetes only creates the hostname-based DNS record when both the pod's subdomain field and a matching service exist.

Compare this to the IP-based pod DNS format. Get the pod's IP:

```bash
kubectl -n tutorial-coredns-advanced get pod web-0 -o jsonpath='{.status.podIP}'
```

If the IP is `10.244.1.5`, the IP-based DNS name would be `10-244-1-5.tutorial-coredns-advanced.pod.cluster.local`:

```bash
kubectl -n tutorial-coredns-advanced exec dns-client -- nslookup 10-244-1-5.tutorial-coredns-advanced.pod.cluster.local
```

This resolves to the same IP, but if you delete and recreate the pod, the new pod gets a new IP and the old IP-based DNS name stops working. The hostname-based DNS name (`web-0.stable-svc.<namespace>.svc.cluster.local`) continues to work because it is tied to the hostname field, not the IP.

## Multiple Cluster Domains

By default, Kubernetes services resolve under the `cluster.local` domain. You can configure CoreDNS to serve multiple cluster domains simultaneously by editing the `kubernetes` plugin line in the Corefile. This is useful in migration scenarios where some applications expect services under a legacy domain, or when integrating Kubernetes clusters with existing DNS infrastructure that uses different domain suffixes.

First, back up the current CoreDNS ConfigMap:

```bash
kubectl -n kube-system get configmap coredns -o yaml > /tmp/coredns-backup.yaml
```

Edit the CoreDNS ConfigMap:

```bash
kubectl -n kube-system edit configmap coredns
```

Find the `kubernetes cluster.local` line in the Corefile (inside the `.:53` server block) and change it to:

```
kubernetes cluster.local custom.local in-addr.arpa ip6.arpa {
```

This tells CoreDNS to serve Kubernetes DNS under both `cluster.local` and `custom.local` domains. The `in-addr.arpa` and `ip6.arpa` zones are for reverse DNS lookups and should always be included. Save and exit the editor. Wait 15 seconds for CoreDNS to reload the configuration (CoreDNS watches the ConfigMap and reloads automatically):

```bash
sleep 15
```

Now verify services resolve under both domains:

```bash
kubectl -n tutorial-coredns-advanced exec dns-client -- nslookup web-clusterip.tutorial-coredns-advanced.svc.cluster.local
kubectl -n tutorial-coredns-advanced exec dns-client -- nslookup web-clusterip.tutorial-coredns-advanced.svc.custom.local
```

Both queries should return the same ClusterIP. This is the CKA Simulator A Question 16 scenario: configure a second cluster domain and verify services resolve in both. After verifying, restore the original CoreDNS configuration:

```bash
kubectl apply -f /tmp/coredns-backup.yaml
sleep 15
```

Verify the second domain no longer works:

```bash
kubectl -n tutorial-coredns-advanced exec dns-client -- nslookup web-clusterip.tutorial-coredns-advanced.svc.custom.local
```

This should return `NXDOMAIN` or `server can't find`, confirming the configuration change was reverted.

## Custom Upstream DNS Configuration

By default, CoreDNS forwards external DNS queries (queries that do not match cluster services or pods) using the upstream nameservers listed in `/etc/resolv.conf` on the node where the CoreDNS pod is running. You can override this behavior by editing the `forward` plugin line in the Corefile to specify explicit upstream DNS servers. This is useful when you need to use corporate DNS servers, specific public resolvers, or custom DNS infrastructure for external domain resolution.

Back up the CoreDNS ConfigMap again if you have not already:

```bash
kubectl -n kube-system get configmap coredns -o yaml > /tmp/coredns-backup-upstream.yaml
```

Edit the CoreDNS ConfigMap:

```bash
kubectl -n kube-system edit configmap coredns
```

Find the `forward . /etc/resolv.conf` line and change it to:

```
forward . 8.8.8.8 1.1.1.1
```

This tells CoreDNS to forward external queries to Google's DNS (8.8.8.8) and Cloudflare's DNS (1.1.1.1) instead of the node's resolv.conf. Save and exit, then wait for CoreDNS to reload:

```bash
sleep 15
```

Verify external DNS resolution still works:

```bash
kubectl -n tutorial-coredns-advanced exec dns-client -- nslookup kubernetes.io
```

The query should resolve successfully, now using the custom upstream servers. If one upstream server is unavailable, CoreDNS automatically fails over to the next server in the list. Restore the original configuration:

```bash
kubectl apply -f /tmp/coredns-backup-upstream.yaml
sleep 15
```

## CoreDNS High Availability

CoreDNS runs as a Deployment in the kube-system namespace, typically with two replicas for high availability. The kube-dns service (a ClusterIP service) load balances DNS requests across all CoreDNS pod replicas. When a CoreDNS pod fails or is deleted, the Deployment controller automatically recreates it, and DNS continues working through the remaining healthy replicas.

Check the current CoreDNS replica count:

```bash
kubectl -n kube-system get deployment coredns
```

You should see at least one replica. If the deployment only has one replica, scale it to two for this demonstration:

```bash
kubectl -n kube-system scale deployment coredns --replicas=2
kubectl -n kube-system wait --for=condition=available deployment/coredns --timeout=60s
```

Verify both CoreDNS pods are running:

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
```

Now delete one CoreDNS pod while simultaneously querying DNS:

```bash
COREDNS_POD=$(kubectl -n kube-system get pods -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}')
kubectl -n kube-system delete pod $COREDNS_POD &
sleep 1
kubectl -n tutorial-coredns-advanced exec dns-client -- nslookup web-clusterip.tutorial-coredns-advanced.svc.cluster.local
```

The DNS query should succeed even while the pod is being deleted, because the kube-dns service routes the request to the remaining healthy CoreDNS pod. After a few seconds, check the CoreDNS pods again:

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
```

You should see a new CoreDNS pod (with a different age) replacing the deleted one. This demonstrates CoreDNS resilience: DNS remains available during pod failures because of multiple replicas and the Deployment controller's automatic recreation.

## Missing kube-dns Service Recovery

The kube-dns service is critical for DNS resolution in the cluster. Every pod's `/etc/resolv.conf` is configured with the kube-dns service ClusterIP as the nameserver. If the kube-dns service is deleted, new DNS queries fail immediately because the service IP no longer routes to CoreDNS pods. Interestingly, `/etc/resolv.conf` inside existing pods does not automatically update when the service is deleted, so the IP is still listed as the nameserver even though it is no longer valid.

Back up the kube-dns service before deleting it:

```bash
kubectl -n kube-system get svc kube-dns -o yaml > /tmp/kube-dns-backup.yaml
```

Delete the kube-dns service:

```bash
kubectl -n kube-system delete svc kube-dns
```

Try a DNS query from the dns-client pod:

```bash
kubectl -n tutorial-coredns-advanced exec dns-client -- nslookup web-clusterip.tutorial-coredns-advanced.svc.cluster.local
```

The query fails or times out. Check the pod's resolv.conf:

```bash
kubectl -n tutorial-coredns-advanced exec dns-client -- cat /etc/resolv.conf
```

The `nameserver` line still shows the old kube-dns service IP, but that IP no longer routes anywhere because the service is gone. Verify the service is actually deleted:

```bash
kubectl -n kube-system get svc kube-dns
```

Output shows `No resources found` or `Error from server (NotFound)`. To recover DNS, recreate the kube-dns service from the backup:

```bash
kubectl apply -f /tmp/kube-dns-backup.yaml
```

The service is recreated with the same ClusterIP (because the backup YAML includes the specific IP). Wait a moment for the service to be fully ready, then verify DNS works again:

```bash
kubectl -n tutorial-coredns-advanced exec dns-client -- nslookup web-clusterip.tutorial-coredns-advanced.svc.cluster.local
```

The query succeeds. New pods created after the service is restored will get the correct nameserver in their resolv.conf automatically, but existing pods keep their old resolv.conf until they are restarted. This scenario tests understanding of the kube-dns service's role in the DNS resolution chain and the recovery workflow.

## Cleanup

Delete the tutorial namespace, which removes all resources created in this tutorial:

```bash
kubectl delete namespace tutorial-coredns-advanced
```

If you scaled CoreDNS to two replicas and want to return it to the original count:

```bash
kubectl -n kube-system scale deployment coredns --replicas=1
```

Remove the backup files:

```bash
rm -f /tmp/coredns-backup.yaml /tmp/coredns-backup-upstream.yaml /tmp/kube-dns-backup.yaml
```

## Reference Commands

### Headless Service Commands

| Task | Command |
|---|---|
| Create headless service | `kubectl expose deployment <name> --name=<svc> --port=<port> --cluster-ip=None` |
| Query headless service DNS | `nslookup <svc>.<ns>.svc.cluster.local` (returns multiple A records) |
| Query SRV records | `dig SRV <svc>.<ns>.svc.cluster.local` |
| Check service has no ClusterIP | `kubectl get svc <svc>` (CLUSTER-IP shows None) |

### ExternalName Service Commands

| Task | Command |
|---|---|
| Create ExternalName service | `kubectl create service externalname <svc> --external-name=<domain>` |
| Query ExternalName service | `nslookup <svc>.<ns>.svc.cluster.local` (shows CNAME) |
| Check CNAME record with dig | `dig <svc>.<ns>.svc.cluster.local` (ANSWER section shows CNAME) |

### Pod Subdomain and Hostname Commands

| Task | Command |
|---|---|
| Set pod hostname and subdomain | Add `hostname: <name>` and `subdomain: <svc>` to pod spec |
| Query stable pod DNS | `nslookup <hostname>.<subdomain>.<ns>.svc.cluster.local` |
| Compare to IP-based DNS | `nslookup <IP-with-dashes>.<ns>.pod.cluster.local` |
| Verify requires headless service | Headless service with name matching subdomain must exist |

### CoreDNS Configuration Commands

| Task | Command |
|---|---|
| Back up CoreDNS ConfigMap | `kubectl -n kube-system get cm coredns -o yaml > /tmp/coredns-backup.yaml` |
| Edit CoreDNS ConfigMap | `kubectl -n kube-system edit cm coredns` |
| Wait for reload | `sleep 15` (CoreDNS reloads ConfigMap automatically) |
| Restore from backup | `kubectl apply -f /tmp/coredns-backup.yaml` |
| Add multiple domains | Change `kubernetes cluster.local` to `kubernetes cluster.local custom.local in-addr.arpa ip6.arpa` |
| Set custom upstream DNS | Change `forward . /etc/resolv.conf` to `forward . 8.8.8.8 1.1.1.1` |

### CoreDNS High Availability Commands

| Task | Command |
|---|---|
| Check CoreDNS replicas | `kubectl -n kube-system get deployment coredns` |
| Scale CoreDNS | `kubectl -n kube-system scale deployment coredns --replicas=<n>` |
| List CoreDNS pods | `kubectl -n kube-system get pods -l k8s-app=kube-dns` |
| Delete CoreDNS pod | `kubectl -n kube-system delete pod <pod-name>` (automatically recreated) |
| Verify kube-dns service | `kubectl -n kube-system get svc kube-dns` |

### DNS Query Commands

| Task | Command |
|---|---|
| Basic A record lookup | `nslookup <name>` |
| Specific record type | `dig <name>` or `dig <type> <name>` |
| Concise output | `dig +short <name>` |
| SRV record query | `dig SRV <name>` |
| Check pod resolv.conf | `cat /etc/resolv.conf` (shows nameserver as kube-dns ClusterIP) |
