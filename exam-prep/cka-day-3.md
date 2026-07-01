# CKA Day 3 (Wed, June 24) | CoreDNS, then the first speed block

Goal: convert the Sim A Q16 CoreDNS skip into a solid edit-the-Corefile-with-backup-and-recover
skill, then start proving the easy questions are also fast. CoreDNS is the primary work and
should not eat the whole day; the speed block is five quick reps that install the robust
defaults flagged in the remediation plan. The exact Q16 scenario is left for the Day 5 session.

## Environment

A kubeadm cluster running CoreDNS as a Deployment with a ConfigMap (your VM or Pi). The
CoreDNS work below backs up the ConfigMap first and restores it after, so it is safe on a
live practice cluster.

## Block A: CoreDNS configuration

Source: `exercises/09-coredns/assignment-2/coredns-homework.md`

- [ ] Exercise 1.2
- [ ] Exercise 2.1
- [ ] Exercise 4.1

Those drill viewing the ConfigMap, the `kubernetes` plugin, and editing the Corefile with a
backup-and-restore cycle. The Q16 task itself is a different edit the corpus does not cover
directly, so do it as an explicit rep on top (setup and verification only, no answer):

- [ ] Back up the CoreDNS ConfigMap to a file. Add a second cluster domain (for example `custom-domain`) so that `SERVICE.NAMESPACE.custom-domain` resolves identically to, and alongside, `SERVICE.NAMESPACE.cluster.local`. Confirm from a `busybox:1.36` pod that both names resolve to the same IP and that the CoreDNS pods stay Running (a CrashLoop means a Corefile syntax error). Then reapply the backup and confirm `custom-domain` stops resolving.

## Block B: first speed block (one timed rep each, robust default installed)

These are known skills; the point is speed and the corrected default, not relearning.

- [ ] StatefulSet scale: `exercises/03-statefulsets/assignment-1/statefulsets-homework.md` Exercise 1.1, then confirm the controller kind with `kubectl get sts,deploy,ds` before scaling it to 1 replica.
- [ ] RBAC: `exercises/12-rbac/assignment-1/rbac-homework.md` Exercises 1.1 and 1.2, built through the imperative generators (`kubectl create serviceaccount`, `role`, `rolebinding`) and verified with `kubectl auth can-i ... --as=`.
- [ ] Cert expiry and renew: `exercises/18-tls-and-certificates/assignment-3/tls-and-certificates-homework.md` Exercises 1.1 and 4.2, capturing the expiry into a file with the order `> file 2>&1`. On a kubeadm control-plane node (your VM or Pi), read-only.
- [ ] kubectl top (no corpus exercise, original task): write `node.sh` showing node usage and `pod.sh` showing per-pod, per-container usage (`kubectl top pod --containers`). Pass: `bash node.sh` prints node CPU and memory, `bash pod.sh` prints the per-container breakdown. Needs metrics-server installed.
- [ ] API from inside a pod (no corpus exercise, original task): create a ServiceAccount plus a Role and RoleBinding that let it list Secrets, run a pod using that ServiceAccount, exec in, and query all Secrets through `https://kubernetes.default` (the DNS name, not a hardcoded ClusterIP) using the mounted SA token. Pass: a valid JSON SecretList comes back.

## Check-in

- [ ] Did the custom-domain edit resolve under both domains with CoreDNS staying Running, and did the backup restore cleanly? On the speed block, which of the five ran over target and what slowed it (a forgotten flag, a hand-written resource that should have been generated, an avoidable doc lookup)? Did the robust default land each time (generators for RBAC, `kubernetes.default` for the in-pod call, `> file 2>&1` for the cert capture)?
