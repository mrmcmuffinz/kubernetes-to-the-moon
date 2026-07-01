# CKA Day 4 (Thu, June 25) | Disputed items and the full-mark sweep

Goal: settle the two disputed Sim A items (Q12 scheduling spread, Q17 crictl labels) and run
the full-mark questions as robustness reps so the easy points are also fast and reliable. This
is a deliberately dense day; if it runs long, the Day 8 buffer absorbs it. Do not rush the
verification to fit the day.

## Environment

- Q12 needs exactly two schedulable workers so the third replica stays Pending: your 3-node Pi cluster.
- Q17 needs a root shell on a node: `ssh` to a Pi node, or `nerdctl exec` into a kind node.
- Q8 must run on a throwaway kubeadm cluster (killercoda or a scratch VM), never the live clusters and never the Pi.

## Block A: scheduling spread (Q12, settle the dispute)

Source: `exercises/01-pods/assignment-4/pod-scheduling-homework.md`

- [ ] Exercise 4.2
- [ ] Exercise 3.3

4.2 and 3.3 are the topologySpreadConstraints and podAntiAffinity forms of the same outcome;
Q12 can be phrased either way, so do both. They target a 3-worker kind cluster, so on your Pi
(2 workers) the "one Pod left Pending" outcome appears with the at-most-one-per-node
anti-affinity form. Settle the Session 1 dispute directly: build the rule present from the very
first apply and confirm the 2-running, 1-Pending split, since a rule added after the fact does
not reschedule running Pods.

## Block B: crictl (Q17, settle the label dispute), original task

- [ ] On a node with a root shell, create a pod (image `httpd:2-alpine`) carrying two labels, find the node it landed on, and use `crictl` to inspect its container. Write the container ID and its `info.runtimeType` to one file and the container logs to another. Pass: `kubectl get pod <name> --show-labels` shows both labels (the exact thing disputed on Session 1), the first file holds a real container ID and a runtime type such as `io.containerd.runc.v2`, and the log file is non-empty. The setup is the node shell; do not look up the crictl flags first, that is the drill.

## Block C: QoS classification (Q4)

Source: `exercises/01-pods/assignment-5/pod-resources-qos-homework.md`

- [ ] Exercise 1.1
- [ ] Exercise 1.2
- [ ] Exercise 1.3
- [ ] Exercise 2.1
- [ ] Exercise 2.2

Answer both framings: which pods are evicted first (BestEffort) and which last (Guaranteed). If
your method only answers "first," it is keying off the wrong signal.

## Block D: kubeadm upgrade and join (Q8)

Source: `exercises/17-cluster-lifecycle/assignment-2/cluster-lifecycle-homework.md`

- [ ] Exercise 2.1
- [ ] Exercise 2.2
- [ ] Exercise 2.3

Those drill cordon, drain, and uncordon, the node-maintenance half. The actual version-pin and
join is best done hands-on and recorded, which the corpus does not do, so do it as an explicit
rep on a throwaway cluster:

- [ ] On a scratch kubeadm cluster with a worker one version behind, update the worker to the control-plane version and `kubeadm join` it, recording every command verbatim including the apt `unhold` / version-pin / `hold` sequence and the join flow. Pass: `kubectl get nodes` shows the worker Ready at the matching version. Throwaway cluster only.

## Block E: robustness second reps and habit checks

- [ ] Q9 second rep (a separate sitting from Day 3): the in-pod Secrets query through `https://kubernetes.default`, valid SecretList back.
- [ ] Q10 second rep: the ServiceAccount plus create-only Role and RoleBinding through the generators, exact `auth can-i --as=` boundary.
- [ ] Q5 habit check: after removing a resource from a Kustomize source, confirm it is actually gone from the live cluster (`kubectl get <kind>`), since Kustomize has no state.
- [ ] Q6 habit check: on any task with an exact path or string, read it back character by character against the question (the `/Volumes/Data` capital-D class of typo).

## Check-in

- [ ] Is the Q12 dispute resolved (2-running, 1-Pending with the rule present from creation), and do you have both the topology-spread and anti-affinity forms? Did Q17's `--show-labels` confirm both labels? Did Q4 answer both eviction framings, and did the Q8 worker reach Ready at the matching version on the throwaway? Did the Q9 and Q10 second reps hold their robust defaults?
