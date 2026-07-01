# CoreDNS and Cluster DNS

**CKA Domain:** Services & Networking (20%)
**Competencies covered:** Understand and use CoreDNS

---

## Rationale for Number of Assignments

CoreDNS and cluster DNS encompass DNS record formats, DNS policies, CoreDNS configuration, Corefile plugin structure, DNS troubleshooting workflows, and specialized DNS patterns. This produces roughly 22-24 distinct subtopics. The material splits naturally into four focused progressions: DNS fundamentals with lookup mechanics, CoreDNS configuration and plugin architecture, comprehensive DNS troubleshooting, and advanced DNS patterns and scenarios. The first three assignments deliver 5-6 core subtopics each, building from basic DNS usage through configuration mastery to diagnostic expertise. The fourth assignment covers specialized scenarios (headless services, ExternalName, pod subdomain, multiple cluster domains, CoreDNS high availability) that appear in CKA exam simulations and advanced troubleshooting contexts.

---

## Assignment Summary

| Assignment | Description | Prerequisites |
|---|---|---|
| assignment-1 | DNS Fundamentals | Service DNS format (<service>.<namespace>.svc.cluster.local), pod DNS records, DNS policies in pod spec (ClusterFirst, Default, None, ClusterFirstWithHostNet), service discovery via DNS, DNS lookup workflow and resolv.conf, DNS queries from pods (nslookup, dig) | 08-services/assignment-1 |
| assignment-2 | CoreDNS Configuration | CoreDNS Deployment in kube-system, CoreDNS ConfigMap and Corefile structure, CoreDNS plugins (kubernetes, forward, cache, errors, health), CoreDNS configuration customization, CoreDNS logging and verbosity, CoreDNS performance tuning | 09-coredns/assignment-1 |
| assignment-3 | DNS Troubleshooting | Diagnosing DNS resolution failures, CoreDNS pod failures, DNS policy misconfigurations, network policies blocking DNS traffic, DNS caching issues, service DNS not resolving | 09-coredns/assignment-2 |
| assignment-4 | Advanced DNS Patterns | Headless service DNS (multiple A records, SRV records), ExternalName service DNS (CNAME behavior), pod subdomain and hostname for custom DNS names, multiple cluster domains in kubernetes plugin, custom upstream DNS configuration, CoreDNS high availability and failover, missing kube-dns service recovery | 09-coredns/assignment-3 |

## Scope Boundaries

This topic covers DNS within the cluster. The following related areas are handled by other topics:

- **Services** (DNS resolves service names, but service creation is separate): covered in `services/`
- **Network Policies** (can block DNS traffic if egress to kube-dns is denied): covered in `network-policies/`
- **DNS failures in cross-domain troubleshooting**: covered in `19-troubleshooting/assignment-4`

Assignment-1 focuses on DNS usage from application perspective. Assignment-2 focuses on CoreDNS configuration and operation. Assignment-3 focuses on DNS troubleshooting and failure diagnosis. Assignment-4 focuses on advanced DNS patterns and edge cases that appear in CKA exam simulations (such as CKA Sim A Q16 multiple cluster domains scenario). The troubleshooting series adds cross-domain scenarios where DNS failures combine with other networking issues.

## Cluster Requirements

Multi-node kind cluster for all three assignments. CoreDNS runs as a Deployment in kube-system by default in kind, so no special configuration is needed. DNS debugging exercises use pods with nslookup/dig tools (busybox or dnsutils images).

## Recommended Order

1. Complete `08-services/assignment-1` first (DNS resolves service names, so understanding services is prerequisite)
2. Work through assignments 1, 2, 3, 4 sequentially
3. Assignment-2 assumes understanding of DNS lookup mechanics from assignment-1
4. Assignment-3 assumes understanding of both DNS usage and CoreDNS configuration from assignments 1 and 2
5. Assignment-4 builds on all three previous assignments and assumes familiarity with service types (from services/assignment-2)
