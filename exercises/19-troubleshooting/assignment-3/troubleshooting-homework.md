# Node and Kubelet Troubleshooting Homework

This homework contains 15 hands-on debugging exercises. Every exercise setup intentionally breaks something on a worker node, and your task is to diagnose the failure, fix it, and verify the node returns to Ready status. Follow the diagnostic workflow from the tutorial: detect the NotReady node, inspect conditions and events, access the node, check kubelet service status, read logs, identify the root cause, fix the configuration, restart services as needed, and verify recovery.

## Preparation

Ensure you have completed the tutorial and have a working multi-node kind cluster with 1 control-plane and 3 worker nodes. Verify all nodes are Ready before starting the exercises.

```bash
kubectl get nodes
# Expected: All nodes show Ready status
```

## Critical Safety Note

All exercises in this assignment break worker nodes only, never the control-plane node. Breaking the control-plane node would make the cluster unusable and prevent you from running kubectl commands for verification. Each exercise specifies which worker node to break (kind-worker, kind-worker2, or kind-worker3). Always verify you are accessing the correct node before running the breaking commands.

---

## Level 1: Basic Kubelet Service Failures

### Exercise 1.1

**Objective:** The kubelet service on kind-worker has stopped.

**Setup:**

```bash
nerdctl exec kind-worker systemctl stop kubelet
```

**Task:**

Diagnose why kind-worker is NotReady, identify that the kubelet service is stopped, and restore it to running state.

**Verification:**

```bash
kubectl get nodes
# Expected: kind-worker shows Ready

kubectl describe node kind-worker | grep -A 5 "Conditions:" | grep "Ready"
# Expected: Ready True

kubectl run verify-1-1 --image=nginx:1.27 --restart=Never \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"kind-worker"}}}' \
  -n default

kubectl get pod verify-1-1 -o wide
# Expected: Pod Running on kind-worker

kubectl delete pod verify-1-1
```

---

### Exercise 1.2

**Objective:** The kubelet binary path in the systemd unit on kind-worker2 is wrong.

**Setup:**

```bash
nerdctl exec kind-worker2 bash -c "cp /etc/systemd/system/kubelet.service.d/10-kubeadm.conf /etc/systemd/system/kubelet.service.d/10-kubeadm.conf.bak"

nerdctl exec kind-worker2 bash -c "sed -i 's|/usr/bin/kubelet|/usr/local/bin/kubelet|' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf"

nerdctl exec kind-worker2 systemctl daemon-reload
nerdctl exec kind-worker2 systemctl restart kubelet
```

**Task:**

Diagnose why kind-worker2 is NotReady, identify the wrong binary path in the systemd ExecStart line, and fix it.

**Verification:**

```bash
kubectl get nodes
# Expected: kind-worker2 shows Ready

kubectl run verify-1-2 --image=busybox:1.36 --restart=Never --command -- sleep 3600 \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"kind-worker2"}}}' \
  -n default

kubectl get pod verify-1-2 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl delete pod verify-1-2
```

---

### Exercise 1.3

**Objective:** The kubelet configuration file on kind-worker3 is missing.

**Setup:**

```bash
nerdctl exec kind-worker3 bash -c "mv /var/lib/kubelet/config.yaml /var/lib/kubelet/config.yaml.backup"

nerdctl exec kind-worker3 systemctl restart kubelet
```

**Task:**

Diagnose why kind-worker3 is NotReady, identify that the kubelet config file is missing, and restore it.

**Verification:**

```bash
kubectl get nodes
# Expected: kind-worker3 shows Ready

nerdctl exec kind-worker3 systemctl status kubelet | grep "active (running)"
# Expected: Output shows active (running)

kubectl run verify-1-3 --image=alpine:3.20 --restart=Never --command -- sleep 3600 \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"kind-worker3"}}}' \
  -n default

kubectl get pod verify-1-3 -o wide
# Expected: Pod Running on kind-worker3

kubectl delete pod verify-1-3
```

---

## Level 2: Configuration File Errors

### Exercise 2.1

**Objective:** The kubelet config file on kind-worker has a syntax error.

**Setup:**

```bash
nerdctl exec kind-worker bash -c "cp /var/lib/kubelet/config.yaml /var/lib/kubelet/config.yaml.good"

nerdctl exec kind-worker bash -c "sed -i '5s/://' /var/lib/kubelet/config.yaml"

nerdctl exec kind-worker systemctl restart kubelet
```

**Task:**

Diagnose why kind-worker is NotReady, identify the YAML syntax error in the kubelet config file, and fix it.

**Verification:**

```bash
kubectl get nodes
# Expected: kind-worker shows Ready

kubectl describe node kind-worker | grep "KubeletReady"
# Expected: No errors, node is Ready

kubectl run verify-2-1 --image=redis:7.2 --restart=Never \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"kind-worker"}}}' \
  -n default

kubectl get pod verify-2-1 -o jsonpath='{.spec.nodeName}'
# Expected: kind-worker

kubectl delete pod verify-2-1
```

---

### Exercise 2.2

**Objective:** The kubeconfig path flag is wrong in the systemd unit on kind-worker2.

**Setup:**

```bash
nerdctl exec kind-worker2 bash -c "sed -i 's|--kubeconfig=/etc/kubernetes/kubelet.conf|--kubeconfig=/etc/kubernetes/kubelet-wrong.conf|' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf"

nerdctl exec kind-worker2 systemctl daemon-reload
nerdctl exec kind-worker2 systemctl restart kubelet
```

**Task:**

Diagnose why kind-worker2 is NotReady, identify that the kubeconfig path is wrong, and fix it.

**Verification:**

```bash
kubectl get nodes
# Expected: kind-worker2 shows Ready

kubectl run verify-2-2 --image=httpd:2.4 --restart=Never \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"kind-worker2"}}}' \
  -n default

kubectl get pod verify-2-2 -o wide
# Expected: Pod Running on kind-worker2

kubectl delete pod verify-2-2
```

---

### Exercise 2.3

**Objective:** The container runtime endpoint in the kubelet config on kind-worker3 is wrong.

**Setup:**

```bash
nerdctl exec kind-worker3 bash -c "cp /var/lib/kubelet/config.yaml /var/lib/kubelet/config.yaml.orig"

nerdctl exec kind-worker3 bash -c "sed -i 's|unix:///run/containerd/containerd.sock|unix:///run/containerd/wrong.sock|' /var/lib/kubelet/config.yaml"

nerdctl exec kind-worker3 systemctl restart kubelet
```

**Task:**

Diagnose why kind-worker3 is NotReady, identify that the container runtime endpoint is wrong, and fix it.

**Verification:**

```bash
kubectl get nodes
# Expected: kind-worker3 shows Ready

kubectl describe node kind-worker3 | grep -A 5 "Conditions:" | grep "Ready.*True"
# Expected: Ready condition is True

kubectl run verify-2-3 --image=nginx:1.27 --restart=Never \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"kind-worker3"}}}' \
  -n default

kubectl get pod verify-2-3 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl delete pod verify-2-3
```

---

## Level 3: Certificate and Authentication Issues

### Exercise 3.1

**Objective:** The kubelet kubeconfig file on kind-worker is missing the client certificate.

**Setup:**

```bash
nerdctl exec kind-worker bash -c "cp /etc/kubernetes/kubelet.conf /etc/kubernetes/kubelet.conf.backup"

nerdctl exec kind-worker bash -c "sed -i '/client-certificate-data:/d' /etc/kubernetes/kubelet.conf"

nerdctl exec kind-worker systemctl restart kubelet
```

**Task:**

Diagnose why kind-worker is NotReady, identify that the client certificate is missing from the kubeconfig, and restore it.

**Verification:**

```bash
kubectl get nodes
# Expected: kind-worker shows Ready

kubectl run verify-3-1 --image=busybox:1.36 --restart=Never --command -- sleep 3600 \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"kind-worker"}}}' \
  -n default

kubectl get pod verify-3-1 -o wide
# Expected: Pod Running on kind-worker

kubectl delete pod verify-3-1
```

---

### Exercise 3.2

**Objective:** The CA certificate reference in the kubelet kubeconfig on kind-worker2 is wrong.

**Setup:**

```bash
nerdctl exec kind-worker2 bash -c "cp /etc/kubernetes/kubelet.conf /etc/kubernetes/kubelet.conf.save"

nerdctl exec kind-worker2 bash -c "sed -i 's|certificate-authority-data:|certificate-authority-data-wrong:|' /etc/kubernetes/kubelet.conf"

nerdctl exec kind-worker2 systemctl restart kubelet
```

**Task:**

Diagnose why kind-worker2 is NotReady, identify that the CA certificate field name is corrupted in the kubeconfig, and fix it.

**Verification:**

```bash
kubectl get nodes
# Expected: kind-worker2 shows Ready

nerdctl exec kind-worker2 systemctl status kubelet | grep "active (running)"
# Expected: Shows active (running)

kubectl run verify-3-2 --image=alpine:3.20 --restart=Never --command -- sleep 3600 \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"kind-worker2"}}}' \
  -n default

kubectl get pod verify-3-2 -o jsonpath='{.spec.nodeName}'
# Expected: kind-worker2

kubectl delete pod verify-3-2
```

---

### Exercise 3.3

**Objective:** The containerd service on kind-worker3 is stopped.

**Setup:**

```bash
nerdctl exec kind-worker3 systemctl stop containerd
```

**Task:**

Diagnose why kind-worker3 is NotReady, identify that containerd is stopped (not kubelet), and start the containerd service.

**Verification:**

```bash
kubectl get nodes
# Expected: kind-worker3 shows Ready

nerdctl exec kind-worker3 systemctl status containerd | grep "active (running)"
# Expected: Shows active (running)

kubectl run verify-3-3 --image=nginx:1.27 --restart=Never \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"kind-worker3"}}}' \
  -n default

kubectl get pod verify-3-3 -o wide
# Expected: Pod Running on kind-worker3

kubectl delete pod verify-3-3
```

---

## Level 4: Multi-Component Failures

### Exercise 4.1

**Objective:** Both the kubelet config file and the systemd unit have errors on kind-worker.

**Setup:**

```bash
nerdctl exec kind-worker bash -c "sed -i 's|clusterDNS:|clusterDNSWrong:|' /var/lib/kubelet/config.yaml"

nerdctl exec kind-worker bash -c "sed -i 's|--config=/var/lib/kubelet/config.yaml|--config=/var/lib/kubelet/config-wrong.yaml|' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf"

nerdctl exec kind-worker systemctl daemon-reload
nerdctl exec kind-worker systemctl restart kubelet
```

**Task:**

Diagnose why kind-worker is NotReady. There are two separate issues. Fix both.

**Verification:**

```bash
kubectl get nodes
# Expected: kind-worker shows Ready

kubectl run verify-4-1 --image=redis:7.2 --restart=Never \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"kind-worker"}}}' \
  -n default

kubectl get pod verify-4-1 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl delete pod verify-4-1
```

---

### Exercise 4.2

**Objective:** The kubelet on kind-worker2 has a wrong config path flag, and containerd socket permissions are broken.

**Setup:**

```bash
nerdctl exec kind-worker2 bash -c "sed -i 's|--config=/var/lib/kubelet/config.yaml|--config=/var/lib/kubelet/missing.yaml|' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf"

nerdctl exec kind-worker2 bash -c "chmod 000 /run/containerd/containerd.sock"

nerdctl exec kind-worker2 systemctl daemon-reload
nerdctl exec kind-worker2 systemctl restart kubelet
```

**Task:**

Diagnose why kind-worker2 is NotReady. Find and fix all issues.

**Verification:**

```bash
kubectl get nodes
# Expected: kind-worker2 shows Ready

nerdctl exec kind-worker2 ls -la /run/containerd/containerd.sock | grep "srw-rw----"
# Expected: Socket has correct permissions

kubectl run verify-4-2 --image=httpd:2.4 --restart=Never \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"kind-worker2"}}}' \
  -n default

kubectl get pod verify-4-2 -o wide
# Expected: Pod Running on kind-worker2

kubectl delete pod verify-4-2
```

---

### Exercise 4.3

**Objective:** The kubelet config file on kind-worker3 has both a YAML syntax error and a wrong runtime endpoint.

**Setup:**

```bash
nerdctl exec kind-worker3 bash -c "sed -i '3s/:/ :/' /var/lib/kubelet/config.yaml"

nerdctl exec kind-worker3 bash -c "sed -i 's|containerRuntimeEndpoint:|containerRuntimeEndpointBroken:|' /var/lib/kubelet/config.yaml"

nerdctl exec kind-worker3 systemctl restart kubelet
```

**Task:**

Diagnose why kind-worker3 is NotReady. Fix all configuration errors.

**Verification:**

```bash
kubectl get nodes
# Expected: kind-worker3 shows Ready

kubectl describe node kind-worker3 | grep "Ready.*True"
# Expected: Ready True

kubectl run verify-4-3 --image=busybox:1.36 --restart=Never --command -- sleep 3600 \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"kind-worker3"}}}' \
  -n default

kubectl get pod verify-4-3 -o jsonpath='{.spec.nodeName}'
# Expected: kind-worker3

kubectl delete pod verify-4-3
```

---

## Level 5: Complex Diagnostic Scenarios

### Exercise 5.1

**Objective:** Multiple issues on kind-worker prevent the kubelet from running correctly.

**Setup:**

```bash
nerdctl exec kind-worker bash -c "sed -i 's|/usr/bin/kubelet|/bin/kubelet|' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf"

nerdctl exec kind-worker bash -c "sed -i 's|apiVersion:|apiVersionWrong:|' /var/lib/kubelet/config.yaml"

nerdctl exec kind-worker bash -c "sed -i 's|--kubeconfig=/etc/kubernetes/kubelet.conf|--kubeconfig=/etc/kubernetes/missing.conf|' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf"

nerdctl exec kind-worker systemctl daemon-reload
nerdctl exec kind-worker systemctl restart kubelet
```

**Task:**

Diagnose why kind-worker is NotReady. There are three distinct issues. Identify and fix all of them.

**Verification:**

```bash
kubectl get nodes
# Expected: kind-worker shows Ready

nerdctl exec kind-worker systemctl status kubelet | grep "active (running)"
# Expected: Shows active (running)

kubectl run verify-5-1 --image=nginx:1.27 --restart=Never \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"kind-worker"}}}' \
  -n default

kubectl get pod verify-5-1 -o wide
# Expected: Pod Running on kind-worker

kubectl delete pod verify-5-1
```

---

### Exercise 5.2

**Objective:** The kubelet and containerd on kind-worker2 both have issues.

**Setup:**

```bash
nerdctl exec kind-worker2 systemctl stop kubelet

nerdctl exec kind-worker2 systemctl stop containerd

nerdctl exec kind-worker2 bash -c "sed -i 's|--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf|--bootstrap-kubeconfig=/etc/kubernetes/missing-bootstrap.conf|' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf"

nerdctl exec kind-worker2 systemctl daemon-reload
```

**Task:**

Diagnose why kind-worker2 is NotReady. Both kubelet and containerd need to be addressed. Fix the configuration and start both services.

**Verification:**

```bash
kubectl get nodes
# Expected: kind-worker2 shows Ready

nerdctl exec kind-worker2 systemctl status kubelet | grep "active (running)"
# Expected: Shows active (running)

nerdctl exec kind-worker2 systemctl status containerd | grep "active (running)"
# Expected: Shows active (running)

kubectl run verify-5-2 --image=alpine:3.20 --restart=Never --command -- sleep 3600 \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"kind-worker2"}}}' \
  -n default

kubectl get pod verify-5-2 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl delete pod verify-5-2
```

---

### Exercise 5.3

**Objective:** The kubelet on kind-worker3 has a corrupted systemd unit, a wrong config file field, and the kubeconfig is missing a required section.

**Setup:**

```bash
nerdctl exec kind-worker3 bash -c "sed -i 's|ExecStart=|ExecStartWrong=|' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf"

nerdctl exec kind-worker3 bash -c "sed -i 's|kind: KubeletConfiguration|kind: KubeletConfigurationBroken|' /var/lib/kubelet/config.yaml"

nerdctl exec kind-worker3 bash -c "sed -i '/client-key-data:/d' /etc/kubernetes/kubelet.conf"

nerdctl exec kind-worker3 systemctl daemon-reload
nerdctl exec kind-worker3 systemctl restart kubelet
```

**Task:**

Diagnose why kind-worker3 is NotReady. There are three separate problems across different configuration files. Identify and fix all of them.

**Verification:**

```bash
kubectl get nodes
# Expected: kind-worker3 shows Ready

kubectl describe node kind-worker3 | grep -A 10 "Conditions:" | grep "Ready.*True"
# Expected: Ready True

nerdctl exec kind-worker3 systemctl status kubelet | grep "active (running)"
# Expected: Shows active (running)

kubectl run verify-5-3 --image=redis:7.2 --restart=Never \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"kind-worker3"}}}' \
  -n default

kubectl get pod verify-5-3 -o wide
# Expected: Pod Running on kind-worker3

kubectl delete pod verify-5-3
```

---

## Cleanup

After completing all exercises, verify all nodes are healthy.

```bash
kubectl get nodes
# Expected: All nodes show Ready
```

If any node is still NotReady, revisit that exercise and ensure you completed all fix steps, reloaded systemd where needed, and restarted the kubelet service.

## Key Takeaways

You have now practiced the complete node and kubelet troubleshooting workflow 15 times with different failure modes. You should be comfortable detecting NotReady nodes from kubectl output, using kubectl describe node to read conditions and events, accessing worker nodes with nerdctl exec, checking kubelet and containerd service status with systemctl, reading logs with journalctl to identify root causes, editing kubelet systemd units and reloading systemd, correcting kubelet configuration file errors, distinguishing kubelet failures from runtime failures, restarting services after fixes, and verifying recovery by confirming the node is Ready and can successfully run pods. These are the exact skills tested in CKA exam questions on node troubleshooting, and you have now built the muscle memory to execute them under time pressure.
