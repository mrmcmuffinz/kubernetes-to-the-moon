# CKA Day 2 (Tue, June 23) | NetworkPolicy

Goal: the egress and port-pairing skill behind the Sim A Q15 you skipped, including the
AND-versus-OR trap (multiple `to` or `ports` entries in one rule form an OR cross-product,
so each destination needs its own rule). This works the corpus on your own cluster with
answer keys; the exact Q15 scenario is left for the Day 5 session. NetworkPolicy is Day 2's
whole job, so plan on most of the day; if it runs long, the plan's buffer day (Day 8)
absorbs it.

## Environment

NetworkPolicy is only enforced by a policy-aware CNI. Use your Calico-backed cluster (the VM
or the Pi), not default kindnet.

- [ ] Confirm enforcement before trusting any result: apply a default-deny in a test namespace and check that a pod there loses connectivity. If traffic still flows, the CNI is not enforcing policy and every exercise below will read as a false pass.

## Block A: fundamentals (ingress, egress, ports, OR semantics)

Source: `exercises/10-network-policies/assignment-1/network-policies-homework.md`

- [ ] Exercise 1.1
- [ ] Exercise 1.2
- [ ] Exercise 1.3
- [ ] Exercise 2.1
- [ ] Exercise 2.2
- [ ] Exercise 2.3

## Block B: cross-namespace and the AND/OR distinction

Source: `exercises/10-network-policies/assignment-2/network-policies-homework.md`

- [ ] Exercise 1.1
- [ ] Exercise 1.2
- [ ] Exercise 2.1

Block A's Exercise 2.2 (multiple `from` entries, OR) and this block's Exercise 2.1 (combined
pod and namespace selectors, AND) are the two halves of the Q15 trap. Do them back to back
and watch the behavior differ.

## Block C: debugging and verification

Source: `exercises/10-network-policies/assignment-3/network-policies-homework.md`

- [ ] Exercise 1.1
- [ ] Exercise 1.2
- [ ] Exercise 1.3

## Check-in

- [ ] Can you write an egress policy that pairs each destination with its own port as separate rules on the first pass, and say out loud when multiple `to` or `ports` entries in one rule become an OR cross-product instead? That first-pass pairing is the exact Q15 closure bar, and it is what to have automatic before the Day 5 session.
