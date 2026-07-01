# Migration from Ingress to Gateway API Tutorial

The Ingress API was frozen in 2019 and the Kubernetes project officially recommends Gateway API for new work. In March 2026 the ingress-nginx project retired and its intended successor, InGate, also retired. The realistic path forward for a production Ingress user is migration to Gateway API. This tutorial teaches that migration using the `ingress2gateway` CLI v1.0.0 (released 2026-03-20), which translates Ingress YAML into equivalent Gateway API resources.

The CLI is a translation tool, not an end-to-end migrator. For standard features (host-based rules, path types, `defaultBackend`, `tls[]`) the translation is mechanical and correct. For controller-specific annotations (rewrite-target, rate-limit, ssl-redirect, custom middlewares), the CLI drops the annotation with a warning; you decide how to express the equivalent in Gateway API filter syntax. The 2026 CKA exam tests both the mechanical translation and the judgment for annotations.

The migration workflow is three steps:

1. **Generate Gateway API YAML** with `ingress2gateway print`.
2. **Review and adjust** the output, filling in gaps for non-translating annotations.
3. **Apply and cut over**, with both routes running in parallel first to verify parity.

## Prerequisites

Traefik from assignment 1 must be installed (`traefik` namespace). Envoy Gateway from assignment 3 must be installed (`envoy-gateway-system` namespace). Gateway API CRDs v1.5.1 must be in place. Multi-node kind cluster with extraPortMappings.

Verify.

```bash
kubectl get pods -n traefik
# Expected: Running Traefik pod

kubectl get pods -n envoy-gateway-system
# Expected: Running Envoy Gateway pod

kubectl get gatewayclass
# Expected: eg row present
```

Create the tutorial namespace.

```bash
kubectl create namespace tutorial-mig
```

## Part 1: Install `ingress2gateway` CLI v1.1.0

This is a host-side CLI tool. Install it on your workstation, not on cluster nodes. Use
the architecture matching your workstation (amd64 for x86_64 hosts), not the architecture
of your cluster nodes.

```bash
curl -L -o /tmp/ingress2gateway.tar.gz \
  https://github.com/kubernetes-sigs/ingress2gateway/releases/download/v1.1.0/ingress2gateway_Linux_x86_64.tar.gz
tar -xzf /tmp/ingress2gateway.tar.gz -C /tmp
sudo install /tmp/ingress2gateway /usr/local/bin/ingress2gateway

ingress2gateway --version
# Expected: includes v1.1.0 in the output
```

Alternative (without sudo): move the binary into a user-writable location on your `PATH`.

## Part 2: Translate a simple Ingress

Write a minimal Ingress YAML to a file and run the CLI.

```bash
cat <<'EOF' > /tmp/simple-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: simple
  namespace: tutorial-mig
spec:
  ingressClassName: traefik
  rules:
  - host: simple.example.test
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: hello
            port:
              number: 80
EOF

ingress2gateway print --input-file=/tmp/simple-ingress.yaml --providers=ingress-nginx
```

Expected output (approximate):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: simple-traefik
  namespace: tutorial-mig
spec:
  gatewayClassName: traefik
  listeners:
  - name: simple-example-test-http
    port: 80
    protocol: HTTP
    hostname: simple.example.test
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: simple
  namespace: tutorial-mig
spec:
  parentRefs:
  - name: simple-traefik
  hostnames:
  - simple.example.test
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: hello
      port: 80
```

The translation preserved the rule 1:1: host became `hostnames`, `pathType: Prefix` became `PathPrefix`, the backend shape was rewritten. The generated Gateway has `gatewayClassName: traefik`, which assumes a Gateway-API implementation running under that class; for the actual cutover you would change it to `eg` (Envoy Gateway) or another Gateway-API implementation since Traefik typically uses its own IngressClass, not GatewayClass.

Note: the `--providers` flag tells the CLI which annotation namespace to look at. For an Ingress with only generic fields (like the one above), any provider works.

## Part 3: Field mapping

**Spec mapping from Ingress to Gateway API:**

| Ingress field | Gateway API equivalent |
|---|---|
| `spec.ingressClassName` | `Gateway.spec.gatewayClassName` (choose a Gateway-API class) |
| `spec.rules[].host` | `Gateway.spec.listeners[].hostname` (listener) + `HTTPRoute.spec.hostnames[]` |
| `spec.rules[].http.paths[].path` | `HTTPRoute.spec.rules[].matches[].path.value` |
| `pathType: Prefix` | `path.type: PathPrefix` |
| `pathType: Exact` | `path.type: Exact` |
| `pathType: ImplementationSpecific` | implementation-dependent; often `PathPrefix` |
| `backend.service.name` | `HTTPRoute.spec.rules[].backendRefs[].name` |
| `backend.service.port.number` | `HTTPRoute.spec.rules[].backendRefs[].port` |
| `spec.defaultBackend` | an HTTPRoute with no match conditions pointing at that Service |
| `spec.tls[].hosts` | `Gateway.spec.listeners[].hostname` (one HTTPS listener per host) |
| `spec.tls[].secretName` | `Gateway.spec.listeners[].tls.certificateRefs[].name` |

Annotations that translate (provider-dependent):

- Some Traefik middlewares have Gateway API filter equivalents (e.g., `traefik.ingress.kubernetes.io/router.middlewares: strip-prefix` can map to a `URLRewrite` filter).
- `nginx.ingress.kubernetes.io/rewrite-target` maps to `URLRewrite` filter.
- `nginx.ingress.kubernetes.io/ssl-redirect: true` maps to a separate HTTPRoute with a `RequestRedirect` filter scheme:https.

Annotations that do NOT translate:

- Rate limiting (no Gateway API primitive in v1.0 stable; some implementations add CRDs).
- ModSecurity, WAF-specific annotations.
- Controller-specific timeout tuning.
- Custom Lua or Nginx config snippets.

## Part 4: Translate an Ingress with path rewriting

```bash
cat <<'EOF' > /tmp/rewrite-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rewritten
  namespace: tutorial-mig
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: rewritten.example.test
    http:
      paths:
      - path: /app
        pathType: Prefix
        backend:
          service:
            name: backend
            port:
              number: 80
EOF

ingress2gateway print --input-file=/tmp/rewrite-ingress.yaml --providers=ingress-nginx
```

Expected output: a Gateway + HTTPRoute with a `URLRewrite` filter generated from the `rewrite-target: /` annotation. The CLI's `--providers=ingress-nginx` tells it to recognize nginx-specific annotations and translate the common ones. Output includes something like:

```yaml
...
  rules:
  - matches:
    - path: {type: PathPrefix, value: /app}
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /
    backendRefs:
    - name: backend
      port: 80
```

This is the best-case scenario. The CLI detected an annotation it knows about and produced the correct Gateway API equivalent.

## Part 5: Translate an Ingress with TLS

```bash
cat <<'EOF' > /tmp/tls-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: secure
  namespace: tutorial-mig
spec:
  ingressClassName: traefik
  tls:
  - hosts: ["secure.example.test"]
    secretName: secure-tls
  rules:
  - host: secure.example.test
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: secure-app
            port:
              number: 80
EOF

ingress2gateway print --input-file=/tmp/tls-ingress.yaml --providers=ingress-nginx
```

Expected output: a Gateway with two listeners (HTTP on 80 and HTTPS on 443), the HTTPS listener carrying `tls.certificateRefs` referencing `secure-tls`, and an HTTPRoute routing to `secure-app`. The CLI replicates the TLS config at the Gateway level instead of the HTTPRoute level, matching Gateway API's design.

## Part 6: Side-by-side running

The safest cutover pattern: run both the original Ingress (served by Traefik) and the translated Gateway API resources (served by Envoy Gateway), route traffic through each, and verify both return the same response. When satisfied, cut over DNS (or the L4 load balancer) to send traffic only to the Gateway API endpoint.

Deploy a backend.

```bash
kubectl apply -n tutorial-mig -f - <<'EOF'
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
data: {index.html: "unchanged-content\n"}
---
apiVersion: v1
kind: Service
metadata: {name: hello}
spec: {selector: {app: hello}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n tutorial-mig rollout status deployment/hello --timeout=60s
```

Apply the Ingress via Traefik.

```bash
kubectl apply -n tutorial-mig -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: {name: old-way}
spec:
  ingressClassName: traefik
  rules:
  - host: parity.example.test
    http:
      paths:
      - {path: /, pathType: Prefix, backend: {service: {name: hello, port: {number: 80}}}}
EOF

sleep 3
curl -s -H "Host: parity.example.test" http://localhost/
# Expected: unchanged-content (via Traefik Ingress)
```

Apply the Gateway API equivalent (with `gatewayClassName: eg` for Envoy Gateway).

```bash
kubectl apply -n tutorial-mig -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: new-way-gw}
spec:
  gatewayClassName: eg
  listeners:
  - {name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: new-way-route}
spec:
  parentRefs: [{name: new-way-gw}]
  hostnames: ["parity.example.test"]
  rules:
  - matches: [{path: {type: PathPrefix, value: /}}]
    backendRefs: [{name: hello, port: 80}]
EOF

sleep 5
SVC=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=tutorial-mig -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n envoy-gateway-system "svc/$SVC" 9090:80 &
sleep 2

curl -s -H "Host: parity.example.test" http://localhost:9090/
# Expected: unchanged-content (via Envoy Gateway)

pkill -f "port-forward" 2>/dev/null
```

Both paths return the same content. At this point the application's clients can start shifting traffic gradually: a small percentage through the Envoy Gateway endpoint, then larger, then 100%. Once all traffic is on Gateway API, delete the Ingress.

## Part 7: Annotations that do not translate

```bash
cat <<'EOF' > /tmp/rate-limit-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: limited
  namespace: tutorial-mig
  annotations:
    nginx.ingress.kubernetes.io/limit-rps: "10"
spec:
  ingressClassName: nginx
  rules:
  - host: rl.example.test
    http:
      paths:
      - {path: /, pathType: Prefix, backend: {service: {name: hello, port: {number: 80}}}}
EOF

ingress2gateway print --input-file=/tmp/rate-limit-ingress.yaml --providers=ingress-nginx 2>&1 | head -n 40
```

Expected output: the CLI prints a warning about the rate-limit annotation with no Gateway API equivalent, plus the Gateway + HTTPRoute with the rate limit omitted. For the manual translation, you would use an implementation-specific CRD (for example, Envoy Gateway's `BackendTrafficPolicy` or NGINX Gateway Fabric's `ClientSettingsPolicy`). These are outside the 2026 CKA scope; the exam tests the judgment that the annotation does not translate, not the CRD-specific substitute.

## Part 8: Rollback strategy

A partial migration rollback: delete the Gateway API resources and ensure the original Ingress is still serving. Because both run in parallel, rollback is simply "stop sending traffic to the Gateway API endpoint and delete the HTTPRoute + Gateway."

```bash
kubectl delete httproute -n tutorial-mig new-way-route
kubectl delete gateway -n tutorial-mig new-way-gw

curl -s -H "Host: parity.example.test" http://localhost/
# Expected: unchanged-content (Traefik/Ingress still serves)
```

The Ingress was never modified; it continues serving. This is the key operational advantage of the "run in parallel first" pattern.

## Cleanup

```bash
kubectl delete namespace tutorial-mig
rm -f /tmp/simple-ingress.yaml /tmp/rewrite-ingress.yaml /tmp/tls-ingress.yaml /tmp/rate-limit-ingress.yaml
```

## Reference Commands

| Task | Command |
|---|---|
| Install ingress2gateway | Download from `github.com/kubernetes-sigs/ingress2gateway/releases/tag/v1.0.0`, `install /usr/local/bin/` |
| Verify version | `ingress2gateway --version` |
| Translate from a file | `ingress2gateway print --input-file=<ingress.yaml> --providers=<list>` |
| Translate from live cluster | `ingress2gateway print --providers=<list>` (reads from current kubeconfig) |
| Supported providers | `ingress-nginx`, `istio`, `kong`, `gce` as of v1.0.0 |
| Preview HTTPS routes that would generate | Look at `listeners[]` in the output |

## Key Takeaways

Migration is a three-step workflow: generate with `ingress2gateway print`, review and adjust manually, apply side by side before cutting over. The CLI handles standard fields (host, path, pathType, backend, tls) mechanically. Controller-specific annotations either translate to Gateway API filters (rewrite-target -> URLRewrite; ssl-redirect -> separate RequestRedirect HTTPRoute) or are dropped with a warning (rate-limit, ModSecurity, custom config snippets). Side-by-side running with two distinct data planes (Traefik Ingress + Envoy Gateway) verifies parity before cutting over. Rollback is trivial because the Ingress was never touched; delete the Gateway API resources and traffic continues through the original path. `Ingress2Gateway` v1.0.0 is the pinned CLI version for this assignment.
