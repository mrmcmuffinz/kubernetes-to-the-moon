# CKA Day 9 (Tue, June 30) | Install the Discipline

**Exam:** Friday, July 3, 2026 at 10:00 AM Central Time (3 days out)

Goal: Install the read-back and verification habits that prevent the 8-subtask typo/omission cluster from the retake. This is not about learning new material; it's about making the pause-and-check reflex automatic before it matters on Friday.

## The 8-Subtask Typo Cluster (Worth 93.5% if Fixed)

From the retake, these lost points where the mechanism was correct but execution had small defects:
- Q1 DNS_3: misspelled namespace, omitted subdomain segment
- Q1 DNS_4: wrong namespace, wrong suffix pattern
- Q2: wrong image tag (nginx:1 vs nginx:1-alpine)
- Q9: scheduler restart timing (didn't wait for pod termination)
- Q13: missing volumeMount on first container
- Q14: missing leading hyphen on static pod suffix
- Q15: used alias `k` instead of `kubectl` in script file

**The pattern:** Correct approach, flawed specific values or incomplete steps.

**The fix:** Make verification automatic, not optional.

## Block A: DNS FQDN Read-Back Habit

**Principle:** Before submitting any FQDN, count the dot-separated segments and verify each segment character-by-character against the question.

Source: `exercises/09-coredns/assignment-4/coredns-homework.md`

- [ ] Exercise 2.1 (pod with hostname and subdomain, verify FQDN `db-primary.db-cluster.ex-2-1.svc.cluster.local`)
- [ ] Exercise 2.2 (pod subdomain DNS survives IP change)
- [ ] Exercise 2.3 (multiple pods with same subdomain)

After each: pause, count the segments, read each one against the question before considering it done.

## Block B: Image Tag Verification Habit

**Principle:** After typing image field, verify the tag suffix matches exactly, not just base image.

Source: `exercises/01-pods/assignment-1/pod-fundamentals-homework.md`

- [ ] Exercise 1.1 (pod with `nginx:1.25`, verify the full tag including version)
- [ ] Exercise 1.2 (pod with `busybox:1.36` and restartPolicy)

## Block C: Multi-Step Procedure Verification

**Principle:** Build checklist, execute steps, verify each completes before next.

Source: `exercises/19-troubleshooting/assignment-3/troubleshooting-homework.md`

- [ ] Exercise 3.2 (kubelet systemd unit fix: edit → daemon-reload → restart)

Scheduler restart pattern (not in corpus, simulate):
- [ ] Move scheduler manifest out of `/etc/kubernetes/manifests/`, wait for pod gone (`kubectl -n kube-system get pod` shows it absent), then move back in. Don't move back on a guess; wait for confirmation.

## Block D: Multi-Container volumeMount Verification

**Principle:** After adding volume and mounts, explicitly verify ALL containers have the mount (don't assume base container got it).

Source: `exercises/01-pods/assignment-6/multi-container-patterns-homework.md`

- [ ] Exercise 2.1 (init container + main container sharing emptyDir)
- [ ] Exercise 2.2 (sidecar pattern with shared volume)
- [ ] Exercise 4.3 (three init containers with shared pipeline volume)

After each: explicitly check all containers have the mount, especially the first/base container.

## Block E: Script Writing Pattern

**Principle:** Never use alias `k` in script files, always spell `kubectl` in full.

- [ ] Write a script file `/tmp/test-events.sh` containing: `kubectl get events --sort-by=.metadata.creationTimestamp`
- [ ] Verify: script contains full command name, not alias

## Block F: Cold Rebuild Without Docs (Optional if Time Permits)

These patterns needed doc lookups on the retake. Test if they're now fast from memory.

Foundation (if needed first):
- PVC pattern: `exercises/07-storage/assignment-1/storage-homework.md` exercises 1.1-1.3
- Job pattern: `exercises/02-jobs-and-cronjobs/assignment-1/jobs-and-cronjobs-homework.md` exercise 1.1

Cold rebuild (timed, no kubectl explain, no docs):

- [ ] StorageClass named `retain-sc` with reclaimPolicy: Retain, PVC named `work-pvc` requesting 1Gi from it, Job named `data-job` mounting the PVC at `/data`. Target: <6 minutes.
- [ ] Pod named `control-plane-pod` with nodeSelector: `node-role.kubernetes.io/control-plane: ""` and toleration for `node-role.kubernetes.io/control-plane:NoSchedule`. Target: <4 minutes.
- [ ] Pod named `multi-app` with 3 containers (busybox:1.36), shared emptyDir volume named `shared` mounted at `/shared` in all three, first container has env var `MY_NODE_NAME` via `fieldRef: spec.nodeName`. Target: <8 minutes.

If any needs docs or misses target: That's fine, plan to use docs on Friday (they're allowed).

## Check-in

By end of day:
- [ ] Read-back habit drill completed on DNS, image tags, multi-step procedures, multi-container mounts
- [ ] Pause-and-check feels automatic (or at least more natural than forced)
- [ ] Script writing rule internalized (kubectl not k)

Tomorrow (Day 10) is final verification and light review before the taper.
