# Killer Shell CKA Simulator B: Official Solutions

This document captures the official Killer.sh walkthroughs for Simulator B, pulled directly from the platform's solutions page. These are the platform's own worked answers, not your submitted work. This is a companion reference for comparing against `cka-simulator-b-results.md` (the score transcription) and `cka-simulator-b-remediation-plan.md` (the gap analysis), the same role `killer-sh-cka-simulator-a-solutions.md` played for Session 1.

**Companion documents:**
- `cka-simulator-b-results.md` (subtask-level score transcription)
- `cka-simulator-b-remediation-plan.md` (gap analysis and remediation steps, built from your own account of what happened)
- `killer-sh-cka-simulator-a-solutions.md` (Session 1's official solutions, for cross-reference on shared topics)

Once your actual submitted commands and YAML are recovered from the post-exam review environment, a `cka-simulator-b-my-submitted-solutions.md` should be built the same way Session 1's was, since per the standing principle, submitted work is authoritative over score feedback when the two disagree, and this official-solutions document is the comparison target for that submitted work, not a substitute for it.

---

## Question 1 | DNS / FQDN / Headless Service

**Solve on:** `ssh cka6016`

The Deployment `controller` in Namespace `lima-control` reaches several cluster-internal endpoints via DNS FQDNs. The ConfigMap backing the Deployment needed four corrected values:

1. `DNS_1`: the `kubernetes` Service in the `default` Namespace
2. `DNS_2`: the headless Service `department` in Namespace `lima-workload`
3. `DNS_3`: the Pod `section100` in Namespace `lima-workload`, resolvable even if the Pod IP changes
4. `DNS_4`: a Pod with IP `1.2.3.4` in Namespace `kube-system`

### Solution

The standard internal DNS form is `SERVICE.NAMESPACE.svc.cluster.local`, which resolves to the Service's ClusterIP. Because the question asks for full FQDNs, the shorter `SERVICE.NAMESPACE` form is not acceptable even though it would also work.

`DNS_1` is the easy one: `kubernetes.default.svc.cluster.local`, confirmed by `nslookup kubernetes.default.svc.cluster.local` returning the cluster's API server ClusterIP.

`DNS_2` follows the identical pattern for a headless Service: `department.lima-workload.svc.cluster.local`. A headless Service has no ClusterIP of its own, but a DNS lookup against it still returns results, in this case the IPs of each Pod sitting behind it. That works because the Service has real Endpoints even without a single virtual IP to front them.

`DNS_3` needs a different mechanism, since the requirement is that resolution survives the Pod's IP changing, which a plain IP-based record cannot do. The headless Service's Pods specify a `hostname` and `subdomain` field in their spec (the subdomain matching the Service name), and that combination produces a resolvable name of the form `HOSTNAME.SUBDOMAIN.NAMESPACE.svc.cluster.local`. For this Pod, that resolves to `section100.section.lima-workload.svc.cluster.local`. This only works because the Pod's manifest sets `hostname: section100` and `subdomain: section` explicitly; without those two fields, the Pod has no such DNS record at all.

`DNS_4` uses the pod-IP-to-FQDN form, `IP-WITH-DASHES.NAMESPACE.pod.cluster.local`, which Kubernetes resolves automatically without needing a Pod to actually exist at that address. For IP `1.2.3.4` in `kube-system`, that's `1-2-3-4.kube-system.pod.cluster.local`.

The ConfigMap update:

```yaml
apiVersion: v1
data:
  DNS_1: kubernetes.default.svc.cluster.local
  DNS_2: department.lima-workload.svc.cluster.local
  DNS_3: section100.section.lima-workload.svc.cluster.local
  DNS_4: 1-2-3-4.kube-system.pod.cluster.local
kind: ConfigMap
metadata:
  name: control-config
  namespace: lima-control
```

After editing, the Deployment needs a restart to pick up the new ConfigMap values, since environment variables sourced from a ConfigMap are not live-updated into already-running containers:

```bash
kubectl -n lima-control rollout restart deploy controller
```

---

## Question 2 | Create a Static Pod and Service

**Solve on:** `ssh cka2560`

Create a Static Pod `my-static-pod` in the `default` Namespace on the controlplane node, image `nginx:1-alpine`, CPU request `10m`, memory request `20Mi`. Expose it via a NodePort Service `static-pod-service` on port 80.

### Solution

Generate the Pod manifest and place it in the static pod manifests directory on the controlplane node:

```bash
sudo -i
cd /etc/kubernetes/manifests/
k run my-static-pod --image=nginx:1-alpine -o yaml --dry-run=client > my-static-pod.yaml
```

Add the resource requests to the generated file:

```yaml
# /etc/kubernetes/manifests/my-static-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: my-static-pod
  name: my-static-pod
spec:
  containers:
  - image: nginx:1-alpine
    name: my-static-pod
    resources:
      requests:
        cpu: 10m
        memory: 20Mi
  dnsPolicy: ClusterFirst
  restartPolicy: Always
```

The kubelet picks this up automatically and creates a Pod named `my-static-pod-cka2560` (the node hostname appended as a suffix, the standard static-pod naming convention). Confirm it's running, then expose it:

```bash
k expose pod my-static-pod-cka2560 --name static-pod-service --type=NodePort --port 80
```

Verify the Service has exactly one Endpoint and that the static Pod is reachable through the node's internal IP on the assigned NodePort.

---

## Question 3 | Kubelet Client/Server Certificate Info

**Solve on:** `ssh cka5248`

Node `cka5248-node1` joined via kubeadm and TLS bootstrapping. Find the Issuer and Extended Key Usage for both the kubelet client certificate (outgoing connections to kube-apiserver) and the kubelet server certificate (incoming connections from kube-apiserver), write both into `/opt/course/3/certificate-info.txt`.

### Solution

The two certificates are genuinely distinct files with distinct roles, and confusing them is the central trap of this question. SSH onto the worker node and locate the kubelet's PKI directory:

```bash
ssh cka5248-node1
sudo -i
find /var/lib/kubelet/pki
```

This typically surfaces `kubelet-client-current.pem` (the client certificate, used for the kubelet's own outbound authentication to the API server) and `kubelet.crt`/`kubelet.key` (the server certificate, used for inbound connections like `kubectl exec` or `kubectl logs` reaching the kubelet's own API).

Client certificate:

```bash
openssl x509 -noout -text -in /var/lib/kubelet/pki/kubelet-client-current.pem | grep Issuer
# Issuer: CN = kubernetes

openssl x509 -noout -text -in /var/lib/kubelet/pki/kubelet-client-current.pem | grep "Extended Key Usage" -A1
# X509v3 Extended Key Usage:
#     TLS Web Client Authentication
```

The client certificate's Issuer is `CN = kubernetes`, since it's issued by the cluster CA, and its Extended Key Usage is client authentication.

Server certificate:

```bash
openssl x509 -noout -text -in /var/lib/kubelet/pki/kubelet.crt | grep Issuer
# Issuer: CN = cka5248-node1-ca@<timestamp>

openssl x509 -noout -text -in /var/lib/kubelet/pki/kubelet.crt | grep "Extended Key Usage" -A1
# X509v3 Extended Key Usage:
#     TLS Web Server Authentication
```

The server certificate is self-generated on the worker node itself, hence the issuer CN carries the node's own hostname and a timestamp rather than `kubernetes`, and its Extended Key Usage is server authentication, the opposite of the client cert.

Write both into the target file:

```text
# /opt/course/3/certificate-info.txt
Issuer: CN = kubernetes
X509v3 Extended Key Usage: TLS Web Client Authentication
Issuer: CN = cka5248-node1-ca@<timestamp>
X509v3 Extended Key Usage: TLS Web Server Authentication
```

---

## Question 4 | Pod Ready if Service is Reachable

**Solve on:** `ssh cka3200`

In Namespace `default`: create Pod `ready-if-service-ready` (image `nginx:1-alpine`) with a LivenessProbe that just runs `true`, and a ReadinessProbe that checks reachability of `http://service-am-i-ready:80` via `wget -T2 -O- http://service-am-i-ready:80`. Confirm it starts not-ready. Then create a second Pod `am-i-ready` (image `nginx:1-alpine`, label `id: cross-server-ready`) so the existing Service `service-am-i-ready` gains that Pod as an Endpoint, and confirm the first Pod becomes ready.

### Solution

This is an intentional anti-pattern (a Pod's readiness gated on a separate Service it doesn't actually serve traffic for), included to exercise probe and Pod-to-Service DNS mechanics rather than as a recommended real-world design. Since `readinessProbe.httpGet` doesn't support arbitrary remote URLs, the workaround uses an `exec` probe running `wget` instead.

```yaml
# 4_pod1.yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: ready-if-service-ready
  name: ready-if-service-ready
spec:
  containers:
  - image: nginx:1-alpine
    name: ready-if-service-ready
    resources: {}
    livenessProbe:
      exec:
        command:
        - 'true'
    readinessProbe:
      exec:
        command:
        - sh
        - -c
        - 'wget -T2 -O- http://service-am-i-ready:80'
  dnsPolicy: ClusterFirst
  restartPolicy: Always
```

After creating it, `k get pod ready-if-service-ready` shows `0/1`, and `k describe pod` confirms the readiness probe is timing out trying to reach `service-am-i-ready`, since the Service currently has no matching Pods and therefore no Endpoints.

Create the second Pod with the label the Service selects on:

```bash
k run am-i-ready --image=nginx:1-alpine --labels="id=cross-server-ready"
```

Once that Pod exists, `k describe svc service-am-i-ready` shows a populated Endpoint, and after the next readiness-probe interval the first Pod flips to `1/1` Ready.

---

## Question 5 | Kubectl Sorting

**Solve on:** `ssh cka8448`

Write two scripts using `kubectl` sort flags: `/opt/course/5/find_pods.sh` listing all Pods across all Namespaces sorted by creation timestamp, and `/opt/course/5/find_pods_uid.sh` sorted by `metadata.uid` instead.

### Solution

```bash
# /opt/course/5/find_pods.sh
kubectl get pod -A --sort-by=.metadata.creationTimestamp
```

```bash
# /opt/course/5/find_pods_uid.sh
kubectl get pod -A --sort-by=.metadata.uid
```

Running each produces a visibly different ordering of the same Pod list, confirming the sort key actually changed the output rather than just being silently ignored.

---

## Question 6 | Fix Kubelet

**Solve on:** `ssh cka1024`

The kubelet on controlplane node `cka1024` isn't running. Fix it, confirm the node reaches Ready, then create Pod `success` (image `nginx:1-alpine`) in the `default` Namespace.

### Solution

`kubectl get node` initially fails outright with a connection-refused error against the API server, which is itself a symptom rather than the root cause, since the API server is also a static Pod managed by the same broken kubelet.

```bash
sudo -i
ps aux | grep kubelet            # no kubelet process running at all
service kubelet status           # confirms: inactive (dead)
service kubelet start
service kubelet status           # now: activating (auto-restart), Result: exit-code
```

The repeated auto-restart-then-exit pattern means the service definition itself is broken, not just stopped. Running the kubelet binary manually surfaces the real problem directly:

```bash
/usr/local/bin/kubelet
# -bash: /usr/local/bin/kubelet: No such file or directory

whereis kubelet
# kubelet: /usr/bin/kubelet
```

The systemd drop-in config points at the wrong binary path. Fix it in the kubeadm drop-in file:

```bash
vim /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf
```

Change the final `ExecStart=` line to use the correct path:

```
ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
```

Reload and restart:

```bash
systemctl daemon-reload
service kubelet restart
service kubelet status        # now: active (running)
```

Confirm the static-pod containers come up (`watch crictl ps` shows etcd, kube-apiserver, kube-scheduler, kube-controller-manager appearing within roughly 30 seconds), then confirm the node itself returns to Ready, which can lag a little behind the containers coming up. Finally create the requested Pod and confirm it lands on the now-healthy node.

---

## Question 7 | Etcd Operations

**Solve on:** `ssh cka2560`

Run `etcd --version`, write the output to `/opt/course/7/etcd-version`. Take an etcd snapshot to `/opt/course/7/etcd-snapshot.db`.

### Solution

`etcd` is not installed as a host binary on the controlplane; it runs as a static Pod, so the version command has to be run inside that Pod via `kubectl exec`:

```bash
sudo -i
k -n kube-system exec etcd-cka2560 -- etcd --version > /opt/course/7/etcd-version
```

For the snapshot, a bare `etcdctl snapshot save` against the default endpoint hangs or fails outright without TLS client credentials, since etcd requires mutual TLS for its client connections. The needed certificate paths are visible in the etcd static Pod manifest, the same flags the API server itself uses to talk to etcd:

```bash
cat /etc/kubernetes/manifests/etcd.yaml | grep -E 'cert-file|key-file|trusted-ca'
```

```bash
ETCDCTL_API=3 etcdctl snapshot save /opt/course/7/etcd-snapshot.db \
  --cacert /etc/kubernetes/pki/etcd/ca.crt \
  --cert /etc/kubernetes/pki/etcd/server.crt \
  --key /etc/kubernetes/pki/etcd/server.key
```

A successful run logs the snapshot being fetched and saved to the target path.

**Optional restore exercise** (high-risk if attempted on a live cluster, only worth doing on a disposable scratch environment): stop all four static control-plane Pods by moving their manifests out of `/etc/kubernetes/manifests/`, wait for the containers to actually disappear (`watch crictl ps`), restore the snapshot into a fresh data directory with `etcdutl snapshot restore` (note: as of etcd 3.6, the restore subcommand moved from `etcdctl` to the separate `etcdutl` binary), point the etcd manifest's data-dir volume at the restored directory, then move the manifests back in and wait for the control plane to come back. A test Pod created before the snapshot and a second one created after should confirm the restore actually rolled the cluster state back to the snapshot point, the post-snapshot Pod should disappear.

---

## Question 8 | Get Controlplane Information

**Solve on:** `ssh cka8448`

Determine how kubelet, kube-apiserver, kube-scheduler, kube-controller-manager, and etcd are each installed/started on the controlplane, and how the DNS application is installed. Write findings to `/opt/course/8/controlplane-components.txt` using `[TYPE]` values of `not-installed`, `process`, `static-pod`, or `pod`.

### Solution

Check whether the kubelet itself is a systemd-managed process:

```bash
sudo -i
find /usr/lib/systemd | grep kube       # finds kubelet.service, no separate services for the others
service kubelet status                   # active, running as a host process
```

Since there's no separate etcd or apiserver systemd service, but the cluster is clearly running (kubeadm-style setup), check the default static-pod manifest directory:

```bash
find /etc/kubernetes/manifests/
# kube-controller-manager.yaml, etcd.yaml, kube-apiserver.yaml, kube-scheduler.yaml
```

All four core control-plane components have manifest files there, confirming static-pod management. Cross-check against the live Namespace:

```bash
k -n kube-system get pod -o wide
# shows coredns-*, etcd-cka8448, kube-apiserver-cka8448, kube-controller-manager-cka8448,
# kube-proxy-*, kube-scheduler-cka8448, weave-net-*, all suffixed with the node name
```

The `-NODENAME` suffix on etcd, apiserver, scheduler, and controller-manager Pods is itself confirmation of static-pod management, since that suffix pattern is specific to how the kubelet names static Pods.

For DNS, check whether it's a DaemonSet or Deployment:

```bash
kubectl -n kube-system get ds      # kube-proxy, weave-net, no coredns here
k -n kube-system get deploy        # coredns, 2/2 ready
```

CoreDNS is controlled by a Deployment, a regular Kubernetes-managed Pod rather than static or systemd-managed.

```text
# /opt/course/8/controlplane-components.txt
kubelet: process
kube-apiserver: static-pod
kube-scheduler: static-pod
kube-controller-manager: static-pod
etcd: static-pod
dns: pod coredns
```

---

## Question 9 | Kill Scheduler, Manual Scheduling

**Solve on:** `ssh cka5248`

Temporarily stop kube-scheduler (recoverable). Create Pod `manual-schedule` (image `httpd:2-alpine`), confirm it's created but unscheduled. Manually schedule it onto node `cka5248`. Restart kube-scheduler, confirm normal operation by creating Pod `manual-schedule2` and checking it lands on `cka5248-node1`.

### Solution

Stop the scheduler by moving its static-pod manifest out of the watched directory, the standard recoverable way to stop any static pod:

```bash
ssh cka5248
sudo -i
kubectl -n kube-system get pod | grep schedule    # confirm it's running first
cd /etc/kubernetes/manifests/
mv kube-scheduler.yaml ..
watch crictl ps                                     # wait for the scheduler container to vanish
kubectl -n kube-system get pod | grep schedule      # confirms gone
```

Create the test Pod and confirm it has no node assigned, the expected symptom of no scheduler being present to bind it:

```bash
k run manual-schedule --image=httpd:2-alpine
k get pod manual-schedule -o wide
# STATUS Pending, NODE <none>
```

To manually schedule it, the scheduler's actual job, setting `spec.nodeName`, is performed by hand. `nodeName` cannot be edited or patched onto a running Pod through `kubectl apply`/`edit`, so the only path is delete-and-recreate (or `replace --force`):

```bash
k get pod manual-schedule -o yaml > 9.yaml
```

Add the `nodeName` field to the spec, immediately under `spec:`, before `containers:`:

```yaml
spec:
  nodeName: cka5248    # ADD the controlplane node name
  containers:
  - image: httpd:2-alpine
    ...
```

```bash
k -f 9.yaml replace --force
k get pod manual-schedule -o wide
# Running, NODE cka5248
```

The Pod lands on the controlplane with no toleration specified at all, which is the core mechanism this question tests: taints, tolerations, and node affinity are scheduler-enforced concepts. Setting `nodeName` directly bypasses the scheduler entirely, so none of those constraints get evaluated, and the kubelet on the named node simply runs whatever it's told to run.

Restart the scheduler the same way it was stopped, by returning its manifest to the watched directory:

```bash
cd /etc/kubernetes/manifests/
mv ../kube-scheduler.yaml .
kubectl -n kube-system get pod | grep schedule   # confirms it's back, Running
```

Create the second test Pod normally and confirm normal scheduler behavior resumed:

```bash
k run manual-schedule2 --image=httpd:2-alpine
k get pod -o wide | grep schedule
# manual-schedule   on cka5248 (still, from the manual step)
# manual-schedule2  on cka5248-node1 (the scheduler picked the worker node this time)
```

---

## Question 10 | PV/PVC Dynamic Provisioning

**Solve on:** `ssh cka6016`

Create StorageClass `local-backup` using provisioner `rancher.io/local-path` and `volumeBindingMode: WaitForFirstConsumer`, with a reclaim policy that retains the PV even if the bound PVC is deleted. Adjust the Job at `/opt/course/10/backup.yaml` to use a PVC requesting `50Mi` against the new StorageClass. Deploy and verify the Job completes and the PVC binds to a newly created PV.

### Solution

An existing `local-path` StorageClass is present (from the Local Path Provisioner project, which backs PVCs with directories on the node's local filesystem rather than networked storage), but it uses `reclaimPolicy: Delete`, the opposite of what's needed for backup data. Use it as a template for the new one:

```yaml
# sc.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-backup
provisioner: rancher.io/local-path
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
```

`reclaimPolicy: Retain` is the key field for the no-data-loss requirement: deleting the PVC leaves the underlying PV (and its data) intact rather than triggering deletion, the default and easy-to-trip-over risk with the cluster's default StorageClass.

The existing Job currently uses an `emptyDir` volume, which is ephemeral and tied to the Pod's own lifetime, so it needs to be replaced with a PVC reference. Edit the Job manifest to add a new PVC object and point the Job's volume at it:

```yaml
# /opt/course/10/backup.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: backup-pvc
  namespace: project-bern        # same Namespace as the Job
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Mi
  storageClassName: local-backup
---
apiVersion: batch/v1
kind: Job
metadata:
  name: backup
  namespace: project-bern
spec:
  backoffLimit: 0
  template:
    spec:
      volumes:
        - name: backup
          persistentVolumeClaim:    # CHANGED from emptyDir
            claimName: backup-pvc   # CHANGED
      containers:
        - name: bash
          image: bash:5
          command: ["bash", "-c", "set -x\ntouch /backup/backup-$(date +%Y-%m-%d-%H-%M-%S).tar.gz\nsleep 15"]
          volumeMounts:
            - name: backup
              mountPath: /backup
      restartPolicy: Never
```

Delete the prior (already-run, emptyDir-based) Job before reapplying, then deploy:

```bash
k delete -f backup.yaml
k apply -f backup.yaml
k -n project-bern get job,pod,pvc,pv
```

The PVC should reach `Bound`, with a dynamically created PV showing `Retain` as its policy. With `WaitForFirstConsumer`, the actual PV provisioning is deferred until the Job's Pod is scheduled, which is also why this StorageClass works correctly even on a single-node cluster where the volume has to land wherever the Pod does.

Re-running the Job (delete the Job, reapply) produces a second backup file in the same underlying volume directory, confirming the PVC and its backing storage persisted across Job runs. Deleting the PVC directly afterward leaves the PV in `Released` status rather than removing it, the direct demonstration of the `Retain` policy doing its job; the data on disk (visible under `/opt/local-path-provisioner/` on a Local Path Provisioner setup) survives.

---

## Question 11 | Create Secret and Mount into Pod

**Solve on:** `ssh cka2560`

In a new Namespace `secret`: create Pod `secret-pod` (image `busybox:1`, kept alive via `sleep 1d`). Create the existing Secret at `/opt/course/11/secret1.yaml` and mount it read-only at `/tmp/secret1`. Create a new Secret `secret2` containing `user=user1` and `pass=1234`, exposed in the Pod as environment variables `APP_USER` and `APP_PASS`.

### Solution

```bash
k create ns secret
```

The provided Secret manifest is namespaced for somewhere else by default and needs its Namespace field updated before creation:

```yaml
# 11_secret1.yaml
apiVersion: v1
data:
  halt: <base64 data>
kind: Secret
metadata:
  name: secret1
  namespace: secret     # UPDATE
```

```bash
k -f 11_secret1.yaml create
```

Create the second Secret directly from literals, faster than hand-writing YAML for a simple key-value pair:

```bash
k -n secret create secret generic secret2 --from-literal=user=user1 --from-literal=pass=1234
```

Scaffold the Pod, then hand-add the volume mount (for `secret1`) and the per-key environment injection (for `secret2`):

```bash
k -n secret run secret-pod --image=busybox:1 --dry-run=client -o yaml -- sh -c "sleep 1d" > 11.yaml
```

```yaml
# 11.yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: secret-pod
  name: secret-pod
  namespace: secret
spec:
  containers:
  - args:
    - sh
    - -c
    - sleep 1d
    image: busybox:1
    name: secret-pod
    resources: {}
    env:                              # add
    - name: APP_USER                  # add
      valueFrom:                     # add
        secretKeyRef:                 # add
          name: secret2                # add
          key: user                   # add
    - name: APP_PASS                  # add
      valueFrom:                     # add
        secretKeyRef:                 # add
          name: secret2                # add
          key: pass                   # add
    volumeMounts:                     # add
    - name: secret1                   # add
      mountPath: /tmp/secret1         # add
      readOnly: true                  # add
  dnsPolicy: ClusterFirst
  restartPolicy: Always
  volumes:                            # add
  - name: secret1                     # add
    secret:                           # add
      secretName: secret1             # add
status: {}
```

```bash
k -f 11.yaml create
```

Verify both mechanisms independently:

```bash
k -n secret exec secret-pod -- env | grep APP
# APP_PASS=1234
# APP_USER=user1

k -n secret exec secret-pod -- find /tmp/secret1
# /tmp/secret1/halt (plus the usual ..data symlink machinery)

k -n secret exec secret-pod -- cat /tmp/secret1/halt
# the decoded contents of the secret1 key
```

---

## Question 12 | Schedule Pod on Controlplane Nodes

**Solve on:** `ssh cka5248`

Create Pod `pod1` (container name `pod1-container`, image `httpd:2-alpine`) in `default`. It should be scheduled **only** on controlplane nodes. Do not add new labels to any node.

### Solution

Identify the controlplane node's existing taint and labels, since the task forbids adding new ones:

```bash
k describe node cka5248 | grep Taint -A1
# Taints: node-role.kubernetes.io/control-plane:NoSchedule

k get node cka5248 --show-labels
# includes: node-role.kubernetes.io/control-plane=
```

The `node-role.kubernetes.io/control-plane` label already exists on every controlplane node by default, so no new labeling is needed, just a `nodeSelector` (or `nodeAffinity`) against that existing key.

**NodeSelector approach** (the simpler, recommended one here):

```yaml
# 12.yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: pod1
  name: pod1
spec:
  containers:
  - image: httpd:2-alpine
    name: pod1-container          # change
    resources: {}
  tolerations:                    # add
  - effect: NoSchedule            # add
    key: node-role.kubernetes.io/control-plane  # add
  nodeSelector:                   # add
    node-role.kubernetes.io/control-plane: ""  # add
status: {}
```

The label is key-only (no meaningful value), so the nodeSelector matches against an empty-string value to match regardless of what (if anything) the value actually is.

Both pieces are required together: the toleration alone permits scheduling on a tainted controlplane node but doesn't prevent scheduling on an untainted worker node, and the nodeSelector alone would leave the Pod permanently unschedulable everywhere because of the taint. Toleration plus nodeSelector together is what makes "only controlplane" actually true.

**NodeAffinity approach** (equivalent but more verbose, the toleration is still required either way):

```yaml
  tolerations:
  - effect: NoSchedule
    key: node-role.kubernetes.io/control-plane
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: node-role.kubernetes.io/control-plane
            operator: Exists
```

```bash
k -f 12.yaml create
k get pod pod1 -o wide
# NODE cka5248
```

---

## Question 13 | Multi Containers and Pod Shared Volume

**Solve on:** `ssh cka3200`

Create multi-container Pod `multi-container-playground` in `default`: a shared, non-persisted, single-Pod-scoped volume mounted into every container. Container `c1` (`nginx:1-alpine`) exposes the node name as env var `MY_NODE_NAME`. Container `c2` (`busybox:1`) appends `date` output to a shared `date.log` file every second. Container `c3` (`busybox:1`) tails that same file to stdout.

### Solution

The "not persisted, not shared with other Pods" requirement for the volume points directly at `emptyDir`, which is created fresh per-Pod and removed when the Pod is removed.

```yaml
# 13.yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: multi-container-playground
  name: multi-container-playground
spec:
  containers:
  - image: nginx:1-alpine
    name: c1                                  # change
    resources: {}
    env:                                       # add
    - name: MY_NODE_NAME                       # add
      valueFrom:                               # add
        fieldRef:                              # add
          fieldPath: spec.nodeName              # add
    volumeMounts:                              # add
    - name: vol                                # add
      mountPath: /vol                          # add
  - image: busybox:1                           # add
    name: c2                                   # add
    command: ["sh", "-c", "while true; do date >> /vol/date.log; sleep 1; done"]  # add
    volumeMounts:                              # add
    - name: vol                                # add
      mountPath: /vol                          # add
  - image: busybox:1                           # add
    name: c3                                   # add
    command: ["sh", "-c", "tail -f /vol/date.log"]  # add
    volumeMounts:                              # add
    - name: vol                                # add
      mountPath: /vol                          # add
  dnsPolicy: ClusterFirst
  restartPolicy: Always
  volumes:                                      # add
  - name: vol                                   # add
    emptyDir: {}                                # add
status: {}
```

`c1`'s node-name exposure uses the downward API (`fieldRef` against `spec.nodeName`), the same mechanism that exposes other Pod-level metadata into a container's environment without the application needing to query the API server directly.

```bash
k -f 13.yaml create
k get pod multi-container-playground
# 3/3 Running

k exec multi-container-playground -c c1 -- env | grep MY
# MY_NODE_NAME=<the actual node name>

k logs multi-container-playground -c c3
# a continuously growing stream of timestamp lines, confirming c2 writes and c3 reads
# from the same shared volume correctly
```

---

## Question 14 | Find Out Cluster Information

**Solve on:** `ssh cka8448`

Determine: number of controlplane nodes, number of worker nodes, the Service CIDR, which CNI plugin is configured and where its config file lives, and the suffix static Pods running on `cka8448` will carry. Write answers into `/opt/course/14/cluster-info` in the specified numbered format.

### Solution

```bash
k get node
# one node total: cka8448, role control-plane
```

One controlplane node, zero worker nodes.

```bash
sudo -i
cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep range
# --service-cluster-ip-range=10.96.0.0/12
```

For the CNI, the kubelet's default lookup directory is `/etc/cni/net.d`:

```bash
find /etc/cni/net.d/
# 10-weave.conflist (plus an 87-podman-bridge.conflist, unrelated to cluster networking)

cat /etc/cni/net.d/10-weave.conflist
# confirms "type": "weave-net" inside the plugin list
```

The configured CNI is Weave, config file at `/etc/cni/net.d/10-weave.conflist`.

Static Pods on a kubeadm-managed node carry a suffix matching the node's own hostname, with a leading hyphen, so on `cka8448` that suffix is `-cka8448`.

```text
# /opt/course/14/cluster-info
1: 1
2: 0
3: 10.96.0.0/12
4: Weave, /etc/cni/net.d/10-weave.conflist
5: -cka8448
```

---

## Question 15 | Cluster Event Logging

**Solve on:** `ssh cka6016`

Write a `kubectl` command into `/opt/course/15/cluster_events.sh` showing the latest cluster-wide events sorted by creation time. Delete the kube-proxy Pod and capture the resulting events into `/opt/course/15/pod_kill.log`. Separately, kill the kube-proxy Pod's containerd container directly via `crictl`, and capture those events into `/opt/course/15/container_kill.log`.

### Solution

```bash
# /opt/course/15/cluster_events.sh
kubectl get events -A --sort-by=.metadata.creationTimestamp
```

Identify and delete the kube-proxy Pod:

```bash
k -n kube-system get pod -l k8s-app=kube-proxy -owide
k -n kube-system delete pod kube-proxy-<hash>
```

Run the events script again and capture the relevant new lines into `pod_kill.log`. Deleting the whole Pod (which belongs to a DaemonSet) triggers a fuller event chain: the container is stopped, the DaemonSet controller notices the missing Pod and creates a replacement, that replacement gets scheduled, its image is confirmed present, and its container is created and started.

```bash
sudo -i
crictl ps | grep kube-proxy
crictl rm --force <container-id>
crictl ps | grep kube-proxy
# confirms a brand-new container ID came up immediately, same Pod
```

Run the events script again and capture the new lines into `container_kill.log`. Killing only the container (the Pod object itself stays intact) produces a noticeably smaller event set than the full Pod deletion, since the DaemonSet controller is never involved, only the kubelet has to notice the container died and restart it inside the existing Pod.

The size difference between the two log files is itself the point of the exercise: a Pod-level kill cascades through the controller layer (DaemonSet reconciliation, new Pod scheduling, new container creation), while a container-level kill is handled entirely by the kubelet's restart policy without involving any higher-level controller at all.

---

## Question 16 | Namespaces and API Resources

**Solve on:** `ssh cka3200`

Write the names of all namespaced Kubernetes resources into `/opt/course/16/resources.txt`. Find the `project-*` Namespace with the most `Role` objects defined in it and write its name and count into `/opt/course/16/crowded-namespace.txt`.

### Solution

```bash
k api-resources --namespaced -o name > /opt/course/16/resources.txt
```

This produces the full namespaced-resource list (`pods`, `configmaps`, `secrets`, `services`, `deployments.apps`, `roles.rbac.authorization.k8s.io`, and so on), distinct from `kubectl api-resources` run with no filter, which would also include cluster-scoped resources like `nodes` and `namespaces` themselves.

For the Role count per Namespace, there's no single built-in flag that aggregates this, so each `project-*` Namespace gets checked individually:

```bash
k -n project-jinan get role --no-headers | wc -l       # 0
k -n project-miami get role --no-headers | wc -l        # 300
k -n project-melbourne get role --no-headers | wc -l    # 2
k -n project-seoul get role --no-headers | wc -l        # 10
k -n project-toronto get role --no-headers | wc -l      # 0
```

```text
# /opt/course/16/crowded-namespace.txt
project-miami with 300 roles
```

---

## Question 17 | Operator, CRDs, RBAC, Kustomize

**Solve on:** `ssh cka6016`

Kustomize config at `/opt/course/17/operator` deploys an operator (already applied via `kubectl kustomize /opt/course/17/operator/prod | kubectl apply -f -`). In the **base** config: (1) the operator needs to `list` certain CRDs, check its logs to find which ones and fix the `operator-role` Role's permissions; (2) add a new Student resource `student4` with any name/description. Redeploy to prod.

### Solution

Kustomize's base/overlay model means the base directory holds the shared resource definitions and overlays (here, `prod`) layer Namespace assignment, labels, and other environment-specific overrides on top without duplicating the base content. Building the base directly (`kubectl kustomize base`) produces Yaml with placeholder values like `NAMESPACE_REPLACE` that aren't meant to be applied as-is; building the `prod` overlay (`kubectl kustomize prod`) produces the actual deployable Yaml with `operator-prod` substituted in everywhere, plus an extra `project_id` label the overlay adds to the Deployment.

Identify the actual error from the running operator's logs:

```bash
k -n operator-prod get pod
k -n operator-prod logs operator-<hash>
```

```
+ kubectl get students
Error from server (Forbidden): students.education.killer.sh is forbidden: User "system:serviceaccount:operator-prod:operator" cannot list resource "students" ...
+ kubectl get classes
Error from server (Forbidden): classes.education.killer.sh is forbidden: ... cannot list resource "classes" ...
```

The operator's own container command (visible in the Deployment spec) is a simple shell loop running `kubectl get students` and `kubectl get classes` repeatedly, so the fix is purely RBAC: the existing `operator-role` Role needs `list` permission on both CRDs.

The fastest path to the corrected Role YAML is generating it imperatively and pasting the result into the base file, rather than hand-editing the existing rules:

```bash
k -n operator-prod create role operator-role --verb list --resource student --resource class -oyaml --dry-run=client
```

```yaml
# base/rbac.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: operator-role
  namespace: default
rules:
- apiGroups:
  - education.killer.sh
  resources:
  - students
  - classes
  verbs:
  - list
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: operator-rolebinding
  namespace: default
subjects:
  - kind: ServiceAccount
    name: operator
    namespace: default
roleRef:
  kind: Role
  name: operator-role
  apiGroup: rbac.authorization.k8s.io
```

Note the base file's Namespace fields stay as the Kustomize placeholder/base value (`default` here); the `prod` overlay is what rewrites these to `operator-prod` at build time, so editing the base file directly is correct and the overlay machinery handles the rest.

For the new Student resource, copy an existing Student entry in the base's `students.yaml` as a template and add a new one alongside it:

```yaml
# base/students.yaml
---
apiVersion: education.killer.sh/v1
kind: Student
metadata:
  name: student4
spec:
  name: Some Name
  description: Some Description
```

Redeploy:

```bash
kubectl kustomize /opt/course/17/operator/prod | kubectl apply -f -
```

The output should show `role.rbac.authorization.k8s.io/operator-role configured` (the only resource that actually changed on the RBAC fix's first apply) and, after the Student addition, `student.education.killer.sh/student4 created`, with every other resource reporting `unchanged`.

```bash
k -n operator-prod logs operator-<hash>
# kubectl get students / kubectl get classes now return normal table output, no Forbidden errors

k -n operator-prod get student
# student1, student2, student3, student4 all listed
```
