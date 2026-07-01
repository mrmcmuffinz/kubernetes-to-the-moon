# Killer Shell CKA Simulator A: Solutions
 
Source: ksh-cka-exam-a-simulator-.pdf (Killer Shell, killer.sh)
 
This is a personal transcription of the official solution walkthroughs for reference during remediation. It is not affiliated with or maintained alongside any other study materials.
 
---
 
## Question 1 | Cluster Access with kubeconfig
 
**Solve on:** `ssh cka9412`
 
Extract information from kubeconfig file `/opt/course/1/kubeconfig` on cka9412:
 
1. Write all kubeconfig context names into `/opt/course/1/contexts`, one per line
2. Write the name of the current context into `/opt/course/1/current-context`
3. Write the client-certificate of user `account-0027` base64-decoded into `/opt/course/1/cert`
### Solution
 
Get all context names:
 
```bash
k --kubeconfig /opt/course/1/kubeconfig config get-contexts
```
 
Result:
 
```
CURRENT   NAME             CLUSTER      AUTHINFO            NAMESPACE
          cluster-admin    kubernetes   admin@internal
          cluster-w100     kubernetes   account-0027@internal
*         cluster-w200     kubernetes   account-0028@internal
```
 
Extract just the names and write to file:
 
```bash
k --kubeconfig /opt/course/1/kubeconfig config get-contexts -oname > /opt/course/1/contexts
```
 
Could also use jsonpath, though it's overkill here:
 
```bash
k --kubeconfig /opt/course/1/kubeconfig config view -o jsonpath="{.contexts[*].name}"
```
 
Query the current context:
 
```bash
k --kubeconfig /opt/course/1/kubeconfig config current-context > /opt/course/1/current-context
```
 
Result: `cluster-w200`
 
Extract the certificate, base64 decoded. Either open the kubeconfig in an editor, copy the `client-certificate-data` value for `account-0027@internal`, and decode manually:
 
```bash
echo LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t... | base64 -d > /opt/course/1/cert
```
 
Or automate it with jsonpath against the raw config:
 
```bash
k --kubeconfig /opt/course/1/kubeconfig config view --raw -ojsonpath="{.users[0].user.client-certificate-data}" | base64 -d > /opt/course/1/cert
```
 
---
 
## Question 2 | CRD, Helm, cert-manager
 
**Solve on:** `ssh cka7968`
 
Install cert-manager using Helm in Namespace `cert-manager`, then configure and create the `ClusterIssuer` CRD:
 
1. Create Namespace `cert-manager`
2. Install Helm chart `jetstack/cert-manager` (with `crds.enabled=true`) into the new Namespace, Helm Release named `cert-manager`
3. Update the `ClusterIssuer` resource in `/opt/course/2/cluster-issuer.yaml` to include `crlDistributionPoints: ["http://example.com/crl"]` under `spec.selfSigned`
4. Create the `ClusterIssuer` resource from `/opt/course/2/cluster-issuer.yaml`
### Background
 
- **Helm Chart:** Kubernetes YAML template files combined into a single package. Values allow customisation.
- **Helm Release:** Installed instance of a Chart.
- **Helm Values:** Allow customisation of the YAML templates in a Chart when creating a Release.
- **Operator:** Pod that communicates with the Kubernetes API and might work with CRDs.
- **CRD:** Custom Resources are extensions of the Kubernetes API.
### Solution
 
Create the namespace:
 
```bash
k create ns cert-manager
```
 
Check the helm repo and install:
 
```bash
helm repo list
helm search repo
helm -n cert-manager install cert-manager jetstack/cert-manager --set crds.enabled=true
```
 
Verify the release and pods:
 
```bash
helm -n cert-manager ls
k -n cert-manager get pod
```
 
Check the CRDs that came in with the chart:
 
```bash
k get crd
```
 
This shows `clusterissuers.cert-manager.io`, `issuers.cert-manager.io`, `certificates.cert-manager.io`, and related CRDs.
 
Inspect available fields for the resource you need to edit:
 
```bash
k explain clusterissuer.spec.selfSigned
```
 
Edit the provided YAML to add the required field:
 
```yaml
# /opt/course/2/cluster-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: course-issuer
spec:
  selfSigned:
    crlDistributionPoints:               # ADD
      - http://example.com/crl           # ADD
```
 
Create it:
 
```bash
k -f /opt/course/2/cluster-issuer.yaml apply
k get clusterissuer
```
 
This scenario installs an operator via Helm and creates a CRD that operator works with, a common Kubernetes pattern.
 
---
 
## Question 3 | Scale a StatefulSet
 
**Solve on:** `ssh cka3962`
 
Two Pods named `o3db-*` exist in Namespace `project-h800`. Scale them down to one replica.
 
### Solution
 
Confirm the Pods exist and identify what manages them:
 
```bash
k -n project-h800 get pod | grep o3db
k -n project-h800 get deploy,ds,sts | grep o3db
k -n project-h800 get pod --show-labels | grep o3db
```
 
Confirms a StatefulSet named `o3db` with 2 replicas.
 
Scale it:
 
```bash
k -n project-h800 scale sts o3db --replicas 1
k -n project-h800 get sts o3db
```
 
---
 
## Question 4 | Pod Quality of Service Classes / Node-pressure Eviction
 
**Solve on:** `ssh cka2556`
 
Find Pods in Namespace `project-c13` that would be terminated first under resource pressure. Write their names into `/opt/course/4/pods-terminated-first.txt`.
 
### Background
 
When nodes run low on cpu or memory, Kubernetes targets Pods using more resources than requested first. Pods with no resource requests/limits set are treated as using more than requested by default. This maps to Kubernetes QoS classes.
 
### Solution
 
Manual approach, inspect Pod descriptions for missing Requests:
 
```bash
k -n project-c13 describe pod | less -p Requests
k -n project-c13 describe pod | grep -A 3 -E 'Requests|^Name:'
```
 
This reveals that Pods of Deployment `c13-3cc-runner-heavy` have no resource requests defined.
 
```
# /opt/course/4/pods-terminated-first.txt
c13-3cc-runner-heavy-65588d7d6-djtv9
c13-3cc-runner-heavy-65588d7d6-v8kf5
c13-3cc-runner-heavy-65588d7d6-wwpb4
```
 
Faster automated approaches:
 
```bash
k -n project-c13 get pod -o jsonpath="{range .items[*]} {.metadata.name} {.spec.containers[*].resources}{'\n'}"
```
 
Or check QoS class directly:
 
```bash
k get pods -n project-c13 -o jsonpath="{range .items[*]}{.metadata.name} {.status.qosClass}{'\n'}"
```
 
Pods with `BestEffort` QoS (no cpu/memory limits or requests) are the eviction-first candidates. The rest in this scenario are `Burstable`.
 
A good practice in general: always set resource requests and limits. If unsure of correct values, use metrics tooling (Prometheus, `kubectl top pod`) or `kubectl exec` plus `top` inside the container to observe real usage.
 
---
 
## Question 5 | Horizontal Pod Autoscaling with Kustomize
 
**Solve on:** `ssh cka5774`
 
Application `api-gateway` previously used an external autoscaler, to be replaced with an HPA. Deployed to Namespaces `api-gateway-staging` and `api-gateway-prod` via:
 
```bash
kubectl kustomize /opt/course/5/api-gateway/staging | kubectl apply -f -
kubectl kustomize /opt/course/5/api-gateway/prod | kubectl apply -f -
```
 
Using the Kustomize config at `/opt/course/5/api-gateway`:
 
1. Remove the ConfigMap `horizontal-scaling-config` completely
2. Add HPA named `api-gateway` for the Deployment `api-gateway` with min 2 and max 4 replicas, scaling at 50% average CPU utilisation
3. In prod the HPA should have max 6 replicas
4. Apply changes for staging and prod so they're reflected in the cluster
### Background
 
Kustomize is a standalone tool for managing K8s YAML, also bundled with kubectl. The common pattern is a base set of YAML, overridden or extended per overlay (here, staging and prod).
 
### Solution
 
Inspect the base:
 
```bash
cd /opt/course/5/api-gateway
k kustomize base
```
 
The base produces a `ServiceAccount`, `ConfigMap` (`horizontal-scaling-config`, value `"70"`), and a `Deployment`, all using a placeholder `namespace: NAMESPACE_REPLACE` since base output isn't meant to be applied directly.
 
Inspect staging:
 
```bash
k kustomize staging
```
 
Staging resolves the namespace to `api-gateway-staging`, changes the ConfigMap value to `"60"`, and adds label `env: staging` to the Deployment. This comes from `staging/kustomization.yaml`:
 
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
patches:
  - path: api-gateway.yaml
transformers:
  - |-
    apiVersion: builtin
    kind: NamespaceTransformer
    metadata:
      name: notImportantHere
      namespace: api-gateway-staging
```
 
Confirm nothing changes yet (already deployed):
 
```bash
k kustomize staging | kubectl diff -f -
k kustomize staging | kubectl apply -f -
```
 
Same pattern for prod, just a different patch value.
 
**Removing the ConfigMap:** it must be removed from `base/api-gateway.yaml`, `staging/api-gateway.yaml`, and `prod/api-gateway.yaml`. Removing it only from base while staging/prod still patch it causes:
 
```
error: no resource matches strategic merge patch "ConfigMap.v1.[noGrp]/horizontal-scaling-config.[noNs]"
```
 
After removing from all three files, both `kustomize staging` and `kustomize prod` build cleanly without the ConfigMap.
 
**Adding the HPA**, add to `base/api-gateway.yaml`:
 
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-gateway
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-gateway
  minReplicas: 2
  maxReplicas: 4
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
```
 
No Namespace is specified, it's set automatically by the staging/prod overlays.
 
For prod's `maxReplicas: 6` override, add to `prod/api-gateway.yaml`:
 
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-gateway
spec:
  maxReplicas: 6
```
 
Verify the build output per overlay:
 
```bash
k kustomize staging | grep maxReplicas -B5   # shows 4
k kustomize prod | grep maxReplicas -B5      # shows 6
```
 
Apply both:
 
```bash
k kustomize staging | kubectl diff -f -
k kustomize staging | kubectl apply -f -
 
k kustomize prod | kubectl diff -f -
k kustomize prod | kubectl apply -f -
```
 
**Important: manual ConfigMap cleanup required.** The HPA is created, but Kustomize will not delete the remote ConfigMap, since it no longer exists in the YAML but was never tracked as state by Kustomize. It must be deleted manually:
 
```bash
k -n api-gateway-staging delete cm horizontal-scaling-config
k -n api-gateway-prod delete cm horizontal-scaling-config
```
 
### Why this manual step is necessary
 
Kustomize keeps no state. It doesn't track what it created versus what exists for other reasons, so it cannot know to delete a resource that's been removed from the YAML source. Helm, by contrast, tracks Release state and will remove resources that only exist because Helm created them.
 
Trade-offs:
 
- **Kustomize:** less complex, no state to manage, but requires manual cleanup work.
- **Helm:** better remote resource tracking, but more complexity and risk if state drifts or mismatches; state-changing actions need coordination.
A secondary note from this scenario: once the HPA is active, the Deployment's `replicas:` field becomes a source of drift (HPA sets it to `minReplicas`, but the Deployment's own spec retains its original `replicas:` value, e.g. 1). Each subsequent `kubectl apply` would attempt to reset replicas back down. This doesn't affect scoring here, but removing `replicas:` entirely from the Deployment spec in base/staging/prod avoids the conflict.
 
---
 
## Question 6 | Configure a Pod to Use Storage
 
**Solve on:** `ssh cka7968`
 
1. Create PersistentVolume `safari-pv`: capacity 2Gi, accessMode `ReadWriteOnce`, hostPath `/Volumes/Data`, no storageClassName
2. Create PersistentVolumeClaim `safari-pvc` in Namespace `project-t230`: request 2Gi, accessMode `ReadWriteOnce`, no storageClassName, should bind to the PV
3. Create Deployment `safari` in Namespace `project-t230` mounting that volume at `/tmp/safari-data`, image `httpd:2-alpine`
> Using the hostPath volume type presents security risks; avoid in production. Data in a hostPath directory is not shared across nodes, availability depends on which node the Pod is scheduled to.
 
### Solution
 
PersistentVolume:
 
```yaml
# 6_pv.yaml
kind: PersistentVolume
apiVersion: v1
metadata:
  name: safari-pv
spec:
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/Volumes/Data"
```
 
```bash
k -f 6_pv.yaml create
```
 
PersistentVolumeClaim:
 
```yaml
# 6_pvc.yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: safari-pvc
  namespace: project-t230
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
```
 
```bash
k -f 6_pvc.yaml create
k -n project-t230 get pv,pvc       # confirm both show Bound
```
 
Deployment, generate a template then add the volume:
 
```bash
k -n project-t230 create deploy safari --image=httpd:2-alpine --dry-run=client -o yaml > 6_dep.yaml
```
 
```yaml
# 6_dep.yaml (relevant additions)
spec:
  template:
    spec:
      volumes:                          # add
        - name: data                    # add
          persistentVolumeClaim:        # add
            claimName: safari-pvc       # add
      containers:
        - image: httpd:2-alpine
          name: container
          volumeMounts:                 # add
            - name: data                # add
              mountPath: /tmp/safari-data  # add
```
 
```bash
k -f 6_dep.yaml create
k -n project-t230 describe pod safari-xxxxx | grep -A2 Mounts:
```
 
---
 
## Question 7 | kubectl Quick Reference (Resource Monitoring)
 
**Solve on:** `ssh cka5774`
 
The metrics-server is installed. Write two bash scripts:
 
1. `/opt/course/7/node.sh` shows resource usage of nodes
2. `/opt/course/7/pod.sh` shows resource usage of Pods and their containers
### Solution
 
```bash
k top -h
k top node
```
 
```bash
# /opt/course/7/node.sh
kubectl top node
```
 
```bash
k top pod -h    # check the --containers flag
```
 
```bash
# /opt/course/7/pod.sh
kubectl top pod --containers=true
```
 
---
 
## Question 8 | Update Kubernetes Version and Join Cluster
 
**Solve on:** `ssh cka3962`
 
Node `cka3962-node1` runs an older Kubernetes version and is not part of the cluster yet.
 
1. Update the node's Kubernetes to the exact version of the controlplane
2. Add the node to the cluster using kubeadm
> Connect to the worker node using `ssh cka3962-node1` from `cka3962`.
 
### Solution
 
Check controlplane version:
 
```bash
k get node    # controlplane shows v1.35.2
```
 
SSH to the worker, check current versions:
 
```bash
ssh cka3962-node1
sudo -i
kubectl version       # client v1.34.5
kubelet --version      # v1.34.5
kubeadm version        # already v1.35.2
```
 
`kubeadm` is already at the right version (otherwise it would need `apt install kubeadm=1.35.2-1.1`).
 
Attempt the normal worker upgrade command:
 
```bash
kubeadm upgrade node
```
 
This fails since the node isn't part of the cluster yet:
 
```
error: couldn't create a Kubernetes client from file "/etc/kubernetes/kubelet.conf": ...no such file or directory
```
 
That's expected, there's nothing to update pre-join. Update kubelet and kubectl packages directly:
 
```bash
apt update
apt show kubectl -a | grep 1.35
apt install kubectl=1.35.2-1.1 kubelet=1.35.2-1.1
kubelet --version    # confirm v1.35.2
service kubelet restart
```
 
The kubelet will show errors/activating state at this point since it isn't joined yet, expected until the join step.
 
On the **controlplane**, generate a join command:
 
```bash
sudo -i
kubeadm token create --print-join-command
kubeadm token list
```
 
Back on the **worker node**, run the join command output above:
 
```bash
ssh cka3962-node1
kubeadm join 192.168.100.31:6443 --token ... --discovery-token-ca-cert-hash sha256:...
```
 
> If `kubeadm join` has trouble, you may need to run `kubeadm reset` first.
 
Verify kubelet is active and the node eventually shows Ready:
 
```bash
service kubelet status
k get node    # from controlplane, give it a moment to go from NotReady to Ready
```
 
---
 
## Question 9 | Contact K8s API from Inside a Pod
 
**Solve on:** `ssh cka9412`
 
ServiceAccount `secret-reader` exists in Namespace `project-swan`. Create a Pod named `api-contact` (image `nginx:1-alpine`) using this ServiceAccount. Exec in and use curl to query all Secrets from the K8s API. Write the result into `/opt/course/9/result.json`.
 
### Solution
 
Generate a Pod template and add the ServiceAccount and Namespace:
 
```bash
k run api-contact --image=nginx:1-alpine --dry-run=client -o yaml > 9.yaml
```
 
```yaml
# 9.yaml
metadata:
  name: api-contact
  namespace: project-swan        # add
spec:
  serviceAccountName: secret-reader   # add
  containers:
    - image: nginx:1-alpine
      name: api-contact
```
 
```bash
k -f 9.yaml apply
k -n project-swan exec api-contact -it -- sh
```
 
Inside the Pod, the API is reachable via the `kubernetes` Service in the `default` namespace, resolvable as `kubernetes.default` through internal DNS. (The API IP can also be found via `env` if needed.)
 
```bash
curl https://kubernetes.default
# fails: untrusted cert
 
curl -k https://kubernetes.default
# 403 Forbidden, connecting as system:anonymous
 
curl -k https://kubernetes.default/api/v1/secrets
# still 403, no auth token passed
```
 
Use the ServiceAccount's mounted token:
 
```bash
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
curl -k https://kubernetes.default/api/v1/secrets -H "Authorization: Bearer ${TOKEN}"
```
 
This succeeds and returns the SecretList.
 
Sanity check the RBAC permission directly:
 
```bash
k auth can-i get secret --as system:serviceaccount:project-swan:secret-reader
```
 
Write the output to file:
 
```bash
curl -k https://kubernetes.default/api/v1/secrets -H "Authorization: Bearer ${TOKEN}" > result.json
exit
k -n project-swan exec api-contact -it -- cat result.json > /opt/course/9/result.json
```
 
To avoid `-k` (insecure mode), use the ServiceAccount's mounted CA cert instead:
 
```bash
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
curl --cacert ${CACERT} https://kubernetes.default/api/v1/secrets -H "Authorization: Bearer ${TOKEN}"
```
 
---
 
## Question 10 | Configure Service Accounts for Pods (RBAC)
 
**Solve on:** `ssh cka3962`
 
Create ServiceAccount `processor` in Namespace `project-hamster`. Create a Role and RoleBinding, both named `processor`, allowing the SA to only **create** Secrets and ConfigMaps in that Namespace.
 
### Background
 
- A **ClusterRole/Role** defines a set of permissions, available cluster-wide or in a single Namespace.
- A **ClusterRoleBinding/RoleBinding** connects permissions to an account, applied cluster-wide or in a single Namespace.
- Four combinations exist, three are valid:
  1. Role + RoleBinding (available + applied in single Namespace)
  2. ClusterRole + ClusterRoleBinding (available + applied cluster-wide)
  3. ClusterRole + RoleBinding (available cluster-wide, applied in single Namespace)
  4. Role + ClusterRoleBinding is **not valid** (a Role is only available in its own Namespace, it can't be applied cluster-wide)
### Solution
 
```bash
k -n project-hamster create sa processor
```
 
Create the Role:
 
```bash
k -n project-hamster create role -h    # check examples
 
k -n project-hamster create role processor --verb=create --resource=secret --resource=configmap
```
 
This produces:
 
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: processor
  namespace: project-hamster
rules:
  - apiGroups: [""]
    resources: ["secrets", "configmaps"]
    verbs: ["create"]
```
 
Bind it:
 
```bash
k -n project-hamster create rolebinding -h    # check examples
 
k -n project-hamster create rolebinding processor --role processor --serviceaccount project-hamster:processor
```
 
Verify with `auth can-i`:
 
```bash
k -n project-hamster auth can-i create secret --as system:serviceaccount:project-hamster:processor      # yes
k -n project-hamster auth can-i create configmap --as system:serviceaccount:project-hamster:processor    # yes
k -n project-hamster auth can-i create pod --as system:serviceaccount:project-hamster:processor          # no
k -n project-hamster auth can-i delete secret --as system:serviceaccount:project-hamster:processor       # no
k -n project-hamster auth can-i get configmap --as system:serviceaccount:project-hamster:processor       # no
```
 
---
 
## Question 11 | DaemonSet with Taints and Tolerations
 
**Solve on:** `ssh cka2556`
 
In Namespace `project-tiger`, create DaemonSet `ds-important`, image `httpd:2-alpine`, labels `id=ds-important` and `uuid=18426a0b-5f59-4e10-923f-c0e078e82462`. Pods request 10 millicore cpu and 10 mebibyte memory, and must run on all nodes including controlplanes.
 
### Solution
 
`kubectl` can't create a DaemonSet directly, so generate a Deployment template and convert it:
 
```bash
k -n project-tiger create deployment --image=httpd:2.4-alpine ds-important --dry-run=client -o yaml > 11.yaml
```
 
```yaml
# 11.yaml
apiVersion: apps/v1
kind: DaemonSet                  # change from Deployment
metadata:
  labels:                        # add
    id: ds-important              # add
    uuid: 18426a0b-5f59-4e10-923f-c0e078e82462  # add
  name: ds-important
  namespace: project-tiger        # important
spec:
  # replicas: 1                  # remove, DaemonSets don't use replicas
  selector:
    matchLabels:
      id: ds-important             # add
      uuid: 18426a0b-5f59-4e10-923f-c0e078e82462  # add
  # strategy: {}                  # remove
  template:
    metadata:
      labels:
        id: ds-important
        uuid: 18426a0b-5f59-4e10-923f-c0e078e82462
    spec:
      containers:
        - image: httpd:2-alpine
          name: ds-important
          resources:                  # add
            requests:                  # add
              cpu: 10m                 # add
              memory: 10Mi              # add
      tolerations:                    # add
        - effect: NoSchedule           # add
          key: node-role.kubernetes.io/control-plane  # add
  # status: {}                     # remove
```
 
```bash
k -f 11.yaml create
k -n project-tiger get ds
k -n project-tiger get pod -l id=ds-important -o wide
```
 
Confirms one Pod scheduled per node, including the controlplane.
 
---
 
## Question 12 | Assigning Pods to Nodes (Anti-Affinity / Topology Spread)
 
**Solve on:** `ssh cka2556`
 
In Namespace `project-tiger`:
 
- Deployment `deploy-important`, 3 replicas
- Label `id=very-important` on the Deployment and its Pods
- `container1` (image `nginx:1-alpine`), `container2` (image `registry.k8s.io/pause:3.10`)
- Only **one** Pod of the Deployment should run per worker node, using `topologyKey: kubernetes.io/hostname`
> With two worker nodes and three replicas, the third Pod should remain unscheduled. This simulates DaemonSet-like behavior with a fixed-replica Deployment.
 
### Solution
 
Two valid approaches: `podAntiAffinity` or `topologySpreadConstraints`.
 
Generate the base Deployment:
 
```bash
k -n project-tiger create deployment --image=nginx:1-alpine deploy-important --dry-run=client -o yaml > 12.yaml
```
 
**Approach 1, podAntiAffinity:**
 
```yaml
spec:
  replicas: 3
  selector:
    matchLabels:
      id: very-important
  template:
    metadata:
      labels:
        id: very-important
    spec:
      containers:
        - image: nginx:1-alpine
          name: container1
        - image: registry.k8s.io/pause:3.10    # add
          name: container2                      # add
      affinity:                                  # add
        podAntiAffinity:                          # add
          requiredDuringSchedulingIgnoredDuringExecution:  # add
            - labelSelector:                       # add
                matchExpressions:                   # add
                  - key: id                           # add
                    operator: In                       # add
                    values:                              # add
                      - very-important                    # add
              topologyKey: kubernetes.io/hostname           # add
```
 
**Approach 2, topologySpreadConstraints** (equivalent outcome):
 
```yaml
spec:
  template:
    spec:
      containers:
        - image: nginx:1-alpine
          name: container1
        - image: registry.k8s.io/pause:3.10
          name: container2
      topologySpreadConstraints:               # add
        - maxSkew: 1                             # add
          topologyKey: kubernetes.io/hostname       # add
          whenUnsatisfiable: DoNotSchedule           # add
          labelSelector:                              # add
            matchLabels:                                # add
              id: very-important                          # add
```
 
Both reference the topology key found by describing a node (a pre-populated Kubernetes label).
 
```bash
k -f 12.yaml create
k -n project-tiger get deploy -l id=very-important     # shows 2/3 ready
k -n project-tiger get pod -o wide -l id=very-important
```
 
One Pod lands on each worker, the third stays Pending. Describing it shows the reason:
 
```
... 2 node(s) didn't match pod anti-affinity rules ...
```
 
or, with the topology spread approach:
 
```
... 2 node(s) didn't match pod topology spread constraints ...
```
 
---
 
## Question 13 | Gateway API Migration from Ingress
 
**Solve on:** `ssh cka7968`
 
Replace an existing Ingress (`networking.k8s.io`) with a Gateway API (`gateway.networking.k8s.io`) solution in Namespace `project-r500`. Old Ingress at `/opt/course/13/ingress.yaml`.
 
1. Create HTTPRoute `traffic-director` replicating the old Ingress routes
2. Extend the HTTPRoute with path `/auto`: forward to mobile backend if User-Agent is exactly `mobile`, otherwise to desktop backend
Should work with:
 
```bash
curl r500.gateway:30080/desktop
curl r500.gateway:30080/mobile
curl r500.gateway:30080/auto -H "User-Agent: mobile"
curl r500.gateway:30080/auto
```
 
### Background
 
Ingress (`networking.k8s.io/v1`) and HTTPRoute (`gateway.networking.k8s.io/v1`) offer similar core functionality with different config structure. Gateway API's real advantage is its broader resource family (GRPCRoute, TCPRoute, etc.) and extendable architecture, allowing cloud providers to build their own implementations against the same CRDs.
 
### Solution
 
Confirm Gateway API CRDs and existing resources:
 
```bash
k get crd                  # confirms httproutes.gateway.networking.k8s.io etc.
k get gateway -A           # existing Gateway "main" in project-r500, class nginx
k get gatewayclass -A      # GatewayClass "nginx" accepted
k -n project-r500 get gateway main -oyaml
```
 
The Gateway listens on port 80 over HTTP, restricted to routes in the same namespace.
 
Test current state, a 404 confirms no routes are defined yet (served by whichever Gateway API implementation is in use, here Nginx Gateway Fabric, but the same CRDs work regardless of implementation):
 
```bash
curl r500.gateway:30080
```
 
The URL works due to a static `/etc/hosts` entry and a NodePort Service on 30080.
 
Inspect the old Ingress to convert:
 
```yaml
# /opt/course/13/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
spec:
  rules:
    - host: r500.gateway
      http:
        paths:
          - backend: { service: { name: web-desktop, port: { number: 80 } } }
            path: /desktop
            pathType: Prefix
          - backend: { service: { name: web-mobile, port: { number: 80 } } }
            path: /mobile
            pathType: Prefix
```
 
Create the equivalent HTTPRoute, referencing the existing Gateway:
 
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: traffic-director
  namespace: project-r500
spec:
  parentRefs:
    - name: main                # the existing Gateway
  hostnames:
    - "r500.gateway"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /desktop
      backendRefs:
        - name: web-desktop
          port: 80
    - matches:
        - path:
            type: PathPrefix
            value: /mobile
      backendRefs:
        - name: web-mobile
          port: 80
```
 
```bash
k -n project-r500 get httproute
curl r500.gateway:30080/desktop    # Web Desktop App
curl r500.gateway:30080/mobile     # Web Mobile App
```
 
**Adding `/auto`**, append two new rules:
 
```yaml
    # NEW FROM HERE ON
    - matches:
        - path:
            type: PathPrefix
            value: /auto
          headers:
            - type: Exact
              name: user-agent
              value: mobile
      backendRefs:
        - name: web-mobile
          port: 80
    - matches:
        - path:
            type: PathPrefix
            value: /auto
      backendRefs:
        - name: web-desktop
          port: 80
```
 
### Critical detail: AND vs OR in `matches`
 
Within one `matches` list item, `- path:` and `headers:` (no leading dash on `headers`) are **ANDed** together, both must match. This is the structure used above: path `/auto` AND header `user-agent: mobile`.
 
**Wrong** version, where `headers` gets its own dash and becomes a second top-level match condition, making path and header **ORed**:
 
```yaml
    # WRONG EXAMPLE
    - matches:
        - path:
            type: PathPrefix
            value: /auto
        - headers:                  # WRONG: now path OR header, not AND
            - type: Exact
              name: user-agent
              value: mobile
      backendRefs:
        - name: web-mobile
          port: 80
```
 
The desktop fallback rule needs no header check at all, since it's the catch-all for `/auto` otherwise. **Rule order matters**: the mobile-matching rule must come before the desktop catch-all, or no request would ever reach the mobile rule.
 
```bash
curl -H "User-Agent: mobile" r500.gateway:30080/auto      # Web Mobile App
curl -H "User-Agent: something" r500.gateway:30080/auto    # Web Desktop App
curl r500.gateway:30080/auto                                # Web Desktop App
```
 
---
 
## Question 14 | Certificate Management with kubeadm
 
**Solve on:** `ssh cka9412`
 
1. Check kube-apiserver server certificate expiration with openssl or cfssl, write the date into `/opt/course/14/expiration`. Confirm against `kubeadm certs check-expiration`.
2. Write the kubeadm command that would renew the kube-apiserver certificate into `/opt/course/14/kubeadm-renew-certs.sh`
### Solution
 
Locate the certificate:
 
```bash
sudo -i
find /etc/kubernetes/pki | grep apiserver
```
 
Check expiration with openssl:
 
```bash
openssl x509 -noout -text -in /etc/kubernetes/pki/apiserver.crt | grep Validity -A2
```
 
Write the result:
 
```
# /opt/course/14/expiration
Oct 29 14:19:27 2025 GMT
```
 
Cross-check with kubeadm:
 
```bash
kubeadm certs check-expiration | grep apiserver
```
 
Both should match.
 
Write the renewal command:
 
```bash
# /opt/course/14/kubeadm-renew-certs.sh
kubeadm certs renew apiserver
```
 
---
 
## Question 15 | NetworkPolicy
 
**Solve on:** `ssh cka7968`
 
An intruder accessed the whole cluster from a single hacked backend Pod. Create NetworkPolicy `np-backend` in Namespace `project-snake` so `backend-*` Pods may **only**:
 
- Connect to `db1-*` Pods on port 1111
- Connect to `db2-*` Pods on port 2222
Use the `app` Pod label.
 
> Example connectivity test: `k -n project-snake exec POD_NAME -- curl POD_IP:PORT`. Connections to `vault-*` on port 3333 should no longer work after the policy is applied.
 
### Solution
 
Check Pods and labels:
 
```bash
k -n project-snake get pod
k -n project-snake get pod -L app
k -n project-snake get pod -o wide   # note IPs
```
 
Baseline, confirm nothing is currently restricted:
 
```bash
k -n project-snake exec backend-0 -- curl -s <db1-ip>:1111    # database one
k -n project-snake exec backend-0 -- curl -s <db2-ip>:2222    # database two
k -n project-snake exec backend-0 -- curl -s <vault-ip>:3333  # vault secret storage
```
 
Correct policy, **two separate rules**, each with its own `to` + `ports` pairing:
 
```yaml
# 15_np.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: np-backend
  namespace: project-snake
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Egress
  egress:
    - to:                              # first rule
        - podSelector:
            matchLabels:
              app: db1
      ports:
        - protocol: TCP
          port: 1111
    - to:                              # second rule
        - podSelector:
            matchLabels:
              app: db2
      ports:
        - protocol: TCP
          port: 2222
```
 
Read as: allow egress if **(dest label app=db1 AND port 1111) OR (dest label app=db2 AND port 2222)**.
 
### Critical detail: the wrong shape
 
A single rule with multiple `to` entries and multiple `ports` entries does **not** produce the intended restriction:
 
```yaml
# WRONG
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: db1
        - podSelector:
            matchLabels:
              app: db2
      ports:
        - protocol: TCP
          port: 1111
        - protocol: TCP
          port: 2222
```
 
This reads as: allow egress if **(dest is db1 OR db2) AND (port is 1111 OR 2222)**, meaning backend could reach db2 on port 1111 or db1 on port 2222, which should be forbidden. This is the exact AND/OR trap to watch for, same underlying logic gotcha as Question 13's HTTPRoute matches.
 
Apply and verify:
 
```bash
k -f 15_np.yaml create
 
k -n project-snake exec backend-0 -- curl -s <db1-ip>:1111    # still works
k -n project-snake exec backend-0 -- curl -s <db2-ip>:2222    # still works
k -n project-snake exec backend-0 -- curl -s <vault-ip>:3333  # now hangs/blocked
```
 
`kubectl describe` on the NetworkPolicy is useful to confirm how Kubernetes interpreted the rules.
 
---
 
## Question 16 | Customizing CoreDNS
 
**Solve on:** `ssh cka5774`
 
1. Back up the existing CoreDNS ConfigMap YAML to `/opt/course/16/coredns_backup.yaml`, recoverable quickly from this backup
2. Update CoreDNS so `SERVICE.NAMESPACE.custom-domain` resolves identically to, and in addition to, `SERVICE.NAMESPACE.cluster.local`
Test from a Pod (image `busybox:1`):
 
```bash
nslookup kubernetes.default.svc.cluster.local
nslookup kubernetes.default.svc.custom-domain
```
 
### Solution
 
CoreDNS runs as a Deployment (2 replicas) using a ConfigMap by default under kubeadm:
 
```bash
k -n kube-system get deploy,pod
k -n kube-system get cm
```
 
Back up first:
 
```bash
k -n kube-system get cm coredns -oyaml > /opt/course/16/coredns_backup.yaml
```
 
Current Corefile relevant section:
 
```
kubernetes cluster.local in-addr.arpa ip6.arpa {
  pods insecure
  fallthrough in-addr.arpa ip6.arpa
  ttl 30
}
```
 
Edit the ConfigMap, add `custom-domain` on the same line as `cluster.local`:
 
```bash
k -n kube-system edit cm coredns
```
 
```
kubernetes custom-domain cluster.local in-addr.arpa ip6.arpa {
  pods insecure
  fallthrough in-addr.arpa ip6.arpa
  ttl 30
}
```
 
Restart CoreDNS to pick up the change:
 
```bash
k -n kube-system rollout restart deploy coredns
k -n kube-system get pod    # confirm both replicas come back healthy, no syntax errors
```
 
Test:
 
```bash
k run bb --image=busybox:1 -- sh -c 'sleep 1d'
k exec -it bb -- sh
 
nslookup kubernetes.default.svc.custom-domain     # resolves to 10.96.0.1
nslookup kubernetes.default.svc.cluster.local     # resolves to 10.96.0.1
```
 
Both resolve to the same IP, the `kubernetes` Service in `default`, commonly used by operators needing to reach the API server.
 
**Recovery path**, if something breaks:
 
```bash
k diff -f /opt/course/16/coredns_backup.yaml   # preview what would change
k delete -f /opt/course/16/coredns_backup.yaml
k apply -f /opt/course/16/coredns_backup.yaml
k -n kube-system rollout restart deploy coredns
```
 
This only works because a backup was taken first.
 
---
 
## Question 17 | Debug with crictl
 
**Solve on:** `ssh cka2556`
 
In Namespace `project-tiger`, create Pod `tigers-reunite` (image `httpd:2-alpine`, labels `pod=container` and `container=pod`). Find which node it's scheduled on, SSH there, find the containerd container.
 
Using `crictl`:
 
1. Write the container ID and `info.runtimeType` into `/opt/course/17/pod-container.txt`
2. Write the container's logs into `/opt/course/17/pod-container.log`
> Connect to worker nodes via `ssh cka2556-node1` or `ssh cka2556-node2` from `cka2556`. In this environment `crictl` is used; in the real exam this could be `docker` instead, with the same arguments.
 
### Solution
 
Create the Pod:
 
```bash
k -n project-tiger run tigers-reunite --image=httpd:2-alpine --labels "pod=container,container=pod"
```
 
Find its node:
 
```bash
k -n project-tiger get pod -o wide
```
 
SSH to that node and find the container:
 
```bash
ssh cka2556-node1
sudo -i
crictl ps | grep tigers-reunite
```
 
Inspect for the runtime type:
 
```bash
crictl inspect <container-id> | grep runtimeType
```
 
Write the result (from the original node, container ID + runtime type):
 
```
# /opt/course/17/pod-container.txt
ba62e5d465ff0 io.containerd.runc.v2
```
 
Get the logs:
 
```bash
crictl logs <container-id>
```
 
Write to the requested file. For short logs, copy/paste manually; for longer logs, write to a file on the worker node and `scp` it back, or pipe through SSH directly.
 
---
 
## Preview Question 1 | Certificates Best Practices (etcd)
 
**Solve on:** `ssh cka9412`
 
Find out about etcd running on cka9412:
 
- Server private key location
- Server certificate expiration date
- Whether client certificate authentication is enabled
Write into `/opt/course/p1/etcd-info.txt`.
 
### Solution
 
Check how etcd runs:
 
```bash
k get node
sudo -i
k -n kube-system get pod    # etcd-cka9412 is a static Pod
```
 
Static Pod manifests live at the default kubelet path:
 
```bash
find /etc/kubernetes/manifests/
vim /etc/kubernetes/manifests/etcd.yaml
```
 
Relevant flags:
 
```
--cert-file=/etc/kubernetes/pki/etcd/server.crt      # server certificate
--client-cert-auth=true                               # enabled
--key-file=/etc/kubernetes/pki/etcd/server.key        # server private key
```
 
Check expiration:
 
```bash
openssl x509 -noout -text -in /etc/kubernetes/pki/etcd/server.crt | grep Validity -A2
```
 
Write the answer:
 
```
# /opt/course/p1/etcd-info.txt
Server private key location: /etc/kubernetes/pki/etcd/server.key
Server certificate expiration date: Oct 29 14:19:29 2025 GMT
Is client certificate authentication enabled: yes
```
 
---
 
## Preview Question 2 | kube-proxy / Service iptables
 
**Solve on:** `ssh cka3962`
 
In Namespace `project-hamster`:
 
1. Create Pod `p2-pod`, image `nginx:1-alpine`
2. Create Service `p2-service` exposing the Pod internally on port `3000->80`
3. Write iptables rules on node `cka3962` for `p2-service` into `/opt/course/p2/iptables.txt`
4. Delete the Service and confirm the iptables rules disappear
### Solution
 
```bash
k -n project-hamster run p2-pod --image=nginx:1-alpine
k -n project-hamster expose pod p2-pod --name p2-service --port 3000 --target-port 80
k -n project-hamster get pod,svc
```
 
Check kube-proxy's mode (informational):
 
```bash
sudo -i
crictl ps | grep kube-proxy
crictl logs <kube-proxy-container-id>    # e.g. "Using iptables proxy"
```
 
Inspect and capture the iptables rules:
 
```bash
iptables-save | grep p2-service
iptables-save | grep p2-service > /opt/course/p2/iptables.txt
```
 
Delete the Service and confirm cleanup:
 
```bash
k -n project-hamster delete svc p2-service
iptables-save | grep p2-service     # empty
```
 
### Background
 
Kubernetes Services are implemented via iptables rules (default config) on every node. Whenever a Service or its Endpoints change, the API server notifies every node's kube-proxy to update the local iptables rules to match current state.
 
---
 
## Preview Question 3 | Change Service CIDR
 
**Solve on:** `ssh cka9412`
 
1. Create Pod `check-ip` in Namespace `default`, image `httpd:2-alpine`
2. Expose it on port 80 as ClusterIP Service `check-ip-service`, note its IP
3. Change the Service CIDR to `11.96.0.0/12` for the cluster
4. Create a second Service `check-ip-service2` pointing to the same Pod
> The second Service should get an IP from the new CIDR range.
 
### Solution
 
```bash
k run check-ip --image=httpd:2-alpine
k expose pod check-ip --name check-ip-service --port 80
k get svc    # note existing CIDR-based IP, e.g. 10.97.6.41
```
 
Edit the kube-apiserver static manifest:
 
```bash
sudo -i
vim /etc/kubernetes/manifests/kube-apiserver.yaml
```
 
```
--service-cluster-ip-range=11.96.0.0/12    # change
```
 
Wait for the apiserver to restart (kubelet watches the manifest):
 
```bash
watch crictl ps
kubectl -n kube-system get pod | grep api
```
 
Repeat the same CIDR change in the controller-manager manifest:
 
```bash
vim /etc/kubernetes/manifests/kube-controller-manager.yaml
```
 
```
--service-cluster-ip-range=11.96.0.0/12    # change
```
 
```bash
watch crictl ps
kubectl -n kube-system get pod | grep controller
```
 
**Register the new range as a `ServiceCIDR` resource**, this is required in addition to the flag changes:
 
```bash
k get servicecidr    # existing "kubernetes" resource shows 10.96.0.0/12
 
cat <<'EOF' | k apply -f -
apiVersion: networking.k8s.io/v1
kind: ServiceCIDR
metadata:
  name: svc-cidr-new
spec:
  cidrs:
    - 11.96.0.0/12
EOF
```
 
Delete the old ServiceCIDR (it will sit in a Terminating state until no Services reference its range any longer; existing Services are unaffected):
 
```bash
k delete servicecidr kubernetes
k get servicecidr kubernetes -oyaml    # status.conditions shows reason: Terminating
```
 
Create the second Service, it picks up an IP from the new range automatically:
 
```bash
k expose pod check-ip --name check-ip-service2 --port 80
k get svc
```
 
`check-ip-service` keeps its original (old-range) IP; `check-ip-service2` gets an IP like `11.108.174.69` from the new range.
 
---
 
## General Exam Tips (from the PDF)
 
- Study all curriculum topics until comfortable, then complete both Killer.sh sessions under timed conditions and review solutions afterward, trying alternate approaches where possible.
- Be fast with kubectl. Speed matters as much as correctness.
- Much of the CKA overlaps with CKAD-style resource creation, so light CKAD prep has crossover value.
- Practice in-browser scenarios at killercoda.com/killer-shell-cka (and killercoda.com/killer-shell-ckad for CKAD crossover).
- Invent your own break/fix scenarios to practice diagnosis from symptoms.
- Review Kubernetes' own debugging guide: kubernetes.io/docs/tasks/debug-application-cluster/debug-cluster
- Review advanced scheduling concepts: kubernetes.io/docs/concepts/scheduling/kube-scheduler
- When troubleshooting a broken component (e.g. kubelet), compare its configuration against a working node in the same or another cluster; config files can be copied over for reference.
- Kubernetes the Hard Way is optional, helpful for conceptual understanding but not required for CKA-level complexity.
- Build your own kubeadm cluster (one controlplane, one worker) and investigate the components directly.
- Know how to use kubeadm to add nodes to a cluster.
- Know how to create Ingress resources.
- Allowed documentation during the exam: kubernetes.io/docs, kubernetes.io/blog, helm.sh/docs, gateway-api.sigs.k8s.io.
- The exam environment is a Remote Desktop (XFCE) on Ubuntu/Debian, accessed via PSI Secure Browser. Multiple monitors and personal bookmarks are not permitted. A timer shows actual time remaining with alerts at 30/15/5 minutes.
- 15 to 20 performance-based questions per attempt, each solved on a separate instance reached via SSH (command provided per question). Questions can be flagged for later review (a personal marker only, doesn't affect scoring); a browser notepad is available for jotting notes on flagged items.
- `kubectl` (aliased `k`), Bash autocompletion, `yq`, `curl`, `wget`, and `man` pages are pre-installed. Installing additional tools like `tmux` or `jq` is allowed.
- Copy/paste: right-click context menu always works; `Ctrl+Shift+C` / `Ctrl+Shift+V` in terminal; normal `Ctrl+C` / `Ctrl+V` in GUI apps like Firefox.
- Since each question is solved on a different instance via SSH, bash aliases set in one session won't carry over, don't rely on them.
- Use `history` and `Ctrl+R` for fast command reuse. Background long-running commands with `&` / `Ctrl+Z` and bring back with `fg`.
- Fast pod deletion: `k delete pod x --grace-period 0 --force`
- Useful `~/.vimrc` settings if pasting/indentation misbehaves: `set tabstop=2`, `set expandtab`, `set shiftwidth=2` (note: vimrc changes don't transfer across SSH sessions to other instances).
- Vim line numbers toggle: `:set number` / `:set nonumber`. Jump to a line: `:22`.
- Vim block operations: mark with `Esc` then `Shift+V` and arrow keys, copy with `y`, cut with `d`, paste with `p`/`P`. For indenting marked blocks: `:set shiftwidth=2`, then `>` or `<`, repeatable with `.`.