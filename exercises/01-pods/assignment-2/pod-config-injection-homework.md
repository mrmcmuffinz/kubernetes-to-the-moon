# Homework: Pod Configuration Injection

Fifteen progressive exercises on ConfigMaps, Secrets, and the four main injection patterns (single env var, bulk env vars, volume mounts, projected volumes). Work through the companion `pod-config-injection-tutorial.md` first if you have not already. That tutorial introduces every pattern used here with a single worked example.

Each exercise is self-contained in its own namespace, so you can do them in any order, though the difficulty is progressive and the suggested order is top to bottom. Copy-paste the setup commands to prepare the environment, read the objective, do the task, and then run the verification commands and check the expected outputs.

## Global Setup

Verify the cluster before starting:

```bash
kubectl cluster-info
kubectl get nodes
```

Both should succeed. Reset your default namespace to `default` in case a previous session left you in a different one:

```bash
kubectl config set-context --current --namespace=default
```

Optional global cleanup (removes all exercise namespaces if you want to start fresh):

```bash
for ns in ex-1-1 ex-1-2 ex-1-3 ex-2-1 ex-2-2 ex-2-3 ex-3-1 ex-3-2 ex-3-3 ex-4-1 ex-4-2 ex-4-3 ex-5-1 ex-5-2 ex-5-3; do
  kubectl delete namespace $ns --ignore-not-found --wait=false
done
```

## Level 1: Basic Single-Concept Tasks

### Exercise 1.1

**Setup:**

```bash
kubectl create namespace ex-1-1
```

**Objective:** Create a ConfigMap named `app-settings` in namespace `ex-1-1` with two keys: `GREETING=hello` and `AUDIENCE=world`. Create a pod named `greeter` using image `busybox:1.36` that runs the command `sh -c 'echo "$GREETING, $AUDIENCE"; sleep 3600'`. Inject both keys as environment variables with matching names, using the bulk-import pattern (one `envFrom` entry, not two individual `env` entries). The pod should write `hello, world` to its logs.

**Verification:**

```bash
kubectl -n ex-1-1 get configmap app-settings -o jsonpath='{.data}' ; echo
# Expected: {"AUDIENCE":"world","GREETING":"hello"}

kubectl -n ex-1-1 wait --for=condition=Ready pod/greeter --timeout=60s
# Expected: pod/greeter condition met

kubectl -n ex-1-1 logs greeter
# Expected: hello, world
```

### Exercise 1.2

**Setup:**

```bash
kubectl create namespace ex-1-2
```

**Objective:** Create a generic Secret named `api-creds` in namespace `ex-1-2` with a single key `API_KEY` whose value is `sk-test-9f8e7d6c5b4a3210`. Create a pod named `api-consumer` using image `busybox:1.36` that runs `sh -c 'echo "key length: ${#API_KEY}"; sleep 3600'`. Expose only the `API_KEY` key from the Secret as a single environment variable named `API_KEY` in the container. The log output should report that the key is 24 characters long.

**Verification:**

```bash
kubectl -n ex-1-2 get secret api-creds -o jsonpath='{.data.API_KEY}' | base64 -d ; echo
# Expected: sk-test-9f8e7d6c5b4a3210

kubectl -n ex-1-2 wait --for=condition=Ready pod/api-consumer --timeout=60s
# Expected: pod/api-consumer condition met

kubectl -n ex-1-2 logs api-consumer
# Expected: key length: 24

kubectl -n ex-1-2 exec api-consumer -- printenv API_KEY
# Expected: sk-test-9f8e7d6c5b4a3210
```

### Exercise 1.3

**Setup:**

```bash
kubectl create namespace ex-1-3
mkdir -p /tmp/ex-1-3
cat > /tmp/ex-1-3/server.conf <<'EOF'
listen 0.0.0.0:8080
worker_threads 4
max_connections 1024
EOF
```

**Objective:** Create a ConfigMap named `server-config` in namespace `ex-1-3` from the file at `/tmp/ex-1-3/server.conf` using the imperative `kubectl create configmap --from-file` form. Create a pod named `config-reader` using image `busybox:1.36` that runs `sh -c 'cat /etc/server/server.conf; sleep 3600'`. Mount the ConfigMap as a volume at `/etc/server` so that `server.conf` appears as a file at that path.

**Verification:**

```bash
kubectl -n ex-1-3 get configmap server-config -o jsonpath='{.data.server\.conf}'
# Expected: listen 0.0.0.0:8080
#           worker_threads 4
#           max_connections 1024

kubectl -n ex-1-3 wait --for=condition=Ready pod/config-reader --timeout=60s
# Expected: pod/config-reader condition met

kubectl -n ex-1-3 exec config-reader -- cat /etc/server/server.conf
# Expected: matching contents of the original file

kubectl -n ex-1-3 logs config-reader
# Expected: the file contents
```

## Level 2: Multi-Concept Tasks

### Exercise 2.1

**Setup:**

```bash
kubectl create namespace ex-2-1
```

**Objective:** Create a ConfigMap named `web-config` with keys `SERVER_NAME=webapp.example.com` and `LOG_LEVEL=debug`. Create a Secret named `web-creds` with keys `DB_USER=webuser` and `DB_PASSWORD=correct-horse-battery-staple`. Create a pod named `web` using image `busybox:1.36` running `sh -c 'env | grep -E "^(SERVER_NAME|LOG_LEVEL|DB_USER|DB_PASSWORD)=" | sort; sleep 3600'`. The pod should receive `SERVER_NAME` and `LOG_LEVEL` as env vars from the ConfigMap, and `DB_USER` and `DB_PASSWORD` as env vars from the Secret, using bulk-import for both.

**Verification:**

```bash
kubectl -n ex-2-1 wait --for=condition=Ready pod/web --timeout=60s
# Expected: pod/web condition met

kubectl -n ex-2-1 exec web -- printenv SERVER_NAME LOG_LEVEL DB_USER DB_PASSWORD
# Expected (each on its own line, in order):
# webapp.example.com
# debug
# webuser
# correct-horse-battery-staple

kubectl -n ex-2-1 logs web
# Expected: all four variables listed alphabetically
```

### Exercise 2.2

**Setup:**

```bash
kubectl create namespace ex-2-2
```

**Objective:** Create a ConfigMap named `nginx-config` in namespace `ex-2-2` with four keys: `server.conf` (value `server { listen 80; }`), `proxy.conf` (value `proxy_pass http://backend;`), `ssl.conf` (value `ssl_protocols TLSv1.2 TLSv1.3;`), and `cache.conf` (value `proxy_cache_valid 200 1h;`). Create a pod named `nginx-sel` using image `busybox:1.36` running `sh -c 'ls /etc/nginx/selected; echo "---"; cat /etc/nginx/selected/default.conf; cat /etc/nginx/selected/tls.conf; sleep 3600'`. Mount the ConfigMap as a volume at `/etc/nginx/selected`, but only the `server.conf` and `ssl.conf` keys should appear in the volume. `server.conf` should be renamed to `default.conf` and `ssl.conf` should be renamed to `tls.conf` on disk. The other two keys must not appear in the mount.

**Verification:**

```bash
kubectl -n ex-2-2 wait --for=condition=Ready pod/nginx-sel --timeout=60s
# Expected: pod/nginx-sel condition met

kubectl -n ex-2-2 exec nginx-sel -- ls /etc/nginx/selected
# Expected (only these two files, alphabetical):
# default.conf
# tls.conf

kubectl -n ex-2-2 exec nginx-sel -- cat /etc/nginx/selected/default.conf
# Expected: server { listen 80; }

kubectl -n ex-2-2 exec nginx-sel -- cat /etc/nginx/selected/tls.conf
# Expected: ssl_protocols TLSv1.2 TLSv1.3;

kubectl -n ex-2-2 exec nginx-sel -- test ! -f /etc/nginx/selected/proxy.conf && echo "ok: proxy.conf not present"
# Expected: ok: proxy.conf not present

kubectl -n ex-2-2 exec nginx-sel -- test ! -f /etc/nginx/selected/cache.conf && echo "ok: cache.conf not present"
# Expected: ok: cache.conf not present
```

### Exercise 2.3

**Setup:**

```bash
kubectl create namespace ex-2-3
```

**Objective:** Create a ConfigMap named `app-config` with one key `app.yaml` whose value is a multi-line YAML document:

```
mode: production
workers: 8
timeouts:
  read: 30s
  write: 30s
```

Create a Secret named `app-secret` with one key `TOKEN` whose value is `tok-abc-123-xyz-789`. Create a pod named `app-pod` using image `nginx:1.25-alpine`. Mount the `app.yaml` key from the ConfigMap as a single file at `/etc/nginx/app.yaml` using `subPath`, so the rest of `/etc/nginx` (including `nginx.conf`) remains unchanged and nginx still starts normally. Expose the Secret's `TOKEN` key as an environment variable named `APP_TOKEN` in the container. The pod should reach Running state (nginx's default startup) without any restarts.

**Verification:**

```bash
kubectl -n ex-2-3 wait --for=condition=Ready pod/app-pod --timeout=60s
# Expected: pod/app-pod condition met

kubectl -n ex-2-3 get pod app-pod -o jsonpath='{.status.containerStatuses[0].restartCount}' ; echo
# Expected: 0

kubectl -n ex-2-3 exec app-pod -- cat /etc/nginx/app.yaml
# Expected: the five-line YAML document from the ConfigMap

kubectl -n ex-2-3 exec app-pod -- ls /etc/nginx/ | grep -c '^nginx.conf$'
# Expected: 1  (the original nginx.conf is still there, not shadowed)

kubectl -n ex-2-3 exec app-pod -- printenv APP_TOKEN
# Expected: tok-abc-123-xyz-789

kubectl -n ex-2-3 exec app-pod -- nginx -t 2>&1 | tail -1
# Expected: nginx: configuration file /etc/nginx/nginx.conf test is successful
```

## Level 3: Debugging Broken Configurations

### Exercise 3.1

**Setup:**

```bash
kubectl create namespace ex-3-1

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: env-config
  namespace: ex-3-1
data:
  APP_NAME: billing
  APP_ENV: prod
  MAX_CONNS: "100"
---
apiVersion: v1
kind: Pod
metadata:
  name: billing
  namespace: ex-3-1
spec:
  restartPolicy: Never
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "env | grep -E '^(APP_|MAX_)' | sort; sleep 3600"]
      env:
        - name: APP_NAME
          valueFrom:
            configMapKeyRef:
              name: env-config
              key: APP_NAME
        - name: APP_ENV
          valueFrom:
            configMapKeyRef:
              name: env-config
              key: APP_ENVIRONMENT
        - name: MAX_CONNS
          valueFrom:
            configMapKeyRef:
              name: env-config
              key: MAX_CONNS
EOF
```

**Objective:** The setup above has one or more problems that prevent the pod `billing` in namespace `ex-3-1` from reaching Running state. Find and fix whatever is needed so that the pod runs successfully and all three environment variables (`APP_NAME`, `APP_ENV`, `MAX_CONNS`) have their expected values inside the container.

**Verification:**

```bash
kubectl -n ex-3-1 wait --for=condition=Ready pod/billing --timeout=60s
# Expected: pod/billing condition met

kubectl -n ex-3-1 exec billing -- printenv APP_NAME APP_ENV MAX_CONNS
# Expected (each on its own line):
# billing
# prod
# 100
```

### Exercise 3.2

**Setup:**

```bash
kubectl create namespace ex-3-2

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
  namespace: ex-3-2
type: Opaque
data:
  DATABASE_URL: postgres://user:pass@db.internal:5432/billing
  API_TOKEN: dG9rLTQyMDY5
---
apiVersion: v1
kind: Pod
metadata:
  name: consumer
  namespace: ex-3-2
spec:
  restartPolicy: Never
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo DB=$DATABASE_URL; echo TOKEN=$API_TOKEN; sleep 3600"]
      envFrom:
        - secretRef:
            name: app-secret
EOF
```

Note: The setup above may produce an error when applied. That error is part of what you are debugging. Read it carefully before fixing.

**Objective:** The setup above has one or more problems. Find and fix whatever is needed so that the pod `consumer` in namespace `ex-3-2` reaches Running state and its logs show the correct decoded values for both `DATABASE_URL` (which should be `postgres://user:pass@db.internal:5432/billing`) and `API_TOKEN` (which should be `tok-42069`).

**Verification:**

```bash
kubectl -n ex-3-2 wait --for=condition=Ready pod/consumer --timeout=60s
# Expected: pod/consumer condition met

kubectl -n ex-3-2 exec consumer -- printenv DATABASE_URL
# Expected: postgres://user:pass@db.internal:5432/billing

kubectl -n ex-3-2 exec consumer -- printenv API_TOKEN
# Expected: tok-42069

kubectl -n ex-3-2 logs consumer | head -2
# Expected:
# DB=postgres://user:pass@db.internal:5432/billing
# TOKEN=tok-42069
```

### Exercise 3.3

**Setup:**

```bash
kubectl create namespace ex-3-3

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: files-config
  namespace: ex-3-3
data:
  app.conf: |
    mode=production
    workers=4
  logging.conf: |
    level=info
    format=json
  features.conf: |
    new_ui=true
---
apiVersion: v1
kind: Pod
metadata:
  name: filereader
  namespace: ex-3-3
spec:
  restartPolicy: Never
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "cat /etc/app/main.conf; echo '---'; cat /etc/app/logs.conf; sleep 3600"]
      volumeMounts:
        - name: cfg
          mountPath: /etc/app
          readOnly: true
  volumes:
    - name: cfg
      configMap:
        name: files-config
        items:
          - key: app.conf
            path: /main.conf
          - key: logging.conf
            path: logs.conf
EOF
```

Note: The setup above may produce an error when applied. That error is part of what you are debugging.

**Objective:** The setup above has one or more problems. Find and fix whatever is needed so that the pod `filereader` in namespace `ex-3-3` reaches Running state and its logs show the contents of the app config followed by a separator followed by the contents of the logging config.

**Verification:**

```bash
kubectl -n ex-3-3 wait --for=condition=Ready pod/filereader --timeout=60s
# Expected: pod/filereader condition met

kubectl -n ex-3-3 exec filereader -- ls /etc/app
# Expected (two files, alphabetical):
# logs.conf
# main.conf

kubectl -n ex-3-3 exec filereader -- cat /etc/app/main.conf
# Expected:
# mode=production
# workers=4

kubectl -n ex-3-3 exec filereader -- cat /etc/app/logs.conf
# Expected:
# level=info
# format=json

kubectl -n ex-3-3 logs filereader
# Expected: main.conf contents, then "---", then logs.conf contents
```

## Level 4: Complex Real-World Scenarios

### Exercise 4.1

**Setup:**

```bash
kubectl create namespace ex-4-1
```

**Objective:** Build a realistic nginx configuration using the `/etc/nginx/conf.d/*.conf` include pattern. Create a ConfigMap named `nginx-sites` in namespace `ex-4-1` with three keys: `default.conf`, `api.conf`, and `admin.conf`. Each should be a valid nginx server block. Use these contents:

`default.conf`:
```
server { listen 80 default_server; server_name _; return 200 "default\n"; }
```

`api.conf`:
```
server { listen 80; server_name api.example.com; location / { return 200 "api\n"; } }
```

`admin.conf`:
```
server { listen 80; server_name admin.example.com; location / { return 200 "admin\n"; } }
```

Create a pod named `nginx-pod` in namespace `ex-4-1` using image `nginx:1.25-alpine`. Mount the ConfigMap as a full volume at `/etc/nginx/conf.d` so that all three files are present. Nginx's default configuration includes files in `/etc/nginx/conf.d/*.conf`, so it will load all three server blocks automatically. The pod must reach Running state with nginx configuration valid.

**Verification:**

```bash
kubectl -n ex-4-1 get configmap nginx-sites -o jsonpath='{.data}' | grep -o 'server ' | wc -l
# Expected: 3

kubectl -n ex-4-1 wait --for=condition=Ready pod/nginx-pod --timeout=60s
# Expected: pod/nginx-pod condition met

kubectl -n ex-4-1 exec nginx-pod -- ls /etc/nginx/conf.d | sort
# Expected (alphabetical):
# admin.conf
# api.conf
# default.conf

kubectl -n ex-4-1 exec nginx-pod -- nginx -t 2>&1 | tail -1
# Expected: nginx: configuration file /etc/nginx/nginx.conf test is successful

kubectl -n ex-4-1 exec nginx-pod -- sh -c 'wget -qO- --header="Host: api.example.com" http://localhost/'
# Expected: api

kubectl -n ex-4-1 exec nginx-pod -- sh -c 'wget -qO- --header="Host: admin.example.com" http://localhost/'
# Expected: admin

kubectl -n ex-4-1 exec nginx-pod -- sh -c 'wget -qO- --header="Host: something-else.com" http://localhost/'
# Expected: default

kubectl -n ex-4-1 get pod nginx-pod -o jsonpath='{.status.containerStatuses[0].restartCount}' ; echo
# Expected: 0
```

### Exercise 4.2

**Setup:**

```bash
kubectl create namespace ex-4-2
```

**Objective:** Build a projected volume pod that represents a typical application deployment. Create a ConfigMap named `app-cfg` in namespace `ex-4-2` with two keys: `app.yaml` (value: `server:\n  port: 8080\n  host: 0.0.0.0\n`) and `LOG_LEVEL` (value: `info`). Create a Secret named `app-secrets` in namespace `ex-4-2` with two keys: `db-password` (value: `super-secret-db-pw`) and `api-key` (value: `sk-prod-abcdef`). Create a pod named `app` in namespace `ex-4-2` using image `busybox:1.36` running `sh -c 'ls -la /etc/app; echo "---"; find /etc/app -type f | sort; sleep 3600'`. Add the labels `app=billing` and `tier=backend` and the annotation `deploy-id=r-42` to the pod metadata.

Mount everything at `/etc/app` using a single projected volume with three sources. The projected volume should produce this layout on disk:

- `/etc/app/config/app.yaml` (from ConfigMap key `app.yaml`)
- `/etc/app/secrets/db-password` (from Secret key `db-password`, mode `0400`)
- `/etc/app/secrets/api-key` (from Secret key `api-key`, mode `0400`)
- `/etc/app/pod/name` (from downward API `metadata.name`)
- `/etc/app/pod/namespace` (from downward API `metadata.namespace`)
- `/etc/app/pod/labels` (from downward API `metadata.labels`)

Other keys (like `LOG_LEVEL` from the ConfigMap) should not appear in the volume. Set the projected volume's `defaultMode` to `0444` (anything not overridden gets owner+group+other read). Also expose `LOG_LEVEL` as an environment variable in the container named `LOG_LEVEL`, sourced from the ConfigMap.

**Verification:**

```bash
kubectl -n ex-4-2 wait --for=condition=Ready pod/app --timeout=60s
# Expected: pod/app condition met

kubectl -n ex-4-2 exec app -- find /etc/app -type f | sort
# Expected (exactly these six paths):
# /etc/app/config/app.yaml
# /etc/app/pod/labels
# /etc/app/pod/name
# /etc/app/pod/namespace
# /etc/app/secrets/api-key
# /etc/app/secrets/db-password

kubectl -n ex-4-2 exec app -- cat /etc/app/config/app.yaml
# Expected:
# server:
#   port: 8080
#   host: 0.0.0.0

kubectl -n ex-4-2 exec app -- cat /etc/app/secrets/db-password
# Expected: super-secret-db-pw

kubectl -n ex-4-2 exec app -- cat /etc/app/secrets/api-key
# Expected: sk-prod-abcdef

kubectl -n ex-4-2 exec app -- stat -c '%a %n' /etc/app/secrets/db-password
# Expected: 400 /etc/app/secrets/db-password

kubectl -n ex-4-2 exec app -- stat -c '%a %n' /etc/app/secrets/api-key
# Expected: 400 /etc/app/secrets/api-key

kubectl -n ex-4-2 exec app -- cat /etc/app/pod/name
# Expected: app

kubectl -n ex-4-2 exec app -- cat /etc/app/pod/namespace
# Expected: ex-4-2

kubectl -n ex-4-2 exec app -- cat /etc/app/pod/labels | sort
# Expected:
# app="billing"
# tier="backend"

kubectl -n ex-4-2 exec app -- printenv LOG_LEVEL
# Expected: info
```

### Exercise 4.3

**Setup:**

```bash
kubectl create namespace ex-4-3
```

**Objective:** Build a multi-container pod where both containers share a single ConfigMap but consume different keys at different paths. Create a ConfigMap named `shared-cfg` in namespace `ex-4-3` with four keys: `writer.conf` (value: `role=writer\nqueue=work-in\n`), `reader.conf` (value: `role=reader\nqueue=work-out\n`), `shared.conf` (value: `cluster=prod\nregion=us-east\n`), and `unused.conf` (value: `nothing=interesting\n`).

Create a pod named `duo` in namespace `ex-4-3` with two containers. The first container is named `writer`, uses image `busybox:1.36`, and runs `sh -c 'echo "writer view:"; ls /etc/writer; cat /etc/writer/role.conf; cat /etc/writer/common.conf; sleep 3600'`. The second container is named `reader`, uses image `busybox:1.36`, and runs `sh -c 'echo "reader view:"; ls /etc/reader; cat /etc/reader/role.conf; cat /etc/reader/common.conf; sleep 3600'`.

Both containers should mount from the same ConfigMap but see different contents. The `writer` container should have `writer.conf` mounted at `/etc/writer/role.conf` and `shared.conf` mounted at `/etc/writer/common.conf`. The `reader` container should have `reader.conf` mounted at `/etc/reader/role.conf` and `shared.conf` mounted at `/etc/reader/common.conf`. Neither container should see `unused.conf`, and neither should see the other container's role file.

**Verification:**

```bash
kubectl -n ex-4-3 wait --for=condition=Ready pod/duo --timeout=60s
# Expected: pod/duo condition met

kubectl -n ex-4-3 get pod duo -o jsonpath='{.spec.containers[*].name}' ; echo
# Expected: writer reader

kubectl -n ex-4-3 exec duo -c writer -- ls /etc/writer | sort
# Expected:
# common.conf
# role.conf

kubectl -n ex-4-3 exec duo -c writer -- cat /etc/writer/role.conf
# Expected:
# role=writer
# queue=work-in

kubectl -n ex-4-3 exec duo -c writer -- cat /etc/writer/common.conf
# Expected:
# cluster=prod
# region=us-east

kubectl -n ex-4-3 exec duo -c reader -- ls /etc/reader | sort
# Expected:
# common.conf
# role.conf

kubectl -n ex-4-3 exec duo -c reader -- cat /etc/reader/role.conf
# Expected:
# role=reader
# queue=work-out

kubectl -n ex-4-3 exec duo -c reader -- cat /etc/reader/common.conf
# Expected:
# cluster=prod
# region=us-east

kubectl -n ex-4-3 exec duo -c writer -- test ! -f /etc/writer/unused.conf && echo "ok: unused.conf hidden from writer"
# Expected: ok: unused.conf hidden from writer

kubectl -n ex-4-3 exec duo -c reader -- test ! -f /etc/reader/writer.conf && echo "ok: writer.conf hidden from reader"
# Expected: ok: writer.conf hidden from reader
```

## Level 5: Advanced Debugging and Comprehensive Tasks

### Exercise 5.1

**Setup:**

```bash
kubectl create namespace ex-5-1

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: runtime-cfg
  namespace: ex-5-1
immutable: true
data:
  mode: staging
  workers: "4"
---
apiVersion: v1
kind: Secret
metadata:
  name: runtime-creds
  namespace: ex-5-1
type: Opaque
data:
  username: YWRtaW4=
  password: s3cret-pw
stringData:
  username: operator
---
apiVersion: v1
kind: Pod
metadata:
  name: runtime
  namespace: ex-5-1
spec:
  restartPolicy: Never
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo MODE=$MODE; echo WORKERS=$WORKERS; echo USER=$USERNAME; echo PASS=$PASSWORD; sleep 3600"]
      env:
        - name: MODE
          valueFrom:
            configMapKeyRef:
              name: runtime-cfg
              key: mode
        - name: WORKERS
          valueFrom:
            configMapKeyRef:
              name: runtime-cfg
              key: workers
        - name: USERNAME
          valueFrom:
            secretKeyRef:
              name: runtime-creds
              key: username
        - name: PASSWORD
          valueFrom:
            secretKeyRef:
              name: runtime-creds
              key: password
EOF
```

Someone then wants to update the ConfigMap and runs:

```bash
kubectl -n ex-5-1 patch configmap runtime-cfg --type merge -p '{"data":{"mode":"production"}}' || true
```

Note: Some or all of the commands above may produce errors. Those errors are part of what you are debugging.

**Objective:** The setup above has several problems. Find and fix whatever is needed so that the pod `runtime` in namespace `ex-5-1` reaches Running state, the ConfigMap `runtime-cfg` reflects `mode: production` and `workers: "4"`, and the pod's logs show these four lines (in order): `MODE=production`, `WORKERS=4`, `USER=operator`, `PASS=s3cret-pw`. Note that the Secret is supposed to hold `username=operator` and `password=s3cret-pw` as the intended plaintext values.

**Verification:**

```bash
kubectl -n ex-5-1 get configmap runtime-cfg -o jsonpath='{.data.mode}' ; echo
# Expected: production

kubectl -n ex-5-1 get configmap runtime-cfg -o jsonpath='{.data.workers}' ; echo
# Expected: 4

kubectl -n ex-5-1 get secret runtime-creds -o jsonpath='{.data.username}' | base64 -d ; echo
# Expected: operator

kubectl -n ex-5-1 get secret runtime-creds -o jsonpath='{.data.password}' | base64 -d ; echo
# Expected: s3cret-pw

kubectl -n ex-5-1 wait --for=condition=Ready pod/runtime --timeout=60s
# Expected: pod/runtime condition met

kubectl -n ex-5-1 exec runtime -- printenv MODE WORKERS USERNAME PASSWORD
# Expected (each on its own line):
# production
# 4
# operator
# s3cret-pw

kubectl -n ex-5-1 logs runtime
# Expected:
# MODE=production
# WORKERS=4
# USER=operator
# PASS=s3cret-pw
```

### Exercise 5.2

**Setup:**

```bash
kubectl create namespace ex-5-2

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: base-cfg
  namespace: ex-5-2
data:
  app.properties: |
    mode=base
    feature.flags=none
  region: us-east
---
apiVersion: v1
kind: Secret
metadata:
  name: combined-creds
  namespace: ex-5-2
type: Opaque
stringData:
  db_password: db-pw-shh
  api_token: api-tok-shh
---
apiVersion: v1
kind: Pod
metadata:
  name: combined
  namespace: ex-5-2
spec:
  restartPolicy: Never
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "ls /etc/combined; echo '---'; cat /etc/combined/api-token; echo '---'; cat /etc/combined/app.properties; sleep 3600"]
      volumeMounts:
        - name: combined
          mountPath: /etc/combined
          readOnly: true
  volumes:
    - name: combined
      projected:
        sources:
          - configMap:
              name: base-cfg
              items:
                - key: app.properties
                  path: app.properties
                - key: region
                  path: /region
          - secret:
              name: combined-creds
              items:
                - key: db_password
                  path: db-password
                - key: api_token
                  path: api-token
          - secret:
              name: combined-creds
              items:
                - key: db_password
                  path: app.properties
EOF
```

Note: The setup above may produce an error when applied. That error is part of what you are debugging.

**Objective:** The setup above has several problems. Find and fix whatever is needed so that the pod `combined` in namespace `ex-5-2` reaches Running state and exposes all four pieces of data at these exact paths: `/etc/combined/app.properties` (the multi-line app properties from the ConfigMap), `/etc/combined/region` (value `us-east`), `/etc/combined/db-password` (value `db-pw-shh`), and `/etc/combined/api-token` (value `api-tok-shh`). No other files should exist under `/etc/combined`. The pod's logs should show the directory listing, the API token, and the app properties in that order.

**Verification:**

```bash
kubectl -n ex-5-2 wait --for=condition=Ready pod/combined --timeout=60s
# Expected: pod/combined condition met

kubectl -n ex-5-2 exec combined -- ls /etc/combined | sort
# Expected (exactly these four, alphabetical):
# api-token
# app.properties
# db-password
# region

kubectl -n ex-5-2 exec combined -- cat /etc/combined/app.properties
# Expected:
# mode=base
# feature.flags=none

kubectl -n ex-5-2 exec combined -- cat /etc/combined/region
# Expected: us-east

kubectl -n ex-5-2 exec combined -- cat /etc/combined/db-password
# Expected: db-pw-shh

kubectl -n ex-5-2 exec combined -- cat /etc/combined/api-token
# Expected: api-tok-shh

kubectl -n ex-5-2 exec combined -- sh -c 'ls /etc/combined | wc -l'
# Expected: 4
```

### Exercise 5.3

**Setup:**

```bash
kubectl create namespace ex-5-3
```

**Objective:** Build a three-tier application configuration. The scenario represents a single pod that behaves as one tier of a larger system; you are setting up its configuration the way a real production manifest would look, with shared base settings, a per-environment override layer, and per-component credentials.

Create three ConfigMaps and two Secrets in namespace `ex-5-3`:

- ConfigMap `base-config` with keys `APP_NAME=orders` and `REGION=us-east-1` (shared across all environments).
- ConfigMap `env-overrides-prod` with keys `LOG_LEVEL=warn` and `WORKERS=16` (production overrides).
- ConfigMap `component-web` with one key `web.yaml` whose value is a multi-line YAML document containing exactly these three lines: `listen: 0.0.0.0:8080`, `timeout: 30s`, `max_body: 10MB`.
- Secret `creds-db` (type Opaque) with keys `username=orders-db-user` and `password=db-tier-pw-2026`.
- Secret `creds-external-api` (type Opaque) with key `token=ext-api-tok-9x8y7z`.

Create a pod named `orders-web` in namespace `ex-5-3` using image `busybox:1.36` running `sh -c 'echo ENV:; env | grep -E "^(APP_NAME|REGION|LOG_LEVEL|WORKERS)=" | sort; echo FILES:; find /etc/orders -type f | sort; echo WEB-CONFIG:; cat /etc/orders/web/web.yaml; sleep 3600'`. Add labels `app=orders` and `component=web` to the pod metadata.

Inject configuration as follows:

- All keys of `base-config` and `env-overrides-prod` as environment variables, using two `envFrom` entries so that the override ConfigMap wins on any conflicting key (there is no conflict in this setup, but the order should be correct regardless).
- A projected volume mounted at `/etc/orders` with four sources: the `web.yaml` key of `component-web` placed at `web/web.yaml`, the two keys of `creds-db` placed under `secrets/db/` with the key names as filenames (so `secrets/db/username` and `secrets/db/password`), the `token` key of `creds-external-api` placed at `secrets/external-api/token`, and the pod's labels from the downward API placed at `pod/labels`.
- All files projected from Secrets should have mode `0400`. The projected volume's `defaultMode` should be `0444`.

**Verification:**

```bash
kubectl -n ex-5-3 get configmap base-config -o jsonpath='{.data.APP_NAME}' ; echo
# Expected: orders

kubectl -n ex-5-3 get configmap env-overrides-prod -o jsonpath='{.data.WORKERS}' ; echo
# Expected: 16

kubectl -n ex-5-3 get configmap component-web -o jsonpath='{.data.web\.yaml}'
# Expected: the three-line YAML document

kubectl -n ex-5-3 get secret creds-db -o jsonpath='{.data.password}' | base64 -d ; echo
# Expected: db-tier-pw-2026

kubectl -n ex-5-3 get secret creds-external-api -o jsonpath='{.data.token}' | base64 -d ; echo
# Expected: ext-api-tok-9x8y7z

kubectl -n ex-5-3 wait --for=condition=Ready pod/orders-web --timeout=60s
# Expected: pod/orders-web condition met

kubectl -n ex-5-3 exec orders-web -- printenv APP_NAME REGION LOG_LEVEL WORKERS
# Expected (each on its own line):
# orders
# us-east-1
# warn
# 16

kubectl -n ex-5-3 exec orders-web -- find /etc/orders -type f | sort
# Expected (exactly these five paths):
# /etc/orders/pod/labels
# /etc/orders/secrets/db/password
# /etc/orders/secrets/db/username
# /etc/orders/secrets/external-api/token
# /etc/orders/web/web.yaml

kubectl -n ex-5-3 exec orders-web -- cat /etc/orders/web/web.yaml
# Expected:
# listen: 0.0.0.0:8080
# timeout: 30s
# max_body: 10MB

kubectl -n ex-5-3 exec orders-web -- cat /etc/orders/secrets/db/username
# Expected: orders-db-user

kubectl -n ex-5-3 exec orders-web -- cat /etc/orders/secrets/db/password
# Expected: db-tier-pw-2026

kubectl -n ex-5-3 exec orders-web -- cat /etc/orders/secrets/external-api/token
# Expected: ext-api-tok-9x8y7z

kubectl -n ex-5-3 exec orders-web -- stat -c '%a' /etc/orders/secrets/db/password
# Expected: 400

kubectl -n ex-5-3 exec orders-web -- stat -c '%a' /etc/orders/secrets/external-api/token
# Expected: 400

kubectl -n ex-5-3 exec orders-web -- cat /etc/orders/pod/labels | sort
# Expected:
# app="orders"
# component="web"
```

## Cleanup

Per-namespace cleanup, one at a time:

```bash
kubectl delete namespace ex-1-1
kubectl delete namespace ex-1-2
kubectl delete namespace ex-1-3
kubectl delete namespace ex-2-1
kubectl delete namespace ex-2-2
kubectl delete namespace ex-2-3
kubectl delete namespace ex-3-1
kubectl delete namespace ex-3-2
kubectl delete namespace ex-3-3
kubectl delete namespace ex-4-1
kubectl delete namespace ex-4-2
kubectl delete namespace ex-4-3
kubectl delete namespace ex-5-1
kubectl delete namespace ex-5-2
kubectl delete namespace ex-5-3
```

Or remove everything in one loop:

```bash
for ns in ex-1-1 ex-1-2 ex-1-3 ex-2-1 ex-2-2 ex-2-3 ex-3-1 ex-3-2 ex-3-3 ex-4-1 ex-4-2 ex-4-3 ex-5-1 ex-5-2 ex-5-3; do
  kubectl delete namespace $ns --ignore-not-found --wait=false
done
```

Local scratch directory from Exercise 1.3:

```bash
rm -rf /tmp/ex-1-3
```

## Key Takeaways

The biggest mental model shift in this assignment is the difference between environment variables and volume-mounted files as injection targets. Environment variables are resolved once at container start. If the ConfigMap or Secret changes afterwards, the env var keeps its original value until the pod is restarted. Volume-mounted files are a kubelet-refreshed projection of the current state of the source, so the files on disk update (eventually, after the kubelet sync interval) when the ConfigMap or Secret changes. The one exception is `subPath` volume mounts, which resolve once at container start and do not receive updates. If you need live-updating file mounts, use full-volume or `items` mounts without `subPath`. If you need absolutely stable values that never change while the pod runs, mark the source ConfigMap or Secret as `immutable: true`, or inject via env vars.

Kubernetes Secrets are base64 encoded, not encrypted. A Secret YAML's `data` field carries base64-encoded bytes because the YAML type system cannot reliably carry arbitrary binary strings. The real security for Secrets comes from two layers that are not part of the Secret object itself: RBAC rules that restrict which identities can read Secret resources, and etcd encryption at rest that prevents offline disclosure of the backing store. Both are covered later in the CKA course under the Security section. For this assignment, treat Secrets as a typed envelope for carrying sensitive data through the pod spec, not as a cryptographic primitive.

When writing Secrets by hand in YAML, prefer `stringData` over `data`. The `stringData` field accepts plain strings and Kubernetes encodes them for you at apply time. If you do use `data` directly, always encode with `base64 -w0` so line wrapping does not insert literal newlines into your values. The older pattern of piping to `tr -d '\n'` works but is more error-prone; `-w0` solves the problem in one flag. If both `data` and `stringData` are specified and they set the same key, `stringData` wins.

Two imperative shortcuts are worth memorizing for exam speed. `kubectl create configmap NAME --from-literal=K=V --from-literal=K2=V2` creates a ConfigMap in one line. `kubectl create secret generic NAME --from-literal=K=V` does the same for an Opaque Secret and handles encoding automatically. Pair either with `--dry-run=client -o yaml` to generate a YAML skeleton you can pipe to a file and edit. This pattern (imperatively generate, then edit, then apply) is faster than writing YAML from scratch and is what the CKA exam expects you to be fluent in.

The four main injection patterns solve different problems. Use `env.valueFrom.configMapKeyRef` or `secretKeyRef` when you need one or a few specific values and want a custom environment variable name. Use `envFrom.configMapRef` or `secretRef` when you want every key as an env var with the key name used verbatim, keeping the manifest short. Use a volume mount (full, `items`, or `subPath`) when the application reads config from disk. Use a projected volume when you need multiple sources consolidated under one mount path, which is the production-realistic pattern for apps that want `/etc/app` to be the single source of configuration truth. The `optional: true` field on any of these makes a missing source or key silently degrade rather than failing the pod, which is useful for non-critical configuration.

Finally, diagnostic speed on the exam comes from knowing exactly which command reveals each failure mode. `kubectl describe pod NAME` and `kubectl get events` catch the classic `CreateContainerConfigError` from missing ConfigMaps or Secrets. `kubectl get configmap NAME -o yaml` and `kubectl get secret NAME -o yaml` catch structural mistakes in the source (wrong field names, bad encoding, wrong type). `kubectl exec NAME -- env` and `kubectl exec NAME -- cat /path` catch the "pod runs but the value is wrong" class of bugs where the YAML is valid but the reference points at the wrong key.
