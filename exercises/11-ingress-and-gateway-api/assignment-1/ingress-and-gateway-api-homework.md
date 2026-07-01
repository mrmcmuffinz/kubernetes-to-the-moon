# Ingress API Fundamentals Homework

Fifteen exercises covering Ingress v1 creation, path types, host-based routing, IngressClass management, defaultBackend, and debugging. Assumes Traefik v3.6.13 from the tutorial is still installed in the `traefik` namespace. Work through the tutorial first.

Exercise namespaces follow `ex-<level>-<exercise>`. Every Ingress in this assignment references `ingressClassName: traefik` unless an exercise explicitly tests a different class.

---

## Level 1: Basic Ingress Creation

### Exercise 1.1

**Objective:** Create an Ingress that routes `/` on a specific host to a single backend Service.

**Setup:**

```bash
kubectl create namespace ex-1-1

kubectl apply -n ex-1-1 -f - <<'EOF'
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
      - name: nginx
        image: nginx:1.27
        volumeMounts:
        - {name: html, mountPath: /usr/share/nginx/html}
      volumes:
      - name: html
        configMap: {name: hello-html}
---
apiVersion: v1
kind: ConfigMap
metadata: {name: hello-html}
data:
  index.html: "hello-world\n"
---
apiVersion: v1
kind: Service
metadata: {name: hello}
spec:
  selector: {app: hello}
  ports: [{port: 80, targetPort: 80}]
EOF

kubectl -n ex-1-1 rollout status deployment/hello --timeout=60s
```

**Task:** In namespace `ex-1-1`, create an Ingress named `hello-ingress` with `ingressClassName: traefik` that routes the host `hello.example.test` on path `/` (pathType: `Prefix`) to the `hello` Service on port 80.

**Verification:**

```bash
sleep 3
kubectl get ingress -n ex-1-1 hello-ingress -o jsonpath='{.spec.ingressClassName}'
# Expected: traefik

curl -s -H "Host: hello.example.test" http://localhost/
# Expected: hello-world
```

---

### Exercise 1.2

**Objective:** Create an Ingress with two path-based rules pointing at two different Services.

**Setup:**

```bash
kubectl create namespace ex-1-2

kubectl apply -n ex-1-2 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: a}
spec:
  replicas: 1
  selector: {matchLabels: {app: a}}
  template:
    metadata: {labels: {app: a}}
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        volumeMounts: [{name: html, mountPath: /etc/nginx/conf.d}]
      volumes: [{name: html, configMap: {name: a-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: a-html}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        return 200 "a-response";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: a}
spec: {selector: {app: a}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: b}
spec:
  replicas: 1
  selector: {matchLabels: {app: b}}
  template:
    metadata: {labels: {app: b}}
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        volumeMounts: [{name: html, mountPath: /etc/nginx/conf.d}]
      volumes: [{name: html, configMap: {name: b-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: b-html}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        return 200 "b-response";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: b}
spec: {selector: {app: b}, ports: [{port: 80, targetPort: 80}]}
EOF

kubectl -n ex-1-2 rollout status deployment/a deployment/b --timeout=60s
```

**Task:** In namespace `ex-1-2`, create an Ingress `paths-ingress` routing `host: paths.example.test` paths `/a` to Service `a` and `/b` to Service `b`, both with pathType `Prefix`.

**Verification:**

```bash
sleep 3
curl -s -H "Host: paths.example.test" http://localhost/a
# Expected: a-response

curl -s -H "Host: paths.example.test" http://localhost/b
# Expected: b-response

curl -sI -H "Host: paths.example.test" http://localhost/c
# Expected: HTTP/1.1 404 Not Found
```

---

### Exercise 1.3

**Objective:** Create an Ingress with a `defaultBackend` that catches every unmatched request.

**Setup:** Reuse Deployment `hello` in namespace `ex-1-3`.

```bash
kubectl create namespace ex-1-3
kubectl apply -n ex-1-3 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: fallback}
spec:
  replicas: 1
  selector: {matchLabels: {app: fallback}}
  template:
    metadata: {labels: {app: fallback}}
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        volumeMounts: [{name: html, mountPath: /etc/nginx/conf.d}]
      volumes: [{name: html, configMap: {name: fallback-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: fallback-html}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        return 200 "fallback-served";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: fallback}
spec: {selector: {app: fallback}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-1-3 rollout status deployment/fallback --timeout=60s
```

**Task:** In namespace `ex-1-3`, create an Ingress `catchall` with `ingressClassName: traefik`, only `defaultBackend` set (no `rules` block), pointing at Service `fallback` on port 80. Then test that unmatched paths on the `catchall.example.test` host return the fallback content.

**Verification:**

```bash
sleep 3
curl -s -H "Host: catchall.example.test" http://localhost/anywhere
# Expected: fallback-served

curl -s -H "Host: catchall.example.test" http://localhost/
# Expected: fallback-served
```

---

## Level 2: Path and Host Routing

### Exercise 2.1

**Objective:** Use `Exact` path type and confirm only the literal path matches.

**Setup:**

```bash
kubectl create namespace ex-2-1
kubectl apply -n ex-2-1 -f - <<'EOF'
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
      - name: nginx
        image: nginx:1.27
        volumeMounts: [{name: html, mountPath: /etc/nginx/conf.d}]
      volumes: [{name: html, configMap: {name: api-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: api-html}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        return 200 "api-v1\n";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: api}
spec: {selector: {app: api}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-2-1 rollout status deployment/api --timeout=60s
```

**Task:** In namespace `ex-2-1`, create Ingress `exact-ingress` on host `exact.example.test` with a single rule: `pathType: Exact`, `path: /api`, backend Service `api` port 80.

**Verification:**

```bash
sleep 3
curl -s -H "Host: exact.example.test" http://localhost/api
# Expected: api-v1

curl -sI -H "Host: exact.example.test" http://localhost/api/extra
# Expected: HTTP/1.1 404 Not Found

curl -sI -H "Host: exact.example.test" http://localhost/api/
# Expected: HTTP/1.1 404 Not Found
```

---

### Exercise 2.2

**Objective:** Combine multiple hosts and paths in a single Ingress.

**Setup:**

```bash
kubectl create namespace ex-2-2
kubectl apply -n ex-2-2 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: foo}
spec:
  replicas: 1
  selector: {matchLabels: {app: foo}}
  template:
    metadata: {labels: {app: foo}}
    spec:
      containers:
      - {name: nginx, image: nginx:1.27, volumeMounts: [{name: html, mountPath: /etc/nginx/conf.d}]}
      volumes: [{name: html, configMap: {name: foo-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: foo-html}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        return 200 "foo-app";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: foo}
spec: {selector: {app: foo}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: bar}
spec:
  replicas: 1
  selector: {matchLabels: {app: bar}}
  template:
    metadata: {labels: {app: bar}}
    spec:
      containers:
      - {name: nginx, image: nginx:1.27, volumeMounts: [{name: html, mountPath: /etc/nginx/conf.d}]}
      volumes: [{name: html, configMap: {name: bar-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: bar-html}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        return 200 "bar-app";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: bar}
spec: {selector: {app: bar}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-2-2 rollout status deployment/foo deployment/bar --timeout=60s
```

**Task:** In namespace `ex-2-2`, create Ingress `multi` routing: host `foo.example.test` path `/` to Service `foo`; host `bar.example.test` path `/` to Service `bar`; host `shared.example.test` paths `/foo` to Service `foo` and `/bar` to Service `bar`.

**Verification:**

```bash
sleep 3
curl -s -H "Host: foo.example.test" http://localhost/
# Expected: foo-app

curl -s -H "Host: bar.example.test" http://localhost/
# Expected: bar-app

curl -s -H "Host: shared.example.test" http://localhost/foo
# Expected: foo-app

curl -s -H "Host: shared.example.test" http://localhost/bar
# Expected: bar-app
```

---

### Exercise 2.3

**Objective:** Use specific host and path rules together with a defaultBackend.

**Setup:**

```bash
kubectl create namespace ex-2-3
kubectl apply -n ex-2-3 -f - <<'EOF'
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
      - {name: nginx, image: nginx:1.27, volumeMounts: [{name: html, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: html, configMap: {name: app-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: app-html}
data: {index.html: "app-alpha\n"}
---
apiVersion: v1
kind: Service
metadata: {name: app}
spec: {selector: {app: app}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: default}
spec:
  replicas: 1
  selector: {matchLabels: {app: default}}
  template:
    metadata: {labels: {app: default}}
    spec:
      containers:
      - {name: nginx, image: nginx:1.27, volumeMounts: [{name: html, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: html, configMap: {name: default-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: default-html}
data: {index.html: "default-fallback\n"}
---
apiVersion: v1
kind: Service
metadata: {name: default}
spec: {selector: {app: default}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-2-3 rollout status deployment/app deployment/default --timeout=60s
```

> **Note:** This exercise uses a `defaultBackend`, which conflicts with the one created in exercise 1.3. Delete that namespace before starting: `kubectl delete namespace ex-1-3`

**Task:** Create two Ingress resources in namespace `ex-2-3`. The first, named `app-route`, has ingressClassName `traefik`, annotation `traefik.ingress.kubernetes.io/router.priority: "10"`, and a single rule: host `app.example.test`, path `/`, pathType `Prefix`, backend Service `app`. The second, named `with-fallback`, has ingressClassName `traefik`, annotation `traefik.ingress.kubernetes.io/router.priority: "1"`, and only a `defaultBackend` pointing at Service `default` (no rules). The priority annotation ensures `app-route` wins for its host while `with-fallback` acts as a cluster-wide catch-all for any host not matched by another Ingress.

**Verification:**

```bash
sleep 3
curl -s -H "Host: app.example.test" http://192.168.200.12:32080/
# Expected: app-alpha

curl -s -H "Host: other.example.test" http://192.168.200.12:32080/
# Expected: default-fallback
```

---

## Level 3: Debugging

### Exercise 3.1

**Objective:** The Ingress below has no ADDRESS assigned. Find and fix the cause.

**Setup:**

```bash
kubectl create namespace ex-3-1
kubectl apply -n ex-3-1 -f - <<'EOF'
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
      - {name: nginx, image: nginx:1.27, volumeMounts: [{name: html, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: html, configMap: {name: hi-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: hi-html}
data: {index.html: "hi-reply\n"}
---
apiVersion: v1
kind: Service
metadata: {name: hi}
spec: {selector: {app: hi}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: {name: stuck}
spec:
  ingressClassName: nginx
  rules:
  - host: stuck.example.test
    http:
      paths:
      - {path: /, pathType: Prefix, backend: {service: {name: hi, port: {number: 80}}}}
EOF
kubectl -n ex-3-1 rollout status deployment/hi --timeout=60s
```

**Task:** The Ingress has ADDRESS `<none>`. Fix it so the request `curl -H "Host: stuck.example.test" http://localhost/` returns `hi-reply`.

**Verification:**

```bash
sleep 5
curl -s -H "Host: stuck.example.test" http://localhost/
# Expected: hi-reply
```

---

### Exercise 3.2

**Objective:** The Ingress below returns 404 for every request despite being accepted by the controller. Find and fix.

**Setup:**

```bash
kubectl create namespace ex-3-2
kubectl apply -n ex-3-2 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: frontend}
spec:
  replicas: 1
  selector: {matchLabels: {app: frontend}}
  template:
    metadata: {labels: {app: frontend}}
    spec:
      containers:
      - {name: nginx, image: nginx:1.27, volumeMounts: [{name: html, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: html, configMap: {name: frontend-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: frontend-html}
data: {index.html: "frontend-ok\n"}
---
apiVersion: v1
kind: Service
metadata: {name: frontend-svc}
spec: {selector: {app: frontend}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: {name: ifu}
spec:
  ingressClassName: traefik
  rules:
  - host: frontend.example.test
    http:
      paths:
      - {path: /, pathType: Prefix, backend: {service: {name: frontend, port: {number: 80}}}}
EOF
kubectl -n ex-3-2 rollout status deployment/frontend --timeout=60s
```

**Task:** Fix the Ingress so traffic reaches the backend.

**Verification:**

```bash
sleep 3
curl -s -H "Host: frontend.example.test" http://localhost/
# Expected: frontend-ok
```

---

### Exercise 3.3

**Objective:** An Ingress returns 404 for a valid path. Find and fix.

**Setup:**

```bash
kubectl create namespace ex-3-3
kubectl apply -n ex-3-3 -f - <<'EOF'
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
      - {name: nginx, image: nginx:1.27, volumeMounts: [{name: html, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: html, configMap: {name: api-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: api-html}
data:
  default.conf: |
    server {
      listen 80;
      location /api/v1 {
        return 200 "api-v1-endpoint";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: api}
spec: {selector: {app: api}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: {name: path-bad}
spec:
  ingressClassName: traefik
  rules:
  - host: api.example.test
    http:
      paths:
      - {path: /api, pathType: Exact, backend: {service: {name: api, port: {number: 80}}}}
EOF
```

Wait, this test requires the nginx config to be mounted too. Fix the Deployment to mount the ConfigMap into `/etc/nginx/conf.d/`:

```bash
kubectl patch deployment -n ex-3-3 api --type='json' -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts","value":[{"name":"conf","mountPath":"/etc/nginx/conf.d"}]},
  {"op":"add","path":"/spec/template/spec/volumes","value":[{"name":"conf","configMap":{"name":"api-html","items":[{"key":"default.conf","path":"default.conf"}]}}]}
]'
kubectl -n ex-3-3 rollout status deployment/api --timeout=60s
```

**Task:** Adjust the Ingress so that `curl -H "Host: api.example.test" http://localhost/api/v1` returns `api-v1-endpoint`.

**Verification:**

```bash
sleep 3
curl -s -H "Host: api.example.test" http://localhost/api/v1
# Expected: api-v1-endpoint
```

---

## Level 4: Configuration and Design

### Exercise 4.1

**Objective:** Create an Ingress with multiple paths and a catchall, combined with the `defaultBackend`.

**Setup:**

```bash
kubectl create namespace ex-4-1
kubectl apply -n ex-4-1 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: svc-x}
spec:
  replicas: 1
  selector: {matchLabels: {app: x}}
  template:
    metadata: {labels: {app: x}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /etc/nginx/conf.d}]}
      volumes: [{name: h, configMap: {name: x-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: x-html}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        return 200 "x-reply";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: svc-x}
spec: {selector: {app: x}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: svc-y}
spec:
  replicas: 1
  selector: {matchLabels: {app: y}}
  template:
    metadata: {labels: {app: y}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /etc/nginx/conf.d}]}
      volumes: [{name: h, configMap: {name: y-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: y-html}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        return 200 "y-reply";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: svc-y}
spec: {selector: {app: y}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: svc-default}
spec:
  replicas: 1
  selector: {matchLabels: {app: default}}
  template:
    metadata: {labels: {app: default}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /etc/nginx/conf.d}]}
      volumes: [{name: h, configMap: {name: default-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: default-html}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        return 200 "default-reply";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: svc-default}
spec: {selector: {app: default}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-4-1 rollout status deployment/svc-x deployment/svc-y deployment/svc-default --timeout=60s
```

> **Note:** This exercise uses a `defaultBackend`, which conflicts with the one created in exercise 2.3. Delete that namespace before starting: `kubectl delete namespace ex-2-3`

**Task:** Create two Ingress resources in namespace `ex-4-1`. The first, named `four-one-routes`, has ingressClassName `traefik`, annotation `traefik.ingress.kubernetes.io/router.priority: "10"`, and two rules under host `app.example.test`: path `/x` (Prefix) -> `svc-x`, path `/y` (Prefix) -> `svc-y`. The second, named `four-one-fallback`, has ingressClassName `traefik`, annotation `traefik.ingress.kubernetes.io/router.priority: "1"`, and only a `defaultBackend` pointing at `svc-default`. Requests to `/z` (or any unmatched path or host) fall through to the catch-all fallback.

**Verification:**

```bash
sleep 3
curl -s -H "Host: app.example.test" http://192.168.200.12:32080/x
# Expected: x-reply

curl -s -H "Host: app.example.test" http://192.168.200.12:32080/y
# Expected: y-reply

curl -s -H "Host: app.example.test" http://192.168.200.12:32080/z
# Expected: default-reply
```

---

### Exercise 4.2

**Objective:** Create two Ingresses using different IngressClasses and confirm only Traefik's Ingress is served (since only Traefik is installed).

**Setup:**

```bash
kubectl create namespace ex-4-2

kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata: {name: future-controller}
spec:
  controller: example.com/future
EOF

kubectl apply -n ex-4-2 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: present}
spec:
  replicas: 1
  selector: {matchLabels: {app: present}}
  template:
    metadata: {labels: {app: present}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: present-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: present-html}
data: {index.html: "present-reply\n"}
---
apiVersion: v1
kind: Service
metadata: {name: present}
spec: {selector: {app: present}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-4-2 rollout status deployment/present --timeout=60s
```

**Task:** Create two Ingresses in namespace `ex-4-2` on host `two-classes.example.test` path `/`: one with `ingressClassName: traefik` and Service `present`, another with `ingressClassName: future-controller` and Service `present`. Confirm only the traefik one has an ADDRESS (the other is ignored because no controller owns `future-controller`).

**Verification:**

```bash
sleep 5
kubectl get ingress -n ex-4-2

curl -s -H "Host: two-classes.example.test" http://localhost/
# Expected: present-reply

# The future-controller Ingress has no ADDRESS; verify:
kubectl get ingress -n ex-4-2 -o jsonpath='{range .items[?(@.spec.ingressClassName=="future-controller")]}{.metadata.name}:{.status.loadBalancer.ingress}{"\n"}{end}'
# Expected: one line with no loadBalancer.ingress populated
```

---

### Exercise 4.3

**Objective:** Route the same hostname to different Services for different paths, using a single Ingress with explicit path types.

**Setup:**

```bash
kubectl create namespace ex-4-3
kubectl apply -n ex-4-3 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: api-v1}
spec:
  replicas: 1
  selector: {matchLabels: {app: api-v1}}
  template:
    metadata: {labels: {app: api-v1}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /etc/nginx/conf.d}]}
      volumes: [{name: h, configMap: {name: api-v1-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: api-v1-html}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        return 200 "api-v1-response";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: api-v1}
spec: {selector: {app: api-v1}, ports: [{port: 80, targetPort: 80}]}
---
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
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /etc/nginx/conf.d}]}
      volumes: [{name: h, configMap: {name: api-v2-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: api-v2-html}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        return 200 "api-v2-response";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: api-v2}
spec: {selector: {app: api-v2}, ports: [{port: 80, targetPort: 80}]}
EOF
kubectl -n ex-4-3 rollout status deployment/api-v1 deployment/api-v2 --timeout=60s
```

**Task:** Create Ingress `versioned` with host `versioned.example.test`: `/api/v1` (Prefix) -> Service `api-v1`, `/api/v2` (Prefix) -> Service `api-v2`.

**Verification:**

```bash
sleep 3
curl -s -H "Host: versioned.example.test" http://localhost/api/v1
# Expected: api-v1-response

curl -s -H "Host: versioned.example.test" http://localhost/api/v2
# Expected: api-v2-response

curl -sI -H "Host: versioned.example.test" http://localhost/api/v3
# Expected: HTTP/1.1 404 Not Found
```

---

## Level 5: Advanced

### Exercise 5.1

**Objective:** Author an Ingress with many routing rules across multiple hosts and paths for a small web application (marketing site, API, admin UI, static assets, health).

**Setup:**

```bash
kubectl create namespace ex-5-1

# Create five backend Services
for svc in marketing api admin; do
  kubectl apply -n ex-5-1 -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: {name: $svc}
spec:
  replicas: 1
  selector: {matchLabels: {app: $svc}}
  template:
    metadata: {labels: {app: $svc}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: $svc-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: $svc-html}
data: {index.html: "$svc-response\n"}
---
apiVersion: v1
kind: Service
metadata: {name: $svc}
spec: {selector: {app: $svc}, ports: [{port: 80, targetPort: 80}]}
EOF
done

# static and health are served at sub-paths; use return 200 so nginx responds
# regardless of which path Traefik forwards (avoids nginx directory redirect)
kubectl apply -n ex-5-1 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: static}
spec:
  replicas: 1
  selector: {matchLabels: {app: static}}
  template:
    metadata: {labels: {app: static}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /etc/nginx/conf.d}]}
      volumes: [{name: h, configMap: {name: static-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: static-html}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        return 200 "static-response";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: static}
spec: {selector: {app: static}, ports: [{port: 80, targetPort: 80}]}
EOF

kubectl apply -n ex-5-1 -f - <<'EOF'
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
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /etc/nginx/conf.d}]}
      volumes: [{name: h, configMap: {name: health-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: health-html}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        return 200 "health-response";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: health}
spec: {selector: {app: health}, ports: [{port: 80, targetPort: 80}]}
EOF
sleep 5
kubectl -n ex-5-1 wait --for=condition=Available deployment --all --timeout=120s
```

**Task:** Create a single Ingress `webapp` with host `www.webapp.example.test` with `/` (Prefix) -> `marketing` and `/static` (Prefix) -> `static`, host `api.webapp.example.test` with `/` (Prefix) -> `api`, host `admin.webapp.example.test` with `/` (Prefix) -> `admin`, and host `health.webapp.example.test` with `/healthz` (Exact) -> `health`.

**Verification:**

```bash
sleep 3
for test in "www.webapp.example.test/:marketing-response" \
            "www.webapp.example.test/static:static-response" \
            "api.webapp.example.test/:api-response" \
            "admin.webapp.example.test/:admin-response" \
            "health.webapp.example.test/healthz:health-response"; do
  host="${test%%/*}"
  path="/${test#*/}"; path="${path%:*}"
  expected="${test##*:}"
  result=$(curl -s -H "Host: $host" "http://localhost$path")
  echo "$host$path -> $result (expected: $expected)"
done
# Expected: each line shows the matching response
```

---

### Exercise 5.2

**Objective:** Diagnose a compound Ingress failure with three issues. Fix all three.

**Setup:**

```bash
kubectl create namespace ex-5-2
kubectl apply -n ex-5-2 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: real-svc}
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
data:
  default.conf: |
    server {
      listen 80;
      location /v1/status { return 200 "healthy-v1"; }
    }
---
apiVersion: v1
kind: Service
metadata: {name: real-svc}
spec: {selector: {app: real}, ports: [{port: 80, targetPort: 80}]}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: {name: broken}
spec:
  ingressClassName: nginx
  rules:
  - host: cascading.example.test
    http:
      paths:
      - {path: /v1/status, pathType: Exact, backend: {service: {name: fake-svc, port: {number: 80}}}}
EOF

kubectl patch deployment -n ex-5-2 real-svc --type='json' -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts","value":[{"name":"conf","mountPath":"/etc/nginx/conf.d"}]},
  {"op":"add","path":"/spec/template/spec/volumes","value":[{"name":"conf","configMap":{"name":"real-html","items":[{"key":"default.conf","path":"default.conf"}]}}]}
]'
kubectl -n ex-5-2 rollout status deployment/real-svc --timeout=60s
```

**Task:** Fix the Ingress so that `curl -H "Host: cascading.example.test" http://localhost/v1/status` returns `healthy-v1`.

**Verification:**

```bash
sleep 3
curl -s -H "Host: cascading.example.test" http://localhost/v1/status
# Expected: healthy-v1
```

---

### Exercise 5.3

**Objective:** Design and apply an Ingress strategy for a production-style two-service application with health, API, and UI: separate Ingress resources for health-check isolation and per-service autonomy.

**Setup:**

```bash
kubectl create namespace ex-5-3

# ui is served at / so root mountPath is correct
kubectl apply -n ex-5-3 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: ui}
spec:
  replicas: 2
  selector: {matchLabels: {app: ui}}
  template:
    metadata: {labels: {app: ui}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /usr/share/nginx/html}]}
      volumes: [{name: h, configMap: {name: ui-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: ui-html}
data: {index.html: "ui-v1\n"}
---
apiVersion: v1
kind: Service
metadata: {name: ui}
spec: {selector: {app: ui}, ports: [{port: 80, targetPort: 80}]}
EOF

# api and health are served at sub-paths; use return 200 so nginx responds
# regardless of which path Traefik forwards (avoids nginx directory redirect)
kubectl apply -n ex-5-3 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: api}
spec:
  replicas: 2
  selector: {matchLabels: {app: api}}
  template:
    metadata: {labels: {app: api}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /etc/nginx/conf.d}]}
      volumes: [{name: h, configMap: {name: api-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: api-html}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        return 200 "api-v1";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: api}
spec: {selector: {app: api}, ports: [{port: 80, targetPort: 80}]}
EOF

kubectl apply -n ex-5-3 -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: health}
spec:
  replicas: 2
  selector: {matchLabels: {app: health}}
  template:
    metadata: {labels: {app: health}}
    spec:
      containers:
      - {name: n, image: nginx:1.27, volumeMounts: [{name: h, mountPath: /etc/nginx/conf.d}]}
      volumes: [{name: h, configMap: {name: health-html}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: health-html}
data:
  default.conf: |
    server {
      listen 80;
      location / {
        return 200 "health-v1";
      }
    }
---
apiVersion: v1
kind: Service
metadata: {name: health}
spec: {selector: {app: health}, ports: [{port: 80, targetPort: 80}]}
EOF
sleep 5
kubectl -n ex-5-3 wait --for=condition=Available deployment --all --timeout=120s
```

**Task:** In namespace `ex-5-3`, create three Ingress resources, one per service, all on the same host `company.example.test`:

- `api-ingress` routes `/api` (Prefix) to `api`.
- `ui-ingress` routes `/` (Prefix) to `ui`.
- `health-ingress` routes `/healthz` (Exact) to `health`.

Having three separate resources lets each team own their own Ingress independently.

**Verification:**

```bash
sleep 3
curl -s -H "Host: company.example.test" http://localhost/healthz
# Expected: health-v1

curl -s -H "Host: company.example.test" http://localhost/api
# Expected: api-v1

curl -s -H "Host: company.example.test" http://localhost/
# Expected: ui-v1

kubectl get ingress -n ex-5-3 | wc -l
# Expected: 4 (3 Ingresses plus the header line)
```

---

## Cleanup

```bash
for ns in ex-1-1 ex-1-2 ex-1-3 ex-2-1 ex-2-2 ex-2-3 ex-3-1 ex-3-2 ex-3-3 \
         ex-4-1 ex-4-2 ex-4-3 ex-5-1 ex-5-2 ex-5-3; do
  kubectl delete namespace "$ns" --ignore-not-found
done

kubectl delete ingressclass future-controller --ignore-not-found
```

To fully remove the Traefik install (keep it installed if continuing to assignment 2 or 5):

```bash
helm uninstall -n traefik traefik
kubectl delete namespace traefik
```

## Key Takeaways

The Ingress v1 API is universal across implementations; the same YAML with only `ingressClassName` changed would work under any conformant controller. Traefik v3.6.13 watches Ingresses tagged `ingressClassName: traefik`. `pathType: Prefix` is the default choice; `Exact` matches only the literal path. `defaultBackend` catches unmatched requests on that specific Ingress. An Ingress with no matching IngressClass stays with an empty ADDRESS and is ignored silently. Debugging starts with `kubectl get ingress` (check ADDRESS), `kubectl describe ingress`, and `kubectl get endpoints` for the backend Services. The `Host:` header in curl substitutes for real DNS resolution.
