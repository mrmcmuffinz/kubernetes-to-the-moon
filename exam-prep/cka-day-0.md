# CKA Day 0 (June 21 if time, else Day 1 morning) | kubectl Fluency Primer

Do this before Day 1 (`cka-day-1.md`). Cap 1 to 2 hours. A single-node kind cluster covers
everything except the two DaemonSet reps in Block B, which use your multi-node Pi cluster.
Attempt each exercise cold with the documentation closed, then check it against the
Verification and Expected sections in its source file. Each exercise's own Setup block creates
its namespace. Open an answer key only after a genuine attempt.

### Step 0: speed setup (about a minute)

- [ ] `alias k=kubectl`, `export do='--dry-run=client -o yaml'`, set the working namespace with `kubectl config set-context --current --namespace=<ns>`, and practice `kubectl config use-context`. Warms up kubeconfig handling.

### Block A: pod construction, Levels 1 and 2

Source: `exercises/01-pods/assignment-1/pod-fundamentals-homework.md`

- [ ] Exercise 1.1
- [ ] Exercise 1.2
- [ ] Exercise 1.3
- [ ] Exercise 2.1
- [ ] Exercise 2.2
- [ ] Exercise 2.3

### Block B: workload controllers, Levels 1 and 2

Source: `exercises/01-pods/assignment-7/workload-controllers-homework.md`

- [ ] Exercise 1.1
- [ ] Exercise 1.2
- [ ] Exercise 1.3
- [ ] Exercise 2.1
- [ ] Exercise 2.2
- [ ] Exercise 2.3

1.3 and 2.2 are DaemonSet exercises: run them on your 3-node Pi cluster (2.2 needs two workers for the label-driven eviction). The file targets a 3-worker kind cluster, so use your own node names and expect one DaemonSet pod per worker, not the literal 3 it checks for.

### Breadth extensions (only if Blocks A and B finished inside the cap)

Not required. If time is left, work down this list in order and stop when your cap is up;
finishing all four is not expected. Each entry is that file's Level 1, listed exam-priority first.

- [ ] `exercises/01-pods/assignment-2/pod-config-injection-homework.md`: Exercises 1.1, 1.2, 1.3
- [ ] `exercises/12-rbac/assignment-1/rbac-homework.md`: Exercises 1.1, 1.2, 1.3
- [ ] `exercises/08-services/assignment-1/services-homework.md`: Exercises 1.1, 1.2, 1.3
- [ ] `exercises/02-jobs-and-cronjobs/assignment-1/jobs-and-cronjobs-homework.md`: Exercises 1.1, 1.2, 1.3

### Capstone: timed self-check (rust gate before Day 1)

A no-docs, from-memory rebuild of the four resource types you lean on all week, each in under
about two minutes. Create a throwaway namespace first with `kubectl create namespace cap`. If
any one of these needs a documentation lookup, that resource type is the rust to drill before
you start Day 1.

- [ ] Pod `web` in namespace `cap`, image `nginx:1.25`, with labels `app=web` and `tier=frontend`. Confirm: `kubectl get pod web -n cap --show-labels` shows Running and both labels.
- [ ] Deployment `api` in namespace `cap`, image `nginx:1.25`, 3 replicas. Confirm: `kubectl get deploy api -n cap` shows `3/3` ready.
- [ ] ClusterIP Service named `api` for that Deployment on port 80. Confirm: `kubectl get svc api -n cap` shows type `ClusterIP`, and `kubectl get endpoints api -n cap` lists 3 endpoint addresses.
- [ ] ConfigMap `app-config` in namespace `cap` with two literal keys, `COLOR=blue` and `MODE=dark`. Confirm: `kubectl get cm app-config -n cap -o yaml` shows both keys.
- [ ] Cleanup: `kubectl delete namespace cap`.
