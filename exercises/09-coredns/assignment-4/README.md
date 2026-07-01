# CoreDNS Assignment 4: Advanced DNS Patterns

This assignment covers specialized DNS scenarios and patterns that appear in CKA exam simulations and advanced troubleshooting contexts. You will work with headless services and their DNS behavior, ExternalName services that create DNS aliases to external domains, pod subdomain and hostname fields for custom DNS names, multiple cluster domains in the CoreDNS configuration, custom upstream DNS servers, CoreDNS high availability, and missing service recovery scenarios. This is the fourth and final assignment in the CoreDNS series, building on the fundamentals (assignment 1), configuration skills (assignment 2), and troubleshooting techniques (assignment 3) you have already developed. After completing this assignment, you will have covered the full spectrum of DNS patterns tested in the CKA exam, including the multiple cluster domains scenario that appears in CKA Simulator A Question 16 and the pod subdomain DNS pattern that appears in CKA Simulator B Question 1.

---

## Files

| File | Description |
|---|---|
| `README.md` | This file (assignment overview and workflow guidance) |
| `prompt.md` | Detailed scope and generation instructions for this assignment |
| `coredns-tutorial.md` | Tutorial covering headless services, ExternalName, pod subdomain, multiple domains, and HA patterns |
| `coredns-homework.md` | 15 progressive exercises across five difficulty levels |
| `coredns-homework-answers.md` | Complete solutions with diagnostic reasoning for debugging exercises |

---

## Recommended Workflow

Start by working through the tutorial. It demonstrates headless service DNS behavior (how DNS returns multiple A records instead of a single VIP), ExternalName service CNAME mapping, pod subdomain and hostname fields that StatefulSets use for stable network identities, adding multiple cluster domains to the CoreDNS configuration (the CKA Sim A Q16 scenario), configuring custom upstream DNS servers, and testing CoreDNS high availability by deleting a replica. The tutorial also walks through the missing kube-dns service recovery scenario. Once you've completed the tutorial, move to the homework exercises. Work through all three exercises at each level before advancing. Levels 1 and 2 build your fluency with headless and ExternalName services plus custom pod DNS. Level 3 presents debugging scenarios where configurations are incomplete or misconfigured. Level 4 applies CoreDNS configuration skills from assignment 2 to new patterns (multiple domains, custom upstream). Level 5 integrates multiple patterns and tests your ability to troubleshoot complex DNS scenarios under exam-like conditions. Consult the answer key only after attempting each exercise.

---

## Difficulty Progression

Level 1 introduces headless service DNS and ExternalName service CNAME behavior through simple construction tasks. Level 2 builds on pod subdomain and hostname fields and integrates headless services with custom pod DNS. Level 3 presents debugging scenarios where services are missing backend pods, headless services are misconfigured, or pod DNS doesn't resolve due to missing headless service. Level 4 applies Corefile editing skills to add multiple cluster domains and configure custom upstream DNS servers, following the backup-edit-verify-restore workflow from assignment 2. Level 5 tests CoreDNS operational resilience (deleting replicas, recovering from missing kube-dns service) and presents integrated scenarios combining multiple DNS patterns.

---

## Prerequisites

This assignment assumes you have completed CoreDNS assignments 1, 2, and 3, plus Services assignment 2 (which introduces headless and ExternalName service types). You should be comfortable with service DNS lookup patterns, CoreDNS Corefile editing, and DNS troubleshooting workflows. The assignment also assumes you've worked through the Mumshad course sections on Networking (S9, lectures 227-240). For cluster setup, follow the multi-node cluster instructions in the [Multi-Node Kind Cluster section](../../docs/cluster-setup.md#multi-node-kind-cluster) of the cluster setup document.

---

## Cluster Requirements

This assignment uses the same multi-node kind cluster as CoreDNS assignments 1-3. See [Multi-Node Kind Cluster](../../docs/cluster-setup.md#multi-node-kind-cluster) in the cluster setup document for creation instructions. No additional components are needed beyond the default kind installation (CoreDNS runs as a Deployment in kube-system with the kube-dns service).

---

## Estimated Time Commitment

Level 1 exercises (headless and ExternalName services) take 10-15 minutes each if you're comfortable with service creation from assignment 2. Level 2 exercises (pod subdomain and hostname) take 15-20 minutes each as you experiment with custom pod DNS. Level 3 debugging exercises take 20-30 minutes each, involving diagnosis of missing services or misconfigured DNS settings. Level 4 exercises (Corefile editing for multiple domains and custom upstream) take 25-35 minutes each, including backup-edit-verify-restore cycles. Level 5 exercises (HA resilience and integrated scenarios) take 30-45 minutes each as they combine multiple patterns and test operational understanding. Plan for 6-8 hours total to complete the tutorial and all 15 exercises at a learning pace. If you're already fluent in headless services and Corefile editing from prior work, you may move faster through Levels 1-2.

---

## Scope Boundary and What Comes Next

This assignment focuses on advanced DNS patterns and edge cases: headless service DNS (multiple A records, SRV records), ExternalName CNAME behavior, pod subdomain/hostname for custom DNS (the foundation StatefulSets build on), multiple cluster domains, custom upstream DNS configuration, and CoreDNS operational resilience. Basic DNS lookup mechanics (FQDN, short names, cross-namespace), DNS policies (ClusterFirst, Default, None), and core CoreDNS plugins (kubernetes, forward, hosts, log, cache) were covered in assignments 1 and 2. DNS troubleshooting workflows (CoreDNS pod failures, Network Policy blocking DNS) were covered in assignment 3. StatefulSet creation and management is covered in the StatefulSets assignment (03-statefulsets/assignment-1), which builds on the pod subdomain/hostname DNS foundation this assignment establishes. Cross-domain DNS troubleshooting scenarios that combine DNS failures with other networking issues appear in the Troubleshooting assignment (19-troubleshooting/assignment-4).

---

## Key Takeaways After Completing This Assignment

After completing this assignment, you should be able to explain how headless service DNS differs from ClusterIP service DNS (multiple A records vs single VIP) and query SRV records with dig, create ExternalName services that alias external domains into the cluster DNS namespace and verify CNAME behavior, configure pod subdomain and hostname fields to create predictable DNS names (the mechanism StatefulSets use), edit the CoreDNS Corefile to add a second cluster domain and verify services resolve in both domains (the CKA Sim A Q16 scenario), configure the forward plugin to use custom upstream DNS servers instead of /etc/resolv.conf, explain how CoreDNS high availability works (multiple replicas behind the kube-dns service) and verify DNS continues during pod failures, and recover from missing kube-dns service by understanding why /etc/resolv.conf still references the deleted service IP and recreating the service from backup. These patterns represent the advanced DNS scenarios tested in CKA exam simulations and production troubleshooting contexts.
