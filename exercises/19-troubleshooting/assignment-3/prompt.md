# Troubleshooting Assignment 3: Node and Kubelet Troubleshooting (Hands-On Breaking Exercises)

**Series:** Troubleshooting (3 of 4)
**Assignment number:** 3
**Prerequisites:** 17-cluster-lifecycle/assignment-1, 17-cluster-lifecycle/assignment-2
**CKA Domain:** Troubleshooting (30%)
**CKA Competencies:** Troubleshoot clusters and nodes, troubleshoot cluster component failure
**Course sections:** S14 (lectures 292-294 Worker node failure)

---

## Scope Declaration

### In Scope for This Assignment

This assignment provides **hands-on kubelet and node breaking exercises** following the same pattern as assignment-2 (control plane troubleshooting). Every exercise setup intentionally breaks something on a worker node, and the task is to diagnose and fix it using real troubleshooting commands.

*Kubelet Service Failures*
- Kubelet stopped (systemctl stop kubelet)
- Kubelet wrong binary path in systemd unit (Simulator B Q6 scenario)
- Kubelet config file syntax errors
- Kubelet port conflicts
- Kubelet certificate issues preventing startup

*Node NotReady Diagnosis*
- kubectl describe node for conditions and events
- Node conditions: Ready=False with reason KubeletNotReady
- Identifying root cause from kubelet logs
- systemctl status kubelet on the node
- journalctl -u kubelet for error messages

*Container Runtime Issues*
- containerd.sock missing or wrong path in kubelet config
- containerd service stopped
- Runtime endpoint configuration errors
- CNI plugin issues causing network unavailable

*Kubelet Configuration Errors*
- Wrong kubeconfig path (--kubeconfig flag)
- Wrong CA certificate path
- Wrong static pod manifest directory
- Invalid YAML in kubelet config file
- Port already in use (healthz port, metrics port)

*Node Recovery Procedures*
- Fixing kubelet systemd unit files
- Restarting kubelet after config fix
- Verifying node returns to Ready
- Confirming pods can schedule on recovered node
- Drain and uncordon workflows

### Out of Scope

The following topics are explicitly not covered in this assignment:

- **Application-layer troubleshooting** (pod crashes, config errors): Covered in 19-troubleshooting/assignment-1
- **Control plane troubleshooting** (API server, scheduler, controller-manager, etcd): Covered in 19-troubleshooting/assignment-2
- **Network troubleshooting** (Service endpoints, DNS, NetworkPolicy): Covered in 19-troubleshooting/assignment-4
- **Node upgrades and kubeadm**: Covered in 17-cluster-lifecycle/assignment-2
- **Real hardware node conditions** (actual MemoryPressure, DiskPressure): Not hands-on reproducible in kind, covered conceptually in tutorial only

---

## Environment Requirements

**Cluster:** Multi-node kind cluster (1 control-plane + 3 workers) to allow safely breaking worker nodes

**Tools:** kubectl, nerdctl (for node access), systemctl, journalctl, crictl

**Node access:** All exercises use `nerdctl exec kind-worker bash` to access worker nodes and break kubelet

**Critical safety:** Never break the control-plane node. All exercises break worker nodes only.

---

## Resource Gate

All CKA resources are in scope (troubleshooting is a capstone assignment).

---

## Topic-Specific Conventions

**Exercise structure (following assignment-2 pattern):**
- Setup: Commands that break the kubelet/node (run these to create the failure)
- Objective: Brief statement of what is broken (bare, no hints)
- Task: What to diagnose and fix
- Verification: Commands showing the fix worked

**Kubelet breaking patterns:**
- Level 1: Service stopped, obvious failures (systemctl status shows inactive)
- Level 2: Configuration errors (wrong paths, wrong flags, syntax errors)
- Level 3: Certificate and auth issues, runtime connectivity
- Level 4: Multi-component failures (kubelet + runtime, kubelet + config + certs)
- Level 5: Complex scenarios requiring full diagnostic workflow

**Node targeting:**
- Exercise 1.1, 1.2, 1.3: kind-worker
- Exercise 2.1, 2.2, 2.3: kind-worker2
- Exercise 3.1, 3.2, 3.3: kind-worker3
- Exercise 4.1, 4.2, 4.3: kind-worker (reuse after recovery)
- Exercise 5.1, 5.2, 5.3: Multiple workers, complex scenarios

**Recovery verification pattern:**
- Node reaches Ready status
- Create test pod that schedules on the recovered node
- Verify pod runs successfully
- Clean up test pod

**Common mistakes to anticipate:**
- Not checking node from kubectl perspective before SSHing to node
- Fixing config but not restarting kubelet (systemctl restart kubelet)
- Fixing systemd unit but not running daemon-reload
- Looking at control-plane kubelet logs instead of worker node logs
- Not verifying node is Ready after fix

---

## Cross-References

**Backward references (prerequisites):**
- 17-cluster-lifecycle/assignment-1: kubeadm cluster setup, understanding kubelet role
- 17-cluster-lifecycle/assignment-2: Node drain/uncordon (used in recovery exercises)

**Forward references:**
- 19-troubleshooting/assignment-4: Network troubleshooting (CNI issues, kube-proxy)

---

## Notes for the Homework Generator

**Exercise type distribution:**
- 15 debugging exercises, all hands-on breaking scenarios
- 0 conceptual "describe how to" exercises (this is not assignment-3's old pattern)
- Every exercise setup includes actual breaking commands
- Every exercise task requires diagnosis → fix → verification

**Verification approach:**
- kubectl get nodes shows node Ready
- systemctl status kubelet shows active (running)
- Test pod schedules and runs on recovered node
- journalctl -u kubelet shows no errors after fix

**Tutorial content requirements:**
- Show full diagnostic workflow: kubectl describe node → identify KubeletNotReady → nerdctl exec to node → systemctl status → journalctl -u kubelet → fix → restart → verify
- Explain kubelet systemd unit structure (/usr/lib/systemd/system/kubelet.service.d/)
- Document common kubelet config file locations
- Show how to distinguish kubelet issues from runtime issues
- Include Simulator B Q6 scenario (wrong binary path) in tutorial examples

**Answer key requirements:**
- Three-stage structure for debugging exercises: diagnosis (commands to run), explanation (what is broken and why), fix (corrected config + restart commands)
- Show both quick fix (restore from backup) and diagnostic fix (identify and correct the error)
- Common mistakes section covering systemd reload, kubelet restart, checking wrong node

**Integration with existing assignments:**
- Reference assignment-2's control plane troubleshooting workflow (similar diagnostic approach)
- Reference cluster-lifecycle assignments for kubelet architecture understanding
- Use same bare heading convention as assignment-1 and assignment-2

**Specific breaking scenarios to include:**
- Exercise covering Simulator B Q6: kubelet binary path wrong in systemd unit (ExecStart=/usr/share/bin/kubelet instead of /usr/bin/kubelet)
- Exercise covering kubelet kubeconfig path wrong
- Exercise covering containerd socket path wrong in kubelet config
- Exercise covering kubelet stopped (simplest failure)
- Exercise covering kubelet config file syntax error (invalid YAML)
- Exercise covering kubelet CA cert path wrong
- Exercise covering multiple simultaneous issues (kubelet stopped + config error)

**Kind-specific notes:**
- Access nodes via nerdctl exec kind-<node-name> bash
- Systemd is available inside kind nodes
- Kubelet runs as systemd service inside the container
- Some real-world node conditions (MemoryPressure, DiskPressure) are difficult to reproduce in kind but the diagnostic workflow is the same
- CNI issues may require different troubleshooting in kind vs real clusters
