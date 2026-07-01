# Advanced Gateway API Routing with NGINX Gateway Fabric Tutorial

Assignment 3 covered Gateway API fundamentals using Envoy Gateway. This tutorial covers the advanced half: header matching, query-param matching, method matching, traffic splitting, and filters (`RequestHeaderModifier`, `RequestRedirect`, `URLRewrite`, `ResponseHeaderModifier`). The implementation is NGINX Gateway Fabric v2.5.1, which runs alongside Envoy Gateway. The payoff is concrete: the exact same HTTPRoute YAML (changing only `parentRefs` to a different Gateway) produces identical behavior under two different implementations.

NGINX Gateway Fabric is NGINX Inc.'s conformant Gateway API implementation. It translates Gateway API resources to NGINX configuration and serves traffic with NGINX itself, while tracking status conditions in the Gateway API's standard way.

## Prerequisites

Complete `exercises/11-ingress-and-gateway-api/assignment-3` first and keep Envoy Gateway installed. Gateway API CRDs must be in place (`docs/cluster-setup.md#gateway-api-crds`). Use the multi-node kind cluster from earlier assignments (`docs/cluster-setup.md#multi-node-kind-cluster`).

Verify.

```bash
kubectl get gatewayclass
# Expected: eg (from Envoy Gateway), potentially more after this tutorial

kubectl get crd gatewayclasses.gateway.networking.k8s.io
# Expected: exists
```

Create the tutorial namespace.

```bash
kubectl create namespace tutorial-gw-adv
```

## Part 1: Install NGINX Gateway Fabric v2.5.1

Add the chart repository and install.

```bash
helm install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --version 2.5.1 \
  --namespace nginx-gateway --create-namespace

kubectl -n nginx-gateway rollout status deployment/ngf-nginx-gateway-fabric --timeout=180s

kubectl get gatewayclass
```

Expected output: now includes a row for `nginx` (controllerName `gateway.nginx.org/nginx-gateway-controller`). NGINX Gateway Fabric's default class is `nginx`.

## Part 2: Side-by-side implementations

Create two Gateways: one attached to Envoy Gateway's class, one to NGINX Gateway Fabric's.

```bash
kubectl apply -n tutorial-gw-adv -f - <<'EOF'
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
EOF
sleep 8
kubectl get gateway -n tutorial-gw-adv
```

Both Gateways come up `Programmed: True`. Envoy Gateway places its data-plane Service in `envoy-gateway-system`. NGINX Gateway Fabric v2.x places its data-plane Service in the Gateway's own namespace (`tutorial-gw-adv` in this case), not in `nginx-gateway`. The NGF data-plane Service is named `<gateway-name>-nginx`, so the Gateway named `gw-nginx` produces a Service named `gw-nginx-nginx` in `tutorial-gw-adv`. Both implementations set `externalTrafficPolicy: Local` on their data-plane Services, so you must target the specific node running the data-plane pod rather than any arbitrary cluster node.

Deploy a backend and two HTTPRoutes, one per Gateway.

```bash
kubectl apply -n tutorial-gw-adv -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: uni}
spec:
  replicas: 1
  selector: {matchLabels: {app: uni}}
  template:
    metadata: {labels: {app: uni}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: uni-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: uni-html}
data: {index.html: "universal-content\n"}
---
apiVersion: v1
kind: Service
metadata: {name: uni}
spec: {selector: {app: uni}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: r-envoy}
spec:
  parentRefs: [{name: gw-envoy}]
  hostnames: ["uni.example.test"]
  rules:
  - backendRefs: [{name: uni, port: 80}]
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: r-nginx}
spec:
  parentRefs: [{name: gw-nginx}]
  hostnames: ["uni.example.test"]
  rules:
  - backendRefs: [{name: uni, port: 80}]
EOF
kubectl -n tutorial-gw-adv rollout status deployment/uni --timeout=60s

# Envoy Gateway: externalTrafficPolicy: Local -- target the node running the Envoy pod
NODE=$(kubectl get pods -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-namespace=tutorial-gw-adv \
  -o jsonpath='{.items[0].spec.nodeName}')
ENVOY_IP=$(kubectl get node "$NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
ENVOY_PORT=$(kubectl get svc -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-namespace=tutorial-gw-adv \
  -o jsonpath='{.items[0].spec.ports[0].nodePort}')

# NGF: also externalTrafficPolicy: Local -- target the node running the NGF data-plane pod
NGF_NODE=$(kubectl get pods -n tutorial-gw-adv \
  -l gateway.networking.k8s.io/gateway-name=gw-nginx \
  -o jsonpath='{.items[0].spec.nodeName}')
NGINX_IP=$(kubectl get node "$NGF_NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NGINX_PORT=$(kubectl get svc -n tutorial-gw-adv gw-nginx-nginx \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

curl -s -H "Host: uni.example.test" "http://$ENVOY_IP:$ENVOY_PORT/"
# Expected (via Envoy): universal-content

curl -s -H "Host: uni.example.test" "http://$NGINX_IP:$NGINX_PORT/"
# Expected (via NGINX): universal-content
```

Both controllers serve the same content.

## Part 3: Header matching

**Spec field reference for `HTTPRoute` match conditions:**

- **`rules[*].matches[*].headers[]`**
  - **Type:** array of objects with `name`, `value`, optional `type`.
  - **Valid `type` values:** `Exact` (default), `RegularExpression`.
  - **Default `type`:** `Exact`.
  - **Failure mode when misconfigured:** header name matching is always case-insensitive; header value matching with `Exact` is case-sensitive. Missing the match means the request falls through to a different rule or 404s.

Apply an HTTPRoute that routes based on an `X-Tenant` header.

```bash
kubectl apply -n tutorial-gw-adv -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: svc-a}
spec:
  replicas: 1
  selector: {matchLabels: {app: a}}
  template:
    metadata: {labels: {app: a}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: a-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: a-html}
data: {index.html: "tenant-a\n"}
---
apiVersion: v1
kind: Service
metadata: {name: svc-a}
spec: {selector: {app: a}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: svc-b}
spec:
  replicas: 1
  selector: {matchLabels: {app: b}}
  template:
    metadata: {labels: {app: b}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: b-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: b-html}
data: {index.html: "tenant-b\n"}
---
apiVersion: v1
kind: Service
metadata: {name: svc-b}
spec: {selector: {app: b}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: header-match}
spec:
  parentRefs: [{name: gw-nginx}]
  hostnames: ["tenants.example.test"]
  rules:
  - matches: [{headers: [{name: X-Tenant, value: alpha}]}]
    backendRefs: [{name: svc-a, port: 80}]
  - matches: [{headers: [{name: X-Tenant, value: beta}]}]
    backendRefs: [{name: svc-b, port: 80}]
EOF

kubectl -n tutorial-gw-adv rollout status deployment/svc-a deployment/svc-b --timeout=60s

curl -s -H "Host: tenants.example.test" -H "X-Tenant: alpha" "http://$NGINX_IP:$NGINX_PORT/"
# Expected: tenant-a

curl -s -H "Host: tenants.example.test" -H "X-Tenant: beta" "http://$NGINX_IP:$NGINX_PORT/"
# Expected: tenant-b

curl -sI -H "Host: tenants.example.test" -H "X-Tenant: gamma" "http://$NGINX_IP:$NGINX_PORT/"
# Expected: 404 (no rule matches)
```

## Part 4: Query-param matching

```bash
kubectl apply -n tutorial-gw-adv -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: query-match}
spec:
  parentRefs: [{name: gw-nginx}]
  hostnames: ["query.example.test"]
  rules:
  - matches: [{queryParams: [{name: version, value: v1}]}]
    backendRefs: [{name: svc-a, port: 80}]
  - matches: [{queryParams: [{name: version, value: v2}]}]
    backendRefs: [{name: svc-b, port: 80}]
EOF
sleep 3

curl -s -H "Host: query.example.test" "http://$NGINX_IP:$NGINX_PORT/?version=v1"
# Expected: tenant-a

curl -s -H "Host: query.example.test" "http://$NGINX_IP:$NGINX_PORT/?version=v2"
# Expected: tenant-b
```

## Part 5: Method matching

```bash
kubectl apply -n tutorial-gw-adv -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: method-match}
spec:
  parentRefs: [{name: gw-nginx}]
  hostnames: ["method.example.test"]
  rules:
  - matches: [{method: GET}]
    backendRefs: [{name: svc-a, port: 80}]
  - matches: [{method: POST}]
    backendRefs: [{name: svc-b, port: 80}]
EOF
sleep 3

curl -s -X GET -H "Host: method.example.test" "http://$NGINX_IP:$NGINX_PORT/"
# Expected: tenant-a

curl -s -X POST -H "Host: method.example.test" "http://$NGINX_IP:$NGINX_PORT/"
# Expected: tenant-b
```

## Part 6: Traffic splitting

```bash
kubectl apply -n tutorial-gw-adv -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: split}
spec:
  parentRefs: [{name: gw-nginx}]
  hostnames: ["split.example.test"]
  rules:
  - backendRefs:
    - {name: svc-a, port: 80, weight: 80}
    - {name: svc-b, port: 80, weight: 20}
EOF
sleep 3

A=0; B=0
for i in $(seq 1 40); do
  resp=$(curl -s -H "Host: split.example.test" "http://$NGINX_IP:$NGINX_PORT/")
  [ "$resp" = "tenant-a" ] && A=$((A+1))
  [ "$resp" = "tenant-b" ] && B=$((B+1))
done
echo "a: $A, b: $B"
# Expected: roughly 32/8, with variance; a should clearly dominate
```

## Part 7: Filters

**Spec field reference for `filters`:**

- **`rules[*].filters[]`**
  - **Type:** array of filter objects.
  - **Valid `type` values:** `RequestHeaderModifier`, `RequestRedirect`, `URLRewrite`, `ResponseHeaderModifier`, `RequestMirror`, `ExtensionRef`.
  - **Default:** empty array (no filters applied).
  - **Failure mode when misconfigured:** filters execute in the order listed; applying a `RequestRedirect` before a `URLRewrite` means the rewrite never runs.

### RequestHeaderModifier

```bash
kubectl apply -n tutorial-gw-adv -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: add-header}
spec:
  parentRefs: [{name: gw-nginx}]
  hostnames: ["addheader.example.test"]
  rules:
  - filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        add:
        - {name: X-Source, value: gateway}
    backendRefs: [{name: svc-a, port: 80}]
EOF
```

The backend nginx doesn't show headers in the default page. To demonstrate the filter actually runs, use `httpbin` or change the backend to one that echoes headers. For this tutorial, accept the filter as demonstrably applied via the controller config (verify via `kubectl describe httproute`).

### RequestRedirect

```bash
kubectl apply -n tutorial-gw-adv -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: redirect}
spec:
  parentRefs: [{name: gw-nginx}]
  hostnames: ["old.example.test"]
  rules:
  - filters:
    - type: RequestRedirect
      requestRedirect:
        scheme: https
        hostname: new.example.test
        statusCode: 301
    backendRefs: [{name: svc-a, port: 80}]
EOF
sleep 3

curl -sI -H "Host: old.example.test" "http://$NGINX_IP:$NGINX_PORT/"
# Expected: HTTP/1.1 301 Moved Permanently
# Expected Location header: https://new.example.test/
```

### URLRewrite

```bash
kubectl apply -n tutorial-gw-adv -f - <<'EOF'
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
        return 200 "path-seen: $request_uri\n";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: echo}
spec: {selector: {app: echo}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: rewrite}
spec:
  parentRefs: [{name: gw-nginx}]
  hostnames: ["rewrite.example.test"]
  rules:
  - matches: [{path: {type: PathPrefix, value: /old}}]
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /new
    backendRefs: [{name: echo, port: 80}]
EOF

kubectl -n tutorial-gw-adv rollout status deployment/echo --timeout=60s

curl -s -H "Host: rewrite.example.test" "http://$NGINX_IP:$NGINX_PORT/old/items"
# Expected: path-seen: /new/items
```

The `URLRewrite` filter with `ReplacePrefixMatch` substitutes the matched path prefix.

## Part 8: Combined matches

```bash
kubectl apply -n tutorial-gw-adv -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: combined}
spec:
  parentRefs: [{name: gw-nginx}]
  hostnames: ["combined.example.test"]
  rules:
  - matches:
    - path: {type: PathPrefix, value: /api}
      method: POST
      headers: [{name: X-API-Key, value: secret}]
    backendRefs: [{name: svc-a, port: 80}]
EOF
sleep 3

# All three conditions must match:
curl -sI -X POST -H "Host: combined.example.test" -H "X-API-Key: secret" "http://$NGINX_IP:$NGINX_PORT/api"
# Expected: 200 OK

# Any condition fails -> no rule match -> 404:
curl -sI -X GET -H "Host: combined.example.test" -H "X-API-Key: secret" "http://$NGINX_IP:$NGINX_PORT/api"
# Expected: 404 (wrong method)

curl -sI -X POST -H "Host: combined.example.test" "http://$NGINX_IP:$NGINX_PORT/api"
# Expected: 404 (missing header)
```

All fields inside a single match object are ANDed. Multiple match objects on one rule are ORed.

## Cleanup

```bash
kubectl delete namespace tutorial-gw-adv
```

To remove NGINX Gateway Fabric (keep for assignment 5):

```bash
helm uninstall -n nginx-gateway ngf
kubectl delete namespace nginx-gateway
```

## Reference Commands

| Task | Command |
|---|---|
| List GatewayClasses | `kubectl get gatewayclass` |
| NGINX Gateway Fabric logs | `kubectl logs -n nginx-gateway -l app.kubernetes.io/instance=ngf --tail=50` |
| Describe an HTTPRoute (all match conditions) | `kubectl describe httproute -n <ns> <name>` |
| Find NGF data-plane pod node | `kubectl get pods -n <gw-ns> -l gateway.networking.k8s.io/gateway-name=<gw-name> -o jsonpath='{.items[0].spec.nodeName}'` |
| Get NGF data-plane NodePort | `kubectl get svc -n <gw-ns> <gw-name>-nginx -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}'` |
| Check which parent accepted a route | `kubectl get httproute -n <ns> <name> -o jsonpath='{.status.parents[*]}'` |

## Key Takeaways

Gateway API's advanced matching (`headers`, `queryParams`, `method`) is all inside `rules[*].matches[*]`. Conditions within one match object are ANDed; multiple match objects within one rule are ORed. Header name matching is case-insensitive; header value matching defaults to `Exact`. Traffic splitting uses `backendRefs[].weight`. Filters (`RequestHeaderModifier`, `RequestRedirect`, `URLRewrite`, `ResponseHeaderModifier`) execute in the order listed. `URLRewrite` with `ReplacePrefixMatch` is the Gateway-API equivalent of Ingress rewrite-target. Running both Envoy Gateway and NGINX Gateway Fabric in the same cluster, with the same HTTPRoute YAML (only `parentRefs` differs), produces identical behavior. NGINX Gateway Fabric v2.5.1 is installed via Helm `oci://ghcr.io/nginx/charts/nginx-gateway-fabric`. In NGF v2.x, a Gateway named `gw` in namespace `ex-1-1` causes NGF to provision a data-plane Service named `gw-nginx` in `ex-1-1`. Both NGF and Envoy Gateway set `externalTrafficPolicy: Local`; target the node running the data-plane pod using the `gateway.networking.k8s.io/gateway-name` label selector.
