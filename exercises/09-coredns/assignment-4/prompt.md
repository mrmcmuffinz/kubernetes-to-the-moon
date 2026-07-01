# CoreDNS Assignment 4: Advanced DNS Patterns

**Series:** CoreDNS (4 of 4)
**Assignment number:** 4
**Prerequisites:** 09-coredns/assignment-3, 08-services/assignment-2
**CKA Domain:** Services & Networking (20%)
**CKA Competencies:** Understand and use CoreDNS, use ClusterIP/NodePort/LoadBalancer service types and endpoints
**Course sections:** S9 (lectures 227-240 Networking)

---

## Scope Declaration

### In Scope for This Assignment

*Headless Service DNS Behavior*
- Headless services (ClusterIP: None) and their DNS behavior
- DNS returning multiple A records (one per pod) instead of single VIP
- SRV record structure and querying for headless services
- Comparing headless vs ClusterIP service DNS responses
- Use cases for headless services (StatefulSet, client-side load balancing)

*ExternalName Service DNS*
- ExternalName service type and CNAME behavior
- DNS aliasing external domains into cluster DNS namespace
- Differences between ExternalName and ClusterIP service DNS resolution
- Creating ExternalName services for external databases or APIs
- Verifying CNAME records with dig and nslookup

*Pod Subdomain and Hostname*
- Using spec.subdomain and spec.hostname for custom pod DNS names
- Pod DNS format: `<hostname>.<subdomain>.<namespace>.svc.cluster.local`
- Relationship between subdomain field and headless service name
- How StatefulSets use subdomain/hostname for stable network identities
- Comparing IP-based pod DNS vs subdomain-based pod DNS

*Multiple Cluster Domains*
- Configuring multiple cluster domains in the kubernetes plugin
- kubernetes plugin syntax: `kubernetes cluster.local custom-domain in-addr.arpa ip6.arpa`
- Verifying services resolve in both cluster domains
- Use cases for multiple domains (migration scenarios, integration with legacy systems)
- CKA Sim A Q16 scenario (adding a second cluster domain)

*Custom Upstream DNS*
- Configuring forward plugin with explicit upstream DNS servers
- Syntax: `forward . 8.8.8.8 1.1.1.1` instead of `forward . /etc/resolv.conf`
- Use cases for custom upstream (corporate DNS, specific resolvers)
- Failover behavior across multiple upstream servers
- Verifying external resolution uses custom upstreams

*CoreDNS High Availability*
- CoreDNS as a Deployment with multiple replicas
- kube-dns service load balancing across CoreDNS pods
- Testing DNS resilience during pod failure
- Deployment controller recreating failed CoreDNS pods
- Scaling CoreDNS replicas for high availability

*Missing kube-dns Service Recovery*
- Role of kube-dns service in pod DNS resolution
- Diagnosing DNS failures when kube-dns service is deleted
- Understanding why pods still reference the service IP after deletion
- Recreating kube-dns service from backup
- Verification workflow for kube-dns service health

### Out of Scope

The following topics are explicitly not covered in this assignment:

- **Basic DNS lookup mechanics** (FQDN, short names, cross-namespace): Covered in 09-coredns/assignment-1
- **DNS policies and dnsConfig**: Covered in 09-coredns/assignment-1
- **CoreDNS plugin architecture** (kubernetes, forward, hosts, log, cache): Covered in 09-coredns/assignment-2
- **Stub domains and separate server blocks**: Covered in 09-coredns/assignment-2
- **DNS troubleshooting workflows** (CoreDNS pod failures, Network Policy blocking DNS): Covered in 09-coredns/assignment-3
- **ClusterIP service creation and selectors**: Covered in 08-services/assignment-1
- **NodePort and LoadBalancer service types**: Covered in 08-services/assignment-2 (referenced here for ExternalName comparison)
- **StatefulSet creation and management**: Covered in 03-statefulsets/assignment-1 (pod subdomain/hostname provides the DNS foundation StatefulSets build on)

---

## Environment Requirements

**Cluster:** Multi-node kind cluster (same as assignments 1-3)

**Tools:** kubectl, nslookup (busybox image), dig (alpine image with bind-tools)

**CoreDNS:** Default kind installation (CoreDNS Deployment in kube-system, kube-dns service)

**Special setup:** Assignment-2 taught Corefile editing and backup/restore workflow. This assignment assumes learners can safely edit the CoreDNS ConfigMap and restore from backup.

---

## Resource Gate

This assignment unlocks after Services and CoreDNS assignments 1-3, so all CKA resources are in scope.

Permitted resources:
- All standard Kubernetes resources (Pods, Services, Deployments, ConfigMaps, etc.)
- Focus is on Service types (ClusterIP with None, ExternalName) and CoreDNS ConfigMap

---

## Topic-Specific Conventions

**Corefile editing safety:**
- Every exercise that edits the CoreDNS ConfigMap must include backup instructions before the edit
- Cleanup sections must restore the original config from backup
- Wait 15 seconds after applying ConfigMap changes for CoreDNS to reload

**DNS verification patterns:**
- Use nslookup for basic A record queries
- Use dig for SRV records and explicit record type queries
- Use dig +short for concise output when checking specific values

**Service DNS testing:**
- Headless services require backend pods to exist for DNS to return A records
- ExternalName services do not have ClusterIP (spec.clusterIP shows None or is absent)
- Subdomain-based pod DNS requires a matching headless service to exist

**Assignment structure:**
- Level 1: Headless and ExternalName service DNS (2 exercises: headless behavior, ExternalName CNAME)
- Level 2: Pod subdomain and hostname (2 exercises: custom pod DNS, StatefulSet DNS foundation)
- Level 3: CoreDNS configuration scenarios (3 exercises: multiple domains, custom upstream, debugging)
- Level 4: CoreDNS high availability (2 exercises: pod failure resilience, missing service recovery)
- Level 5: Integrated scenarios (2 exercises: combining multiple patterns, exam-style troubleshooting)

**Difficulty progression:**
- Levels 1-2 test understanding of specialized service and pod DNS patterns
- Level 3 applies Corefile editing skills from assignment-2 to new scenarios
- Level 4 tests operational understanding of CoreDNS infrastructure
- Level 5 integrates multiple patterns in realistic troubleshooting scenarios

**Common mistakes to anticipate:**
- Forgetting to create backend pods for headless services (DNS returns NXDOMAIN)
- Creating subdomain-based pod DNS without a matching headless service
- Not waiting for CoreDNS reload after ConfigMap edits
- Deleting kube-dns service and not understanding why /etc/resolv.conf still references it

---

## Cross-References

**Backward references (prerequisites):**
- 08-services/assignment-1: ClusterIP service DNS, service selectors, endpoints
- 08-services/assignment-2: NodePort and LoadBalancer service types, ExternalName mentioned but DNS behavior not tested in depth
- 09-coredns/assignment-1: Service and pod DNS fundamentals, DNS policies, nslookup/dig usage
- 09-coredns/assignment-2: CoreDNS ConfigMap structure, kubernetes and forward plugins, Corefile editing workflow
- 09-coredns/assignment-3: DNS troubleshooting techniques, CoreDNS pod and service health checks

**Forward references:**
- 03-statefulsets/assignment-1: StatefulSets use pod subdomain/hostname for stable DNS (this assignment provides the DNS foundation)
- 19-troubleshooting/assignment-4: Cross-domain network troubleshooting includes advanced DNS failure scenarios

---

## Notes for the Homework Generator

**Exercise type distribution:**
- 6 exercises test specialized DNS patterns (headless, ExternalName, subdomain, multiple domains, custom upstream, HA resilience)
- 3 exercises involve Corefile editing (following assignment-2 conventions: backup, edit, verify, restore)
- 2 exercises test troubleshooting (missing service, integrated failure scenarios)
- 4 debugging exercises present intentional failures (missing backend pods, missing headless service, wrong upstream DNS, service deletion)

**Verification approach:**
- Headless service exercises verify multiple A records are returned
- ExternalName exercises verify CNAME record in dig output
- Subdomain exercises verify custom pod DNS resolves and compare to IP-based DNS
- Multiple domain exercises verify the same service resolves in both domains
- HA exercises verify DNS continues working while CoreDNS pod is recreating

**Tutorial content requirements:**
- Explain headless service DNS behavior with diagram showing DNS returning pod IPs
- Show ExternalName CNAME chain (service name → external domain → external IP)
- Diagram pod subdomain/hostname DNS format and relationship to headless service
- Show multiple cluster domains configuration in Corefile with before/after examples
- Explain CoreDNS Deployment scaling and kube-dns service load balancing

**Answer key requirements:**
- Debugging answers must explain the diagnostic steps (check service type, verify backend pods exist, inspect endpoints)
- For Corefile editing exercises, show the exact plugin line before and after the change
- For missing service recovery, show the kubectl get svc command that reveals the service is gone, and the restoration workflow

**Integration with existing assignments:**
- Reference assignment-2 Corefile editing conventions (backup to /tmp, apply, wait, verify, restore)
- Reference assignment-1 DNS lookup patterns (short name, namespace-qualified, FQDN)
- Reference assignment-3 troubleshooting workflow (check CoreDNS pods, check kube-dns service, check endpoints)
