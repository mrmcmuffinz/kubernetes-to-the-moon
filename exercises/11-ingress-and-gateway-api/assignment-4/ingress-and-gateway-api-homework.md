# Advanced Gateway API Routing Homework

Fifteen exercises covering NGINX Gateway Fabric v2.5.1, header/query/method matching, traffic splitting, and filters (RequestHeaderModifier, RequestRedirect, URLRewrite, ResponseHeaderModifier). Work through the tutorial first. Assumes Envoy Gateway and NGINX Gateway Fabric are both installed.

Namespaces follow `ex-<level>-<exercise>`. The setup blocks create a Gateway per namespace. NGF v2.x provisions a dedicated data-plane pod and Service named `<gateway-name>-nginx` in the Gateway's namespace. Both NGF and Envoy Gateway set `externalTrafficPolicy: Local`, so verification commands must target the specific node running the data-plane pod. The label `gateway.networking.k8s.io/gateway-name=<gw-name>` selects the NGF data-plane pod.

---

## Level 1: NGF Basics

### Exercise 1.1

**Objective:** Create an HTTPRoute attached to an NGF-managed Gateway and verify end-to-end.

**Setup:**

```bash
kubectl create namespace ex-1-1
kubectl apply -n ex-1-1 -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw}
spec:
  gatewayClassName: nginx
  listeners: [{name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: hi}
spec:
  replicas: 1
  selector: {matchLabels: {app: hi}}
  template:
    metadata: {labels: {app: hi}}
    spec:
      containers:
      - {name: 'n', image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: hi-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: hi-html}
data: {index.html: "hi-one-one\n"}
---
apiVersion: v1
kind: Service
metadata: {name: hi}
spec: {selector: {app: hi}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-1-1 rollout status deployment/hi --timeout=60s
```

**Task:** Create HTTPRoute `hi-route` in namespace `ex-1-1` attached to `gw`, hostname `hi.example.test`, path `/` prefix, backendRef Service `hi` port 80.

**Verification:**

```bash
sleep 5
kubectl get httproute -n ex-1-1 hi-route \
  -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'
# Expected: True

NGF_NODE=$(kubectl get pods -n ex-1-1 \
  -l gateway.networking.k8s.io/gateway-name=gw \
  -o jsonpath='{.items[0].spec.nodeName}')
NGINX_IP=$(kubectl get node "$NGF_NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NGINX_PORT=$(kubectl get svc -n ex-1-1 gw-nginx \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
curl -s -H "Host: hi.example.test" "http://$NGINX_IP:$NGINX_PORT/"
# Expected: hi-one-one
```

---

### Exercise 1.2

**Objective:** Create a Gateway using the `nginx` GatewayClass and confirm NGF provisions the expected data-plane resources.

**Setup:**

```bash
kubectl create namespace ex-1-2
```

**Task:** Create a Gateway named `gw` in namespace `ex-1-2` using the `nginx` GatewayClass with an HTTP listener on port 80. Confirm the Gateway reaches `Programmed: True` and identify the data-plane Service NGF provisions in the namespace.

**Verification:**

```bash
sleep 10
kubectl get gateway -n ex-1-2 gw \
  -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}'
# Expected: True

kubectl get svc -n ex-1-2 gw-nginx -o jsonpath='{.spec.type}'
# Expected: LoadBalancer
```

---

### Exercise 1.3

**Objective:** Apply the same HTTPRoute spec under both `eg` and `nginx` Gateways and confirm both respond with the same content.

**Setup:**

```bash
kubectl create namespace ex-1-3
kubectl apply -n ex-1-3 -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw-envoy}
spec:
  gatewayClassName: eg
  listeners: [{name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}]
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw-nginx}
spec:
  gatewayClassName: nginx
  listeners: [{name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: same}
spec:
  replicas: 1
  selector: {matchLabels: {app: same}}
  template:
    metadata: {labels: {app: same}}
    spec:
      containers:
      - {name: 'n', image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: same-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: same-html}
data: {index.html: "parity\n"}
---
apiVersion: v1
kind: Service
metadata: {name: same}
spec: {selector: {app: same}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-1-3 rollout status deployment/same --timeout=60s
```

**Task:** Create two HTTPRoutes (one per Gateway) with identical specs except for `parentRefs`, hostname `same.example.test`, path `/` -> Service `same`.

**Verification:**

```bash
sleep 5
NODE=$(kubectl get pods -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-namespace=ex-1-3 \
  -o jsonpath='{.items[0].spec.nodeName}')
ENVOY_IP=$(kubectl get node "$NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
ENVOY_PORT=$(kubectl get svc -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-namespace=ex-1-3 \
  -o jsonpath='{.items[0].spec.ports[0].nodePort}')

NGF_NODE=$(kubectl get pods -n ex-1-3 \
  -l gateway.networking.k8s.io/gateway-name=gw-nginx \
  -o jsonpath='{.items[0].spec.nodeName}')
NGINX_IP=$(kubectl get node "$NGF_NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NGINX_PORT=$(kubectl get svc -n ex-1-3 gw-nginx-nginx \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

curl -s -H "Host: same.example.test" "http://$ENVOY_IP:$ENVOY_PORT/"
# Expected: parity

curl -s -H "Host: same.example.test" "http://$NGINX_IP:$NGINX_PORT/"
# Expected: parity
```

---

## Level 2: Advanced Matching

### Exercise 2.1

**Objective:** Route by an `X-Tenant` header value.

**Setup:**

```bash
kubectl create namespace ex-2-1
kubectl apply -n ex-2-1 -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw}
spec:
  gatewayClassName: nginx
  listeners: [{name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: red-app}
spec:
  replicas: 1
  selector: {matchLabels: {app: red-app}}
  template:
    metadata: {labels: {app: red-app}}
    spec:
      containers:
      - {name: 'n', image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: red-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: red-html}
data: {index.html: "red\n"}
---
apiVersion: v1
kind: Service
metadata: {name: red-app}
spec: {selector: {app: red-app}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: blue-app}
spec:
  replicas: 1
  selector: {matchLabels: {app: blue-app}}
  template:
    metadata: {labels: {app: blue-app}}
    spec:
      containers:
      - {name: 'n', image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: blue-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: blue-html}
data: {index.html: "blue\n"}
---
apiVersion: v1
kind: Service
metadata: {name: blue-app}
spec: {selector: {app: blue-app}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-2-1 rollout status deployment/red-app deployment/blue-app --timeout=60s
```

**Task:** Create HTTPRoute `tenant-routing` with two rules: `X-Tenant: red` -> `red-app`, `X-Tenant: blue` -> `blue-app`. Hostname `tenant.example.test`.

**Verification:**

```bash
sleep 5
NGF_NODE=$(kubectl get pods -n ex-2-1 \
  -l gateway.networking.k8s.io/gateway-name=gw \
  -o jsonpath='{.items[0].spec.nodeName}')
NGINX_IP=$(kubectl get node "$NGF_NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NGINX_PORT=$(kubectl get svc -n ex-2-1 gw-nginx \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

curl -s -H "Host: tenant.example.test" -H "X-Tenant: red" "http://$NGINX_IP:$NGINX_PORT/"
# Expected: red

curl -s -H "Host: tenant.example.test" -H "X-Tenant: blue" "http://$NGINX_IP:$NGINX_PORT/"
# Expected: blue

curl -sI -H "Host: tenant.example.test" "http://$NGINX_IP:$NGINX_PORT/"
# Expected: 404 (no header)
```

---

### Exercise 2.2

**Objective:** Route by query parameter.

**Setup:** Continue using ex-2-1's Gateway and backends.

**Task:** Create HTTPRoute `query-routing` in `ex-2-1` attached to `gw`, hostname `query.example.test`, with two rules: requests with query param `env=prod` route to `red-app`, requests with `env=staging` route to `blue-app`.

**Verification:**

```bash
sleep 5
NGF_NODE=$(kubectl get pods -n ex-2-1 \
  -l gateway.networking.k8s.io/gateway-name=gw \
  -o jsonpath='{.items[0].spec.nodeName}')
NGINX_IP=$(kubectl get node "$NGF_NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NGINX_PORT=$(kubectl get svc -n ex-2-1 gw-nginx \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

curl -s -H "Host: query.example.test" "http://$NGINX_IP:$NGINX_PORT/?env=prod"
# Expected: red

curl -s -H "Host: query.example.test" "http://$NGINX_IP:$NGINX_PORT/?env=staging"
# Expected: blue
```

---

### Exercise 2.3

**Objective:** Combine path + method + header matches in a single rule (AND semantics).

**Setup:**

```bash
kubectl create namespace ex-2-3
kubectl apply -n ex-2-3 -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw}
spec:
  gatewayClassName: nginx
  listeners: [{name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: echo-app}
spec:
  replicas: 1
  selector: {matchLabels: {app: echo-app}}
  template:
    metadata: {labels: {app: echo-app}}
    spec:
      containers:
      - name: 'n'
        image: nginx:1.27
        volumeMounts: [{name: c, mountPath: /etc/nginx/conf.d}]
      volumes: [{name: c, configMap: {name: echo-app-conf}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: echo-app-conf}
data:
  default.conf: |
    server {
      listen 80;
      location / { return 200 "echo-red\n"; }
    }
---
apiVersion: v1
kind: Service
metadata: {name: echo-app}
spec: {selector: {app: echo-app}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-2-3 rollout status deployment/echo-app --timeout=60s
```

**Task:** Create HTTPRoute `combined` in `ex-2-3` attached to `gw`, hostname `combined.example.test`, with a single rule that matches all three conditions simultaneously: path prefix `/api`, method `POST`, and header `X-API-Key: admin`, routing to `echo-app`.

**Verification:**

```bash
sleep 5
NGF_NODE=$(kubectl get pods -n ex-2-3 \
  -l gateway.networking.k8s.io/gateway-name=gw \
  -o jsonpath='{.items[0].spec.nodeName}')
NGINX_IP=$(kubectl get node "$NGF_NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NGINX_PORT=$(kubectl get svc -n ex-2-3 gw-nginx \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

# All three match:
curl -s -X POST -H "Host: combined.example.test" -H "X-API-Key: admin" "http://$NGINX_IP:$NGINX_PORT/api"
# Expected: echo-red

# Missing header:
curl -sI -X POST -H "Host: combined.example.test" "http://$NGINX_IP:$NGINX_PORT/api"
# Expected: HTTP/1.1 404

# Wrong method:
curl -sI -X GET -H "Host: combined.example.test" -H "X-API-Key: admin" "http://$NGINX_IP:$NGINX_PORT/api"
# Expected: HTTP/1.1 404
```

---

## Level 3: Debugging

### Exercise 3.1

**Objective:** An HTTPRoute filter combination is not producing the expected response. Fix.

**Setup:**

```bash
kubectl create namespace ex-3-1
kubectl apply -n ex-3-1 -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw}
spec:
  gatewayClassName: nginx
  listeners: [{name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}]
---
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
      - {name: n, image: nginx:1.27, volumeMounts: [{name: c, mountPath: /etc/nginx/conf.d}]}
      volumes: [{name: c, configMap: {name: app-conf}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: app-conf}
data:
  default.conf: |
    server {
      listen 80;
      location / { return 200 "app-got: $request_uri\n"; }
    }
---
apiVersion: v1
kind: Service
metadata: {name: app}
spec: {selector: {app: app}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: order-bug}
spec:
  parentRefs: [{name: gw}]
  hostnames: ["order.example.test"]
  rules:
  - matches: [{path: {type: PathPrefix, value: /old}}]
    filters:
    - type: URLRewrite
      urlRewrite:
        path: {type: ReplacePrefixMatch, replacePrefixMatch: /new}
    - type: RequestRedirect
      requestRedirect: {scheme: https, statusCode: 301}
    backendRefs: [{name: app, port: 80}]
EOF
kubectl -n ex-3-1 rollout status deployment/app --timeout=60s
```

**Task:** Fix the HTTPRoute so that a request to `/old/items` returns `app-got: /new/items`.

**Verification:**

```bash
sleep 5
NGF_NODE=$(kubectl get pods -n ex-3-1 \
  -l gateway.networking.k8s.io/gateway-name=gw \
  -o jsonpath='{.items[0].spec.nodeName}')
NGINX_IP=$(kubectl get node "$NGF_NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NGINX_PORT=$(kubectl get svc -n ex-3-1 gw-nginx \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

curl -s -H "Host: order.example.test" "http://$NGINX_IP:$NGINX_PORT/old/items"
# Expected: app-got: /new/items
```

---

### Exercise 3.2

**Objective:** An HTTPRoute with a header match is not routing as expected. Diagnose and fix.

**Setup:**

```bash
kubectl create namespace ex-3-2
kubectl apply -n ex-3-2 -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw}
spec:
  gatewayClassName: nginx
  listeners: [{name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}]
---
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
data: {index.html: "case-app\n"}
---
apiVersion: v1
kind: Service
metadata: {name: app}
spec: {selector: {app: app}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: case-sensitive}
spec:
  parentRefs: [{name: gw}]
  hostnames: ["case.example.test"]
  rules:
  - matches: [{headers: [{name: X-Env, value: Production}]}]
    backendRefs: [{name: app, port: 80}]
EOF
kubectl -n ex-3-2 rollout status deployment/app --timeout=60s
```

**Task:** Fix the HTTPRoute so that requests with `X-Env: production` reach the backend.

**Verification:**

```bash
sleep 5
NGF_NODE=$(kubectl get pods -n ex-3-2 \
  -l gateway.networking.k8s.io/gateway-name=gw \
  -o jsonpath='{.items[0].spec.nodeName}')
NGINX_IP=$(kubectl get node "$NGF_NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NGINX_PORT=$(kubectl get svc -n ex-3-2 gw-nginx \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

curl -s -H "Host: case.example.test" -H "X-Env: production" "http://$NGINX_IP:$NGINX_PORT/"
# Expected: case-app
```

---

### Exercise 3.3

**Objective:** A traffic split is not distributing traffic as expected. Fix.

**Setup:**

```bash
kubectl create namespace ex-3-3
kubectl apply -n ex-3-3 -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw}
spec:
  gatewayClassName: nginx
  listeners: [{name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: v1-svc}
spec:
  replicas: 1
  selector: {matchLabels: {app: v1-svc}}
  template:
    metadata: {labels: {app: v1-svc}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: v1-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: v1-html}
data: {index.html: "v1\n"}
---
apiVersion: v1
kind: Service
metadata: {name: v1-svc}
spec: {selector: {app: v1-svc}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: v2-svc}
spec:
  replicas: 1
  selector: {matchLabels: {app: v2-svc}}
  template:
    metadata: {labels: {app: v2-svc}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: v2-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: v2-html}
data: {index.html: "v2\n"}
---
apiVersion: v1
kind: Service
metadata: {name: v2-svc}
spec: {selector: {app: v2-svc}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: bad-split}
spec:
  parentRefs: [{name: gw}]
  hostnames: ["split.example.test"]
  rules:
  - backendRefs:
    - {name: v1-svc, port: 80, weight: 0}
    - {name: v2-svc, port: 80, weight: 100}
EOF
kubectl -n ex-3-3 rollout status deployment/v1-svc deployment/v2-svc --timeout=60s
```

**Task:** Fix the configuration so that v1 receives 70% of traffic and v2 receives 30%.

**Verification:**

```bash
sleep 5
NGF_NODE=$(kubectl get pods -n ex-3-3 \
  -l gateway.networking.k8s.io/gateway-name=gw \
  -o jsonpath='{.items[0].spec.nodeName}')
NGINX_IP=$(kubectl get node "$NGF_NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NGINX_PORT=$(kubectl get svc -n ex-3-3 gw-nginx \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

V1=0; V2=0
for i in $(seq 1 50); do
  r=$(curl -s -H "Host: split.example.test" "http://$NGINX_IP:$NGINX_PORT/")
  [ "$r" = "v1" ] && V1=$((V1+1))
  [ "$r" = "v2" ] && V2=$((V2+1))
done
echo "v1: $V1, v2: $V2"
# Expected: roughly 35/15 (with variance; v1 clearly dominates)
```

---

## Level 4: Filters

### Exercise 4.1

**Objective:** Apply `RequestHeaderModifier` to add a header to requests before they reach the backend. Verify via backend-reflected header.

**Setup:**

```bash
kubectl create namespace ex-4-1
kubectl apply -n ex-4-1 -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw}
spec:
  gatewayClassName: nginx
  listeners: [{name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: echo}
spec:
  replicas: 1
  selector: {matchLabels: {app: echo}}
  template:
    metadata: {labels: {app: echo}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: c, mountPath: /etc/nginx/conf.d}]}
      volumes: [{name: c, configMap: {name: echo-conf}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: echo-conf}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        return 200 "x-source=$http_x_source\n";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: echo}
spec: {selector: {app: echo}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-4-1 rollout status deployment/echo --timeout=60s
```

**Task:** Create HTTPRoute `add-hdr` with filter `RequestHeaderModifier` that adds `X-Source: gateway-filter`, hostname `header.example.test`, backend `echo`.

**Verification:**

```bash
sleep 5
NGF_NODE=$(kubectl get pods -n ex-4-1 \
  -l gateway.networking.k8s.io/gateway-name=gw \
  -o jsonpath='{.items[0].spec.nodeName}')
NGINX_IP=$(kubectl get node "$NGF_NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NGINX_PORT=$(kubectl get svc -n ex-4-1 gw-nginx \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

curl -s -H "Host: header.example.test" "http://$NGINX_IP:$NGINX_PORT/"
# Expected: x-source=gateway-filter
```

---

### Exercise 4.2

**Objective:** Redirect HTTP to HTTPS via `RequestRedirect`.

**Setup:**

```bash
kubectl create namespace ex-4-2
kubectl apply -n ex-4-2 -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw}
spec:
  gatewayClassName: nginx
  listeners: [{name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: dummy}
spec:
  replicas: 1
  selector: {matchLabels: {app: dummy}}
  template:
    metadata: {labels: {app: dummy}}
    spec:
      containers:
      - {name: n, image: nginx:1.27}
---
apiVersion: v1
kind: Service
metadata: {name: dummy}
spec: {selector: {app: dummy}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-4-2 rollout status deployment/dummy --timeout=60s
```

**Task:** Create HTTPRoute `to-https` that redirects all requests on host `insecure.example.test` to `https://secure.example.test/` with status 301.

**Verification:**

```bash
sleep 5
NGF_NODE=$(kubectl get pods -n ex-4-2 \
  -l gateway.networking.k8s.io/gateway-name=gw \
  -o jsonpath='{.items[0].spec.nodeName}')
NGINX_IP=$(kubectl get node "$NGF_NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NGINX_PORT=$(kubectl get svc -n ex-4-2 gw-nginx \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

curl -sI -H "Host: insecure.example.test" "http://$NGINX_IP:$NGINX_PORT/anywhere"
# Expected: HTTP/1.1 301 Moved Permanently
# Expected (Location): https://secure.example.test/anywhere
```

---

### Exercise 4.3

**Objective:** Use `URLRewrite` with `ReplaceFullPath` to map any request to a fixed path on the backend.

**Setup:**

```bash
kubectl create namespace ex-4-3
kubectl apply -n ex-4-3 -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw}
spec:
  gatewayClassName: nginx
  listeners: [{name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: echo}
spec:
  replicas: 1
  selector: {matchLabels: {app: echo}}
  template:
    metadata: {labels: {app: echo}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: c, mountPath: /etc/nginx/conf.d}]}
      volumes: [{name: c, configMap: {name: echo-conf}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: echo-conf}
data:
  default.conf: |
    server {
      listen 80;
      location / { return 200 "path=$request_uri\n"; }
    }
---
apiVersion: v1
kind: Service
metadata: {name: echo}
spec: {selector: {app: echo}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-4-3 rollout status deployment/echo --timeout=60s
```

**Task:** Create HTTPRoute `rewrite-all` that rewrites the full path of any request to `/fixed`, routing to Service `echo`.

**Verification:**

```bash
sleep 5
NGF_NODE=$(kubectl get pods -n ex-4-3 \
  -l gateway.networking.k8s.io/gateway-name=gw \
  -o jsonpath='{.items[0].spec.nodeName}')
NGINX_IP=$(kubectl get node "$NGF_NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NGINX_PORT=$(kubectl get svc -n ex-4-3 gw-nginx \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

curl -s -H "Host: rw.example.test" "http://$NGINX_IP:$NGINX_PORT/dynamic/path"
# Expected: path=/fixed

curl -s -H "Host: rw.example.test" "http://$NGINX_IP:$NGINX_PORT/another"
# Expected: path=/fixed
```

---

## Level 5: Advanced

### Exercise 5.1

**Objective:** Set up a canary release: 90% of traffic to `v1-app`, 10% to `v2-app`. Then shift to 50/50. Observe the traffic distribution in both states.

**Setup:**

```bash
kubectl create namespace ex-5-1
kubectl apply -n ex-5-1 -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw}
spec:
  gatewayClassName: nginx
  listeners: [{name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}]
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
data: {index.html: "v1\n"}
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
data: {index.html: "v2\n"}
---
apiVersion: v1
kind: Service
metadata: {name: v2-app}
spec: {selector: {app: v2-app}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-5-1 rollout status deployment/v1-app deployment/v2-app --timeout=60s
```

**Task:** Create HTTPRoute `canary` with `backendRefs` v1-app weight 90, v2-app weight 10. Observe 100 requests, confirm ~90/10 split. Then patch to 50/50 and observe again.

**Verification:**

```bash
sleep 5
NGF_NODE=$(kubectl get pods -n ex-5-1 \
  -l gateway.networking.k8s.io/gateway-name=gw \
  -o jsonpath='{.items[0].spec.nodeName}')
NGINX_IP=$(kubectl get node "$NGF_NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NGINX_PORT=$(kubectl get svc -n ex-5-1 gw-nginx \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

echo "Phase 1 (90/10):"
V1=0; V2=0
for i in $(seq 1 100); do
  r=$(curl -s -H "Host: canary.example.test" "http://$NGINX_IP:$NGINX_PORT/")
  [ "$r" = "v1" ] && V1=$((V1+1))
  [ "$r" = "v2" ] && V2=$((V2+1))
done
echo "v1: $V1, v2: $V2"
# Expected: v1 around 85-95, v2 around 5-15

kubectl patch httproute -n ex-5-1 canary --type='json' -p='[
  {"op":"replace","path":"/spec/rules/0/backendRefs/0/weight","value":50},
  {"op":"replace","path":"/spec/rules/0/backendRefs/1/weight","value":50}
]'
sleep 3

echo "Phase 2 (50/50):"
V1=0; V2=0
for i in $(seq 1 100); do
  r=$(curl -s -H "Host: canary.example.test" "http://$NGINX_IP:$NGINX_PORT/")
  [ "$r" = "v1" ] && V1=$((V1+1))
  [ "$r" = "v2" ] && V2=$((V2+1))
done
echo "v1: $V1, v2: $V2"
# Expected: both in roughly [40, 60] range
```

---

### Exercise 5.2

**Objective:** An HTTPRoute is not forwarding requests to the backend as expected. Diagnose and fix.

**Setup:**

```bash
kubectl create namespace ex-5-2
kubectl apply -n ex-5-2 -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw}
spec:
  gatewayClassName: nginx
  listeners: [{name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}]
---
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
      - {name: n, image: nginx:1.27, volumeMounts: [{name: c, mountPath: /etc/nginx/conf.d}]}
      volumes: [{name: c, configMap: {name: app-conf}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: app-conf}
data:
  default.conf: |
    server {
      listen 80;
      location / { return 200 "final-path=$request_uri\n"; }
    }
---
apiVersion: v1
kind: Service
metadata: {name: app}
spec: {selector: {app: app}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: bad-order}
spec:
  parentRefs: [{name: gw}]
  hostnames: ["order.example.test"]
  rules:
  - matches: [{path: {type: PathPrefix, value: /old-api}}]
    filters:
    - type: RequestRedirect
      requestRedirect:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /new-api
        statusCode: 302
    - type: URLRewrite
      urlRewrite:
        path: {type: ReplacePrefixMatch, replacePrefixMatch: /v2}
    backendRefs: [{name: app, port: 80}]
EOF
kubectl -n ex-5-2 rollout status deployment/app --timeout=60s
```

**Task:** Fix the HTTPRoute so that a request to `/old-api/data` returns `final-path=/v2/data`.

**Verification:**

```bash
sleep 5
NGF_NODE=$(kubectl get pods -n ex-5-2 \
  -l gateway.networking.k8s.io/gateway-name=gw \
  -o jsonpath='{.items[0].spec.nodeName}')
NGINX_IP=$(kubectl get node "$NGF_NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NGINX_PORT=$(kubectl get svc -n ex-5-2 gw-nginx \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

curl -s -H "Host: order.example.test" "http://$NGINX_IP:$NGINX_PORT/old-api/data"
# Expected: final-path=/v2/data
```

---

### Exercise 5.3

**Objective:** Apply a production-style pattern: header-based canary routing combined with URL rewrite for the canary path.

**Setup:**

```bash
kubectl create namespace ex-5-3
kubectl apply -n ex-5-3 -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw}
spec:
  gatewayClassName: nginx
  listeners: [{name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: stable}
spec:
  replicas: 1
  selector: {matchLabels: {app: stable}}
  template:
    metadata: {labels: {app: stable}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: c, mountPath: /etc/nginx/conf.d}]}
      volumes: [{name: c, configMap: {name: stable-conf}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: stable-conf}
data:
  default.conf: |
    server {
      listen 80;
      location / { return 200 "stable path=$request_uri\n"; }
    }
---
apiVersion: v1
kind: Service
metadata: {name: stable}
spec: {selector: {app: stable}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: canary}
spec:
  replicas: 1
  selector: {matchLabels: {app: canary}}
  template:
    metadata: {labels: {app: canary}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: c, mountPath: /etc/nginx/conf.d}]}
      volumes: [{name: c, configMap: {name: canary-conf}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: canary-conf}
data:
  default.conf: |
    server {
      listen 80;
      location / { return 200 "canary path=$request_uri\n"; }
    }
---
apiVersion: v1
kind: Service
metadata: {name: canary}
spec: {selector: {app: canary}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-5-3 rollout status deployment/stable deployment/canary --timeout=60s
```

**Task:** Create HTTPRoute `production` with two rules, both on host `prod.example.test`:

1. Requests with header `X-Canary: true` on `/api` are rewritten to `/v2` and routed to `canary`.
2. All other requests on `/api` are routed to `stable` with no rewrite.

**Verification:**

```bash
sleep 5
NGF_NODE=$(kubectl get pods -n ex-5-3 \
  -l gateway.networking.k8s.io/gateway-name=gw \
  -o jsonpath='{.items[0].spec.nodeName}')
NGINX_IP=$(kubectl get node "$NGF_NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NGINX_PORT=$(kubectl get svc -n ex-5-3 gw-nginx \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

curl -s -H "Host: prod.example.test" -H "X-Canary: true" "http://$NGINX_IP:$NGINX_PORT/api/data"
# Expected: canary path=/v2/data

curl -s -H "Host: prod.example.test" "http://$NGINX_IP:$NGINX_PORT/api/data"
# Expected: stable path=/api/data
```

---

## Cleanup

```bash
for ns in ex-1-1 ex-1-2 ex-1-3 ex-2-1 ex-2-3 ex-3-1 ex-3-2 ex-3-3 \
         ex-4-1 ex-4-2 ex-4-3 ex-5-1 ex-5-2 ex-5-3; do
  kubectl delete namespace "$ns" --ignore-not-found
done
```

## Key Takeaways

HTTPRoute `matches` combine path + headers + queryParams + method (AND within one match object, OR across multiple). Header matching is case-insensitive for names, case-sensitive for values by default. Traffic splitting via `backendRefs[].weight`. Filters (RequestHeaderModifier, RequestRedirect, URLRewrite, ResponseHeaderModifier) execute in list order; a RequestRedirect is terminal. `URLRewrite` supports `ReplacePrefixMatch` and `ReplaceFullPath`. NGINX Gateway Fabric v2.5.1 and Envoy Gateway both implement this surface; the same YAML works under both. Both implementations set `externalTrafficPolicy: Local`; use `gateway.networking.k8s.io/gateway-name=<gw-name>` to find the NGF data-plane pod's node, then target that node's IP and the Service NodePort.
