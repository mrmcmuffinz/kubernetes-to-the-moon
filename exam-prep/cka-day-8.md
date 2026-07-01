# CKA Day 8 (Mon, June 29) | Close the Real Gaps

**Exam:** Friday, July 3, 2026 at 10:00 AM Central Time (4 days out)

Goal: Close the two genuine conceptual gaps from the Simulator B retake (Q17 CRD confusion, Q16 api-resources vocabulary) and memorize the fixed paths that cost time during the attempt. This is targeted surgical work on diagnosed issues, not broad review.

## What the Retake Revealed

Simulator B retake scored 79/93 (85%), but 72% on truly fresh questions (Q12-Q17). Of the 14 lost subtasks:
- 8 are typo/omission class (fixable with discipline, addressed Day 9)
- 6 are genuine gaps: Q16 (1 subtask) + Q17 (5 subtasks) ← today's focus

## Block A: Q17 CRD Instance Drill

**The gap:** Confused CRD definition file (`base/crd.yaml`, defines the schema) with CRD instance file (`base/students.yaml`, holds actual Student objects). Time ran out during this confusion on the retake.

**The fix:** Build muscle memory distinguishing "add a new type to Kubernetes" (edit CRD definition) from "create one more object of an existing type" (add instance to instances file).

Source: `exercises/15-crds-and-operators/assignment-1/crds-and-operators-homework.md`

- [ ] Exercise 1.1 (create CRD definition)
- [ ] Exercise 1.2 (create instance of that CRD)
- [ ] Exercise 1.3 (create multiple CRD versions)

Source: `exercises/15-crds-and-operators/assignment-2/crds-and-operators-homework.md`

- [ ] Complete the setup (creates the `applications.apps.example.com` CRD)
- [ ] Exercise 2.1 (create custom resource instances)

**Target practice after completing those:**
- [ ] Given an existing CRD with 2-3 instances in a multi-doc YAML file, add a 4th instance by copying an existing one and changing name/spec. Target: <3 minutes.

## Block B: Q16 API Resources Vocabulary

**The gap:** Submitted namespace names and pod names when the question wanted resource *type* names (the output of `kubectl api-resources --namespaced`).

**The fix:** Internalize that "namespaced resources" means "resource types scoped to a namespace" (pods, secrets, deployments), not "things in this namespace."

Source: `exercises/15-crds-and-operators/assignment-2/crds-and-operators-tutorial.md`

- [ ] Read section "Custom Resource Discovery" (covers `kubectl api-resources`)

Source: `exercises/15-crds-and-operators/assignment-2/crds-and-operators-homework.md`

- [ ] Exercise 2.2 (use api-resources to discover custom resources)

**Quick drill after the exercise:**
- [ ] Practice the Q16 deliverable: `kubectl api-resources --namespaced -o name > /tmp/namespaced-types.txt`
- [ ] Verify you understand the output contains TYPE NAMES (pods, secrets) not instance names or namespace names

## Block C: Fixed Path Memorization

**The gap:** Q14's CNI config path was found by filesystem archaeology instead of recall, costing time.

Memorize these six paths/patterns:

| What | Path | Why it matters |
|---|---|---|
| CNI config directory | `/etc/cni/net.d/` | Q14 asked for this, you searched instead of knowing |
| Static pod manifests | `/etc/kubernetes/manifests/` | Already know this, confirm it sticks |
| Kubelet PKI directory | `/var/lib/kubelet/pki/` | Q3 needed this, now solidified |
| Kubelet client cert | `/var/lib/kubelet/pki/kubelet-client-current.pem` | Q3 specifically |
| Kubelet server cert | `/var/lib/kubelet/pki/kubelet.crt` | Q3 specifically |
| Static pod suffix format | `-<nodename>` (includes hyphen) | Q14 missed the hyphen |

- [ ] Cover the right column, quiz yourself on each path. Repeat until automatic.

## Block D: Application TLS Endpoint Drill (30 minutes)

**The gap:** Not tested in either simulator, but a standard admin task that could appear on the real exam. No hands-on practice yet.

**The drill:** Deploy nginx with HTTPS using a self-signed certificate in a Secret.

- [ ] Create self-signed cert and key: `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /tmp/app.key -out /tmp/app.crt -subj "/CN=app.example.test"`
- [ ] Create TLS Secret: `kubectl create secret tls app-tls --cert=/tmp/app.crt --key=/tmp/app.key -n default`
- [ ] Deploy nginx pod/deployment that mounts the Secret at `/etc/nginx/ssl/`
- [ ] Create nginx ConfigMap with SSL config: `listen 443 ssl; ssl_certificate /etc/nginx/ssl/tls.crt; ssl_certificate_key /etc/nginx/ssl/tls.key;`
- [ ] Expose via Service (ClusterIP on port 443)
- [ ] Verify: `kubectl port-forward svc/<name> 8443:443` then `curl -k https://localhost:8443` returns nginx welcome page

Target: Complete the full flow in <15 minutes after first rep.

## Check-in

- [ ] Q17 CRD instance drill completed, <3 minute target hit
- [ ] Q16 api-resources vocabulary confirmed
- [ ] All 6 fixed paths memorized
- [ ] Application TLS endpoint deployed and verified

These blocks close the genuine gaps. Tomorrow (Day 9) installs the discipline to prevent the typo cluster.
