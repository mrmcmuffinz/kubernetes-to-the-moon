# Ingress API Fundamentals Homework Answers

Complete solutions. Level 3 and Level 5 debugging answers use the three-stage structure.

---

## Exercise 1.1 Solution

command: `k create ingress hello-ingress -n ex-1-1 $do --rule="hello.example.test/*=hello:80" --class=traefik`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-ingress
  namespace: ex-1-1
spec:
  ingressClassName: traefik
  rules:
  - host: hello.example.test
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: hello
            port:
              number: 80
```

`ingressClassName: traefik` sends this Ingress to the Traefik controller from the tutorial. `pathType: Prefix` with `path: /` matches every request on this host. `backend.service.name: hello` and `backend.service.port.number: 80` route to the Service and its port.

---

## Exercise 1.2 Solution

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: paths-ingress
  namespace: ex-1-2
spec:
  ingressClassName: traefik
  rules:
  - host: paths.example.test
    http:
      paths:
      - {path: /a, pathType: Prefix, backend: {service: {name: a, port: {number: 80}}}}
      - {path: /b, pathType: Prefix, backend: {service: {name: b, port: {number: 80}}}}
```

Two paths on the same host, each pointing to its own Service. `Prefix` matching respects path-segment boundaries, so `/a/anything` matches `/a` but `/apple` does not.

---

## Exercise 1.3 Solution

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: catchall
  namespace: ex-1-3
spec:
  ingressClassName: traefik
  defaultBackend:
    service: {name: fallback, port: {number: 80}}
```

No `rules` means no specific routing. `defaultBackend` receives every request. Since there is only one Ingress in this namespace and it has only `defaultBackend`, any Host header that reaches Traefik and does not match other Ingresses in the cluster lands here.

---

## Exercise 2.1 Solution

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: exact-ingress
  namespace: ex-2-1
spec:
  ingressClassName: traefik
  rules:
  - host: exact.example.test
    http:
      paths:
      - path: /api
        pathType: Exact
        backend: {service: {name: api, port: {number: 80}}}
```

`Exact` matches the path character-for-character. `/api` matches only `/api` (no trailing slash, no subpath). `/api/` and `/api/extra` do not match.

---

## Exercise 2.2 Solution

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: multi
  namespace: ex-2-2
spec:
  ingressClassName: traefik
  rules:
  - host: foo.example.test
    http:
      paths:
      - {path: /, pathType: Prefix, backend: {service: {name: foo, port: {number: 80}}}}
  - host: bar.example.test
    http:
      paths:
      - {path: /, pathType: Prefix, backend: {service: {name: bar, port: {number: 80}}}}
  - host: shared.example.test
    http:
      paths:
      - {path: /foo, pathType: Prefix, backend: {service: {name: foo, port: {number: 80}}}}
      - {path: /bar, pathType: Prefix, backend: {service: {name: bar, port: {number: 80}}}}
```

Three rules (three `host` entries), the third with two paths. The `host` field scopes the rule to a specific Host header.

---

## Exercise 2.3 Solution

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-route
  namespace: ex-2-3
  annotations:
    traefik.ingress.kubernetes.io/router.priority: "10"
spec:
  ingressClassName: traefik
  rules:
  - host: app.example.test
    http:
      paths:
      - {path: /, pathType: Prefix, backend: {service: {name: app, port: {number: 80}}}}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: with-fallback
  namespace: ex-2-3
  annotations:
    traefik.ingress.kubernetes.io/router.priority: "1"
spec:
  ingressClassName: traefik
  defaultBackend:
    service: {name: default, port: {number: 80}}
```

Two Ingresses in the same namespace. `app-route` handles `app.example.test` with explicit priority 10. `with-fallback` has no rules, only a `defaultBackend`, with priority 1. Traefik's Kubernetes Ingress provider treats a no-rules Ingress as a cluster-wide catch-all router; the lower priority ensures it never wins over any Ingress that has an explicit rule. Requests to unknown hosts fall to `with-fallback`. Note: Traefik v3 does not support `defaultBackend` combined with `rules` in a single Ingress -- the split-Ingress pattern with explicit priority is the Traefik-idiomatic equivalent.

---

## Exercise 3.1 Solution

**Diagnosis.**

```bash
kubectl describe ingress -n ex-3-1 stuck
kubectl get ingressclass
```

Describe shows no loadBalancer.ingress, no events. `kubectl get ingressclass` shows `traefik`, not `nginx`. The Ingress's `ingressClassName: nginx` names a non-existent class.

**What the bug is and why.** The Ingress references `ingressClassName: nginx`. No controller in this cluster watches the `nginx` class (only `traefik` does). Traefik ignores the Ingress because its class does not match. No controller assigns an ADDRESS; traffic returns 404.

**Fix.**

```bash
kubectl patch ingress -n ex-3-1 stuck -p '{"spec":{"ingressClassName":"traefik"}}'
```

Traefik immediately picks up the Ingress. ADDRESS populates within a few seconds. Traffic routes correctly.

---

## Exercise 3.2 Solution

**Diagnosis.**

```bash
kubectl describe ingress -n ex-3-2 ifu | grep Backends
kubectl get svc -n ex-3-2
```

The Ingress names Service `frontend`. Only `frontend-svc` exists; no Service named `frontend`. Traefik's 404 comes from routing to a non-existent Service.

**What the bug is and why.** The Ingress's `backend.service.name` points at a Service that does not exist. Kubernetes does not validate Service existence at Ingress creation time; the controller sees no endpoints and returns 404 at request time.

**Fix.**

```bash
kubectl patch ingress -n ex-3-2 ifu --type='json' \
  -p='[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/name","value":"frontend-svc"}]'
```

---

## Exercise 3.3 Solution

**Diagnosis.**

```bash
curl -sI -H "Host: api.example.test" http://localhost/api/v1
# Returns 404

curl -sI -H "Host: api.example.test" http://localhost/api
# Also 404 (application serves at /api/v1, not /api)
```

The Ingress's `path: /api, pathType: Exact` matches only the literal `/api`. But the nginx backend only responds at `/api/v1`. So even when the Ingress matches, the backend 404s. And `/api/v1` does not match `Exact /api` in the Ingress.

**What the bug is and why.** `Exact` matching requires the request path to exactly equal the Ingress path. `/api/v1` does not equal `/api`. The fix is to change to `pathType: Prefix` (so `/api` matches `/api/v1` too) and keep the nginx config serving at `/api/v1`.

**Fix.**

```bash
kubectl patch ingress -n ex-3-3 path-bad --type='json' \
  -p='[{"op":"replace","path":"/spec/rules/0/http/paths/0/pathType","value":"Prefix"}]'
```

---

## Exercise 4.1 Solution

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: four-one-routes
  namespace: ex-4-1
  annotations:
    traefik.ingress.kubernetes.io/router.priority: "10"
spec:
  ingressClassName: traefik
  rules:
  - host: app.example.test
    http:
      paths:
      - {path: /x, pathType: Prefix, backend: {service: {name: svc-x, port: {number: 80}}}}
      - {path: /y, pathType: Prefix, backend: {service: {name: svc-y, port: {number: 80}}}}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: four-one-fallback
  namespace: ex-4-1
  annotations:
    traefik.ingress.kubernetes.io/router.priority: "1"
spec:
  ingressClassName: traefik
  defaultBackend:
    service: {name: svc-default, port: {number: 80}}
```

`four-one-routes` handles the two specific paths on `app.example.test` at high priority. `four-one-fallback` has no rules, making it a cluster-wide catch-all at priority 1 -- it handles any path on any host that no other router claims, including `/z` on `app.example.test`.

---

## Exercise 4.2 Solution

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: traefik-version
  namespace: ex-4-2
spec:
  ingressClassName: traefik
  rules:
  - host: two-classes.example.test
    http:
      paths:
      - {path: /, pathType: Prefix, backend: {service: {name: present, port: {number: 80}}}}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: future-version
  namespace: ex-4-2
spec:
  ingressClassName: future-controller
  rules:
  - host: two-classes.example.test
    http:
      paths:
      - {path: /, pathType: Prefix, backend: {service: {name: present, port: {number: 80}}}}
```

Only `traefik-version` serves traffic. `future-version` sits with no ADDRESS because the `future-controller` IngressClass has no controller watching it. The key lesson: multiple IngressClasses can coexist in a cluster; each owns its own Ingresses.

---

## Exercise 4.3 Solution

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: versioned
  namespace: ex-4-3
spec:
  ingressClassName: traefik
  rules:
  - host: versioned.example.test
    http:
      paths:
      - {path: /api/v1, pathType: Prefix, backend: {service: {name: api-v1, port: {number: 80}}}}
      - {path: /api/v2, pathType: Prefix, backend: {service: {name: api-v2, port: {number: 80}}}}
```

Two paths on one host. Prefix matching means `/api/v1/x` routes to `api-v1` and `/api/v2/y` routes to `api-v2`. `/api/v3` 404s because no rule matches.

---

## Exercise 5.1 Solution

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: webapp
  namespace: ex-5-1
spec:
  ingressClassName: traefik
  rules:
  - host: www.webapp.example.test
    http:
      paths:
      - {path: /static, pathType: Prefix, backend: {service: {name: static, port: {number: 80}}}}
      - {path: /, pathType: Prefix, backend: {service: {name: marketing, port: {number: 80}}}}
  - host: api.webapp.example.test
    http:
      paths:
      - {path: /, pathType: Prefix, backend: {service: {name: api, port: {number: 80}}}}
  - host: admin.webapp.example.test
    http:
      paths:
      - {path: /, pathType: Prefix, backend: {service: {name: admin, port: {number: 80}}}}
  - host: health.webapp.example.test
    http:
      paths:
      - {path: /healthz, pathType: Exact, backend: {service: {name: health, port: {number: 80}}}}
```

On `www.webapp.example.test`, `/static` is listed before `/` so the more-specific Prefix wins for paths starting with `/static`. Traefik sorts paths by specificity; listing the more-specific path first is good practice for clarity.

---

## Exercise 5.2 Solution

**Diagnosis.**

```bash
kubectl get ingress -n ex-5-2 broken
kubectl get ingressclass
kubectl get svc -n ex-5-2
```

Three facts surface:

- Ingress has no ADDRESS. Its `ingressClassName: nginx` has no matching controller; only `traefik` exists.
- Even with the class fixed, `backend.service.name: fake-svc` points at a non-existent Service.
- Even with both fixed, `pathType: Exact` on `/v1/status` will match `/v1/status` but the application also needs `Prefix` if any subpaths are ever added (for this exercise, `Exact` on `/v1/status` matches because the nginx config explicitly serves at that path).

Actually the third issue: the nginx backend ConfigMap defines the location at `/v1/status`, which matches `Exact /v1/status`. So `Exact` works here. The real issues are the first two.

**What the bug is and why.**

- The IngressClass is wrong. No controller watches `nginx` in this cluster.
- The Service name is wrong. `fake-svc` does not exist.

**Fix.**

```bash
kubectl patch ingress -n ex-5-2 broken --type='json' -p='[
  {"op":"replace","path":"/spec/ingressClassName","value":"traefik"},
  {"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/name","value":"real-svc"}
]'
```

Within seconds, the ADDRESS populates and requests route through.

---

## Exercise 5.3 Solution

Three separate Ingress resources, each owned by a hypothetical team:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: {name: api-ingress, namespace: ex-5-3}
spec:
  ingressClassName: traefik
  rules:
  - host: company.example.test
    http:
      paths:
      - {path: /api, pathType: Prefix, backend: {service: {name: api, port: {number: 80}}}}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: {name: ui-ingress, namespace: ex-5-3}
spec:
  ingressClassName: traefik
  rules:
  - host: company.example.test
    http:
      paths:
      - {path: /, pathType: Prefix, backend: {service: {name: ui, port: {number: 80}}}}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: {name: health-ingress, namespace: ex-5-3}
spec:
  ingressClassName: traefik
  rules:
  - host: company.example.test
    http:
      paths:
      - {path: /healthz, pathType: Exact, backend: {service: {name: health, port: {number: 80}}}}
```

Multiple Ingresses on the same host are merged by the controller; the more-specific path (`/healthz`, `/api`) wins over the general `/`. This is the pattern used in production to decouple per-team Ingress ownership: the API team owns `api-ingress`, the UI team owns `ui-ingress`, and SRE owns `health-ingress`.

---

## Common Mistakes

**1. Forgetting `ingressClassName`.** Omitting the field relies on the cluster's default IngressClass (if any), which changes across environments. In production always set `ingressClassName` explicitly.

**2. Typing the wrong class name.** `nginx` vs `traefik` vs `haproxy` are all common typos. The Ingress sits with empty ADDRESS and no events.

**3. Assuming `pathType: Prefix` is a simple string prefix.** `Prefix /app` matches `/app`, `/app/`, `/app/anything` but not `/application`. Path-segment boundaries matter.

**4. Using `pathType: Exact` for a backend that serves multiple paths.** Exact matches only the literal path. Clients requesting any child path 404. Use Prefix unless truly a single endpoint.

**5. Pointing at a non-existent Service.** Kubernetes does not validate that the `backend.service.name` exists at Ingress creation. The first symptom is a 404 or 503 at request time; describe the Ingress and check endpoints.

**6. Pointing at a Service that exists but has no endpoints.** If the backend Deployment is unhealthy, the Service has no endpoints, and the Ingress returns 503. Always check `kubectl get endpoints` during debugging.

**7. Putting Ingress on the wrong node in a kind cluster.** kind's `extraPortMappings` only apply to one specific node. Traefik must be scheduled on that node (via `nodeSelector: ingress-ready=true` in the Helm install) for traffic on `localhost:80` to reach it.

**8. Testing an Ingress with a browser expecting DNS resolution.** DNS for custom hosts (`app.example.test`) is not configured by default. Use `curl -H "Host: <hostname>"` or add hosts to `/etc/hosts`.

---

## Verification Commands Cheat Sheet

| Check | Command |
|---|---|
| Ingress ADDRESS (controller accepted) | `kubectl get ingress -n <ns> <name>` |
| Ingress rules and backends | `kubectl describe ingress -n <ns> <name>` |
| IngressClasses available | `kubectl get ingressclass` |
| Default IngressClass | `kubectl get ingressclass -o jsonpath='{range .items[?(@.metadata.annotations.ingressclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}'` |
| Backend Service endpoints | `kubectl get endpoints -n <ns> <service>` |
| Test host-based routing | `curl -H "Host: <host>" http://localhost/<path>` |
| Traefik controller logs | `kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=50` |
| Change IngressClass via patch | `kubectl patch ingress <name> -p '{"spec":{"ingressClassName":"<class>"}}'` |
