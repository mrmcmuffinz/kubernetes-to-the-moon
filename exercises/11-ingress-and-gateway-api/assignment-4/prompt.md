# Prompt: Advanced Gateway API Routing with NGINX Gateway Fabric (assignment-4)

## Header

- **Series:** Ingress and Gateway API (4 of 5)
- **CKA domain:** Services & Networking (20%)
- **Competencies covered:** Use the Gateway API to manage Ingress traffic (advanced routing patterns); demonstrate that Gateway API is universal across implementations
- **Course sections referenced:** S9 (lectures 238-240, Gateway API)
- **Prerequisites:** `11-ingress-and-gateway-api/assignment-3` (Gateway API fundamentals with Envoy Gateway)

## Scope declaration

### In scope for this assignment

*NGINX Gateway Fabric as the implementation*
- Installing NGINX Gateway Fabric v2.5.1 via Helm (see the tutorial for the exact install command)
- NGINX Gateway Fabric's GatewayClass name (`nginx` by default)
- Running NGINX Gateway Fabric alongside Envoy Gateway (from assignment-3) to reinforce that the same Gateway/HTTPRoute YAML works across implementations

*Advanced HTTPRoute matching*
- Header-based matching (`matches[].headers[]` with `type: Exact` or `RegularExpression`)
- Query parameter matching (`matches[].queryParams[]`)
- Method matching (`matches[].method`)
- Combined match conditions (all matches in one rule must hold)

*Traffic splitting and weighted routing*
- `backendRefs[].weight` for percentage-based splitting
- Canary deployment pattern via weighted backends
- Blue/green pattern via rapid weight flip

*Request and response filters*
- `filters[]` in HTTPRoute rules
- `RequestHeaderModifier` (add, set, remove headers)
- `RequestRedirect` (status code, scheme, hostname, port, path)
- `URLRewrite` (prefix replacement, full replacement)
- `ResponseHeaderModifier` (add, set, remove response headers)

*Observing NGINX Gateway Fabric's translation*
- Viewing the generated NGINX config (inside the controller pod at `/etc/nginx/conf.d/`)
- Understanding how Gateway API HTTPRoutes map to NGINX server and location blocks
- Debugging when the translation does not produce the expected behavior

*Advanced diagnostic workflow*
- HTTPRoute rule ordering semantics (more specific matches take precedence)
- Diagnosing header-match failures (case-insensitivity on header names, case-sensitivity on values)
- Verifying traffic split percentages with repeated requests and response grouping

### Out of scope (covered in other assignments, do not include)

- Gateway API fundamentals (GatewayClass, Gateway, HTTPRoute structure): covered in assignment-3
- Ingress v1 API: covered in assignments 1 and 2
- Migration from Ingress to Gateway API: covered in assignment-5
- TLS termination at the Gateway level: in scope at a basic level, deep TLS work (including SNI across multiple certificates) is out of scope for the 2026 CKA curriculum
- Custom filters beyond the built-in set: out of CKA scope
- NGINX-specific features via `NginxProxy` custom resource: out of scope; the assignment focuses on upstream Gateway API conformance

## Environment requirements

- Multi-node kind cluster with extraPortMappings for 80 and 443
- Gateway API CRDs v1.5.1 installed per `docs/cluster-setup.md#gateway-api-crds` (installed once per cluster; can be shared with assignment-3's Envoy Gateway)
- NGINX Gateway Fabric v2.5.1 installed via Helm; Envoy Gateway from assignment-3 may remain installed for same-cluster comparison exercises

## Resource gate

All CKA resources are in scope. Exercises primarily use GatewayClass, Gateway, HTTPRoute, Service, Deployment, and Pod. Some exercises use multiple backend Deployments to demonstrate weighted routing and canary patterns.

## Topic-specific conventions

- Every traffic-splitting exercise must include a verification script that sends many requests and counts responses by backend, to make the weight distribution empirically observable.
- Header-match exercises must include both the positive case (matching header) and negative case (missing or wrong header) in the same exercise's verification.
- The tutorial must include at least one worked example showing the same HTTPRoute YAML applied under both Envoy Gateway and NGINX Gateway Fabric, with side-by-side verification, to reinforce the implementation-agnostic lesson.
- Debugging exercises should include at least one scenario where a filter is applied in the wrong order or with the wrong type, producing a response that looks correct on first glance but fails a specific verification check.
- Cleanup must uninstall only the assignment's GatewayClass, Gateway, and HTTPRoute resources (not the controller itself, which is shared with assignment-5 if that assignment follows).
- Debugging exercise objectives must describe the symptom without naming the bug type or count. "A traffic split is not distributing traffic as expected" is acceptable; "Traffic split with mismatched weights" is not.
- Build exercises must require the learner to write the resource YAML. Pre-applying the configuration in the setup block and asking the learner to verify is not a build task and violates the homework gate.
- Exercise objectives must not state expected values the learner is meant to discover. Quoting a specific controllerName, service name, or configuration value in the objective gives away the answer before the learner runs any commands.

## Cross-references

**Prerequisites (must be completed first):**
- `exercises/11-11-ingress-and-gateway-api/assignment-3`: Gateway API fundamentals with Envoy Gateway

**Adjacent topics:**
- `exercises/11-11-ingress-and-gateway-api/assignment-5`: migration from Ingress to Gateway API

**Forward references:**
- `exercises/19-19-troubleshooting/assignment-4`: network troubleshooting including Gateway API failure scenarios

---

## Fix required: NGF v2.5.1 data-plane service discovery

All four content files were generated assuming NGF v1.x behavior, where a single shared
NGINX pod served all Gateways and its Service lived in the `nginx-gateway` namespace.
NGF v2.x uses a provisioner model. This section documents what to fix and how.

### Root cause

When a Gateway resource is created with `gatewayClassName: nginx`, NGF v2.x provisions a
dedicated NGINX Deployment and Service in the same namespace as the Gateway. The Service is
named `<gateway-name>-nginx` and is type `LoadBalancer` with a NodePort auto-assigned.
EXTERNAL-IP is pending (no LB controller in this kind cluster), but the NodePort works.

Confirmed behavior on the actual cluster:
```
# After creating a Gateway named "gw" in namespace "ex-1-1":
NAMESPACE   NAME        TYPE           CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
ex-1-1      gw-nginx    LoadBalancer   10.96.1.166   <pending>     80:32316/TCP   10s
```

The only service in `nginx-gateway` namespace is the NGF controller's gRPC agent service
(`ngf-nginx-gateway-fabric`, port 443 only). It is NOT the HTTP data plane. Port-forwarding
to it on port 80 connects to nothing.

Naming rule: a Gateway named `gw` produces a Service named `gw-nginx`. A Gateway named
`gw-nginx` produces a Service named `gw-nginx-nginx`.

NGF v2.x data-plane Services use `externalTrafficPolicy: Local`, the same as Envoy Gateway.
Traffic must target the specific node running the NGF data-plane pod. The NGF data-plane pod
carries the label `gateway.networking.k8s.io/gateway-name=<gateway-name>`, which is the
correct selector to find its node.

### Do NOT change (Envoy Gateway patterns are correct)

```bash
# Envoy Gateway -- must target specific node due to externalTrafficPolicy: Local
NODE=$(kubectl get pods -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-namespace=<ns> \
  -o jsonpath='{.items[0].spec.nodeName}')
NODEIP=$(kubectl get node $NODE \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NODEPORT=$(kubectl get svc -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-namespace=<ns> \
  -o jsonpath='{.items[0].spec.ports[0].nodePort}')
```

### Replacement pattern for NGF

Replace the broken pattern:
```bash
SVC=$(kubectl get svc -n nginx-gateway -l app.kubernetes.io/instance=ngf -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n nginx-gateway "svc/$SVC" <host-port>:80 &
sleep 2
curl ... http://localhost:<host-port>/...
pkill -f "port-forward.*$SVC" 2>/dev/null
```

With:
```bash
NGF_NODE=$(kubectl get pods -n <exercise-namespace> \
  -l gateway.networking.k8s.io/gateway-name=<gateway-name> \
  -o jsonpath='{.items[0].spec.nodeName}')
NGINX_IP=$(kubectl get node "$NGF_NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NGINX_PORT=$(kubectl get svc -n <exercise-namespace> <gateway-name>-nginx \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
curl ... "http://$NGINX_IP:$NGINX_PORT/..."
```

### Per-exercise namespace and service name

| Exercise    | Namespace       | NGF Gateway name | NGF Service name |
|-------------|-----------------|------------------|------------------|
| Tutorial    | tutorial-gw-adv | gw-nginx         | gw-nginx-nginx   |
| Ex 1.1      | ex-1-1          | gw               | gw-nginx         |
| Ex 1.2      | ex-1-2          | gw               | gw-nginx         |
| Ex 1.3      | ex-1-3          | gw-nginx         | gw-nginx-nginx   |
| Ex 2.1      | ex-2-1          | gw               | gw-nginx         |
| Ex 2.2      | ex-2-1          | gw               | gw-nginx         |
| Ex 2.3      | ex-2-3          | gw               | gw-nginx         |
| Ex 3.1      | ex-3-1          | gw               | gw-nginx         |
| Ex 3.2      | ex-3-2          | gw               | gw-nginx         |
| Ex 3.3      | ex-3-3          | gw               | gw-nginx         |
| Ex 4.1      | ex-4-1          | gw               | gw-nginx         |
| Ex 4.2      | ex-4-2          | gw               | gw-nginx         |
| Ex 4.3      | ex-4-3          | gw               | gw-nginx         |
| Ex 5.1      | ex-5-1          | gw               | gw-nginx         |
| Ex 5.2      | ex-5-2          | gw               | gw-nginx         |
| Ex 5.3      | ex-5-3          | gw               | gw-nginx         |

### Changes per file

**ingress-and-gateway-api-tutorial.md**

- Install command (Part 1): Remove `--set service.type=ClusterIP`. In v2.x that flag
  only affects the controller's gRPC service (irrelevant). Per-Gateway data-plane services
  default to LoadBalancer+NodePort, which is what we want.
- Part 2 prose: Fix "Each has its own data-plane Service in the respective controller's
  namespace." NGF v2.x puts the data-plane Service in the Gateway's own namespace, not in
  `nginx-gateway`.
- Part 2 verification block: Replace port-forward block for NGINX with NodePort discovery
  against `gw-nginx-nginx` in `tutorial-gw-adv`. Keep Envoy Gateway's port-forward (or
  switch it to the per-node NodePort form). Assign `NGINX_PORT` alongside `ENVOY_IP` and
  `ENVOY_PORT`.
- Parts 3-8: Remove all `NGINX_SVC` assignments and `pkill` lines. Replace
  `http://localhost:<port>/` with `http://$NODEIP:$NGINX_PORT/`. The `NGINX_PORT`
  variable from Part 2 carries through (same namespace, same service for the whole
  tutorial).
- Reference Commands table: Replace the port-forward row with a NodePort discovery row.

**ingress-and-gateway-api-homework.md**

- All verification blocks except Ex 1.2: replace the `SVC`/port-forward/`pkill` pattern
  with the NodePort pattern using the table above.
- Ex 1.3 special case: both Envoy Gateway and NGF require per-node IP discovery
  (`externalTrafficPolicy: Local`). Use `gateway.envoyproxy.io/owning-gateway-namespace=ex-1-3`
  for Envoy and `gateway.networking.k8s.io/gateway-name=gw-nginx` for NGF against `gw-nginx-nginx`
  in `ex-1-3`.
- Exercises 2.2 and 2.3 are build tasks; the learner must write the HTTPRoute YAML.
  Each verification block includes its own per-node discovery for self-contained clarity.

**ingress-and-gateway-api-homework-answers.md**

- Ex 3.1 Diagnosis: replace `http://localhost:9041/old/items` with NodePort curl against
  `gw-nginx` in `ex-3-1`.
- Ex 3.2 Diagnosis: replace both `http://localhost:9042/` occurrences with NodePort curl
  against `gw-nginx` in `ex-3-2`.
- Ex 5.2 Diagnosis: replace `http://localhost:9052/old-api/data` with NodePort curl
  against `gw-nginx` in `ex-5-2`.
- Verification Commands Cheat Sheet: replace the wrong "NGF data-plane Service" row
  (which points to `nginx-gateway` namespace) with two rows: one for per-Gateway service
  discovery and one for NodePort extraction.

**README.md**

- Fix broken path prefix `11-11-` in two places: Prerequisites section and Scope
  Boundary section. Correct path is `exercises/11-ingress-and-gateway-api/assignment-3`.
- The tutorial also has the same broken path prefix in its Prerequisites section.

### Constraints for the fix session

- Write each file in its entirety (full replacement). That is the repo convention.
- No em dashes. Use commas, periods, or parentheses.
- Do not add inline comments explaining what changed.
- Preserve all existing prose, structure, exercises, setup blocks, and task blocks exactly.
  Only verification blocks and the specific prose passages listed above change.
- Use per-node IP discovery via the `gateway.networking.k8s.io/gateway-name` label selector
  for all NGF verification examples. Do not use a static NODEIP placeholder.
- Container images keep explicit version tags (for example, `nginx:1.27`).
- Read each file before editing it.
