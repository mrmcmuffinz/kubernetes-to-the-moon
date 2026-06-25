# Gateway API Fundamentals with Envoy Gateway Tutorial

Gateway API is the Kubernetes replacement for the frozen Ingress API. It is more expressive (native traffic splitting, header matching, typed filters), more extensible (CRDs for specialized route types), and role-oriented: instead of one Ingress resource owned by one team, Gateway API splits responsibility across three resources owned by three personas. This tutorial teaches Gateway API using Envoy Gateway v1.7.2 as the implementation, which is one of the reference conformant controllers and a good stand-in for the API itself.

The three core resources are:

- **GatewayClass** — the administrator's statement that a specific controller is available. Usually set up once per cluster by the infrastructure team.
- **Gateway** — the infrastructure piece. Defines listeners (port, protocol, hostname, allowed routes). Usually owned by the platform team.
- **HTTPRoute** — the routing rules themselves (match paths, forward to Services, apply filters). Owned by application teams.

Persona separation is the practical payoff: the application team writes HTTPRoutes in their namespace, which attach to Gateways in the platform namespace, as long as the Gateway's `allowedRoutes` permit attachment. This is the Gateway API's answer to "anyone can create an Ingress and accidentally route traffic to their Service."

## Prerequisites

A multi-node kind cluster with extraPortMappings for 80 and 443. See `docs/cluster-setup.md#multi-node-kind-cluster`. The Gateway API CRDs must be installed before Envoy Gateway, see `docs/cluster-setup.md#gateway-api-crds`.

Verify cluster and CRDs.

```bash
kubectl get nodes
# Expected: 1 control-plane and 3 workers, all Ready

kubectl get crd gatewayclasses.gateway.networking.k8s.io
kubectl get crd gateways.gateway.networking.k8s.io
kubectl get crd httproutes.gateway.networking.k8s.io
# Expected: all three CRDs present
```

If any CRD is missing, install the Gateway API standard bundle:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
```

Create the tutorial namespaces (persona-separated: `tutorial-gw-infra` for the Gateway, `tutorial-gw-app` for the HTTPRoute).

```bash
kubectl create namespace tutorial-gw-infra
kubectl create namespace tutorial-gw-app
```

## Part 1: Install Envoy Gateway v1.7.2

Install via Helm.

```bash
helm install envoy-gateway \
  oci://docker.io/envoyproxy/gateway-helm \
  --version v1.7.2 \
  --namespace envoy-gateway-system --create-namespace

kubectl -n envoy-gateway-system rollout status deployment/envoy-gateway --timeout=180s

kubectl get gatewayclass
```

Expected output: a row named `eg` (Envoy Gateway's default class), controller `gateway.envoyproxy.io/gatewayclass-controller`, STATUS `Accepted: True`.

## Part 2: Spec field reference

**Spec field reference for `GatewayClass`:**

- **`spec.controllerName`**
  - **Type:** string.
  - **Valid values:** the controller's unique identifier. For Envoy Gateway, `gateway.envoyproxy.io/gatewayclass-controller`.
  - **Default:** none; required.
  - **Failure mode when misconfigured:** a GatewayClass whose `controllerName` does not match any running controller sits with no status.

**Spec field reference for `Gateway`:**

- **`spec.gatewayClassName`**
  - **Type:** string (name of a GatewayClass).
  - **Valid values:** any GatewayClass in the cluster.
  - **Default:** none; required.
  - **Failure mode when misconfigured:** if the named class does not exist or its controller is not running, the Gateway has no status and no listener endpoint is provisioned.

- **`spec.listeners[]`**
  - **Type:** array. Each listener has `name`, `port`, `protocol`, optionally `hostname`, `allowedRoutes`, `tls`.
  - **Valid `protocol` values:** `HTTP`, `HTTPS`, `TLS`, `TCP`, `UDP`.
  - **Default:** none; at least one listener is required.
  - **Failure mode when misconfigured:** a listener with `protocol: HTTPS` but no `tls` block is rejected. An `allowedRoutes` restriction that excludes every namespace blocks all HTTPRoutes.

- **`spec.listeners[*].allowedRoutes.namespaces.from`**
  - **Type:** string.
  - **Valid values:** `All` (any namespace), `Same` (only the Gateway's namespace), `Selector` (namespaces matching a label selector).
  - **Default:** `Same`.
  - **Failure mode when misconfigured:** if `from` is `Same` but the HTTPRoute is in a different namespace, the HTTPRoute's `parents[*].conditions[type=Accepted].status` is `False` with a reason mentioning namespace restriction.

**Spec field reference for `HTTPRoute`:**

- **`spec.parentRefs[]`**
  - **Type:** array of references (name, namespace, kind).
  - **Valid values:** each reference points at a Gateway. Defaults `kind: Gateway`, `group: gateway.networking.k8s.io`.
  - **Default:** `namespace` defaults to the HTTPRoute's namespace.
  - **Failure mode when misconfigured:** if the referenced Gateway does not exist, or its `allowedRoutes` block the HTTPRoute's namespace, the HTTPRoute's status shows `Accepted: False`.

- **`spec.hostnames[]`**
  - **Type:** array of strings.
  - **Valid values:** DNS hostnames. Must be a subset of the listener's hostnames (or any if the listener has none).
  - **Default:** empty (matches any Host header).
  - **Failure mode when misconfigured:** a hostname outside the listener's scope is silently dropped; the HTTPRoute is accepted but routes traffic only for the subset that intersects.

- **`spec.rules[]`**
  - **Type:** array of rule objects.
  - **Valid values:** each rule has `matches`, `filters`, `backendRefs`.
  - **Default:** at least one rule required.
  - **Failure mode when misconfigured:** a rule with no `backendRefs` drops traffic (the match produces no response).

- **`spec.rules[*].matches[*].path`**
  - **Type:** object with `type` (string) and `value` (string).
  - **Valid `type` values:** `PathPrefix` (default), `Exact`, `RegularExpression`.
  - **Default:** `PathPrefix` with value `/`.
  - **Failure mode when misconfigured:** similar to Ingress paths; `PathPrefix` matches path segment boundaries.

- **`spec.rules[*].backendRefs[]`**
  - **Type:** array of service references.
  - **Valid values:** Service name and port, optionally weight.
  - **Default:** required.
  - **Failure mode when misconfigured:** reference to a non-existent Service shows up as a `ResolvedRefs: False` condition.

## Part 3: First Gateway and HTTPRoute

Create a Gateway in the infra namespace that accepts HTTPRoutes from any namespace.

```bash
kubectl apply -n tutorial-gw-infra -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: tut-gateway
spec:
  gatewayClassName: eg
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
EOF

sleep 5
kubectl get gateway -n tutorial-gw-infra tut-gateway
kubectl get gateway -n tutorial-gw-infra tut-gateway -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}'
```

Expected output: a row with an ADDRESS populated, and the jsonpath query returns `True`. The Gateway is "programmed" meaning the controller has pushed the listener configuration to the data-plane Envoy pods.

Deploy a backend in the app namespace.

```bash
kubectl apply -n tutorial-gw-app -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: hello}
spec:
  replicas: 2
  selector: {matchLabels: {app: hello}}
  template:
    metadata: {labels: {app: hello}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: hello-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: hello-html}
data: {index.html: "hello-via-gateway\n"}
---
apiVersion: v1
kind: Service
metadata: {name: hello}
spec: {selector: {app: hello}, ports: [{port: 80, targetPort: 80}]}
EOF

kubectl -n tutorial-gw-app rollout status deployment/hello --timeout=60s
```

Create the HTTPRoute in the app namespace, attaching to the Gateway in the infra namespace.

```bash
kubectl apply -n tutorial-gw-app -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: hello-route
spec:
  parentRefs:
  - name: tut-gateway
    namespace: tutorial-gw-infra
  hostnames: ["hello.example.test"]
  rules:
  - matches:
    - path: {type: PathPrefix, value: /}
    backendRefs:
    - name: hello
      port: 80
EOF

sleep 5
kubectl get httproute -n tutorial-gw-app hello-route
kubectl get httproute -n tutorial-gw-app hello-route \
  -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'
```

Expected output:

```
True
```

Verify routing. The Envoy Gateway proxy pod is behind a Service in `envoy-gateway-system`. Port-forward to reach it from the host, or obtain its ADDRESS.

```bash
kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=tutorial-gw-infra
```

The Service is named like `envoy-tutorial-gw-infra-tut-gateway-<hash>`. Port-forward to it on port 8090.

```bash
SVC=$(kubectl get svc -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-namespace=tutorial-gw-infra \
  -o jsonpath='{.items[0].metadata.name}')

kubectl port-forward -n envoy-gateway-system "svc/$SVC" 8090:80 &
PF_PID=$!
sleep 2
curl -s -H "Host: hello.example.test" http://localhost:8090/
# Expected: hello-via-gateway

kill $PF_PID 2>/dev/null

# NodePort alternative (externalTrafficPolicy: Local — must hit the node running the Envoy pod):
NODE=$(kubectl get pods -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-namespace=tutorial-gw-infra \
  -o jsonpath='{.items[0].spec.nodeName}')
NODEIP=$(kubectl get node $NODE \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NODEPORT=$(kubectl get svc -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-namespace=tutorial-gw-infra \
  -o jsonpath='{.items[0].spec.ports[0].nodePort}')
curl -s -H "Host: hello.example.test" http://$NODEIP:$NODEPORT/
# Expected: hello-via-gateway
```

## Part 4: Status and conditions

Gateway API conditions are the single best source of diagnostic information. Every Gateway and HTTPRoute has a `status.conditions[]` array with typed entries.

Gateway conditions:

- `Accepted` — the controller recognized the Gateway.
- `Programmed` — the Gateway's configuration has been pushed to the data plane.
- `ResolvedRefs` — all listener references resolve.

HTTPRoute conditions (per parent):

- `Accepted` — the parent Gateway accepted this HTTPRoute's attachment.
- `ResolvedRefs` — all backends referenced by `backendRefs` resolve.

```bash
kubectl get gateway -n tutorial-gw-infra tut-gateway \
  -o jsonpath='{range .status.conditions[*]}{.type}:{.status} ({.reason}){"\n"}{end}'
```

Expected output (all True):

```
Accepted:True (Accepted)
Programmed:True (Programmed)
...
```

## Part 5: `allowedRoutes` and namespace restrictions

Restrict the Gateway to only accept HTTPRoutes from namespaces with a specific label.

```bash
kubectl label namespace tutorial-gw-app team=frontend --overwrite

kubectl patch gateway -n tutorial-gw-infra tut-gateway --type='json' -p='[
  {"op":"replace","path":"/spec/listeners/0/allowedRoutes","value":{"namespaces":{"from":"Selector","selector":{"matchLabels":{"team":"frontend"}}}}}
]'
```

The existing HTTPRoute in `tutorial-gw-app` (labeled `team=frontend`) still attaches. Try attaching a new HTTPRoute in a namespace without the label.

```bash
kubectl create namespace tutorial-gw-rogue

kubectl apply -n tutorial-gw-rogue -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: rogue
spec:
  parentRefs:
  - name: tut-gateway
    namespace: tutorial-gw-infra
  hostnames: ["rogue.example.test"]
  rules:
  - backendRefs: []
EOF

sleep 5
kubectl get httproute -n tutorial-gw-rogue rogue \
  -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status} {.status.parents[0].conditions[?(@.type=="Accepted")].reason}'
```

Expected output:

```
False NotAllowedByListeners
```

The listener's `allowedRoutes` excludes the rogue namespace; the HTTPRoute's `Accepted` condition is `False` with reason `NotAllowedByListeners`. This is the typed failure mode that Ingress lacked; before Gateway API, a misconfigured Ingress might silently work or fail with controller-specific log lines.

## Part 6: `ReferenceGrant`

When an HTTPRoute in namespace A points at a Service in namespace B, Kubernetes requires explicit permission via a `ReferenceGrant` in namespace B. This prevents cross-namespace reference without the destination's consent.

```bash
kubectl create namespace tutorial-gw-svc

kubectl apply -n tutorial-gw-svc -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: remote}
spec:
  replicas: 1
  selector: {matchLabels: {app: remote}}
  template:
    metadata: {labels: {app: remote}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: remote-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: remote-html}
data: {index.html: "remote-service\n"}
---
apiVersion: v1
kind: Service
metadata: {name: remote}
spec: {selector: {app: remote}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl label namespace tutorial-gw-svc team=frontend --overwrite

kubectl apply -n tutorial-gw-app -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: cross-ns}
spec:
  parentRefs:
  - name: tut-gateway
    namespace: tutorial-gw-infra
  hostnames: ["remote.example.test"]
  rules:
  - backendRefs:
    - name: remote
      namespace: tutorial-gw-svc
      port: 80
EOF

sleep 5
kubectl get httproute -n tutorial-gw-app cross-ns \
  -o jsonpath='{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status} {.status.parents[0].conditions[?(@.type=="ResolvedRefs")].reason}'
```

Expected output:

```
False RefNotPermitted
```

The destination namespace has not granted permission for the cross-namespace reference. Add a ReferenceGrant.

```bash
kubectl apply -n tutorial-gw-svc -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata: {name: grant-remote}
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: tutorial-gw-app
  to:
  - group: ""
    kind: Service
    name: remote
EOF

sleep 5
kubectl get httproute -n tutorial-gw-app cross-ns \
  -o jsonpath='{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}'
```

Expected output: `True`. The HTTPRoute now resolves the cross-namespace Service.

## Part 7: Debugging data-plane connectivity

When traffic is not reaching the backend, work through the chain layer by layer rather than guessing. Each layer either confirms it is healthy or surfaces the failure point.

**Layer 1: Control plane -- did it accept and program the config?**

Start here. There is no point chasing network issues if the config was never applied.

```bash
kubectl get gateway -n <ns> <name> \
  -o jsonpath='{range .status.conditions[*]}{.type}:{.status} ({.reason}){"\n"}{end}'

kubectl get httproute -n <ns> <name> \
  -o jsonpath='{range .status.parents[0].conditions[*]}{.type}:{.status} ({.reason}){"\n"}{end}'
```

You need `Programmed: True` on the Gateway and both `Accepted: True` and `ResolvedRefs: True` on the HTTPRoute before anything downstream matters.

**Layer 2: Did the config reach the Envoy proxy?**

The Envoy proxy exposes an admin interface on port 19000. Port-forward to it to inspect the live xDS state. Always specify `--address 127.0.0.1` -- without it, `kubectl port-forward` binds to IPv6 by default, and browsers connect over IPv4, causing the connection to hang.

```bash
ENVOY_POD=$(kubectl get pods -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-namespace=<ns> \
  -o jsonpath='{.items[0].metadata.name}')

kubectl port-forward --address 127.0.0.1 -n envoy-gateway-system \
  "$ENVOY_POD" 19000:19000 &
sleep 2
```

Check that your listener and cluster are present:

```bash
curl http://localhost:19000/config_dump | jq '.configs[] | select(.["@type"] | contains("Listener"))'
curl http://localhost:19000/config_dump | jq '.configs[] | select(.["@type"] | contains("Cluster"))'
```

If your route or backend cluster is missing here, the control plane did not translate your Gateway/HTTPRoute into xDS config correctly despite reporting success in status conditions.

**Layer 3: Is Envoy receiving the request?**

Envoy emits access logs to stdout. If your request does not appear here, the problem is upstream of Envoy (port-forward, NodePort reachability, or the wrong Host header).

```bash
kubectl logs -n envoy-gateway-system "$ENVOY_POD"
```

A 404 means Envoy received the request but found no matching route (check hostnames and path). A 503 means Envoy matched the route but could not reach the backend.

**Layer 4: Does the backend Service have endpoints?**

An empty endpoints list means no pods matched the Service selector. Envoy will 503 every request.

```bash
kubectl get endpoints -n <ns> <service>
```

**Layer 5: Does the backend pod respond directly?**

Bypass the entire Gateway stack and hit the backend pod from within the cluster. This confirms the application itself is healthy.

```bash
kubectl run debug --rm -it --image=curlimages/curl \
  -n <same-ns-as-backend> \
  -- curl http://<service>.<namespace>.svc.cluster.local
```

## Cleanup

```bash
kubectl delete namespace tutorial-gw-infra tutorial-gw-app tutorial-gw-rogue tutorial-gw-svc
```

To remove Envoy Gateway entirely (keep for assignment 4 and 5):

```bash
helm uninstall -n envoy-gateway-system envoy-gateway
kubectl delete namespace envoy-gateway-system
```

## Reference Commands

| Task | Command |
|---|---|
| List GatewayClasses | `kubectl get gatewayclass` |
| Gateway status | `kubectl get gateway -n <ns> <name> -o jsonpath='{.status.conditions}'` |
| HTTPRoute status per parent | `kubectl get httproute -n <ns> <name> -o jsonpath='{.status.parents[0].conditions}'` |
| Envoy Gateway controller logs | `kubectl logs -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gatewayclass=eg --tail=50` |
| Find the data-plane Service for a Gateway | `kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=<ns>` |
| Port-forward to Envoy admin (IPv4) | `kubectl port-forward --address 127.0.0.1 -n envoy-gateway-system <pod> 19000:19000` |
| Envoy xDS config dump | `curl http://localhost:19000/config_dump \| jq .` |
| Envoy access logs | `kubectl logs -n envoy-gateway-system <envoy-pod>` |

## Key Takeaways

Gateway API splits routing into GatewayClass (controller), Gateway (infra listener), HTTPRoute (routing rules). Each resource has a distinct persona and typed `status.conditions[]` that replace Ingress's implicit-behavior model. `allowedRoutes` on a Gateway listener controls which namespaces can attach HTTPRoutes to it, replacing "anyone can create an Ingress." HTTPRoute `parentRefs` attach the route to one or more Gateways; `backendRefs` point to Services. Cross-namespace Service references require a `ReferenceGrant` in the destination namespace. Diagnostic path: read `Accepted`, `Programmed`, and `ResolvedRefs` on the resource's status. Envoy Gateway v1.7.2 is installed via Helm as `oci://docker.io/envoyproxy/gateway-helm` with version `v1.7.2`.
