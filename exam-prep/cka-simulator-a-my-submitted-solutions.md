# Killer Shell CKA Simulator A: My Submitted Solutions
 
This document captures the actual commands, YAML, and command history I submitted during my Simulator A attempt, recovered from the post-exam review environment. This is a personal record for comparing against the official solutions doc and the remediation plan, not a study reference on its own.
 
**Companion documents:**
- `killer-sh-cka-simulator-a-solutions.md` (official solution walkthroughs)
- `cka-simulator-a-remediation-plan.md` (gap analysis and remediation steps)
---
 
## Question 1 | Cluster Access with kubeconfig
 
**Solve on:** `ssh cka9412`
 
```bash
candidate@cka9412:~$ export KUBECONFIG=/opt/course/1/kubeconfig
candidate@cka9412:~$ kubectl config current-context>/opt/course/1/current-context
candidate@cka9412:~$ kubectl config view --raw -o jsonpath="{.users[0].user.client-certificate-data}"|base64 -d>/opt/course/1/cert
   25  kubectl config view -o jsonpath='{.contexts[*].name}' >/opt/course/1/contexts
```
 
---
 
## Question 2 | CRD, Helm, cert-manager
 
**Solve on:** `ssh cka7968`
 
Command history:
 
```bash
candidate@cka7968:~$ history
    1  kubectl create ns cert-manager
    2  helm repo list
    3  helm install -h
    4  clear
    5  helm install cert-manager --set crds.enabled=true jetstack/cert-manager -n cert-manager
    6  helm list cert-manager
    7  helm list -n cert-manager
    8  helm get values cert-manager -n cert-manager
    9  vim /opt/course/2/cluster-issuer.yaml
   10  kubectl apply -f /opt/course/2/cluster-issuer.yaml
   11  kubectl get ClusterIssuer
```
 
Final ClusterIssuer file:
 
```bash
candidate@cka7968:~$ cat /opt/course/2/cluster-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: course-issuer
spec:
  selfSigned:
    crlDistributionPoints: ["http://example.com/crl"]
```
 
**Score:** 5/5
 
---
 
## Question 3 | Scale a StatefulSet
 
**Solve on:** `ssh cka3962`
 
Command history:
 
```bash
    3  kubectl -n project-h800 get statefulset
    4  kubectl -n project-h800 scale statefulset o3db --replicas=1
    5  kubectl -n project-h800 get statefulset
    6  kubectl -n project-h800 get pods
```
 
**Score:** 1/1
 
---
 
## Question 4 | Pod Quality of Service Classes / Node-pressure Eviction
 
**Solve on:** `ssh cka2556`
 
Done twice, two different approaches, same correct result.
 
### Attempt 1: custom-columns inspection
 
```bash
candidate@cka2556:~$ kubectl -n project-c13 get pods -o custom-columns='NAME:.metadata.name,CPU:.spec.containers[].resources.requests.cpu,MEM:.spec.containers[].resources.requests.memory'
NAME                                    CPU      MEM
c13-2x3-api-5847f4f998-2dw5c            50m      20Mi
c13-2x3-api-5847f4f998-hl6w8            50m      20Mi
c13-2x3-api-5847f4f998-qsm2k            50m      20Mi
c13-2x3-web-f6d4cccc6-4dn9k             50m      10Mi
c13-2x3-web-f6d4cccc6-4t79h             50m      10Mi
c13-2x3-web-f6d4cccc6-6lxtw             50m      10Mi
c13-2x3-web-f6d4cccc6-clh5c             50m      10Mi
c13-2x3-web-f6d4cccc6-dhl5q             50m      10Mi
c13-2x3-web-f6d4cccc6-vgn4p             50m      10Mi
c13-3cc-data-75c75647db-54gwm           30m      10Mi
c13-3cc-data-75c75647db-sg99n           30m      10Mi
c13-3cc-data-75c75647db-v4bqb           30m      10Mi
c13-3cc-runner-heavy-84f9fc458c-857tg   <none>   <none>
c13-3cc-runner-heavy-84f9fc458c-c6stf   <none>   <none>
c13-3cc-runner-heavy-84f9fc458c-c7p9s   <none>   <none>
c13-3cc-web-68d5c97cbf-6dm6f            50m      10Mi
c13-3cc-web-68d5c97cbf-7p68w            50m      10Mi
c13-3cc-web-68d5c97cbf-hp446            50m      10Mi
c13-3cc-web-68d5c97cbf-wvws5            50m      10Mi
candidate@cka2556:~$ kubectl -n project-c13 get pods -o custom-columns='NAME:.metadata.name,CPU:.spec.containers[].resources.requests.cpu,MEM:.spec.containers[].resources.requests.memory'|grep none|awk '{print $1}'> /opt/course/4/pods-terminated-first.txt
candidate@cka2556:~$ cat /opt/course/4/pods-terminated-first.txt
c13-3cc-runner-heavy-84f9fc458c-857tg
c13-3cc-runner-heavy-84f9fc458c-c6stf
c13-3cc-runner-heavy-84f9fc458c-c7p9s
```
 
### Attempt 2: deployment label inspection
 
Identified the namespace had Deployments, inspected their requested resources, then selected by label directly:
 
```bash
kubectl -n project-c13 get pods -l "id=c13-3cc-runner-heavy" -o custom-columns='NAME:.metadata.name'>/opt/course/4/pods-terminated-first.txt
```
 
**Score:** 1/1 (both attempts produced the same correct three pod names)
 
---
 
## Question 5 | Horizontal Pod Autoscaling with Kustomize
 
**Solve on:** `ssh cka5774`
 
Self-noted: used `kubectl autoscale --dry-run=client` to generate the HPA YAML rather than hand-writing it, then adapted into the Kustomize base.
 
1. Removed the hardcoded ConfigMap from the kustomize resource YAML files.
2. Generated the HPA YAML via `kubectl autoscale --dry-run=client -o yaml` and added it to the base kustomize project.
```bash
candidate@cka5774:~$ kubectl -n api-gateway-staging autoscale deployment.apps/api-gateway --min=2 --max=4 --cpu=50% --name api-gateway --dry-run=client -o yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-gateway
  namespace: api-gateway-staging
spec:
  maxReplicas: 4
  metrics:
  - resource:
      name: cpu
      target:
        averageUtilization: 50
        type: Utilization
    type: Resource
  minReplicas: 2
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-gateway
status:
  currentMetrics: null
  desiredReplicas: 0
```
 
Resulting `base/api-gateway.yaml`:
 
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
spec:
  replicas: 1
  selector:
    matchLabels:
      id: api-gateway
  template:
    metadata:
      labels:
        id: api-gateway
    spec:
      serviceAccountName: api-gateway
      containers:
        - image: httpd:2-alpine
          name: httpd
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-gateway
spec:
  maxReplicas: 4
  metrics:
  - resource:
      name: cpu
      target:
        averageUtilization: 50
        type: Utilization
    type: Resource
  minReplicas: 2
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-gateway
```
 
Modified `staging/api-gateway.yaml`:
 
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  labels:
    env: staging
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-gateway
  labels:
    env: staging
```
 
Modified `prod/api-gateway.yaml`:
 
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  labels:
    env: prod
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-gateway
  labels:
    env: prod
spec:
  maxReplicas: 6
```
 
`prod/kustomization.yaml`:
 
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
      namespace: api-gateway-prod
```
 
**Self-noted miss:** forgot to manually delete the live ConfigMap from the cluster after removing it from the Kustomize source.
 
**Score:** 5/6 — matches the score feedback exactly (HPA created correctly with right values in both overlays, ConfigMap removed from source but not deleted live).
 
---
 
## Question 6 | Configure a Pod to Use Storage
 
**Solve on:** `ssh cka7968`
 
```yaml
candidate@cka7968:~$ cat r.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: safari-pv
  labels:
    type: local
spec:
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/Volumes/data"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: safari-pvc
  namespace: project-t230
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: safari
  name: safari
  namespace: project-t230
spec:
  replicas: 1
  selector:
    matchLabels:
      app: safari
  strategy: {}
  template:
    metadata:
      labels:
        app: safari
    spec:
      containers:
      - image: httpd:2-alpine
        name: httpd
        volumeMounts:
        - name: data
          mountPath: /tmp/safari-data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: safari-pvc
```
 
**Note:** the YAML as originally submitted during the exam had `hostPath.path: "/Volumes/data"` (lowercase d), matching the score feedback's stated reason for the 5/6 score. This was corrected to the proper capital-D `/Volumes/Data` manually after exam submission, for review/remediation purposes, the version above reflects the original (incorrect) submission.
 
**Score:** 5/6 — matches the score feedback (hostPath path capitalization mismatch).
 
---
 
## Question 7 | kubectl Quick Reference (Resource Monitoring)
 
**Solve on:** `ssh cka5774`
 
Command history:
 
```bash
   59  echo "kubectl top nodes" > /opt/course/7/node.sh
   60  kubectl top pods -h
   61  kubectl top pods --containers
   62  kubectl top pods --containers=true
   63  echo "kubectl top pods --containers=true" > /opt/course/7/pod.sh
   64  chmod +x /opt/course/7/{node.sh,pod.sh}
   65  /opt/course/7/pod.sh
   66  /opt/course/7/node.sh
```
 
**Score:** 2/2
 
---
 
## Question 8 | Update Kubernetes Version and Join Cluster
 
**Solve on:** `ssh cka3962`
 
Approach (narrative, partial command history captured):
 
1. From the control plane, queried `dpkg` for `kube*` packages to find the baseline/target version:
```bash
    9  sudo dpkg -l |grep kube
```
 
2. SSHed to the worker node and upgraded the kubelet/kubectl packages to match the controlplane version first.
3. Returned to the control plane and created a long-lived token (`kubeadm token create --print-join-command` or equivalent) to use for the join.
4. SSHed back to the worker node and ran the `kubeadm join` command.
**Note:** only the initial `dpkg` inspection line was captured from history; the apt install, token creation, and join command steps are not yet recovered verbatim, but the full sequence was executed correctly per the score.
 
**Score:** 4/4
 
---
 
## Question 12 | Assigning Pods to Nodes (Anti-Affinity / Topology Spread)
 
**Solve on:** `ssh cka2556`
 
Used the `topologySpreadConstraints` approach (not `podAntiAffinity`).
 
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: deploy-important
    id: very-important
  name: deploy-important
  namespace: project-tiger
spec:
  replicas: 3
  selector:
    matchLabels:
      app: deploy-important
  strategy: {}
  template:
    metadata:
      labels:
        app: deploy-important
        id: very-important
    spec:
      containers:
      - name: container1
        image: nginx:1-alpine
      - name: container2
        image: registry.k8s.io/pause:3.10
      topologySpreadConstraints:
      - topologyKey: "kubernetes.io/hostname"
        maxSkew: 1
        whenUnsatisfiable: "DoNotSchedule"
        labelSelector:
          matchLabels:
            id: very-important
```
 
**Discrepancy flagged for review:** this YAML already includes `labelSelector.matchLabels: id: very-important`, which contradicts the score feedback's stated reason (missing `labelSelector.matchLabels`). The constraint logic itself (maxSkew 1, DoNotSchedule, two worker nodes, three replicas) looks structurally correct for producing the expected 2-running/1-pending split.
 
**Working theory pending discussion:** the constraint may not have been in effect at the time the Deployment was first created/scheduled, e.g. if this YAML reflects a later edit/reapply rather than the original `create`, Kubernetes would not retroactively reschedule already-running Pods to satisfy a constraint added after the fact. This would explain the observed result (`readyReplicas: 3`, all three Pods on the same node) despite the YAML looking correct now. Not yet confirmed, needs follow-up.
 
**Score:** 8/11 (reason disputed, see above)
 
---
 
## Question 9 | Contact K8s API from Inside a Pod
 
**Solve on:** `ssh cka9412`
 
```yaml
candidate@cka9412:~$ cat d.yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: api-contact
  name: api-contact
  namespace: project-swan
spec:
  serviceAccountName: secret-reader
  containers:
  - image: nginx:1-alpine
    name: api-contact
  dnsPolicy: ClusterFirst
  restartPolicy: Always
```
 
```bash
candidate@cka9412:~$ kubectl -n project-swan exec -it api-contact -- sh -c 'cd /run/secrets/kubernetes.io/serviceaccount; curl --cacert ca.crt --header "Authorization: Bearer $(cat token)" -X GET https://10.96.0.1:443/api/v1/secrets'>/opt/course/9/result.json
```
 
**Note:** used the literal Service ClusterIP (`10.96.0.1:443`) directly rather than the `kubernetes.default` DNS name, and used `--cacert` against the mounted `ca.crt` rather than `-k`, avoiding the insecure flag entirely. Functionally equivalent to the documented approach.
 
**Score:** 2/2
 
---
 
## Question 10 | Configure Service Accounts for Pods (RBAC)
 
**Solve on:** `ssh cka3962`
 
```yaml
candidate@cka3962:~$ cat r.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: processor
  namespace: project-hamster
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: processor
  namespace: project-hamster
rules:
- apiGroups:
  - ""
  resources:
  - configmaps
  - secrets
  verbs:
  - create
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: processor
  namespace: project-hamster
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: processor
subjects:
- kind: ServiceAccount
  name: processor
  namespace: project-hamster
```
 
```bash
candidate@cka3962:~$ kubectl apply -f r.yaml
```
 
Verification:
 
```bash
candidate@cka3962:~$ kubectl auth can-i create secrets -n project-hamster --as=system:serviceaccount:project-hamster:processor
candidate@cka3962:~$ kubectl auth can-i create configmaps -n project-hamster --as=system:serviceaccount:project-hamster:processor
```
 
**Score:** 6/6
 
---
 
## Question 11 | DaemonSet with Taints and Tolerations
 
**Solve on:** `ssh cka2556`
 
```yaml
candidate@cka2556:~$ cat ds.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ds-important
  namespace: project-tiger
  labels:
    id: ds-important
    uuid: 18426a0b-5f59-4e10-923f-c0e078e82462
spec:
  selector:
    matchLabels:
      name: httpd
  template:
    metadata:
      labels:
        name: httpd
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      containers:
      - name: httpd
        image: httpd:2-alpine
        resources:
          requests:
            cpu: 10m
            memory: 10Mi
```
 
```bash
candidate@cka2556:~$ kubectl apply -f ds.yaml
```
 
**Note:** added a second toleration for the legacy `node-role.kubernetes.io/master` taint key alongside `control-plane`, covering both naming conventions defensively. Pod template label used `name: httpd` rather than reusing the `id`/`uuid` pair as the selector, both are valid since the question only required the Pod labels to match the selector, not specifically reuse the DaemonSet's own identifying labels.
 
**Score:** 4/4
 
---
 
## Question 13 | Gateway API Migration from Ingress
 
**Solve on:** `ssh cka7968`
 
**Skipped.** No attempt made during the exam.
 
**Score:** 0/5 — matches the score feedback (all subtasks failed, consistent with no attempt rather than a partial/incorrect attempt). This resolves the open question from the remediation plan about whether this was a coverage gap from a failed attempt versus simply not attempted, it was the latter.
 
---
 
## Question 14 | Certificate Management with kubeadm
 
**Solve on:** `ssh cka9412`
 
```bash
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -enddate 2>&1 > /opt/course/14/expiration
```
 
Compared against:
 
```bash
kubeadm certs check-expiration
```
 
Then:
 
```bash
root@cka9412:/home/candidate# echo "kubeadm certs renew apiserver" > /opt/course/14/kubeadm-renew-certs.sh
```
 
**Note:** used `-enddate` (returns just the `notAfter=` line) rather than `-text | grep Validity -A2` (returns the full Validity block with both Not Before and Not After). Both surface the expiration date; `-enddate` is the more direct flag for this specific ask. The `2>&1` redirect captures stderr alongside stdout into the file, harmless here since openssl shouldn't error on a valid cert read.
 
**Score:** 2/2
 
---
 
## Question 15 | NetworkPolicy
 
**Solve on:** `ssh cka7968`
 
**Skipped.** No attempt made during the exam.
 
**Score:** 0/7 — matches the score feedback (all subtasks failed, consistent with no attempt rather than a partial/incorrect attempt). Same resolution as Question 13: this was not an attempted-but-wrong NetworkPolicy, it simply wasn't attempted. The AND/OR egress-rule trap flagged in the remediation plan is still worth drilling, but it wasn't the actual cause of this particular score.
 
---
 
## Question 16 | Customizing CoreDNS
 
**Solve on:** `ssh cka5774`
 
**Skipped.** No attempt made during the exam.
 
**Score:** 0/3 — matches the score feedback (all subtasks failed, consistent with no attempt). Same resolution as Questions 13 and 15.
 
---
 
## Why Questions 13, 15, and 16 Were Skipped
 
All three zero-score "coverage gaps" identified in the remediation plan (Gateway API/HTTPRoute, NetworkPolicy, CoreDNS custom domain) were not attempted-and-failed, they were skipped outright. The reasoning given: these were topics where the solution wasn't confidently known, and attempting them would have required looking up reference documentation and spending several minutes on a question with uncertain payoff, time that was better spent on questions with a clearer path to points.
 
**This changes the diagnostic categorization from the remediation plan.** The original plan treated these as "coverage gap: wrong mental model produced a failing attempt." The accurate categorization is closer to **time-allocation triage under uncertainty**: recognizing unfamiliar territory fast and reallocating time to higher-confidence questions is a reasonable exam strategy, but it does mean these three topics remain completely unverified, there is no attempt data showing whether the AND/OR matches/rules trap would have actually been hit, only that the underlying procedures (HTTPRoute creation, NetworkPolicy egress rules, CoreDNS ConfigMap editing) were not confidently known well enough to attempt under time pressure.
 
The remediation steps in the companion plan (re-read docs, rebuild from scratch, compare against solutions) are still the right next action for all three. What changes is the framing: this is **first-pass learning**, not **debugging a wrong mental model**. Worth tracking on the next attempt (Killer.sh Session 2) whether these get attempted at all, since a repeat skip would indicate the redo session didn't build enough confidence to engage with the topic under time pressure, whereas an attempt (even an imperfect one) would indicate real progress.
 
---
 
## Question 17 | Debug with crictl
 
**Solve on:** `ssh cka2556`
 
```bash
candidate@cka2556:~$ kubectl -n project-tiger run tigers-reunite --image=httpd:2-alpine --dry-run=client -o yaml> p.yaml
```
 
Added the required labels to `p.yaml` manually, then applied. Confirmed scheduling:
 
```bash
candidate@cka2556:~$ kubectl get pod tigers-reunite -n project-tiger -o wide
NAME             READY   STATUS    RESTARTS   AGE     IP           NODE            NOMINATED NODE   READINESS GATES
tigers-reunite   1/1     Running   0          4h54m   10.44.0.19   cka2556-node1   <none>           <none>
```
 
SSHed to the worker node:
 
```bash
candidate@cka2556:~$ ssh cka2556-node1
candidate@cka2556-node1:~$ crictl ps -a
FATA[0000] validate service connection: validate CRI v1 runtime API for endpoint "unix:///run/containerd/containerd.sock": rpc error: code = Unavailable desc = connection error: desc = "transport: Error while dialing: dial unix /run/containerd/containerd.sock: connect: permission denied"
candidate@cka2556-node1:~$ sudo -s
root@cka2556-node1:/home/candidate# crictl ps -a
CONTAINER           IMAGE               CREATED             STATE               NAME                ATTEMPT             POD ID              POD                                     NAMESPACE
067f40df6e533       873ed75102791       About an hour ago   Running             container2          0                   fc3476215f557       deploy-important-69bc956688-zv8rs       project-tiger
f9a4a9a91bbb3       812d47f806db4       About an hour ago   Running             container1          0                   fc3476215f557       deploy-important-69bc956688-zv8rs       project-tiger
10505004b889c       1330ad8e3398d       5 hours ago         Running             tigers-reunite      0                   914c0336cd45e       tigers-reunite                          project-tig
```
 
**Note:** hit `permission denied` on `crictl ps -a` as a regular user first, since the containerd socket requires root, resolved with `sudo -s`. Worth keeping in mind for the real exam, default to `sudo -i` or `sudo -s` on worker nodes before running `crictl` rather than troubleshooting the permission error first.
 
Inspected the container:
 
```bash
root@cka2556-node1:/home/candidate# crictl inspect 10505004b889c|grep id
        "io.kubernetes.pod.uid": "ec5b1520-9319-4167-8c74-fc4f0db36526"
            "pid": 1,
    "pid": 22809,
        "io.kubernetes.cri.sandbox-id": "914c0336cd45e7d53304f73487719e63777f0d31aacc2426d0fa4a9bb7cd0005",
        "io.kubernetes.cri.sandbox-uid": "ec5b1520-9319-4167-8c74-fc4f0db36526"
            "type": "pid"
            "nosuid",
            "nosuid",
            "nosuid",
            "gid=5"
            "nosuid",
            "nosuid",
            "nosuid",
          "additionalGids": [
          "gid": 0,
          "uid": 0
    "id": "10505004b889ce0d8cb054ca4deb7860546629caef3b14fe89a43f54df0859f2",
      "io.kubernetes.pod.uid": "ec5b1520-9319-4167-8c74-fc4f0db36526"
        "gidMappings": [],
        "uidMappings": []
        "gidMappings": [],
        "uidMappings": []
        "gidMappings": [],
        "uidMappings": []
        "gid": "0",
        "uid": "0"
root@cka2556-node1:/home/candidate# crictl inspect 10505004b889c|jq '.info.runtimeType'
"io.containerd.runc.v2"
```
 
**Note:** used `crictl inspect <id> | jq '.info.runtimeType'` to extract the runtime type cleanly via jq, rather than `grep runtimeType`. Both work; jq with the explicit field path is more precise and avoids any risk of grep matching an unintended line.
 
Returned to the control plane and manually wrote the container ID and runtime type into `/opt/course/17/pod-container.txt`.
 
Captured logs directly via `kubectl logs` rather than `crictl logs` on the node:
 
```bash
candidate@cka2556:~$ kubectl -n project-tiger logs tigers-reunite > /opt/course/17/pod-container.log
```
 
**Note:** this is a meaningful deviation from the documented approach, which uses `crictl logs <container-id>` run on the worker node itself. `kubectl logs` goes through the API server/kubelet log-streaming path rather than reading the container runtime's log directly, but for a single-container Pod with no log rotation or buffering issues, the output is equivalent. Worth keeping `crictl logs` in mind as the more "on-the-node" debugging-flavored approach the question is likely testing for, even though `kubectl logs` produced a passing score here.
 
**Score:** stated as 6/6 here, but the original score export (and remediation plan) recorded this question at 5/6 with the stated reason "pod missing the `pod: container` label, only `container: pod` and an extra `run: tigers-reunite` label were present." The `p.yaml` above started from `kubectl run ... --dry-run=client` (which auto-adds `run: tigers-reunite`) with labels "added manually" afterward, consistent with a scenario where one of the two required labels could have been missed in that manual edit, matching the original score feedback. Flagged as unreconciled, needs a check against the actual final label set on the live Pod (`kubectl get pod tigers-reunite -n project-tiger --show-labels`) if still accessible, rather than relying on memory of the intended edit.
 
---
 
## Open Items for Review
 
- **Question 8:** recover the full command sequence (apt install version pin, token creation, kubeadm join) if useful for the remediation record; not essential since the score was full marks.
- **Question 12:** confirm or rule out the "constraint added after initial creation" theory as the actual root cause, rather than the missing-labelSelector explanation from the score feedback.
- **Question 17:** reconcile the 6/6 stated here against the 5/6 recorded in the original score export and remediation plan, which cited a missing `pod: container` label. Check the live Pod's label set if still accessible.
- **Remediation plan revision needed:** Questions 13, 15, and 16 (the three "coverage gap" zero-scores) were all skipped outright, not attempted-and-failed. See the "Why Questions 13, 15, and 16 Were Skipped" section above. The remediation plan's categorization of these as conceptual/structural failures should be corrected to reflect that they are first-pass learning gaps rather than corrections to a wrong mental model.