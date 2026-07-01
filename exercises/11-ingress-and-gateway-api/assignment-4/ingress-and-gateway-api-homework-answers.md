# Advanced Gateway API Routing Homework Answers

Complete solutions. Level 3 and Level 5 debugging answers use the three-stage structure.

---

## Exercise 1.1 Solution

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: hi-route, namespace: ex-1-1}
spec:
  parentRefs: [{name: gw}]
  hostnames: ["hi.example.test"]
  rules:
  - matches: [{path: {type: PathPrefix, value: /}}]
    backendRefs: [{name: hi, port: 80}]
```

Attached to the NGF Gateway via `parentRefs`. Same shape as Envoy Gateway HTTPRoutes in assignment 3; the implementation-agnostic spec pays off.

---

## Exercise 1.2 Solution

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw, namespace: ex-1-2}
spec:
  gatewayClassName: nginx
  listeners: [{name: http, protocol: HTTP, port: 80, allowedRoutes: {namespaces: {from: Same}}}]
```

When NGF processes this Gateway, it provisions a dedicated data-plane Deployment and a Service named `gw-nginx` in `ex-1-2`, following the `<gateway-name>-nginx` naming rule. The Service is type `LoadBalancer` with a NodePort assigned; `EXTERNAL-IP` stays pending on clusters without a LoadBalancer controller. The Gateway reaches `Programmed: True` once the data-plane pod is running and healthy.

---

## Exercise 1.3 Solution

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: r-envoy, namespace: ex-1-3}
spec:
  parentRefs: [{name: gw-envoy}]
  hostnames: ["same.example.test"]
  rules:
  - backendRefs: [{name: same, port: 80}]
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: r-nginx, namespace: ex-1-3}
spec:
  parentRefs: [{name: gw-nginx}]
  hostnames: ["same.example.test"]
  rules:
  - backendRefs: [{name: same, port: 80}]
```

Both HTTPRoutes identical except for `parentRefs`. Both return `parity`. The Gateway API is truly implementation-agnostic.

---

## Exercise 2.1 Solution

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: tenant-routing, namespace: ex-2-1}
spec:
  parentRefs: [{name: gw}]
  hostnames: ["tenant.example.test"]
  rules:
  - matches: [{headers: [{name: X-Tenant, value: red}]}]
    backendRefs: [{name: red-app, port: 80}]
  - matches: [{headers: [{name: X-Tenant, value: blue}]}]
    backendRefs: [{name: blue-app, port: 80}]
```

Each rule scopes to a specific header value. A request with no `X-Tenant` header matches no rule and returns 404.

---

## Exercise 2.2 Solution

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: query-routing, namespace: ex-2-1}
spec:
  parentRefs: [{name: gw}]
  hostnames: ["query.example.test"]
  rules:
  - matches: [{queryParams: [{name: env, value: prod}]}]
    backendRefs: [{name: red-app, port: 80}]
  - matches: [{queryParams: [{name: env, value: staging}]}]
    backendRefs: [{name: blue-app, port: 80}]
```

`queryParams` matches follow the same pattern as `headers`: `name` and `value`, defaulting to `type: Exact`.

---

## Exercise 2.3 Solution

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: combined, namespace: ex-2-3}
spec:
  parentRefs: [{name: gw}]
  hostnames: ["combined.example.test"]
  rules:
  - matches:
    - path: {type: PathPrefix, value: /api}
      method: POST
      headers: [{name: X-API-Key, value: admin}]
    backendRefs: [{name: echo-app, port: 80}]
```

All conditions inside one `matches[*]` object AND together. If any fails, the rule does not match. Exercise 2.3 uses its own namespace (`ex-2-3`) rather than sharing with 2.1 and 2.2. NGF v2.x indexes internal proxy routes per-namespace; adding a new backend to a namespace that already has others causes route index conflicts that prevent the new backend from being reached correctly.

---

## Exercise 3.1 Solution

**Diagnosis.**

```bash
kubectl get httproute -n ex-3-1 order-bug -o yaml | grep -A 20 "filters"
NGF_NODE=$(kubectl get pods -n ex-3-1 \
  -l gateway.networking.k8s.io/gateway-name=gw \
  -o jsonpath='{.items[0].spec.nodeName}')
NGINX_IP=$(kubectl get node "$NGF_NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NGINX_PORT=$(kubectl get svc -n ex-3-1 gw-nginx \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
curl -s -H "Host: order.example.test" "http://$NGINX_IP:$NGINX_PORT/old/items"
```

The HTTPRoute has both `URLRewrite` and `RequestRedirect` in its filters array. `RequestRedirect` is terminal; when applied, the response is a 3xx and control does not proceed to the backend. With both present in that order, the rewrite computes the new path and then the redirect returns a 3xx based on the rewritten path. The backend never sees the request.

**What the bug is and why.** `RequestRedirect` ends the request processing with a response to the client. Any filter (or backend) after it is meaningless. The intent in this exercise was to rewrite and then forward; the redirect defeats that.

**Fix.** Remove the RequestRedirect filter.

```bash
kubectl patch httproute -n ex-3-1 order-bug --type='json' \
  -p='[{"op":"remove","path":"/spec/rules/0/filters/1"}]'
```

Now only URLRewrite remains; the backend sees `/new/items`.

---

## Exercise 3.2 Solution

**Diagnosis.**

```bash
NGF_NODE=$(kubectl get pods -n ex-3-2 \
  -l gateway.networking.k8s.io/gateway-name=gw \
  -o jsonpath='{.items[0].spec.nodeName}')
NGINX_IP=$(kubectl get node "$NGF_NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NGINX_PORT=$(kubectl get svc -n ex-3-2 gw-nginx \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
curl -v -H "Host: case.example.test" -H "X-Env: production" "http://$NGINX_IP:$NGINX_PORT/"
# 404
curl -v -H "Host: case.example.test" -H "X-Env: Production" "http://$NGINX_IP:$NGINX_PORT/"
# 200 case-app
```

The HTTPRoute rule requires `X-Env: Production`. The client sends `X-Env: production` (lowercase). Header VALUE matching is case-sensitive by default.

**What the bug is and why.** Gateway API's default header match type is `Exact`, which is case-sensitive for values. The client and controller disagree on the expected casing.

**Fix.** Align the rule with what clients send.

```bash
kubectl patch httproute -n ex-3-2 case-sensitive --type='json' \
  -p='[{"op":"replace","path":"/spec/rules/0/matches/0/headers/0/value","value":"production"}]'
```

---

## Exercise 3.3 Solution

**Diagnosis.**

```bash
kubectl get httproute -n ex-3-3 bad-split -o yaml | grep -A 10 "backendRefs"
```

Weights are `v1-svc: 0, v2-svc: 100`. All traffic goes to v2.

**What the bug is and why.** `weight: 0` explicitly excludes that backend from the distribution. The weights sum to 100, so 100% goes to v2.

**Fix.** Set the weights to 70 and 30.

```bash
kubectl patch httproute -n ex-3-3 bad-split --type='json' -p='[
  {"op":"replace","path":"/spec/rules/0/backendRefs/0/weight","value":70},
  {"op":"replace","path":"/spec/rules/0/backendRefs/1/weight","value":30}
]'
```

---

## Exercise 4.1 Solution

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: add-hdr, namespace: ex-4-1}
spec:
  parentRefs: [{name: gw}]
  hostnames: ["header.example.test"]
  rules:
  - filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        add:
        - {name: X-Source, value: gateway-filter}
    backendRefs: [{name: echo, port: 80}]
```

The filter injects the header before the request reaches the backend. The echo backend reports `x-source=gateway-filter`. If the client sent its own `X-Source`, the `add` operation appends (does not replace); use `set` for replacement semantics.

---

## Exercise 4.2 Solution

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: to-https, namespace: ex-4-2}
spec:
  parentRefs: [{name: gw}]
  hostnames: ["insecure.example.test"]
  rules:
  - filters:
    - type: RequestRedirect
      requestRedirect:
        scheme: https
        hostname: secure.example.test
        statusCode: 301
    backendRefs: [{name: dummy, port: 80}]
```

`backendRefs` is required by the schema even though the redirect means the backend is never consulted. Without it, the API rejects the HTTPRoute.

---

## Exercise 4.3 Solution

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: rewrite-all, namespace: ex-4-3}
spec:
  parentRefs: [{name: gw}]
  hostnames: ["rw.example.test"]
  rules:
  - filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplaceFullPath
          replaceFullPath: /fixed
    backendRefs: [{name: echo, port: 80}]
```

`ReplaceFullPath` replaces the entire path unconditionally. Every request to this hostname reaches the backend as `/fixed`.

---

## Exercise 5.1 Solution

Initial HTTPRoute:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: canary, namespace: ex-5-1}
spec:
  parentRefs: [{name: gw}]
  hostnames: ["canary.example.test"]
  rules:
  - backendRefs:
    - {name: v1-app, port: 80, weight: 90}
    - {name: v2-app, port: 80, weight: 10}
```

Shift to 50/50 via patch:

```bash
kubectl patch httproute -n ex-5-1 canary --type='json' -p='[
  {"op":"replace","path":"/spec/rules/0/backendRefs/0/weight","value":50},
  {"op":"replace","path":"/spec/rules/0/backendRefs/1/weight","value":50}
]'
```

Envoy Gateway and NGINX Gateway Fabric both propagate weight changes to the data plane within seconds. A canary deployment traditionally uses this pattern: start at 1%, increase to 5%, 10%, 50%, and eventually shift all traffic.

---

## Exercise 5.2 Solution

**Diagnosis.**

```bash
NGF_NODE=$(kubectl get pods -n ex-5-2 \
  -l gateway.networking.k8s.io/gateway-name=gw \
  -o jsonpath='{.items[0].spec.nodeName}')
NGINX_IP=$(kubectl get node "$NGF_NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NGINX_PORT=$(kubectl get svc -n ex-5-2 gw-nginx \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
curl -sI -H "Host: order.example.test" "http://$NGINX_IP:$NGINX_PORT/old-api/data"
# HTTP/1.1 302 Found
# Location: /new-api/data
```

The request receives a 302 redirect instead of the expected 200 response. The HTTPRoute filters list `RequestRedirect` before `URLRewrite`; the redirect is terminal so the rewrite never runs and the backend is never reached. The intent was to forward after rewriting.

**What the bug is and why.** `RequestRedirect` is a terminal filter. When it runs, the client gets a 3xx response immediately; nothing after it executes, including other filters and `backendRefs`.

**Fix.** Remove the RequestRedirect.

```bash
kubectl patch httproute -n ex-5-2 bad-order --type='json' \
  -p='[{"op":"remove","path":"/spec/rules/0/filters/0"}]'
```

Now only the URLRewrite remains; the backend sees `/v2/data`.

---

## Exercise 5.3 Solution

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: production, namespace: ex-5-3}
spec:
  parentRefs: [{name: gw}]
  hostnames: ["prod.example.test"]
  rules:
  - matches:
    - path: {type: PathPrefix, value: /api}
      headers: [{name: X-Canary, value: "true"}]
    filters:
    - type: URLRewrite
      urlRewrite:
        path: {type: ReplacePrefixMatch, replacePrefixMatch: /v2}
    backendRefs: [{name: canary, port: 80}]
  - matches: [{path: {type: PathPrefix, value: /api}}]
    backendRefs: [{name: stable, port: 80}]
```

The first rule is more specific (requires both path and header); it wins for canary requests. The second rule catches the rest on `/api`. Rule ordering in the spec reflects "more-specific first" logic; controllers are required to pick the most specific match.

---

## Common Mistakes

**1. Placing a terminal filter (RequestRedirect) before a non-terminal one (URLRewrite).** The non-terminal filter never runs. The client gets a redirect; the backend never sees the request.

**2. Case-sensitive header values.** `X-Env: Production` and `X-Env: production` do not match with default `type: Exact`. Use `RegularExpression` if you need case-insensitive matching.

**3. `weight: 0` on a backendRef.** That backend gets 0% of traffic. If all backends except one are zero, traffic is effectively deterministic.

**4. Expecting `rules[]` to short-circuit after one match.** Gateway API rules use specificity-based selection. Multiple rules can be candidates for the same request; the most specific wins. Adding another rule below does not automatically "fall through"; it depends on match specificity.

**5. Using `ReplaceFullPath` when `ReplacePrefixMatch` was intended.** `ReplaceFullPath` overwrites the whole path; the backend sees only the replacement. `ReplacePrefixMatch` replaces only the matched prefix; the backend sees the replacement plus the un-matched suffix.

**6. Forgetting `backendRefs` on a RequestRedirect-only rule.** The schema requires `backendRefs` even when the redirect means the backend is never consulted. Use a dummy Service.

**7. Applying a filter on `parentRefs` instead of `rules[]`.** Filters live on `rules[]` (and on `backendRefs[]` for some filter types, which is rarer). Putting them in the wrong place is a schema error.

**8. Assuming request-header filters see headers added by the client.** The `RequestHeaderModifier` filter runs in the Gateway data plane on the forwarded request. The `add` operation combines; the `set` operation replaces.

---

## Verification Commands Cheat Sheet

| Check | Command |
|---|---|
| NGF Gateway programmed | `kubectl get gateway -n <ns> <name> -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}'` |
| HTTPRoute matches debug | `kubectl describe httproute -n <ns> <name>` |
| Find NGF data-plane pod node | `kubectl get pods -n <ns> -l gateway.networking.k8s.io/gateway-name=<gw-name> -o jsonpath='{.items[0].spec.nodeName}'` |
| Get node internal IP | `kubectl get node <node> -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'` |
| NGF data-plane NodePort | `kubectl get svc -n <ns> <gw-name>-nginx -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}'` |
| NGF controller logs | `kubectl logs -n nginx-gateway -l app.kubernetes.io/instance=ngf --tail=50` |
| Request with header | `curl -H "X-Tenant: red" "http://$NGINX_IP:$NGINX_PORT/"` |
| Request with query param | `curl "http://$NGINX_IP:$NGINX_PORT/?env=prod"` |
| Request with explicit method | `curl -X POST "http://$NGINX_IP:$NGINX_PORT/"` |
| Follow redirects off | `curl -sI ...` shows the 3xx response; `-L` follows |
