# Killer.sh CKA Simulator B: Results (Retake)

**Score:** 79 / 93 subtasks (85%), labeled "High Score"
**Session ID:** 2107aee7-a1f2-4fee-b60e-e50819497912
**Date recorded:** 2026-06-27
**Comparison:** the first attempt on this same simulator session scored 46/93 (49.5%, "Low Score") on 2026-06-26. This retake gained 33 subtasks. The time cascade documented in `cka-simulator-b-remediation-plan.md` is gone: every question from Q12 through Q17 was attempted this time, where six of them scored a flat zero last time from never being reached. This document is a literal transcription of the subtask-level pass/fail data and the score-feedback text shown on the results page, parallel in structure to `cka-simulator-b-results.md` (the first attempt), with your own direct account folded in for the questions where the score feedback alone didn't capture what actually happened (Q9's rollout-restart awareness, Q14's CNI-path search, Q15's container-kill method, Q17's CRD confusion, and doc-lookup usage on Q10/Q12).

**The headline arithmetic:** fixing only the typo- and omission-class misses below (Q1's DNS_3/DNS_4 values and the resulting deployment check, Q2's image tag, Q9's restart timing, Q13's missing volumeMount, Q14's missing hyphen, Q15's script alias) would move this score to 87/93 (93.5%), past the 90% target, with only Q16 and Q17 remaining as genuine gaps rather than care-level misses. This confirms the session's own read of the result.

---

## Question 1 | CoreDNS ConfigMap (2/5)

| Subtask | Result |
|---|---|
| DNS_1 in ConfigMap correct | Pass |
| DNS_2 in ConfigMap correct | Pass |
| DNS_3 in ConfigMap correct | Fail |
| DNS_4 in ConfigMap correct | Fail |
| Correct values from ConfigMap available in Deployment | Fail |

**Score feedback:** `DNS_3` is set to `section100.lime-workload.svc.cluster.local`, which has two separate problems: the namespace is misspelled (`lime-workload` instead of `lima-workload`), and the subdomain segment (`.section`) is missing entirely, so the value reads as if `lime-workload` were the subdomain rather than the namespace. `DNS_4` is set to `1-2-3-4.default.svc.cluster.local`, which has the wrong namespace (`default` instead of `kube-system`) and the wrong suffix entirely (`.svc.cluster.local` instead of `.pod.cluster.local`), meaning this isn't a near-miss on the pod-IP form, it's a different DNS pattern altogether. Because the Deployment pods picked up these incorrect values, the downstream "values available in Deployment" check also failed.

**Comparison to the first attempt:** DNS_2 (the typo from last time, missing `.svc`) is now correct, confirming the read-back fix held. DNS_3 has correctly moved to the right *structural pattern* (hostname.subdomain rather than the pod-IP form used last time), which confirms the hostname/subdomain mechanism was learned, but the specific values inside that pattern have two new, unrelated errors: a misspelled namespace and an omitted subdomain segment. DNS_4 is an entirely new miss not present on the first attempt, where DNS_4 had passed.

**Category:** typo/omission, not a knowledge gap. The mechanism for both DNS_3 and DNS_4 was understood, since the structural pattern chosen for each was correct; the actual characters typed into each value were wrong in small, specific ways.

---

## Question 2 | Static Pod, Resources, Service (6/7)

| Subtask | Result |
|---|---|
| Static Pod my-static-pod-cka2560 exists | Pass |
| Pod has single container | Pass |
| Pod container has correct image | Fail |
| Pod has correct CPU resource requests | Pass |
| Pod has correct memory resource requests | Pass |
| Service is of type NodePort | Pass |
| Service selector matches Pod | Pass |

**Score feedback:** the container uses image `nginx:1` instead of the required `nginx:1-alpine`.

**Comparison to the first attempt:** this question scored full marks (7/7) on the first attempt. This is a new miss, a wrong image tag, on a question that was previously clean.

**Category:** typo/recall, not a knowledge gap.

---

## Question 3 | Kubelet Certificates (4/4)

| Subtask | Result |
|---|---|
| Kubelet Client Certificate Issuer is correct | Pass |
| Kubelet Client Certificate Extended Key Usage is correct | Pass |
| Kubelet Server Certificate Issuer is correct | Pass |
| Kubelet Server Certificate Extended Key Usage is correct | Pass |

Full marks, no feedback shown. First attempt scored 2/4 (server cert issuer and EKU both wrong). The certificate-identification fix held completely.

---

## Question 4 | Pods with Probes and Labels (11/11)

Full marks, no feedback shown. Held from the first attempt (also full marks).

---

## Question 5 | Scripted Pod Queries (2/2)

Full marks, no feedback shown. Held from the first attempt (also full marks).

---

## Question 6 | Fix Kubelet (2/2)

| Subtask | Result |
|---|---|
| Node is Ready | Pass |
| Pod is created and running | Pass |

Full marks, no feedback shown. Held from the first attempt (also full marks). The score gives no detail on method, only outcome, so whether the full-output-reading habit drilled in remediation was actually used here, versus another workaround, remains unconfirmed by this result alone.

---

## Question 7 | Etcd Version and Snapshot (2/2)

Full marks, no feedback shown. Held from the first attempt (also full marks).

---

## Question 8 | Control Plane Component Health (6/6)

Full marks, no feedback shown. Held from the first attempt (also full marks).

---

## Question 9 | Multi-Pod Scheduling and Scheduler Restart (9/10)

| Subtask | Result |
|---|---|
| Pod1 is running in namespace default | Pass |
| Pod1 is scheduled on cka5248 | Pass |
| Pod1 has single container | Pass |
| Pod1 container has correct image | Pass |
| Pod2 is running in namespace default | Pass |
| Pod2 is scheduled on cka5248-node1 | Pass |
| Pod2 has single container | Pass |
| Pod2 container has correct image | Pass |
| kube-scheduler-cka5248 is running | Pass |
| kube-scheduler-cka5248 was restarted | Fail |

**Score feedback:** the scheduler's start time is identical to the apiserver's start time (both timestamped the same instant), which means the scheduler was never actually restarted with a fresh process after the manual pod-scheduling steps. To get a genuinely new start time, the scheduler's manifest needs to be moved out of `/etc/kubernetes/manifests/`, the kubelet needs to be given time to fully terminate the existing static pod, and only then should the manifest be moved back in. Moving it back too quickly, before the old pod has actually torn down, can result in the kubelet treating it as never having stopped.

**Comparison to the first attempt:** this question scored 0/10 on the first attempt, never attempted at all due to the time cascade. This retake landed 9 of 10 subtasks, the nodeName-bypass mechanism (the genuine coverage gap from before) is now fully demonstrated correctly across both pods. The single remaining miss is procedural rather than conceptual: the restart step needs a wait between moving the manifest out and moving it back in.

**Category:** procedural timing, not a knowledge gap. The mechanism (move manifest out, then back in) was correctly identified; the wait between the two steps was skipped or too short.

---

## Question 10 | StorageClass, PVC, and Backup Job (5/5)

Full marks, no feedback shown. Held from the first attempt (also full marks).

**Note from direct account:** the kubernetes.io documentation link provided in the simulator was used for PVC creation syntax on this question. The result was fully correct, so this is a fluency flag rather than a score issue: would the PVC/StorageClass/Job YAML structure be fast and correct from memory without the doc lookup? Worth a from-scratch timed rebuild to check, the same review question already applied to Q10/Q11's `kubectl explain` usage in the prior remediation round.

---

## Question 11 | Secrets Mounted and Injected (7/7)

Full marks, no feedback shown. Held from the first attempt (also full marks).

---

## Question 12 | Control-Plane-Only Pod Scheduling (6/6)

| Subtask | Result |
|---|---|
| Pod is running | Pass |
| Pod has single container | Pass |
| Container has correct name | Pass |
| Container has correct image | Pass |
| Pod is scheduled on controlplane | Pass |
| Pod will only be scheduled on controlplane nodes | Pass |

Full marks, no feedback shown. First attempt scored 0/6, never attempted due to the time cascade. This is the question the revised remediation plan flagged as the fastest of the six cascade topics to close (4-minute target, nodeSelector plus toleration against the existing control-plane label), and it closed completely.

**Note from direct account:** the kubernetes.io documentation link was also used here, for the node affinity and tolerations syntax. Same fluency flag as Q10: fully correct, worth a from-scratch timed check to see whether the doc lookup is still needed or was a one-time refresher.

---

## Question 13 | Multi-Container Pod with Shared Volume (10/11)

| Subtask | Result |
|---|---|
| Pod is running | Pass |
| Pod has three containers | Pass |
| Pod has three Ready containers | Pass |
| Pod container 1 has correct name | Pass |
| Pod container 1 has correct image | Pass |
| Pod container 1 has env variable MY_NODE_NAME | Pass |
| Pod container 2 has correct name | Pass |
| Pod container 2 has correct image | Pass |
| Pod container 3 has correct name | Pass |
| Pod container 3 has correct image | Pass |
| All Pod containers have volume mounted | Fail |

**Score feedback:** container `c1` has only one volumeMount, the automatically injected ServiceAccount token, while containers `c2` and `c3` each have two volumeMounts (the ServiceAccount token plus the shared volume). The question requires every container to have the shared `emptyDir` volume mounted, and `c1` specifically is missing it.

**Comparison to the first attempt:** this question scored 0/11 on the first attempt, never attempted. This retake landed 10 of 11, every structural and content requirement satisfied (three containers, correct names and images, the downward-API env var) except one volumeMount omitted on the first container specifically. This is the largest single point-value question on the exam (11 subtasks) and came within one omitted line of a clean sweep.

**Category:** omission, not a knowledge gap. The pattern (every container needs the shared volume mounted) was correctly applied to two of three containers, just not the first one, likely because `c1` was built first as the base pod (via `kubectl run --dry-run=client`) before the volume requirement was layered on, and the volumeMount addition to `c1` itself got missed when `c2` and `c3` were added afterward with the mount included from the start.

---

## Question 14 | Short-Answer Questions (4/5)

| Subtask | Result |
|---|---|
| Answer 1 valid | Pass |
| Answer 2 valid | Pass |
| Answer 3 valid | Pass |
| Answer 4 valid | Pass |
| Answer 5 valid | Fail |

**Score feedback:** answer 5 was submitted as `cka8448`, but the question requires the static-pod hostname suffix with its leading hyphen, `-cka8448`.

**Comparison to the first attempt:** this question scored 0/5 on the first attempt, never reached. This retake landed 4 of 5, with the one miss being the same leading-hyphen detail flagged as a thing to get right in the official-solution review during remediation, missed in the actual execution despite being named in the prep.

**Note from direct account, the more important finding on this question:** time was spent on the CNI sub-question (likely Answer 4, "which CNI plugin and where is its config file") not because the CNI itself was unfamiliar, but because the config file's path wasn't known directly. The actual method used was: `kubectl describe pod` on a CNI-related pod, reading its volume mounts, then `ls -l` on each mounted path until the conflist file turned up. This is a real, working detective method, but it's slow by construction for something with a fixed, well-known answer. The official solution and general CKA prep both point straight at `/etc/cni/net.d/` as the kubelet's default CNI config lookup directory; finding this by filesystem archaeology instead of recall is the actual time cost on this question, separate from the hyphen miss that cost the point.

**Category:** two distinct findings. The scored miss (Answer 5) is an omission. The unscored but real time cost (the CNI path search) is a missing fixed fact, a genuine small coverage gap distinct from the typo/omission pattern seen elsewhere on this retake.

---

## Question 15 | Cluster Events and Kill Logs (2/3)

| Subtask | Result |
|---|---|
| File /opt/course/15/cluster_events.sh valid | Fail |
| File /opt/course/15/pod_kill.log contains correct logs | Pass |
| File /opt/course/15/container_kill.log contains correct logs | Pass |

**Score feedback:** the script at `/opt/course/15/cluster_events.sh` contains `k get events` instead of `kubectl get events`, the `kubectl` substring is missing from the command, likely because the shell alias `k` (which works interactively) was written into the script file, where the alias isn't expanded the same way.

**Comparison to the first attempt:** this question scored 0/3 on the first attempt, never reached. This retake landed 2 of 3: both log-content subtasks, which depend on actually understanding and reproducing the event-generating actions (deleting a pod, killing a container), passed cleanly. The one miss is narrowly mechanical: an alias used in scripts that doesn't resolve the same way it does at an interactive prompt.

**Note from direct account on how the two passing subtasks were actually produced.** For the container-kill half specifically, the question's wording ("kill the container") was read closely enough to correctly rule out `crictl stop` as the wrong tool, since stopping and killing are different operations; the method used instead was locating the kube-proxy process directly via `ps -aef | grep kube-proxy` and killing it by PID at the OS level. This works and is evidence of careful reading of the question's exact verb, but it is one level lower than necessary; `crictl rm --force <container-id>` operates directly on the container runtime and is the more direct tool for this exact instruction, without the extra step of mapping a PID back to the right container. Separately, a brief documentation lookup (under a minute) was needed to find the `--for` flag on `kubectl events` for filtering events to a specific pod, after an initial attempt with a `--label` filter didn't work; this was a fast, well-targeted lookup that resolved the actual blocker and is not a concern.

**Category:** the scored miss (the `k`/`kubectl` alias issue) is a mechanical script-writing habit, not a knowledge gap: aliases configured for interactive shells do not exist inside non-interactive script execution, so any alias relied upon at the prompt needs to be written out in full inside a script file. Worth a general rule: write the full command in any file meant to be executed as a script, never the aliased short form, regardless of which alias it is.

---

## Question 16 | Namespaced Resources and Crowded Namespace (1/2)

| Subtask | Result |
|---|---|
| File /opt/course/16/resources.txt contains namespaced resources | Fail |
| File /opt/course/16/crowded-namespace.txt correct content | Pass |

**Score feedback:** `/opt/course/16/resources.txt` contains namespace names and pod names rather than the required namespaced resource *type* names; the question wants the output of `kubectl api-resources --namespaced -o name`, which should include type strings like `persistentvolumeclaims`, `pods`, `secrets`, `services`, `deployments`. The `crowded-namespace.txt` file is correct, containing both `project-miami` and `300`.

**Comparison to the first attempt:** this question scored 0/2 on the first attempt, never reached. This retake landed the harder of the two subtasks (correctly identifying which `project-*` namespace had the most Roles, the per-namespace `wc -l` loop) but missed the easier one (the resource-type listing), apparently due to misunderstanding what "namespaced resources" meant in the question, listing instances of namespaces and pods rather than resource type names.

**Category:** a genuine conceptual miss, not a typo. "Namespaced resources" in this question means resource *types* that are scoped to a namespace (the `kubectl api-resources --namespaced` output, type-name strings like `pods`, `secrets`, `deployments`), not actual namespace objects or actual pod instances running in those namespaces. This is the one clear remaining gap on this retake outside of Q17.

---

## Question 17 | Operator, CRDs, RBAC, Kustomize (0/5)

| Subtask | Result |
|---|---|
| Kustomize Role updated | Fail |
| Operator has correct permissions | Fail |
| Kustomize Student added in base | Fail |
| Student created | Fail |
| Kustomize Build base and prod without error after updates | Fail |

**Score feedback:** none shown (no expandable feedback block rendered).

**Comparison to the first attempt:** this question scored 0/5 on the first attempt as well, never reached either time.

**Full account, from direct description:** unlike the first attempt (where this question and the rest of the cascade were never reached at all), this attempt did reach Q17 and ran out of time *during* it, on a specific, identifiable blocker. The RBAC half was understood correctly: the fix needed `list` permission added to the `operator-role` Role for the relevant CRDs, and a `kubectl rollout restart` on the operator's Deployment afterward so the running pod would pick up the new permissions rather than continuing to run with its original, stale RBAC context. Both of these were known. The blocker was the second half of the question, adding a new Student custom-resource instance: this was misread as needing to modify `base/crd.yaml` (the file defining the Student *type itself*, the `CustomResourceDefinition` schema) rather than `base/students.yaml` (the file holding actual Student *instances*, where three Students already existed as a template to copy). That confusion, treating an instance-creation task as if it were a type-definition task, is what consumed the remaining time, since editing a CRD definition is a meaningfully bigger and less familiar operation than appending one more object of an already-existing type, and time ran out before the right file was identified.

**Category:** a genuine, fully diagnosed conceptual gap, distinct from every other miss on this retake. This is not a typo, not an omission, and not a missing fixed fact; it's a structural confusion between two different artifacts that happen to both relate to the same CRD (the schema that defines a type, versus an instance of that type), which is conceptually the same distinction as "editing a Deployment's pod template" versus "creating a new Pod," just one level more abstract because the type itself (`Student`) isn't a built-in Kubernetes kind.

---

## Summary by Outcome

**Full marks (8 questions, 39 subtasks):** Q3, Q4, Q5, Q6, Q7, Q8, Q10, Q11. (Q10 and Q12, also full marks, involved a documentation lookup; see their individual notes.)

**Near-full, single-subtask miss, all typo/omission/procedural class (3 questions, 30 of 33 subtasks):** Q9 (9/10, scheduler restart timing), Q13 (10/11, one missing volumeMount), Q14 (4/5, missing leading hyphen, plus a separate unscored CNI-path time cost).

**Partial, mixed misses (4 questions, 11 of 17 subtasks):** Q1 (2/5, two new and different DNS value errors, typo/omission class), Q2 (6/7, wrong image tag, typo class), Q15 (2/3, alias-in-script issue, mechanical class), Q16 (1/2, a genuine conceptual miss on what "namespaced resources" means as a deliverable).

**Full zero, fully diagnosed (1 question, 0 of 5 subtasks):** Q17 (Kustomize RBAC and overlay). Unlike the first attempt, this was reached and partially worked, not skipped; the blocker was a specific, nameable confusion between CRD type-definition files and CRD instance files, now fully understood.

**The arithmetic that matters most:** of the 14 lost subtasks, 8 are typo, omission, or procedural-timing misses where the underlying mechanism was demonstrably understood (Q1's DNS_3/DNS_4 plus the cascading deployment check, Q2, Q9, Q13, Q14's hyphen, Q15). Fixing only these moves the score to 87/93 (93.5%), past the 90% target. The remaining 6 lost subtasks split into one genuine conceptual gap (Q16, 1 subtask) and one genuine, now fully diagnosed conceptual gap (Q17, 5 subtasks). Q14's CNI-path search is a separate, smaller finding: it didn't cost a point directly, but it cost time that contributes to the same kind of pressure that caused the original cascade, and it has an easy, durable fix (memorize `/etc/cni/net.d/`).

This retake confirms the central hypothesis of the prior remediation plan: fixing Q1, Q3, Q6, Q10, and Q11's time costs did prevent the cascade, since every previously-zero question except Q17 was reached and substantially solved. The work remaining is narrower and more specific than the original session: a handful of careful-reading and read-back habits (the same fix already named for Q1's DNS_2 typo last round, now generalized across more questions), one fixed fact to memorize (the CNI path), and two genuine concepts to learn properly (what "namespaced resources" means as a deliverable, and the CRD-definition-versus-instance distinction).
