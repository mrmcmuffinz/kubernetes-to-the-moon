# CKA Day 7 (Sun, June 28) | Targeted fixes, or broad speed and accuracy

Goal: address exactly what Session 2 revealed. If it revealed specific misses, drill only
those. If it was clean, this becomes a broad speed-and-accuracy day rather than a light one,
because at the 90%+ bar the whole question set has to be fast, not just the known-weak topics.

## If Session 2 revealed specific misses

- [ ] Drill only what it actually showed, not a repeat of Days 1 to 4. Re-open the matching day file (Day 2 for NetworkPolicy, Day 3 for CoreDNS, and so on) and redo the relevant block cold.
- [ ] A genuinely new weak domain becomes a new worksheet in this style: corpus pointers by exercise number, explicit setup, no answers. Drill it the same way (docs, attempt cold, verify, compare, two timed reps).

## If Session 2 was clean

- [ ] Broad timed reps across a mix of the week's blocks, including any question that ran over target on Session 2. Run the verification each time, not just the build.
- [ ] The three preview-question drills for breadth: etcd certificate inspection (`exercises/17-cluster-lifecycle/assignment-3/cluster-lifecycle-homework.md`, the etcd exploration level), kube-proxy Service iptables, and changing the Service CIDR. The last two edit a kubeadm node, so use a throwaway cluster.
- [ ] Documentation-navigation drills: find the right page fast on kubernetes.io/docs, kubernetes.io/blog, helm.sh/docs, and gateway-api.sigs.k8s.io.

## Check-in

- [ ] For everything you touched today, including anything that scored full marks on Session 2, did the verification pass under target on a cold rep? Anything still correct-but-slow goes on the Day 8 list.
