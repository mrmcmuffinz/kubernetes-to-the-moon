# Advanced Ingress and TLS Homework

Fifteen exercises covering HAProxy Ingress v3.2.6, annotations, rewrite-target, TLS termination with self-signed certs, multi-host TLS with SNI, and debugging cross-controller annotation mistakes. Assumes HAProxy Ingress is installed in `haproxy-ingress` namespace and Traefik from assignment 1 is still installed in `traefik` namespace. Maintain a `kubectl port-forward` to the HAProxy Service at 8080/8443 for verification; exercises assume this.

Exercise namespaces follow `ex-<level>-<exercise>`.

---

## Level 1: HAProxy Basics

### Exercise 1.1

**Objective:** Create a backend Service and an Ingress under the `haproxy` IngressClass that returns a simple response.

**Setup:**

```bash
kubectl create namespace ex-1-1
kubectl apply -n ex-1-1 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: site}
spec:
  replicas: 1
  selector: {matchLabels: {app: site}}
  template:
    metadata: {labels: {app: site}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: site-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: site-html}
data: {index.html: "level-1-1\n"}
---
apiVersion: v1
kind: Service
metadata: {name: site}
spec: {selector: {app: site}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-1-1 rollout status deployment/site --timeout=60s
```

**Task:** Create Ingress `ex-1-1-ing` (ingressClassName haproxy) routing host `one.example.test` path `/` (Prefix) to Service `site` port 80.

**Verification:**

```bash
sleep 3
curl -s -H "Host: one.example.test" http://localhost:8080/
# Expected: level-1-1

kubectl get ingress -n ex-1-1 ex-1-1-ing -o jsonpath='{.spec.ingressClassName}'
# Expected: haproxy
```

---

### Exercise 1.2

**Objective:** Apply an HAProxy rate-limit annotation and verify it is present in the Ingress resource.

**Setup:**

```bash
kubectl create namespace ex-1-2
kubectl apply -n ex-1-2 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: api}
spec:
  replicas: 1
  selector: {matchLabels: {app: api}}
  template:
    metadata: {labels: {app: api}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: api-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: api-html}
data: {index.html: "api-limited\n"}
---
apiVersion: v1
kind: Service
metadata: {name: api}
spec: {selector: {app: api}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-1-2 rollout status deployment/api --timeout=60s
```

**Task:** Create Ingress `api-rate-limited` with annotation `haproxy-ingress.github.io/rate-limit-rpm: "120"`, `ingressClassName: haproxy`, host `api.example.test`, path `/` -> Service `api`.

**Verification:**

```bash
sleep 3
curl -s -H "Host: api.example.test" http://localhost:8080/
# Expected: api-limited

kubectl get ingress -n ex-1-2 api-rate-limited -o jsonpath='{.metadata.annotations.haproxy-ingress\.github\.io/rate-limit-rpm}'
# Expected: 120
```

---

### Exercise 1.3

**Objective:** Read HAProxy controller logs to confirm an Ingress was picked up.

**Setup:** Reuse the Ingress from 1.2.

**Task:** Run a command that prints the last 50 log lines from the HAProxy controller pod and verify the Ingress `api-rate-limited` is referenced in the logs.

**Verification:**

```bash
kubectl logs -n haproxy-ingress -l app.kubernetes.io/name=haproxy-ingress --tail=100 | grep -c "api-rate-limited" || echo "0"
# Expected: a non-zero number (the Ingress name appears in the controller's update log)
```

---

## Level 2: Annotations and Rewrite

### Exercise 2.1

**Objective:** Use rewrite-target to strip a path prefix before forwarding.

**Setup:**

```bash
kubectl create namespace ex-2-1
kubectl apply -n ex-2-1 -f - <<'EOF'
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
        return 200 "you-sent: $request_uri\n";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: echo}
spec: {selector: {app: echo}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-2-1 rollout status deployment/echo --timeout=60s
```

**Task:** Create Ingress `rewrite` with HAProxy `rewrite-target: /` annotation, host `echo.example.test`, path `/strip` (Prefix) -> Service `echo`. A request to `/strip/hello` should reach the backend as `/`.

**Verification:**

```bash
sleep 3
curl -s -H "Host: echo.example.test" http://localhost:8080/strip/hello
# Expected: you-sent: /
```

---

### Exercise 2.2

**Objective:** Apply a response-header-modifier annotation and verify headers are injected.

**Setup:**

```bash
kubectl create namespace ex-2-2
kubectl apply -n ex-2-2 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: web}
spec:
  replicas: 1
  selector: {matchLabels: {app: web}}
  template:
    metadata: {labels: {app: web}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: web-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: web-html}
data: {index.html: "web-ok\n"}
---
apiVersion: v1
kind: Service
metadata: {name: web}
spec: {selector: {app: web}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-2-2 rollout status deployment/web --timeout=60s
```

**Task:** Create Ingress `with-headers` with HAProxy annotation `haproxy-ingress.github.io/response-headers: "X-App-Name: example"`, `ingressClassName: haproxy`, host `headers.example.test`, path `/` -> Service `web`.

**Verification:**

```bash
sleep 3
curl -sI -H "Host: headers.example.test" http://localhost:8080/
# Expected (response headers include): X-App-Name: example
```

---

### Exercise 2.3

**Objective:** Run the same Ingress spec under both `haproxy` and `traefik` classes by changing only `ingressClassName`, and verify both serve the backend.

**Setup:**

```bash
kubectl create namespace ex-2-3
kubectl apply -n ex-2-3 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: both}
spec:
  replicas: 1
  selector: {matchLabels: {app: both}}
  template:
    metadata: {labels: {app: both}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: both-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: both-html}
data: {index.html: "both-served\n"}
---
apiVersion: v1
kind: Service
metadata: {name: both}
spec: {selector: {app: both}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-2-3 rollout status deployment/both --timeout=60s
```

**Task:** Create two Ingresses in namespace `ex-2-3` with identical rules (host `both.example.test`, path `/` -> Service `both`), one with `ingressClassName: traefik` and the other with `ingressClassName: haproxy`.

**Verification:**

```bash
sleep 3
curl -s -H "Host: both.example.test" http://localhost/
# Expected: both-served (via Traefik on port 80)

curl -s -H "Host: both.example.test" http://localhost:8080/
# Expected: both-served (via HAProxy on port 8080)
```

---

## Level 3: Debugging

### Exercise 3.1

**Objective:** An HAProxy Ingress has a rewrite configured but requests are not reaching the backend as expected. Diagnose and fix.

**Setup:**

```bash
kubectl create namespace ex-3-1
kubectl apply -n ex-3-1 -f - <<'EOF'
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
      location / {
        return 200 "got: $request_uri\n";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: app}
spec: {selector: {app: app}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wrong-annotation
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: strip-prefix
spec:
  ingressClassName: haproxy
  rules:
  - host: wrong.example.test
    http:
      paths:
      - {path: /wrong, pathType: Prefix, backend: {service: {name: app, port: {number: 80}}}}
EOF
kubectl -n ex-3-1 rollout status deployment/app --timeout=60s
```

**Task:** Fix the Ingress so that requests to `/wrong/anything` reach the backend as `/`.

**Verification:**

```bash
sleep 3
curl -s -H "Host: wrong.example.test" http://localhost:8080/wrong/anything
# Expected: got: /
```

---

### Exercise 3.2

**Objective:** A TLS-enabled Ingress is not terminating TLS correctly. Diagnose and fix.

**Setup:**

```bash
kubectl create namespace ex-3-2

openssl req -x509 -newkey rsa:2048 -nodes -sha256 \
  -subj "/CN=secure.example.test/O=ex32" -days 30 \
  -addext "subjectAltName = DNS:secure.example.test" \
  -keyout /tmp/ex32.key -out /tmp/ex32.crt

kubectl create secret generic -n ex-3-2 wrong-secret \
  --from-file=certificate.pem=/tmp/ex32.crt \
  --from-file=private-key.pem=/tmp/ex32.key

kubectl apply -n ex-3-2 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: secure-app}
spec:
  replicas: 1
  selector: {matchLabels: {app: secure-app}}
  template:
    metadata: {labels: {app: secure-app}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: secure-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: secure-html}
data: {index.html: "secure\n"}
---
apiVersion: v1
kind: Service
metadata: {name: secure-app}
spec: {selector: {app: secure-app}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: {name: tls-broken}
spec:
  ingressClassName: haproxy
  tls:
  - hosts: ["secure.example.test"]
    secretName: wrong-secret
  rules:
  - host: secure.example.test
    http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: secure-app, port: {number: 80}}}}]}
EOF
kubectl -n ex-3-2 rollout status deployment/secure-app --timeout=60s
```

**Task:** The Ingress is not terminating TLS with the expected certificate. Diagnose and fix the root cause.

**Verification:**

```bash
sleep 3
curl -sk --resolve secure.example.test:8443:127.0.0.1 -v https://secure.example.test:8443/ 2>&1 | grep "subject" | head -n1
# Expected: subject: CN=secure.example.test (or similar including the correct CN)

kubectl get secret -n ex-3-2 wrong-secret -o jsonpath='{.type}'
# Expected: kubernetes.io/tls
```

---

### Exercise 3.3

**Objective:** An Ingress has no ADDRESS despite the HAProxy controller being healthy. Diagnose.

**Setup:**

```bash
kubectl create namespace ex-3-3
kubectl apply -n ex-3-3 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: dangling}
spec:
  replicas: 1
  selector: {matchLabels: {app: dangling}}
  template:
    metadata: {labels: {app: dangling}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: dangling-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: dangling-html}
data: {index.html: "dangling\n"}
---
apiVersion: v1
kind: Service
metadata: {name: dangling}
spec: {selector: {app: dangling}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: {name: stuck}
spec:
  rules:
  - host: stuck.example.test
    http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: dangling, port: {number: 80}}}}]}
EOF
kubectl -n ex-3-3 rollout status deployment/dangling --timeout=60s
```

**Task:** Fix the Ingress so it is picked up by the controller and has an ADDRESS.

**Verification:**

```bash
sleep 3
kubectl get ingress -n ex-3-3 stuck -o jsonpath='{.spec.ingressClassName}'
# Expected: haproxy

curl -s -H "Host: stuck.example.test" http://localhost:8080/
# Expected: dangling
```

---

## Level 4: TLS

### Exercise 4.1

**Objective:** Create a TLS-terminated Ingress with a self-signed certificate.

**Setup:**

```bash
kubectl create namespace ex-4-1
openssl req -x509 -newkey rsa:2048 -nodes -sha256 \
  -subj "/CN=one-tls.example.test/O=ex41" -days 30 \
  -addext "subjectAltName = DNS:one-tls.example.test" \
  -keyout /tmp/ex41.key -out /tmp/ex41.crt

kubectl apply -n ex-4-1 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: one}
spec:
  replicas: 1
  selector: {matchLabels: {app: one}}
  template:
    metadata: {labels: {app: one}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: one-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: one-html}
data: {index.html: "one-tls-payload\n"}
---
apiVersion: v1
kind: Service
metadata: {name: one}
spec: {selector: {app: one}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-4-1 rollout status deployment/one --timeout=60s
```

**Task:** Create TLS Secret `one-tls` from `/tmp/ex41.crt` and `/tmp/ex41.key`. Create Ingress `one-secure` with `tls: [{hosts: [one-tls.example.test], secretName: one-tls}]`, `ingressClassName: haproxy`, host `one-tls.example.test` path `/` -> Service `one`.

**Verification:**

```bash
sleep 3
curl -sk --resolve one-tls.example.test:8443:127.0.0.1 https://one-tls.example.test:8443/
# Expected: one-tls-payload

curl -sk --resolve one-tls.example.test:8443:127.0.0.1 -v https://one-tls.example.test:8443/ 2>&1 | grep subject | head -n1
# Expected (contains): CN=one-tls.example.test
```

---

### Exercise 4.2

**Objective:** Configure multi-host TLS with two different certificates.

**Setup:** (Continuing from 4.1's namespace pattern.)

```bash
kubectl create namespace ex-4-2
for host in site-a site-b; do
  openssl req -x509 -newkey rsa:2048 -nodes -sha256 \
    -subj "/CN=$host.example.test/O=ex42" -days 30 \
    -addext "subjectAltName = DNS:$host.example.test" \
    -keyout "/tmp/$host.key" -out "/tmp/$host.crt"
done

kubectl apply -n ex-4-2 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: site-a}
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
data: {index.html: "site-a\n"}
---
apiVersion: v1
kind: Service
metadata: {name: site-a}
spec: {selector: {app: a}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: site-b}
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
data: {index.html: "site-b\n"}
---
apiVersion: v1
kind: Service
metadata: {name: site-b}
spec: {selector: {app: b}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-4-2 rollout status deployment/site-a deployment/site-b --timeout=60s
```

**Task:** Create two TLS Secrets (`site-a-tls`, `site-b-tls`) from the corresponding cert/key pairs. Create Ingress `multi` with two `tls[]` entries and two rules, routing each host to its respective Service.

**Verification:**

```bash
sleep 3
curl -sk --resolve site-a.example.test:8443:127.0.0.1 https://site-a.example.test:8443/
# Expected: site-a

curl -sk --resolve site-b.example.test:8443:127.0.0.1 https://site-b.example.test:8443/
# Expected: site-b

# SNI returns the right cert for each:
curl -sk --resolve site-a.example.test:8443:127.0.0.1 -v https://site-a.example.test:8443/ 2>&1 | grep "subject" | head -n1
# Expected (contains): CN=site-a.example.test
```

---

### Exercise 4.3

**Objective:** Force an HTTP-to-HTTPS redirect with HAProxy's `ssl-redirect` annotation.

**Setup:** Reuse `ex-4-1` setup (cert, Service).

```bash
kubectl create namespace ex-4-3
kubectl apply -n ex-4-3 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: redirect-me}
spec:
  replicas: 1
  selector: {matchLabels: {app: redirect-me}}
  template:
    metadata: {labels: {app: redirect-me}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: redirect-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: redirect-html}
data: {index.html: "redirected-payload\n"}
---
apiVersion: v1
kind: Service
metadata: {name: redirect-me}
spec: {selector: {app: redirect-me}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-4-3 rollout status deployment/redirect-me --timeout=60s

openssl req -x509 -newkey rsa:2048 -nodes -sha256 \
  -subj "/CN=redir.example.test/O=ex43" -days 30 \
  -addext "subjectAltName = DNS:redir.example.test" \
  -keyout /tmp/redir.key -out /tmp/redir.crt
kubectl create secret tls -n ex-4-3 redir-tls --cert=/tmp/redir.crt --key=/tmp/redir.key
```

**Task:** Create Ingress `redir` with annotation `haproxy-ingress.github.io/ssl-redirect: "true"`, `tls: [{hosts: [redir.example.test], secretName: redir-tls}]`, ingressClassName haproxy, host redir.example.test path `/` -> Service `redirect-me`.

**Verification:**

```bash
sleep 3
curl -sI -H "Host: redir.example.test" http://localhost:8080/
# Expected: HTTP/1.1 301 (or 302) Moved Permanently, with Location: https://...

curl -sk --resolve redir.example.test:8443:127.0.0.1 https://redir.example.test:8443/
# Expected: redirected-payload
```

---

## Level 5: Advanced

### Exercise 5.1

**Objective:** Build an Ingress stack with TLS termination, HTTP-to-HTTPS redirect, and a rewrite-target for a specific path prefix.

**Setup:**

```bash
kubectl create namespace ex-5-1
kubectl apply -n ex-5-1 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: api-v2}
spec:
  replicas: 1
  selector: {matchLabels: {app: api-v2}}
  template:
    metadata: {labels: {app: api-v2}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: c, mountPath: /etc/nginx/conf.d}]}
      volumes: [{name: c, configMap: {name: api-v2-conf}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: api-v2-conf}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        return 200 "v2-served for $request_uri\n";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: api-v2}
spec: {selector: {app: api-v2}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-5-1 rollout status deployment/api-v2 --timeout=60s

openssl req -x509 -newkey rsa:2048 -nodes -sha256 \
  -subj "/CN=production.example.test/O=ex51" -days 30 \
  -addext "subjectAltName = DNS:production.example.test" \
  -keyout /tmp/prod.key -out /tmp/prod.crt
kubectl create secret tls -n ex-5-1 prod-tls --cert=/tmp/prod.crt --key=/tmp/prod.key
```

**Task:** Create Ingress `production` in namespace `ex-5-1` that: has `haproxy-ingress.github.io/ssl-redirect: "true"` and `haproxy-ingress.github.io/rewrite-target: /` annotations, TLS termination on `production.example.test` via `prod-tls`, rule host `production.example.test` path `/api/v2` (Prefix) -> Service `api-v2`.

**Verification:**

```bash
sleep 3
curl -sI -H "Host: production.example.test" http://localhost:8080/api/v2/things
# Expected: HTTP/1.1 301 (redirect)

curl -sk --resolve production.example.test:8443:127.0.0.1 https://production.example.test:8443/api/v2/things
# Expected: v2-served for /things  (rewrite stripped /api/v2)
```

---

### Exercise 5.2

**Objective:** Diagnose a compound TLS failure with three issues. Fix all three.

**Setup:**

```bash
kubectl create namespace ex-5-2

openssl req -x509 -newkey rsa:2048 -nodes -sha256 \
  -subj "/CN=five-two.example.test/O=ex52" -days 30 \
  -addext "subjectAltName = DNS:five-two.example.test" \
  -keyout /tmp/ex52.key -out /tmp/ex52.crt

kubectl create secret generic -n ex-5-2 bad-secret \
  --from-file=ca.crt=/tmp/ex52.crt \
  --from-file=ca.key=/tmp/ex52.key

kubectl apply -n ex-5-2 -f - <<'EOF'
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
data: {index.html: "backend-served\n"}
---
apiVersion: v1
kind: Service
metadata: {name: backend}
spec: {selector: {app: backend}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: multi-issue
  annotations:
    traefik.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: haproxy
  tls:
  - hosts: ["other.example.test"]
    secretName: bad-secret
  rules:
  - host: five-two.example.test
    http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: backend, port: {number: 80}}}}]}
EOF
kubectl -n ex-5-2 rollout status deployment/backend --timeout=60s
```

**Task:** Fix the Ingress so HTTP requests redirect to HTTPS, HTTPS requests succeed, and the certificate CN matches the hostname.

**Verification:**

```bash
sleep 3
curl -sI -H "Host: five-two.example.test" http://localhost:8080/
# Expected: HTTP/1.1 301 Moved Permanently

curl -sk --resolve five-two.example.test:8443:127.0.0.1 https://five-two.example.test:8443/
# Expected: backend-served

curl -sk --resolve five-two.example.test:8443:127.0.0.1 -v https://five-two.example.test:8443/ 2>&1 | grep "subject" | head -n1
# Expected (contains): CN=five-two.example.test
```

---

### Exercise 5.3

**Objective:** Design a production-style Ingress pattern: HAProxy-served HTTPS with SNI-based multi-tenancy, per-tenant rewrite, and one shared health-check path that remains HTTP-only.

**Setup:**

```bash
kubectl create namespace ex-5-3
for tenant in t1 t2; do
  kubectl apply -n ex-5-3 -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: {name: $tenant-app}
spec:
  replicas: 1
  selector: {matchLabels: {app: $tenant-app}}
  template:
    metadata: {labels: {app: $tenant-app}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: c, mountPath: /etc/nginx/conf.d}]}
      volumes: [{name: c, configMap: {name: $tenant-conf}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: $tenant-conf}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        return 200 "$tenant serves: \$request_uri\n";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: $tenant-app}
spec: {selector: {app: $tenant-app}, ports: [{port: 80, targetPort: 80}]}
EOF
done
kubectl -n ex-5-3 wait --for=condition=Available deployment --all --timeout=120s

kubectl apply -n ex-5-3 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: health}
spec:
  replicas: 1
  selector: {matchLabels: {app: health}}
  template:
    metadata: {labels: {app: health}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: health-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: health-html}
data: {index.html: "OK\n"}
---
apiVersion: v1
kind: Service
metadata: {name: health}
spec: {selector: {app: health}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-5-3 rollout status deployment/health --timeout=60s

for t in t1 t2; do
  openssl req -x509 -newkey rsa:2048 -nodes -sha256 \
    -subj "/CN=$t.example.test/O=ex53" -days 30 \
    -addext "subjectAltName = DNS:$t.example.test" \
    -keyout "/tmp/$t.key" -out "/tmp/$t.crt"
  kubectl create secret tls -n ex-5-3 "$t-tls" --cert="/tmp/$t.crt" --key="/tmp/$t.key"
done
```

**Task:** Create two Ingresses: `tenants` with TLS on `t1.example.test` and `t2.example.test` and per-tenant rewrite-target annotations routing `/api` -> each tenant's Service; `health` with no TLS, path `/healthz` -> Service `health`, host `status.example.test`.

**Verification:**

```bash
sleep 3
curl -sk --resolve t1.example.test:8443:127.0.0.1 https://t1.example.test:8443/api/items
# Expected: t1 serves: /items

curl -sk --resolve t2.example.test:8443:127.0.0.1 https://t2.example.test:8443/api/items
# Expected: t2 serves: /items

curl -s -H "Host: status.example.test" http://localhost:8080/healthz
# Expected: OK

# Confirm SNI:
curl -sk --resolve t1.example.test:8443:127.0.0.1 -v https://t1.example.test:8443/ 2>&1 | grep "subject" | head -n1
# Expected (contains): CN=t1.example.test
```

---

## Cleanup

```bash
for ns in ex-1-1 ex-1-2 ex-2-1 ex-2-2 ex-2-3 ex-3-1 ex-3-2 ex-3-3 \
         ex-4-1 ex-4-2 ex-4-3 ex-5-1 ex-5-2 ex-5-3; do
  kubectl delete namespace "$ns" --ignore-not-found
done

rm -f /tmp/ex*.key /tmp/ex*.crt /tmp/site-*.key /tmp/site-*.crt /tmp/t1.* /tmp/t2.* /tmp/redir.* /tmp/prod.*
```

## Key Takeaways

Annotations are controller-specific; HAProxy uses `haproxy-ingress.github.io/*`. Applying a Traefik annotation to an HAProxy Ingress is silently ignored. TLS termination requires a `kubernetes.io/tls`-typed Secret with `tls.crt` and `tls.key` keys; `kubectl create secret tls` builds this correctly. Multi-host TLS uses one `tls[]` entry per host and SNI selects the right cert. HTTPS redirect, rewrite-target, and rate-limit are all implemented as controller-specific annotations. Running multiple controllers in the same cluster is common production practice; each owns its own IngressClass.
