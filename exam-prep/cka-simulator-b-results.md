# Killer.sh CKA Simulator B: Results

**Score:** 46 / 93 subtasks (49.5%), labeled "Low Score"
**Session ID:** 2107aee7-a1f2-4fee-b60e-e50819497912
**Date recorded:** 2026-06-26
**Comparison:** Simulator A scored 53/74 (71.6%). Simulator B uses a different question set with more subtasks (93 vs 74), so the raw percentages are not directly comparable question-for-question, but the drop from 71.6% to 49.5% is a real signal, not an artifact of scale.

This document is a literal transcription of the subtask-level pass/fail data and the score-feedback text shown on the results page. It does not yet contain root-cause analysis or remediation steps. That belongs in a follow-up remediation plan, written the same way `cka-simulator-a-remediation-plan.md` was written for Session 1, once the submitted solutions are recovered and checked against this feedback (score feedback text is not authoritative on its own, per the Simulator A precedent).

---

## Question 1 | CoreDNS ConfigMap (2/5)

| Subtask | Result |
|---|---|
| DNS_1 in ConfigMap correct | Pass |
| DNS_2 in ConfigMap correct | Fail |
| DNS_3 in ConfigMap correct | Fail |
| DNS_4 in ConfigMap correct | Pass |
| Correct values from ConfigMap available in Deployment | Fail |

**Score feedback:** the ConfigMap has two incorrect values. `DNS_2` is set to `department.lima-workload.cluster.local` but should be `department.lima-workload.svc.cluster.local` (missing the `.svc` segment). `DNS_3` is set to `10-32-0-9.lima-workload.pod.cluster.local` but should be `section100.section.lima-workload.svc.cluster.local` (a pod-IP-based format was used where a hostname-and-subdomain format was required). Because the Deployment pods picked up these incorrect ConfigMap values through their environment, the downstream "values available in Deployment" check also failed.

---

## Question 2 | Static Pod, Resources, Service (7/7)

| Subtask | Result |
|---|---|
| Static Pod my-static-pod-cka2560 exists | Pass |
| Pod has single container | Pass |
| Pod container has correct image | Pass |
| Pod has correct CPU resource requests | Pass |
| Pod has correct memory resource requests | Pass |
| Service is of type NodePort | Pass |
| Service selector matches Pod | Pass |

Full marks, no feedback shown.

---

## Question 3 | Kubelet Certificates (2/4)

| Subtask | Result |
|---|---|
| Kubelet Client Certificate Issuer is correct | Pass |
| Kubelet Client Certificate Extended Key Usage is correct | Pass |
| Kubelet Server Certificate Issuer is correct | Fail |
| Kubelet Server Certificate Extended Key Usage is correct | Fail |

**Score feedback:** the submitted file `/opt/course/3/certificate-info.txt` contains only the client certificate information. Both required fields for the server certificate, the CN `cka5248-node1-ca` and the "TLS Web Server Authentication" usage, are absent. The second certificate entry in the file incorrectly shows `issuer=CN = kubernetes` instead of the worker node's own server CA, and the Extended Key Usage line reads "No extensions in certificate" instead of the required server-authentication value. This indicates the wrong certificate (likely the client cert inspected twice, or the API server's own cert) was checked instead of the kubelet's server certificate.

---

## Question 4 | Pods with Probes and Labels (11/11)

| Subtask | Result |
|---|---|
| Pod1 is running | Pass |
| Pod1 has single container | Pass |
| Pod1 container is Ready | Pass |
| Pod1 container has correct image | Pass |
| Pod1 container has LivenessProbe | Pass |
| Pod1 container has ReadinessProbe | Pass |
| Pod2 is running | Pass |
| Pod2 has correct label | Pass |
| Pod2 has single container | Pass |
| Pod2 container is Ready | Pass |
| Pod2 container has correct image | Pass |

Full marks, no feedback shown.

---

## Question 5 | Scripted Pod Queries (2/2)

| Subtask | Result |
|---|---|
| File /opt/course/5/find_pods.sh valid | Pass |
| File /opt/course/5/find_pods_uid.sh valid | Pass |

Full marks, no feedback shown.

---

## Question 6 | Node Readiness and Pod Scheduling (2/2)

| Subtask | Result |
|---|---|
| Node is Ready | Pass |
| Pod is created and running | Pass |

Full marks, no feedback shown.

---

## Question 7 | etcd Version and Snapshot (2/2)

| Subtask | Result |
|---|---|
| Version info correct | Pass |
| Snapshot created | Pass |

Full marks, no feedback shown.

---

## Question 8 | Control Plane Component Health (6/6)

| Subtask | Result |
|---|---|
| Kubelet info valid | Pass |
| Kube-apiserver info valid | Pass |
| Kube-scheduler info valid | Pass |
| Kube-controller-manager info valid | Pass |
| ETCD info valid | Pass |
| DNS info valid | Pass |

Full marks, no feedback shown.

---

## Question 9 | Multi-Pod Scheduling and Scheduler Restart (0/10)

| Subtask | Result |
|---|---|
| Pod1 is running in namespace default | Fail |
| Pod1 is scheduled on cka5248 | Fail |
| Pod1 has single container | Fail |
| Pod1 container has correct image | Fail |
| Pod2 is running in namespace default | Fail |
| Pod2 is scheduled on cka5248-node1 | Fail |
| Pod2 has single container | Fail |
| Pod2 container has correct image | Fail |
| kube-scheduler-cka5248 is running | Fail |
| kube-scheduler-cka5248 was restarted | Fail |

**Score feedback:** none shown (no expandable feedback block rendered for this question). Zero of ten subtasks passed, including both pods existing at all and the scheduler pod state checks. This pattern, a full-zero across every subtask including basic pod existence, points toward either a skip (not attempted) or a fundamental setup failure (wrong cluster/context, wrong namespace, or a build step that never completed) rather than a partial misconfiguration. This needs to be checked against actual command history once recovered, per the Simulator A precedent of not trusting the failure pattern alone.

---

## Question 10 | StorageClass, PVC, and Backup Job (5/5)

| Subtask | Result |
|---|---|
| StorageClass created | Pass |
| Job uses PVC | Pass |
| PVC uses StorageClass | Pass |
| PVC requests required storage | Pass |
| Job created backups on the PVC | Pass |

Full marks, no feedback shown.

---

## Question 11 | Secrets Mounted and Injected into Pod (7/7)

| Subtask | Result |
|---|---|
| Secret secret1 exists | Pass |
| Secret secret2 exists | Pass |
| Pod exists | Pass |
| Pod has single container | Pass |
| Pod container has correct image | Pass |
| Pod mounts secret1 readonly | Pass |
| Pod has secret2 env variables | Pass |

Full marks, no feedback shown.

---

## Question 12 | Control-Plane-Only Pod Scheduling (0/6)

| Subtask | Result |
|---|---|
| Pod is running | Fail |
| Pod has single container | Fail |
| Container has correct name | Fail |
| Container has correct image | Fail |
| Pod is scheduled on controlplane | Fail |
| Pod will only be scheduled on controlplane nodes | Fail |

**Score feedback:** none shown. Another full-zero across every subtask, including basic pod existence, in a question that is conceptually a standard toleration-plus-nodeSelector (or nodeAffinity) exercise. Same caveat as Question 9: this pattern reads as not attempted or a setup failure rather than a near-miss, but needs command-history confirmation.

---

## Question 13 | Multi-Container Pod with Shared Volume (0/11)

| Subtask | Result |
|---|---|
| Pod is running | Fail |
| Pod has three containers | Fail |
| Pod has three Ready containers | Fail |
| Pod container 1 has correct name | Fail |
| Pod container 1 has correct image | Fail |
| Pod container 1 has env variable MY_NODE_NAME | Fail |
| Pod container 2 has correct name | Fail |
| Pod container 2 has correct image | Fail |
| Pod container 3 has correct name | Fail |
| Pod container 3 has correct image | Fail |
| All Pod containers have volume mounted | Fail |

**Score feedback:** none shown. Full-zero, eleven subtasks, the largest single point loss on this attempt (11 of the 47 lost points). Same not-attempted-or-setup-failure caveat applies.

---

## Question 14 | Short-Answer Questions (0/5)

| Subtask | Result |
|---|---|
| Answer 1 valid | Fail |
| Answer 2 valid | Fail |
| Answer 3 valid | Fail |
| Answer 4 valid | Fail |
| Answer 5 valid | Fail |
| Answer 5 valid | Fail |

**Score feedback:** none shown. Full-zero across all five short-answer subtasks. Unlike the cluster-task questions, this one has no setup dependency, so a full-zero here most likely means not attempted (skipped) rather than a build failure, similar to the Simulator A skip pattern on Q13/15/16.

---

## Question 15 | Cluster Events and Kill Logs (0/3)

| Subtask | Result |
|---|---|
| File /opt/course/15/cluster_events.sh valid | Fail |
| File /opt/course/15/pod_kill.log contains correct logs | Fail |
| File /opt/course/15/container_kill.log contains correct logs | Fail |

**Score feedback:** none shown. Full-zero. Notably, this is the same topic area (event-log scripting) that appeared as a skip on Simulator A, so a repeat zero here is a meaningful signal worth checking directly: was it attempted and wrong, or skipped again.

---

## Question 16 | Namespaced Resources and Crowded Namespace (0/2)

| Subtask | Result |
|---|---|
| File /opt/course/16/resources.txt contains namespaced resources | Fail |
| File /opt/course/16/crowded-namespace.txt correct content | Fail |

**Score feedback:** none shown. Full-zero, same topic area as one of the Simulator A skips (cluster-wide resource and namespace introspection), so this is another repeat-zero worth checking for skip-versus-attempt.

---

## Question 17 | Kustomize RBAC and Overlay (0/5)

| Subtask | Result |
|---|---|
| Kustomize Role updated | Fail |
| Operator has correct permissions | Fail |
| Kustomize Student added in base | Fail |
| Student created | Fail |
| Kustomize Build base and prod without error after updates | Fail |

**Score feedback:** none shown. Full-zero, five subtasks, on a Kustomize-and-RBAC question, a topic combination not previously drilled in the Simulator A remediation work.

---

## Summary by Outcome

**Full marks (8 questions, 42 subtasks):** Q2, Q4, Q5, Q6, Q7, Q8, Q10, Q11.

**Partial credit with specific feedback (2 questions, 4 of 9 subtasks passed):** Q1 (CoreDNS, 2/5), Q3 (kubelet certificates, 2/4).

**Full zero (7 questions, 0 of 42 subtasks passed):** Q9 (scheduling/scheduler restart, 0/10), Q12 (control-plane-only scheduling, 0/6), Q13 (multi-container shared volume, 0/11), Q14 (short answers, 0/5), Q15 (event/kill logs, 0/3), Q16 (namespaced resources, 0/2), Q17 (Kustomize RBAC, 0/5).

Forty-two of the forty-seven lost points sit inside the seven full-zero questions. That concentration is the headline finding: this was not a broad pattern of small misses, it was a small number of partial misses (Q1, Q3) plus a large block of questions that returned nothing at all. Before any remediation plan gets written, the actual command history and submitted YAML for Q9, Q12, Q13, Q14, Q15, Q16, and Q17 need to be recovered and checked, the same way `cka-simulator-a-my-submitted-solutions.md` was built, because "zero on every subtask including basic pod existence" is consistent with either a skip (not attempted, the Simulator A pattern that already showed up on Q13/15/16 type content) or a setup failure (wrong context, wrong node name, a typo in a resource name that cascaded, or running out of time mid-cluster-build). Those are different diagnostic categories requiring different fixes, and score feedback text was not even rendered for six of the seven zero questions, so there is no shortcut here: the submission record is the only way to know which it was.
