# Cluster Setup

This document is the single source of truth for the cluster configurations used
across the CKA exam prep assignments. Every assignment README references a section
of this document by anchor rather than inlining setup commands, so a version bump
or URL change happens in exactly one place.

All commands assume the Linux shell and target a local machine running rootless
containerd via `nerdctl`. If you use Docker instead of nerdctl, omit the
`KIND_EXPERIMENTAL_PROVIDER=nerdctl` prefix.

**Last verified:** 2026-04-18 (see the version matrix at the bottom of this file).

---

## Contents

- [Prerequisites](#prerequisites)
- [Single-node kind cluster](#single-node-kind-cluster)
- [Multi-node kind cluster](#multi-node-kind-cluster)
- [Multi-node with Calico (NetworkPolicy support)](#multi-node-with-calico-networkpolicy-support)
- [MetalLB for LoadBalancer services](#metallb-for-loadbalancer-services)
- [Metrics-server](#metrics-server)
- [Gateway API CRDs](#gateway-api-crds)
- [Ingress controllers](#ingress-controllers)
- [Pi cluster (bare-metal) installation notes](#pi-cluster-bare-metal-installation-notes)
- [Teardown](#teardown)
- [Version matrix](#version-matrix)

---

## Prerequisites

The exercises assume the following tools are installed on the host.

| Tool | Minimum version | Purpose |
|---|---|---|
| `kind` | v0.31.0 | Creates local Kubernetes clusters as containers. v0.31.0 is the first release that ships a `kindest/node:v1.35.0` image. |
| `kubectl` | v1.34 or v1.35 | Kubernetes command-line tool. The Kubernetes version skew policy allows kubectl to be one minor version higher or lower than the cluster. |
| `nerdctl` | rootless mode | Container runtime frontend. Required for the `KIND_EXPERIMENTAL_PROVIDER=nerdctl` provider. |
| `openssl` | any recent | Used by the RBAC and TLS assignments. |
| `helm` | v3.x | Required only for the Helm topic. |

Verify:

```bash
kind version
kubectl version --client
nerdctl version
```

---

## Single-node kind cluster

The default cluster for most assignments. Uses the `kindest/node:v1.35.0` image.

```bash
KIND_EXPERIMENTAL_PROVIDER=nerdctl kind create cluster \
  --image kindest/node:v1.35.0
```

Verify:

```bash
kubectl get nodes
```

Expected: a single `control-plane` node in `Ready` status.

---

## Multi-node kind cluster

Required for scheduling, workload controllers, services, networking, and
troubleshooting assignments. Three workers give enough surface area to demonstrate
node affinity, pod anti-affinity, topology spread, and DaemonSet behavior.

```bash
cat <<EOF | KIND_EXPERIMENTAL_PROVIDER=nerdctl kind create cluster \
  --image kindest/node:v1.35.0 --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
- role: worker
EOF
```

Verify:

```bash
kubectl get nodes
```

Expected: four nodes (1 control-plane, 3 workers) all in `Ready` status.

---

## Multi-node with Calico (NetworkPolicy support)

Required for `network-policies/` assignments and `19-troubleshooting/assignment-4`.
Kind's default CNI (kindnet) does not enforce `NetworkPolicy` resources, so
Calico is installed in its place. This differs from the plain multi-node setup
by disabling the default CNI before install.

Create the cluster with the default CNI disabled:

```bash
cat <<EOF | KIND_EXPERIMENTAL_PROVIDER=nerdctl kind create cluster \
  --image kindest/node:v1.35.0 --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
nodes:
- role: control-plane
- role: worker
- role: worker
- role: worker
EOF
```

Install Calico:

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.5/manifests/calico.yaml
```

Wait for Calico to become ready:

```bash
kubectl wait --for=condition=Ready pods -l k8s-app=calico-node -n kube-system --timeout=180s
kubectl wait --for=condition=Ready pods -l k8s-app=calico-kube-controllers -n kube-system --timeout=180s
```

Verify pods on all nodes can reach each other (Calico initial programming takes
a few seconds after ready):

```bash
kubectl get nodes
kubectl get pods -n kube-system
```

All nodes should be `Ready` and kube-system pods `Running`.

---

## MetalLB for LoadBalancer services

Required for `08-services/assignment-1` and `08-services/assignment-2` LoadBalancer
exercises. Kind does not natively provision external load balancers, so MetalLB
provides an IP address pool drawn from the kind network.

Install MetalLB:

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml
```

Wait for MetalLB to be ready:

```bash
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=120s
```

Identify the kind network subnet:

```bash
nerdctl network inspect kind | grep -i subnet
```

Configure the IP address pool (adjust the address range to fall inside the kind
subnet output above; the `172.18.255.x` range below works for the default kind
subnet `172.18.0.0/16`):

```bash
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: kind-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.18.255.200-172.18.255.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: kind-l2
  namespace: metallb-system
EOF
```

Verify a LoadBalancer Service receives an external IP:

```bash
kubectl create deployment nginx --image=nginx:1.27
kubectl expose deployment nginx --type=LoadBalancer --port=80
kubectl get svc nginx
```

The `EXTERNAL-IP` column should show an address from the configured pool.

---

## Metrics-server

Required for `19-troubleshooting/assignment-1` and any exercise using
`kubectl top`. The `--kubelet-insecure-tls` flag is needed on kind because
kind's kubelet uses self-signed certificates.

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.8.1/components.yaml
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
kubectl wait --for=condition=Available deployment/metrics-server -n kube-system --timeout=180s
```

Verify:

```bash
kubectl top nodes
```

---

## Gateway API CRDs

Required for all `11-ingress-and-gateway-api/assignment-3` and later assignments
using Gateway API. Gateway API resources are delivered as CRDs that must be
installed before any Gateway API implementation.

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
```

Verify the CRDs are registered:

```bash
kubectl get crd gatewayclasses.gateway.networking.k8s.io
kubectl get crd gateways.gateway.networking.k8s.io
kubectl get crd httproutes.gateway.networking.k8s.io
```

All three should exist.

The `standard-install.yaml` bundle contains the stable resources (GatewayClass,
Gateway, HTTPRoute, ReferenceGrant). Experimental resources (TCPRoute, TLSRoute,
UDPRoute, GRPCRoute) require `experimental-install.yaml` instead.

---

## Ingress controllers

Each ingress-and-gateway-api assignment installs a different controller to build
breadth across Ingress API and Gateway API implementations. The per-assignment
controller install commands live in the assignment's own tutorial file, because
every controller has its own install flow. This section lists the pinned versions
for reference.

| Assignment | Controller | Version | API |
|---|---|---|---|
| `11-ingress-and-gateway-api/assignment-1` | Traefik | v3.6.13 | Ingress v1 |
| `11-ingress-and-gateway-api/assignment-2` | HAProxy Kubernetes Ingress (`haproxytech/kubernetes-ingress`, chart 1.49.0) | v3.2.6 | Ingress v1 |
| `11-ingress-and-gateway-api/assignment-3` | Envoy Gateway | v1.7.2 | Gateway API |
| `11-ingress-and-gateway-api/assignment-4` | NGINX Gateway Fabric | v2.5.1 | Gateway API |
| `11-ingress-and-gateway-api/assignment-5` | Traefik and Envoy Gateway from prior assignments, plus the `Ingress2Gateway` CLI v1.0.0 | n/a (reuses prior installs) | Both (migration) |

All controller versions verified against each project's official releases page
on 2026-04-18. The per-assignment tutorial for each ingress assignment contains
the exact Helm or manifest install command for that controller, produced under
Phase 4 regeneration (completed 2026-04-18). The transitional `ingress-nginx
controller-v1.15.1` pin that briefly appeared in assignments 1-3 is no longer
used by any content file.

---

## Pi cluster (bare-metal) installation notes

The sections above target kind clusters running on a local machine. The notes below
capture differences and gotchas observed when installing Gateway API controllers on a
bare-metal kubeadm cluster (Raspberry Pi 5 nodes, Calico CNI). They apply to any
bare-metal or VM cluster where no cloud load balancer is available.

### Install order matters

Install Gateway API CRDs before any controller. Envoy Gateway's Helm chart bundles its
own copy of the Gateway API CRDs. If the controller is installed first, the chart
silently fails to create the GatewayClass because the CRD does not exist yet, and the
controller starts with nothing to manage.

Correct order:

1. Gateway API CRDs (`kubectl apply -f standard-install.yaml`)
2. Envoy Gateway
3. NGINX Gateway Fabric

### Envoy Gateway: use `--skip-crds` and create the GatewayClass manually

Use `--skip-crds` to prevent Helm from applying its bundled (older) CRD copies on top
of the separately-installed v1.5.1 bundle. Without it, two errors occur: field manager
conflicts between `kubectl apply` and Helm's server-side apply on the standard CRD
annotations, and the `safe-upgrades.gateway.networking.k8s.io` ValidatingAdmissionPolicy
(installed with the standard bundle) blocks the chart from downgrading the experimental
CRDs to pre-v1.5.0 versions.

```bash
helm install envoy-gateway \
  oci://docker.io/envoyproxy/gateway-helm \
  --version v1.7.2 \
  --namespace envoy-gateway-system --create-namespace \
  --skip-crds

kubectl -n envoy-gateway-system rollout status deployment/envoy-gateway --timeout=180s
```

Envoy Gateway stores the `eg` GatewayClass in the chart's `crds/` directory alongside
the actual CRDs, so `--skip-crds` skips it too. Create it manually after install:

```bash
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
EOF

kubectl get gatewayclass eg
# Expected: eg    gateway.envoyproxy.io/gatewayclass-controller    True    <age>
```

### Envoy Gateway: fix missing EnvoyProxy CRD after `--skip-crds`

The `--skip-crds` flag skips everything in the chart's `crds/` directory, which includes
both the Gateway API standard CRDs and the `EnvoyProxy` CRD. The other Envoy
Gateway-specific CRDs (BackendTrafficPolicy, ClientTrafficPolicy, etc.) live in
`templates/` and are installed normally. The net result is that `envoyproxies.gateway.envoyproxy.io`
is missing from the cluster, which blocks the NodePort fix below.

The EnvoyProxy CRD schema is too large for `kubectl apply`'s `last-applied-configuration`
annotation (exceeds 262144 bytes), so client-side apply fails. Extract and apply it with
server-side apply:

```bash
helm template envoy-gateway oci://docker.io/envoyproxy/gateway-helm \
  --version v1.7.2 \
  --namespace envoy-gateway-system \
  --include-crds 2>/dev/null | python3 -c "
import sys, yaml
for doc in yaml.safe_load_all(sys.stdin):
    if doc and doc.get('kind') == 'CustomResourceDefinition' \
       and 'envoyproxy.io' in doc.get('spec', {}).get('group', ''):
        print('---')
        print(yaml.dump(doc))
" | kubectl apply --server-side -f -
```

Verify:

```bash
kubectl api-resources --api-group=gateway.envoyproxy.io | grep envoyprox
# Expected: a row for EnvoyProxy (shortname: eproxy)
```

### Envoy Gateway: configure NodePort for bare-metal

Without a load balancer controller, Envoy Gateway provisions data-plane Services of type
`LoadBalancer` that never receive an external IP. This causes every Gateway to show
`Programmed: False` with the message "No addresses have been assigned to the Gateway."
Port-forward still reaches the data plane, but the status condition is wrong for exercises
that check it.

Fix by creating an `EnvoyProxy` resource that sets the service type to `NodePort` and
linking it to the `eg` GatewayClass. This applies cluster-wide to all Gateways.

```bash
kubectl apply -f - <<'EOF'
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: nodeport-config
  namespace: envoy-gateway-system
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        type: NodePort
EOF

kubectl patch gatewayclass eg --type='merge' \
  -p='{"spec":{"parametersRef":{"group":"gateway.envoyproxy.io","kind":"EnvoyProxy","name":"nodeport-config","namespace":"envoy-gateway-system"}}}'
```

Any Gateway created after this patch will have a NodePort Service and will show
`Programmed: True`. Gateways created before the patch must be deleted and recreated.

### Envoy Gateway cleanup: delete orphaned CRDs manually

`helm uninstall` does not delete CRDs (Helm default behavior). After uninstalling Envoy
Gateway, experimental CRDs remain in the cluster and must be deleted manually before
reinstalling, otherwise the ValidatingAdmissionPolicy blocks the reinstall:

```bash
kubectl delete crd \
  tcproutes.gateway.networking.k8s.io \
  udproutes.gateway.networking.k8s.io \
  xbackendtrafficpolicies.gateway.networking.x-k8s.io \
  xmeshes.gateway.networking.x-k8s.io
```

### NGINX Gateway Fabric: use ClusterIP

The default service type is `LoadBalancer`, which stays `Pending` on bare-metal without
a load balancer controller. Use `ClusterIP` and reach the data-plane via
`kubectl port-forward`, which is how all the exercises verify anyway:

```bash
helm install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --version 2.5.1 \
  --namespace nginx-gateway --create-namespace \
  --set service.type=ClusterIP

kubectl -n nginx-gateway rollout status deployment/ngf-nginx-gateway-fabric --timeout=180s
```

### Traefik: skip kind-specific configuration

The assignment-1 tutorial includes a kind-specific hostPort shim, `nodeSelector.ingress-ready`,
and `extraPortMappings` that are not needed on bare-metal. Install with only:

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  --set image.tag=v3.6.13 \
  --set service.type=NodePort \
  --set providers.kubernetesIngress.enabled=true

kubectl -n traefik rollout status deployment/traefik --timeout=180s
```

### `ingress2gateway` CLI: install on the host, not the cluster nodes

`ingress2gateway` is a workstation CLI tool that translates Ingress YAML into Gateway API
resources. It is not deployed into the cluster. Install the binary matching your
workstation architecture (amd64 for x86_64 hosts), regardless of what architecture your
cluster nodes run. On a Pi cluster with an x86_64 workstation:

```bash
curl -L -o /tmp/ingress2gateway.tar.gz \
  https://github.com/kubernetes-sigs/ingress2gateway/releases/download/v1.1.0/ingress2gateway_Linux_x86_64.tar.gz
tar -xzf /tmp/ingress2gateway.tar.gz -C /tmp
sudo install /tmp/ingress2gateway /usr/local/bin/ingress2gateway
ingress2gateway --version
```

### Full verification after all three controllers are installed

```bash
kubectl get gatewayclass
# Expected: eg (Accepted: True) and nginx (Accepted: True)

kubectl get ingressclass
# Expected: traefik
```

---

## Teardown

Delete a cluster when finished:

```bash
kind delete cluster
```

Or, for a named multi-node cluster:

```bash
kind delete cluster --name <cluster-name>
```

---

## Version matrix

Every pinned version in this document is verified against the project's official
documentation or releases page. This section records the verification date and
source for each pin so future maintenance can re-verify efficiently.

| Component | Version | Verified against | Date |
|---|---|---|---|
| Kubernetes (exam target) | v1.35 | `github.com/cncf/curriculum` (`CKA_Curriculum_v1.35.pdf`) | 2026-04-18 |
| kind | v0.31.0 | `github.com/kubernetes-sigs/kind/releases` | 2026-04-18 |
| `kindest/node` | v1.35.0 | Default node image for kind v0.31.0 | 2026-04-18 |
| Calico | v3.31.5 | `docs.tigera.io/calico/latest/getting-started/kubernetes/requirements`, `github.com/projectcalico/calico/releases` | 2026-04-18 |
| MetalLB | v0.15.3 | `metallb.io/installation/`, `github.com/metallb/metallb/releases` | 2026-04-18 |
| metrics-server | v0.8.1 | `github.com/kubernetes-sigs/metrics-server` compatibility table | 2026-04-18 |
| Gateway API CRDs | v1.5.1 | `github.com/kubernetes-sigs/gateway-api/releases/tag/v1.5.1` (latest standard-channel release, March 2025) | 2026-04-18 |
| Traefik (11-ingress-and-gateway-api/assignment-1) | v3.6.13 | `github.com/traefik/traefik/releases` | 2026-04-18 |
| HAProxy Kubernetes Ingress (assignment-2) | v3.2.6 (chart 1.49.0) | `github.com/haproxytech/kubernetes-ingress/releases`, `haproxytech.github.io/helm-charts` | 2026-06-23 |
| Envoy Gateway (assignment-3) | v1.7.2 | `github.com/envoyproxy/gateway/releases` | 2026-04-18 |
| NGINX Gateway Fabric (assignment-4) | v2.5.1 | `github.com/nginx/nginx-gateway-fabric/releases` | 2026-04-18 |
| Ingress2Gateway CLI (assignment-5) | v1.1.0 | `github.com/kubernetes-sigs/ingress2gateway/releases` | 2026-06-23 |

When updating a pin, verify against the project's official source and update
both the pin and the verification date in this table. Do not rely on general
knowledge.
