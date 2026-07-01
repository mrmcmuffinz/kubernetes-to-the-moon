# Gateway API Fundamentals Homework

Fifteen exercises covering Envoy Gateway v1.7.2, Gateway/HTTPRoute creation, `parentRefs`, `hostnames`, path matching, `allowedRoutes`, `ReferenceGrant`, and reading `status.conditions`. Assumes Envoy Gateway is installed in `envoy-gateway-system` and the Gateway API CRDs (v1.5.1) are in place.

Exercise namespaces follow `ex-<level>-<exercise>` for HTTPRoutes and `ex-<level>-<exercise>-gw` for Gateway-owning namespaces when needed.

## Data-plane connectivity

Each Gateway provisions a dedicated Envoy data-plane Service of type NodePort in `envoy-gateway-system` with `externalTrafficPolicy: Local`. Two methods reach it for traffic verification.

**Port-forward** tunnels through the Kubernetes API server and works from any machine with cluster access regardless of node networking. This is the default method shown in each verification block.

**NodePort direct** requires no tunnel but `externalTrafficPolicy: Local` means the request must go to the specific node where the Envoy pod is scheduled, not any node. Discover the correct address with:

```bash
NS=<gateway-owning-namespace>
NODE=$(kubectl get pods -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-namespace=$NS \
  -o jsonpath='{.items[0].spec.nodeName}')
NODEIP=$(kubectl get node $NODE \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NODEPORT=$(kubectl get svc -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-namespace=$NS \
  -o jsonpath='{.items[0].spec.ports[0].nodePort}')
echo "$NODEIP:$NODEPORT"
```

Both methods are shown in each verification block that tests traffic. For exercises where the Gateway lives in a separate namespace from the HTTPRoute (for example `ex-4-1-infra`), use the Gateway's namespace as `$NS`.

---

## Level 1: Gateway API Basics

### Exercise 1.1

**Objective:** Create a Gateway with one HTTP listener that accepts HTTPRoutes from any namespace.

**Setup:**

```bash
kubectl create namespace ex-1-1
```

**Task:** Create Gateway `basic-gw` in namespace `ex-1-1` with `gatewayClassName: eg`, one listener `http` on port 80 protocol HTTP, `allowedRoutes.namespaces.from: All`.

**Verification:**

```bash
sleep 5
kubectl get gateway -n ex-1-1 basic-gw -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}'
# Expected: True

kubectl get gateway -n ex-1-1 basic-gw -o jsonpath='{.status.addresses[0].value}'
# Expected: an IP address (the data-plane Envoy pod IP)
```

---

### Exercise 1.2

**Objective:** Attach an HTTPRoute to a Gateway and verify the route is accepted.

**Setup:** Continue from 1.1's Gateway.

```bash
kubectl apply -n ex-1-1 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: app}
spec:
  replicas: 1
  selector: {matchLabels: {app: app}}
  template:
    metadata: {labels: {app: app}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: app-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: app-html}
data: {index.html: "one-one-served\n"}
---
apiVersion: v1
kind: Service
metadata: {name: app}
spec: {selector: {app: app}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-1-1 rollout status deployment/app --timeout=60s
```

**Task:** Create HTTPRoute `app-route` in namespace `ex-1-1` with `parentRefs: [{name: basic-gw}]`, `hostnames: [hello.example.test]`, one rule matching `pathType: PathPrefix`, `path: /`, backendRef Service `app` port 80.

**Verification:**

```bash
sleep 5
kubectl get httproute -n ex-1-1 app-route \
  -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'
# Expected: True

kubectl get httproute -n ex-1-1 app-route \
  -o jsonpath='{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}'
# Expected: True
```

---

### Exercise 1.3

**Objective:** List every GatewayClass in the cluster and identify the one served by Envoy Gateway.

**Task:** Extract the GatewayClass name whose controllerName starts with `gateway.envoyproxy.io/` using `kubectl get gc -o jsonpath`.

**Verification:**

```bash
kubectl get gatewayclass -o jsonpath='{range .items[?(@.spec.controllerName=="gateway.envoyproxy.io/gatewayclass-controller")]}{.metadata.name}{"\n"}{end}'
# Expected: eg
```

---

## Level 2: Routing

### Exercise 2.1

**Objective:** Create an HTTPRoute with path-based rules pointing at two Services.

**Setup:**

```bash
kubectl create namespace ex-2-1

kubectl apply -n ex-2-1 -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: paths-gw}
spec:
  gatewayClassName: eg
  listeners:
  - {name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: svc-a}
spec:
  replicas: 1
  selector: {matchLabels: {app: svc-a}}
  template:
    metadata: {labels: {app: svc-a}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: a-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: a-html}
data: {index.html: "A-backend\n"}
---
apiVersion: v1
kind: Service
metadata: {name: svc-a}
spec: {selector: {app: svc-a}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: svc-b}
spec:
  replicas: 1
  selector: {matchLabels: {app: svc-b}}
  template:
    metadata: {labels: {app: svc-b}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: b-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: b-html}
data: {index.html: "B-backend\n"}
---
apiVersion: v1
kind: Service
metadata: {name: svc-b}
spec: {selector: {app: svc-b}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-2-1 rollout status deployment/svc-a deployment/svc-b --timeout=60s
```

**Task:** Create HTTPRoute `paths` in namespace `ex-2-1` with `parentRefs: [{name: paths-gw}]`, `hostnames: [paths.example.test]`, two rules: `/a` (PathPrefix) -> `svc-a`, `/b` (PathPrefix) -> `svc-b`.

**Verification:**

```bash
sleep 5
# Port-forward to the data plane for this Gateway (set $PF via helper):
SVC=$(kubectl get svc -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-namespace=ex-2-1 \
  -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n envoy-gateway-system "svc/$SVC" 8090:80 &
sleep 2

curl -s -H "Host: paths.example.test" http://localhost:8090/a
# Expected: A-backend

curl -s -H "Host: paths.example.test" http://localhost:8090/b
# Expected: B-backend

curl -sI -H "Host: paths.example.test" http://localhost:8090/c
# Expected: 404

pkill -f "port-forward.*$SVC" 2>/dev/null

# NodePort alternative (externalTrafficPolicy: Local — must hit the node running the Envoy pod):
NODE=$(kubectl get pods -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-2-1 -o jsonpath='{.items[0].spec.nodeName}')
NODEIP=$(kubectl get node $NODE -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NODEPORT=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-2-1 -o jsonpath='{.items[0].spec.ports[0].nodePort}')
curl -s -H "Host: paths.example.test" http://$NODEIP:$NODEPORT/a
# Expected: A-backend
curl -s -H "Host: paths.example.test" http://$NODEIP:$NODEPORT/b
# Expected: B-backend
curl -sI -H "Host: paths.example.test" http://$NODEIP:$NODEPORT/c
# Expected: 404
```

---

### Exercise 2.2

**Objective:** Use `hostnames` to route different hosts to different Services on a single HTTPRoute.

**Setup:**

```bash
kubectl create namespace ex-2-2
# Apply a Gateway and Services similar to 2.1 but with the Gateway in ex-2-2
kubectl apply -n ex-2-2 -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: hosts-gw}
spec:
  gatewayClassName: eg
  listeners:
  - {name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: red}
spec:
  replicas: 1
  selector: {matchLabels: {app: red}}
  template:
    metadata: {labels: {app: red}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: red-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: red-html}
data: {index.html: "red-app\n"}
---
apiVersion: v1
kind: Service
metadata: {name: red}
spec: {selector: {app: red}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: blue}
spec:
  replicas: 1
  selector: {matchLabels: {app: blue}}
  template:
    metadata: {labels: {app: blue}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: blue-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: blue-html}
data: {index.html: "blue-app\n"}
---
apiVersion: v1
kind: Service
metadata: {name: blue}
spec: {selector: {app: blue}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-2-2 rollout status deployment/red deployment/blue --timeout=60s
```

**Task:** Create two HTTPRoutes both attached to `hosts-gw`: `red-route` for `hostnames: [red.example.test]` to Service `red`, and `blue-route` for `hostnames: [blue.example.test]` to Service `blue`. Both rules at `path /` PathPrefix.

**Verification:**

```bash
sleep 5
SVC=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-2-2 -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n envoy-gateway-system "svc/$SVC" 8091:80 &
sleep 2

curl -s -H "Host: red.example.test" http://localhost:8091/
# Expected: red-app

curl -s -H "Host: blue.example.test" http://localhost:8091/
# Expected: blue-app

pkill -f "port-forward.*$SVC" 2>/dev/null

# NodePort alternative:
NODE=$(kubectl get pods -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-2-2 -o jsonpath='{.items[0].spec.nodeName}')
NODEIP=$(kubectl get node $NODE -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NODEPORT=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-2-2 -o jsonpath='{.items[0].spec.ports[0].nodePort}')
curl -s -H "Host: red.example.test" http://$NODEIP:$NODEPORT/
# Expected: red-app
curl -s -H "Host: blue.example.test" http://$NODEIP:$NODEPORT/
# Expected: blue-app
```

---

### Exercise 2.3

**Objective:** Route to multiple backends with weighted distribution (a 50/50 split).

**Setup:**

```bash
kubectl create namespace ex-2-3
kubectl apply -n ex-2-3 -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: split-gw}
spec:
  gatewayClassName: eg
  listeners:
  - {name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: v1-app}
spec:
  replicas: 1
  selector: {matchLabels: {app: v1-app}}
  template:
    metadata: {labels: {app: v1-app}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: v1-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: v1-html}
data: {index.html: "v1-reply\n"}
---
apiVersion: v1
kind: Service
metadata: {name: v1-app}
spec: {selector: {app: v1-app}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: v2-app}
spec:
  replicas: 1
  selector: {matchLabels: {app: v2-app}}
  template:
    metadata: {labels: {app: v2-app}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: v2-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: v2-html}
data: {index.html: "v2-reply\n"}
---
apiVersion: v1
kind: Service
metadata: {name: v2-app}
spec: {selector: {app: v2-app}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-2-3 rollout status deployment/v1-app deployment/v2-app --timeout=60s
```

**Task:** Create HTTPRoute `split` in namespace `ex-2-3` with `parentRefs: [split-gw]`, host `split.example.test`, one rule with `backendRefs` containing both `v1-app` weight 50 and `v2-app` weight 50.

**Verification:**

```bash
sleep 5
SVC=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-2-3 -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n envoy-gateway-system "svc/$SVC" 8092:80 &
sleep 2

# Send 20 requests and count responses
V1=0; V2=0
for i in $(seq 1 20); do
  RESP=$(curl -s -H "Host: split.example.test" http://localhost:8092/)
  [ "$RESP" = "v1-reply" ] && V1=$((V1+1))
  [ "$RESP" = "v2-reply" ] && V2=$((V2+1))
done
echo "v1: $V1, v2: $V2"
# Expected: roughly 10/10, each in range [5, 15] allowing for variance

pkill -f "port-forward.*$SVC" 2>/dev/null

# NodePort alternative:
NODE=$(kubectl get pods -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-2-3 -o jsonpath='{.items[0].spec.nodeName}')
NODEIP=$(kubectl get node $NODE -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NODEPORT=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-2-3 -o jsonpath='{.items[0].spec.ports[0].nodePort}')
V1=0; V2=0
for i in $(seq 1 20); do
  RESP=$(curl -s -H "Host: split.example.test" http://$NODEIP:$NODEPORT/)
  [ "$RESP" = "v1-reply" ] && V1=$((V1+1))
  [ "$RESP" = "v2-reply" ] && V2=$((V2+1))
done
echo "v1: $V1, v2: $V2"
# Expected: roughly 10/10, each in range [5, 15] allowing for variance
```

---

## Level 3: Debugging

### Exercise 3.1

**Objective:** An HTTPRoute shows `Accepted: False`. Find and fix.

**Setup:**

```bash
kubectl create namespace ex-3-1
kubectl apply -n ex-3-1 -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw}
spec:
  gatewayClassName: eg
  listeners:
  - {name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}
EOF

kubectl create namespace ex-3-1-other
kubectl apply -n ex-3-1-other -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: world}
spec:
  replicas: 1
  selector: {matchLabels: {app: world}}
  template:
    metadata: {labels: {app: world}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: world-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: world-html}
data: {index.html: "from-other\n"}
---
apiVersion: v1
kind: Service
metadata: {name: world}
spec: {selector: {app: world}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: blocked}
spec:
  parentRefs:
  - {name: gw, namespace: ex-3-1}
  hostnames: ["blocked.example.test"]
  rules:
  - backendRefs: [{name: world, port: 80}]
EOF
kubectl -n ex-3-1-other rollout status deployment/world --timeout=60s
```

**Task:** Fix the Gateway so the HTTPRoute in `ex-3-1-other` is accepted. Do not change the HTTPRoute.

**Verification:**

```bash
sleep 5
kubectl get httproute -n ex-3-1-other blocked \
  -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'
# Expected: True
```

---

### Exercise 3.2

**Objective:** An HTTPRoute shows `ResolvedRefs: False`. Diagnose and fix.

**Setup:**

```bash
kubectl create namespace ex-3-2
kubectl apply -n ex-3-2 -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw}
spec:
  gatewayClassName: eg
  listeners:
  - {name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: real}
spec:
  replicas: 1
  selector: {matchLabels: {app: real}}
  template:
    metadata: {labels: {app: real}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: real-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: real-html}
data: {index.html: "real-backend\n"}
---
apiVersion: v1
kind: Service
metadata: {name: real}
spec: {selector: {app: real}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: unresolved}
spec:
  parentRefs: [{name: gw}]
  hostnames: ["unresolved.example.test"]
  rules:
  - backendRefs: [{name: nonexistent, port: 80}]
EOF
kubectl -n ex-3-2 rollout status deployment/real --timeout=60s
```

**Task:** Fix the HTTPRoute so `ResolvedRefs: True` and traffic reaches the backend.

**Verification:**

```bash
sleep 5
kubectl get httproute -n ex-3-2 unresolved \
  -o jsonpath='{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}'
# Expected: True

SVC=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-3-2 -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n envoy-gateway-system "svc/$SVC" 8093:80 &
sleep 2
curl -s -H "Host: unresolved.example.test" http://localhost:8093/
# Expected: real-backend
pkill -f "port-forward.*$SVC" 2>/dev/null

# NodePort alternative:
NODE=$(kubectl get pods -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-3-2 -o jsonpath='{.items[0].spec.nodeName}')
NODEIP=$(kubectl get node $NODE -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NODEPORT=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-3-2 -o jsonpath='{.items[0].spec.ports[0].nodePort}')
curl -s -H "Host: unresolved.example.test" http://$NODEIP:$NODEPORT/
# Expected: real-backend
```

---

### Exercise 3.3

**Objective:** An HTTPRoute shows `Accepted: False`. Find and fix.

**Setup:**

```bash
kubectl create namespace ex-3-3
kubectl create namespace ex-3-3-gw

kubectl apply -n ex-3-3-gw -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: shared-gw}
spec:
  gatewayClassName: eg
  listeners:
  - {name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: All}}}
EOF

kubectl apply -n ex-3-3 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: q}
spec:
  replicas: 1
  selector: {matchLabels: {app: q}}
  template:
    metadata: {labels: {app: q}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: q-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: q-html}
data: {index.html: "q-reply\n"}
---
apiVersion: v1
kind: Service
metadata: {name: q}
spec: {selector: {app: q}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: orphan}
spec:
  parentRefs:
  - {name: shared-gw}
  hostnames: ["orphan.example.test"]
  rules:
  - backendRefs: [{name: q, port: 80}]
EOF
kubectl -n ex-3-3 rollout status deployment/q --timeout=60s
```

**Task:** Fix the HTTPRoute's `parentRefs` so it is accepted by `shared-gw`.

**Verification:**

```bash
sleep 5
kubectl get httproute -n ex-3-3 orphan \
  -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'
# Expected: True
```

---

## Level 4: Persona Separation and `ReferenceGrant`

### Exercise 4.1

**Objective:** Create a Gateway in an infra namespace and an HTTPRoute in an app namespace, with the Gateway allowing routes from a labeled namespace.

**Setup:**

```bash
kubectl create namespace ex-4-1-infra
kubectl create namespace ex-4-1-app
kubectl label namespace ex-4-1-app tier=app
```

**Task:** In `ex-4-1-infra`, create Gateway `platform` with `gatewayClassName: eg`, listener HTTP port 80, `allowedRoutes.namespaces.from: Selector` with `matchLabels: {tier: app}`. Deploy a Service `ex-4-1-app/demo` that returns `ok-4-1`. Create HTTPRoute `tenant-route` in `ex-4-1-app` attached to `ex-4-1-infra/platform`.

**Verification:**

```bash
sleep 5
kubectl get httproute -n ex-4-1-app tenant-route \
  -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'
# Expected: True

SVC=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-4-1-infra -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n envoy-gateway-system "svc/$SVC" 8094:80 &
sleep 2
curl -s -H "Host: tenant.example.test" http://localhost:8094/
# Expected: ok-4-1
pkill -f "port-forward.*$SVC" 2>/dev/null

# NodePort alternative (Gateway is in ex-4-1-infra):
NODE=$(kubectl get pods -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-4-1-infra -o jsonpath='{.items[0].spec.nodeName}')
NODEIP=$(kubectl get node $NODE -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NODEPORT=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-4-1-infra -o jsonpath='{.items[0].spec.ports[0].nodePort}')
curl -s -H "Host: tenant.example.test" http://$NODEIP:$NODEPORT/
# Expected: ok-4-1
```

---

### Exercise 4.2

**Objective:** Create an HTTPRoute in namespace A that points at a Service in namespace B. Add a ReferenceGrant to permit the reference.

**Setup:**

```bash
kubectl create namespace ex-4-2-gw
kubectl create namespace ex-4-2-route
kubectl create namespace ex-4-2-svc

kubectl apply -n ex-4-2-gw -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw}
spec:
  gatewayClassName: eg
  listeners: [{name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: All}}}]
EOF

kubectl apply -n ex-4-2-svc -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: shared}
spec:
  replicas: 1
  selector: {matchLabels: {app: shared}}
  template:
    metadata: {labels: {app: shared}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: shared-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: shared-html}
data: {index.html: "cross-ns-ok\n"}
---
apiVersion: v1
kind: Service
metadata: {name: shared}
spec: {selector: {app: shared}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-4-2-svc rollout status deployment/shared --timeout=60s

kubectl apply -n ex-4-2-route -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: xroute}
spec:
  parentRefs: [{name: gw, namespace: ex-4-2-gw}]
  hostnames: ["xns.example.test"]
  rules:
  - backendRefs:
    - {name: shared, namespace: ex-4-2-svc, port: 80}
EOF
```

**Task:** Add a `ReferenceGrant` in namespace `ex-4-2-svc` permitting HTTPRoutes from `ex-4-2-route` to reference Service `shared`.

**Verification:**

```bash
sleep 5
kubectl get httproute -n ex-4-2-route xroute \
  -o jsonpath='{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}'
# Expected: True

SVC=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-4-2-gw -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n envoy-gateway-system "svc/$SVC" 8095:80 &
sleep 2
curl -s -H "Host: xns.example.test" http://localhost:8095/
# Expected: cross-ns-ok
pkill -f "port-forward.*$SVC" 2>/dev/null

# NodePort alternative (Gateway is in ex-4-2-gw):
NODE=$(kubectl get pods -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-4-2-gw -o jsonpath='{.items[0].spec.nodeName}')
NODEIP=$(kubectl get node $NODE -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NODEPORT=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-4-2-gw -o jsonpath='{.items[0].spec.ports[0].nodePort}')
curl -s -H "Host: xns.example.test" http://$NODEIP:$NODEPORT/
# Expected: cross-ns-ok
```

---

### Exercise 4.3

**Objective:** Use multiple `parentRefs` on a single HTTPRoute to attach to two Gateways simultaneously.

**Setup:**

```bash
kubectl create namespace ex-4-3
kubectl apply -n ex-4-3 -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw-a}
spec:
  gatewayClassName: eg
  listeners: [{name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}]
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw-b}
spec:
  gatewayClassName: eg
  listeners: [{name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: multi-attached}
spec:
  replicas: 1
  selector: {matchLabels: {app: multi}}
  template:
    metadata: {labels: {app: multi}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: multi-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: multi-html}
data: {index.html: "multi-served\n"}
---
apiVersion: v1
kind: Service
metadata: {name: multi}
spec: {selector: {app: multi}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-4-3 rollout status deployment/multi-attached --timeout=60s
```

**Task:** Create HTTPRoute `both-gateways` in `ex-4-3` with `parentRefs: [{name: gw-a}, {name: gw-b}]`, hostname `multi.example.test`, backend Service `multi`.

**Verification:**

```bash
sleep 5
kubectl get httproute -n ex-4-3 both-gateways -o jsonpath='{.status.parents[*].conditions[?(@.type=="Accepted")].status}'
# Expected: True True
```

---

## Level 5: Advanced

### Exercise 5.1

**Objective:** Design a Gateway API platform for three teams (api, ui, admin), each with its own namespace and one HTTPRoute, all attaching to a single shared Gateway.

**Setup:**

```bash
kubectl create namespace ex-5-1-platform
for team in api ui admin; do
  kubectl create namespace "ex-5-1-$team"
  kubectl label namespace "ex-5-1-$team" gateway-attach=allowed
done
```

**Task:** Create Gateway `shared` in `ex-5-1-platform` that allows routes from namespaces labeled `gateway-attach=allowed`. Each team deploys a Service in its own namespace and creates an HTTPRoute attaching to the shared Gateway on its own hostname (`api.ex-5-1.test`, `ui.ex-5-1.test`, `admin.ex-5-1.test`).

**Verification:**

```bash
sleep 5
for team in api ui admin; do
  STATUS=$(kubectl get httproute -n "ex-5-1-$team" route \
    -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}' 2>/dev/null || echo none)
  echo "$team: $STATUS"
done
# Expected: each team shows "True"
```

---

### Exercise 5.2

**Objective:** Diagnose a compound failure with three issues preventing the HTTPRoute from being accepted and routing traffic. Fix all three.

**Setup:**

```bash
kubectl create namespace ex-5-2-gw
kubectl create namespace ex-5-2-route
kubectl create namespace ex-5-2-svc

kubectl apply -n ex-5-2-gw -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw}
spec:
  gatewayClassName: nonexistent-class
  listeners:
  - {name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}
EOF

kubectl apply -n ex-5-2-svc -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: backend}
spec:
  replicas: 1
  selector: {matchLabels: {app: backend}}
  template:
    metadata: {labels: {app: backend}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: backend-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: backend-html}
data: {index.html: "five-two-ok\n"}
---
apiVersion: v1
kind: Service
metadata: {name: backend}
spec: {selector: {app: backend}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-5-2-svc rollout status deployment/backend --timeout=60s

kubectl apply -n ex-5-2-route -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: three-bugs}
spec:
  parentRefs:
  - {name: gw, namespace: ex-5-2-gw}
  hostnames: ["five-two.example.test"]
  rules:
  - backendRefs:
    - {name: backend, namespace: ex-5-2-svc, port: 80}
EOF
```

**Task:** Diagnose why the HTTPRoute cannot be accepted and why traffic cannot reach the backend. Apply all necessary fixes so that `Accepted: True`, `ResolvedRefs: True`, and traffic flows.

**Verification:**

```bash
sleep 5
kubectl get httproute -n ex-5-2-route three-bugs \
  -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status} {.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}'
# Expected: True True

SVC=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-5-2-gw -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n envoy-gateway-system "svc/$SVC" 8096:80 &
sleep 2
curl -s -H "Host: five-two.example.test" http://localhost:8096/
# Expected: five-two-ok
pkill -f "port-forward.*$SVC" 2>/dev/null

# NodePort alternative (Gateway is in ex-5-2-gw):
NODE=$(kubectl get pods -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-5-2-gw -o jsonpath='{.items[0].spec.nodeName}')
NODEIP=$(kubectl get node $NODE -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NODEPORT=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-5-2-gw -o jsonpath='{.items[0].spec.ports[0].nodePort}')
curl -s -H "Host: five-two.example.test" http://$NODEIP:$NODEPORT/
# Expected: five-two-ok
```

---

### Exercise 5.3

**Objective:** Express an equivalent to an existing Ingress as Gateway API resources, preserving the same routing behavior.

**Setup:**

```bash
kubectl create namespace ex-5-3
kubectl apply -n ex-5-3 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: legacy-api}
spec:
  replicas: 1
  selector: {matchLabels: {app: legacy-api}}
  template:
    metadata: {labels: {app: legacy-api}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: legacy-api-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: legacy-api-html}
data: {index.html: "legacy-api-v1\n"}
---
apiVersion: v1
kind: Service
metadata: {name: legacy-api}
spec: {selector: {app: legacy-api}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: {name: legacy}
spec:
  ingressClassName: traefik
  rules:
  - host: legacy.example.test
    http:
      paths:
      - {path: /api, pathType: Prefix, backend: {service: {name: legacy-api, port: {number: 80}}}}
EOF
kubectl -n ex-5-3 rollout status deployment/legacy-api --timeout=60s
```

**Task:** Create equivalent Gateway API resources in `ex-5-3`: a Gateway `modern-gw` on port 80 allowing Same-namespace routes, and an HTTPRoute `modern-route` with hostname `legacy.example.test` and a rule matching PathPrefix `/api` to Service `legacy-api`. Verify both the Ingress (through Traefik) and the HTTPRoute (through Envoy Gateway) serve the same content for the same URL.

**Verification:**

```bash
sleep 5
# Ingress via Traefik on :80 (assuming Traefik from assignment-1 is still installed):
curl -s -H "Host: legacy.example.test" http://localhost/api
# Expected: legacy-api-v1

# HTTPRoute via Envoy Gateway:
SVC=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-5-3 -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n envoy-gateway-system "svc/$SVC" 8097:80 &
sleep 2
curl -s -H "Host: legacy.example.test" http://localhost:8097/api
# Expected: legacy-api-v1
pkill -f "port-forward.*$SVC" 2>/dev/null

# NodePort alternative (Gateway is in ex-5-3):
NODE=$(kubectl get pods -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-5-3 -o jsonpath='{.items[0].spec.nodeName}')
NODEIP=$(kubectl get node $NODE -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NODEPORT=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=ex-5-3 -o jsonpath='{.items[0].spec.ports[0].nodePort}')
curl -s -H "Host: legacy.example.test" http://$NODEIP:$NODEPORT/api
# Expected: legacy-api-v1
```

---

## Cleanup

```bash
for ns in ex-1-1 ex-2-1 ex-2-2 ex-2-3 ex-3-1 ex-3-1-other ex-3-2 ex-3-3 ex-3-3-gw \
         ex-4-1-infra ex-4-1-app ex-4-2-gw ex-4-2-route ex-4-2-svc ex-4-3 \
         ex-5-1-platform ex-5-1-api ex-5-1-ui ex-5-1-admin \
         ex-5-2-gw ex-5-2-route ex-5-2-svc ex-5-3; do
  kubectl delete namespace "$ns" --ignore-not-found
done
```

## Key Takeaways

Gateway API has three primary resources: GatewayClass (controller), Gateway (listener), HTTPRoute (rules). Status conditions (`Accepted`, `Programmed`, `ResolvedRefs`) are typed and the primary diagnostic source. `allowedRoutes.namespaces.from: All | Same | Selector` on a listener controls which HTTPRoutes may attach. Cross-namespace Service references require a `ReferenceGrant` in the destination namespace. HTTPRoute `parentRefs` can attach to multiple Gateways. The same application routing can be expressed as either an Ingress or a set of Gateway API resources; migration (assignment 5) is mechanical.
