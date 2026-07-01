# Advanced Ingress and TLS with HAProxy Ingress Tutorial

Assignment 1 covered the Ingress v1 API using Traefik v3.6.13. This tutorial covers the advanced half of Ingress: controller-specific annotations, rewrite-target, and TLS termination, using HAProxy Kubernetes Ingress Controller v3.2.6 as the implementation. Installing HAProxy alongside Traefik reinforces the lesson that the API is universal; the differences you see are in the annotation syntax and in feature-specific extensions.

The CKA exam allows the Gateway API documentation set but has removed NGINX Ingress Controller from the allowed URLs for the 2026 exam. The candidate-reported material focuses on the API itself, not any specific controller. This assignment builds breadth by showing the same Ingress YAML (with `ingressClassName` changed) working under both Traefik and HAProxy Ingress, then diverging only where annotations come into play.

## Prerequisites

The same cluster as assignment 1 (multi-node kind with extraPortMappings for 80 and 443). Leave Traefik installed; this tutorial adds HAProxy Ingress alongside it. See `docs/cluster-setup.md#multi-node-kind-cluster` for the base cluster. Complete `exercises/18-18-tls-and-certificates/assignment-1` for the certificate creation workflow; this tutorial consumes certs without reteaching openssl.

Verify the cluster and Traefik.

```bash
kubectl get nodes
# Expected: 1 control-plane, 3 workers, all Ready

kubectl get pods -n traefik
# Expected: one Running traefik pod
```

Create the tutorial namespace.

```bash
kubectl create namespace tutorial-ingress2
```

## Part 1: Installing HAProxy Ingress v3.2.6

HAProxy Ingress v3.2.6 is distributed via the `haproxytech/kubernetes-ingress` Helm chart (upstream repository `https://haproxytech.github.io/helm-charts`). Chart version `1.49.0` corresponds to app version `3.2.6`. The chart creates an IngressClass named `haproxy` by default.

```bash
helm repo add haproxytech https://haproxytech.github.io/helm-charts
helm repo update

helm install haproxy-ingress haproxytech/kubernetes-ingress \
  --version 1.49.0 \
  --namespace haproxy-ingress --create-namespace \
  --set controller.service.type=ClusterIP
```

Because kind's port 80 and 443 are already bound by Traefik on the control-plane node, run HAProxy Ingress on a worker node with its own NodePort for testing on the internal ClusterIP. For this tutorial, we focus on Ingress API behavior and use `kubectl port-forward` to reach HAProxy from the host for verification.

```bash
kubectl -n haproxy-ingress rollout status deployment/haproxy-ingress --timeout=180s
kubectl get ingressclass
```

Expected output: both `traefik` and `haproxy` rows are visible.

```bash
kubectl get pods -n haproxy-ingress
# Expected: one haproxy-ingress pod Running
```

Set up a port-forward in a separate shell to reach the HAProxy controller on localhost:8080 and :8443.

```bash
# In a separate terminal, leave running:
kubectl port-forward -n haproxy-ingress svc/haproxy-ingress 8080:80 8443:443
```

The convention for the rest of the tutorial is:

- Requests on `localhost:80`/`:443` reach Traefik (assignment 1 setup).
- Requests on `localhost:8080`/`:8443` reach HAProxy Ingress (via port-forward).

## Part 2: Same YAML, different controllers

Deploy a backend.

```bash
kubectl apply -n tutorial-ingress2 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: app}
spec:
  replicas: 2
  selector: {matchLabels: {app: app}}
  template:
    metadata: {labels: {app: app}}
    spec:
      containers:
      - {name: nginx, image: nginx:1.27, volumeMounts: [{name: html, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: html, configMap: {name: app-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: app-html}
data: {index.html: "universal-app\n"}
---
apiVersion: v1
kind: Service
metadata: {name: app}
spec: {selector: {app: app}, ports: [{port: 80, targetPort: 80}]}
EOF

kubectl -n tutorial-ingress2 rollout status deployment/app --timeout=60s
```

Apply the same Ingress twice, once under Traefik and once under HAProxy.

```bash
kubectl apply -n tutorial-ingress2 -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-on-traefik
spec:
  ingressClassName: traefik
  rules:
  - host: universal.example.test
    http:
      paths:
      - {path: /, pathType: Prefix, backend: {service: {name: app, port: {number: 80}}}}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-on-haproxy
spec:
  ingressClassName: haproxy
  rules:
  - host: universal.example.test
    http:
      paths:
      - {path: /, pathType: Prefix, backend: {service: {name: app, port: {number: 80}}}}
EOF

sleep 3
curl -s -H "Host: universal.example.test" http://localhost/
# Expected: universal-app (via Traefik)

curl -s -H "Host: universal.example.test" http://localhost:8080/
# Expected: universal-app (via HAProxy)
```

The same response from two controllers, same YAML except for `ingressClassName`. This is the payoff of the Ingress API's universality.

## Part 3: Annotation namespacing

Each controller watches its own annotation namespace. Traefik uses `traefik.ingress.kubernetes.io/*`; HAProxy Ingress uses `haproxy-ingress.github.io/*`. Applying a Traefik annotation to an HAProxy Ingress is silently ignored by HAProxy (and vice versa).

Apply an Ingress with an HAProxy rate-limit annotation.

```bash
kubectl apply -n tutorial-ingress2 -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rate-limited
  annotations:
    haproxy-ingress.github.io/rate-limit-rpm: "60"
spec:
  ingressClassName: haproxy
  rules:
  - host: limited.example.test
    http:
      paths:
      - {path: /, pathType: Prefix, backend: {service: {name: app, port: {number: 80}}}}
EOF

sleep 3
curl -s -H "Host: limited.example.test" http://localhost:8080/
# Expected: universal-app
```

Check the HAProxy controller config to confirm the rate-limit is active.

```bash
kubectl logs -n haproxy-ingress -l app.kubernetes.io/name=haproxy-ingress --tail=50 | grep rate-limit || true
```

Expected: log lines referencing the rate-limit in the applied HAProxy config.

## Part 4: Rewrite-target

Rewrite-target strips a prefix from the request path before forwarding to the backend. Useful when the Ingress path and the backend path disagree.

```bash
kubectl apply -n tutorial-ingress2 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: rewritten}
spec:
  replicas: 1
  selector: {matchLabels: {app: rewritten}}
  template:
    metadata: {labels: {app: rewritten}}
    spec:
      containers:
      - {name: nginx, image: nginx:1.27, volumeMounts: [{name: c, mountPath: /etc/nginx/conf.d}]}
      volumes: [{name: c, configMap: {name: rewritten-conf}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: rewritten-conf}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        return 200 "received-path: $request_uri\n";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: rewritten}
spec: {selector: {app: rewritten}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rewritten
  annotations:
    haproxy-ingress.github.io/rewrite-target: /
spec:
  ingressClassName: haproxy
  rules:
  - host: rewrite.example.test
    http:
      paths:
      - {path: /prefix, pathType: Prefix, backend: {service: {name: rewritten, port: {number: 80}}}}
EOF

kubectl -n tutorial-ingress2 rollout status deployment/rewritten --timeout=60s
sleep 3

curl -s -H "Host: rewrite.example.test" http://localhost:8080/prefix
# Expected: received-path: /
```

The Ingress matches `/prefix`; the annotation rewrites to `/`; the backend sees a request for `/` and responds with `received-path: /`. Without the annotation, the backend would see `/prefix` instead.

## Part 5: TLS termination

TLS termination is configured via `spec.tls[]` on the Ingress, plus a `kubernetes.io/tls`-typed Secret containing the certificate and key. Generate a self-signed certificate.

```bash
openssl req -x509 -newkey rsa:2048 -nodes -sha256 \
  -subj "/CN=tls.example.test/O=tutorial" \
  -days 30 \
  -addext "subjectAltName = DNS:tls.example.test" \
  -keyout /tmp/tls.key -out /tmp/tls.crt
```

Create the TLS Secret.

```bash
kubectl create secret tls tut-tls \
  -n tutorial-ingress2 \
  --cert=/tmp/tls.crt --key=/tmp/tls.key
```

Create an Ingress with TLS.

```bash
kubectl apply -n tutorial-ingress2 -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: secure
spec:
  ingressClassName: haproxy
  tls:
  - hosts: ["tls.example.test"]
    secretName: tut-tls
  rules:
  - host: tls.example.test
    http:
      paths:
      - {path: /, pathType: Prefix, backend: {service: {name: app, port: {number: 80}}}}
EOF

sleep 3
curl -k -v --resolve tls.example.test:8443:127.0.0.1 https://tls.example.test:8443/ 2>&1 | head -n 20
```

Expected output: includes `TLS handshake, Certificate`, the cert's subject `CN=tls.example.test`, HTTP/2 or HTTP/1.1 200, and the body `universal-app`. The `-k` skips validation (because the cert is self-signed); the `--resolve` maps the hostname to localhost:8443 without DNS.

**Spec field reference for `spec.tls`:**

- **`hosts[]`**
  - **Type:** array of strings.
  - **Valid values:** hostnames that the TLS block covers. Must match the cert's Subject Alternative Names.
  - **Default:** empty list (TLS block applies to any Host if omitted; behavior varies by controller).
  - **Failure mode when misconfigured:** if the Host header does not match any `hosts` entry, the controller may return the default backend via HTTP instead of terminating TLS.

- **`secretName`**
  - **Type:** string (Secret name in the same namespace).
  - **Valid values:** name of a `kubernetes.io/tls`-typed Secret containing `tls.crt` and `tls.key`.
  - **Default:** none.
  - **Failure mode when misconfigured:** missing Secret produces log warnings on the controller; the controller often serves a fake or self-signed fallback certificate, which a strict client rejects.

Verify the TLS handshake used the right certificate.

```bash
curl -sk --resolve tls.example.test:8443:127.0.0.1 \
  https://tls.example.test:8443/ -v 2>&1 | grep -E "subject|issuer" | head
```

Expected output includes `CN=tls.example.test`.

## Part 6: Multi-host TLS

A single Ingress can terminate TLS for multiple hostnames, each with its own Secret.

```bash
openssl req -x509 -newkey rsa:2048 -nodes -sha256 \
  -subj "/CN=alpha.example.test/O=tutorial" -days 30 \
  -addext "subjectAltName = DNS:alpha.example.test" \
  -keyout /tmp/alpha.key -out /tmp/alpha.crt

openssl req -x509 -newkey rsa:2048 -nodes -sha256 \
  -subj "/CN=beta.example.test/O=tutorial" -days 30 \
  -addext "subjectAltName = DNS:beta.example.test" \
  -keyout /tmp/beta.key -out /tmp/beta.crt

kubectl create secret tls alpha-tls -n tutorial-ingress2 --cert=/tmp/alpha.crt --key=/tmp/alpha.key
kubectl create secret tls beta-tls  -n tutorial-ingress2 --cert=/tmp/beta.crt  --key=/tmp/beta.key

kubectl apply -n tutorial-ingress2 -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: multi-tls
spec:
  ingressClassName: haproxy
  tls:
  - hosts: ["alpha.example.test"]
    secretName: alpha-tls
  - hosts: ["beta.example.test"]
    secretName: beta-tls
  rules:
  - host: alpha.example.test
    http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: app, port: {number: 80}}}}]}
  - host: beta.example.test
    http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: app, port: {number: 80}}}}]}
EOF

sleep 3
curl -sk --resolve alpha.example.test:8443:127.0.0.1 -v https://alpha.example.test:8443/ 2>&1 | grep -E "subject" | head
# Expected: CN=alpha.example.test

curl -sk --resolve beta.example.test:8443:127.0.0.1 -v https://beta.example.test:8443/ 2>&1 | grep -E "subject" | head
# Expected: CN=beta.example.test
```

HAProxy selects the correct cert via SNI (Server Name Indication). The client sends the hostname in the TLS handshake; the controller matches it against `spec.tls[*].hosts` and presents the right Secret's cert.

## Part 7: HTTPS redirect

Force HTTP requests to redirect to HTTPS using an HAProxy annotation.

```bash
kubectl apply -n tutorial-ingress2 -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: redirect-only
  annotations:
    haproxy-ingress.github.io/ssl-redirect: "true"
spec:
  ingressClassName: haproxy
  tls:
  - hosts: ["tls.example.test"]
    secretName: tut-tls
  rules:
  - host: tls.example.test
    http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: app, port: {number: 80}}}}]}
EOF

sleep 3
curl -sI -H "Host: tls.example.test" http://localhost:8080/
# Expected: HTTP/1.1 301 Moved Permanently (or 302) with Location: https://...
```

The annotation name is HAProxy-specific. Traefik uses a different pattern (`traefik.ingress.kubernetes.io/router.middlewares: <ns>-redirect-https@kubernetescrd`); if this annotation were applied to a Traefik-watched Ingress, HAProxy's annotation would be ignored.

## Cleanup

Delete the tutorial namespace.

```bash
kubectl delete namespace tutorial-ingress2
rm -f /tmp/tls.key /tmp/tls.crt /tmp/alpha.key /tmp/alpha.crt /tmp/beta.key /tmp/beta.crt
```

Leave both Traefik and HAProxy installed for the homework exercises. To remove HAProxy entirely:

```bash
helm uninstall -n haproxy-ingress haproxy-ingress
kubectl delete namespace haproxy-ingress
```

## Reference Commands

| Task | Command |
|---|---|
| List controllers | `kubectl get pods -A | grep -E "traefik\|haproxy"` |
| Port-forward to HAProxy | `kubectl port-forward -n haproxy-ingress svc/haproxy-ingress 8080:80 8443:443` |
| Create a TLS Secret from files | `kubectl create secret tls <name> --cert=<crt> --key=<key>` |
| Test TLS with SNI | `curl -k --resolve <host>:<port>:127.0.0.1 https://<host>:<port>/<path> -v` |
| Extract cert from a Secret | `kubectl get secret <name> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text` |
| HAProxy controller logs | `kubectl logs -n haproxy-ingress -l app.kubernetes.io/name=haproxy-ingress --tail=50` |

## Key Takeaways

Same Ingress YAML, different controllers: only `ingressClassName` changes. Annotations are controller-specific (`haproxy-ingress.github.io/*` for HAProxy; `traefik.ingress.kubernetes.io/*` for Traefik). Applying the wrong controller's annotation is silently ignored. TLS termination uses `spec.tls[]` plus a `kubernetes.io/tls`-typed Secret containing `tls.crt` and `tls.key`. Multi-host TLS uses one `tls[]` entry per host; the controller uses SNI to pick the right cert. `kubectl create secret tls` is the concise way to build the Secret from PEM files. HTTPS redirect is controller-specific but universally available (`haproxy-ingress.github.io/ssl-redirect: "true"` for HAProxy). Running both controllers in the same cluster makes the universal-API lesson concrete: the same YAML, served twice.
