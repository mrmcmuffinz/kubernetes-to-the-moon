# Node and Kubelet Troubleshooting Tutorial

## Introduction

Node failures are among the most disruptive issues in a Kubernetes cluster. When a node becomes NotReady, all pods scheduled on that node become unreachable, workloads may fail to reschedule if they were using local volumes, and the cluster's available capacity shrinks immediately. The kubelet is the primary component responsible for maintaining node health. It registers the node with the API server, runs the container runtime to manage pods, reports node conditions (Ready, MemoryPressure, DiskPressure, PIDPressure), and executes pod lifecycle operations (start, stop, restart based on policy). When the kubelet fails or is misconfigured, the node cannot perform its core functions.

This tutorial teaches the systematic diagnostic workflow for kubelet and node failures. You will learn to detect NotReady nodes from kubectl output, interpret node conditions and events, access worker nodes to inspect kubelet service status, read kubelet logs using journalctl, identify common kubelet configuration errors, distinguish kubelet issues from container runtime problems, fix kubelet systemd units and configuration files, restart the kubelet service, and verify that the node returns to Ready status with pods able to schedule successfully. The workflow mirrors the control plane troubleshooting pattern from assignment-2, applied to worker node components rather than control plane static pods.

We will work through a complete example where a kubelet binary path is wrong in the systemd unit (the scenario from Killer.sh CKA Simulator B Question 6), diagnose the failure using the five-step process (cluster-level detection, node conditions and events, node access, service logs, configuration inspection), apply the fix, restart the kubelet, and verify recovery. This single walkthrough covers all the diagnostic steps you will apply repeatedly in the 15 exercises.

## Prerequisites

Create a multi-node kind cluster with 1 control-plane and 3 worker nodes following the instructions in [docs/cluster-setup.md#multi-node-kind-cluster](../../../docs/cluster-setup.md#multi-node-kind-cluster). The multi-node setup is required because we will safely break worker nodes without affecting cluster control plane availability. Verify the cluster is running and all nodes are Ready before starting the tutorial.

```bash
kubectl get nodes
```

Expected output shows four nodes, all with status Ready.

## Setup

Create the tutorial namespace for any test pods we will use during diagnosis and verification.

```bash
kubectl create namespace tutorial-troubleshooting
```

## Understanding Kubelet Architecture

The kubelet is the primary node agent in Kubernetes. It runs on every node (both control-plane and worker nodes) as a systemd service. The kubelet's responsibilities include registering the node with the API server using the credentials in its kubeconfig file, watching the API server for pod assignments targeting this node, instructing the container runtime (containerd in most modern clusters) to start and stop containers according to pod specs, reporting pod status back to the API server, reporting node conditions (Ready, MemoryPressure, DiskPressure, PIDPressure, NetworkUnavailable) based on system resource monitoring, executing liveness and readiness probes and restarting containers when probes fail according to the pod's restart policy, mounting volumes and exposing them to containers, and running static pods from manifests in the configured staticPodPath directory.

The kubelet does not run as a pod. It runs directly on the host (or in the case of kind, inside the node container) as a systemd service. This is different from control plane components in kubeadm clusters, which run as static pods managed by the kubelet itself. The kubelet's configuration comes from two sources: command-line flags passed in the systemd unit's ExecStart line, and a configuration file (typically /var/lib/kubelet/config.yaml) referenced via the `--config` flag. The configuration file is the primary source for most settings (cluster DNS, cluster domain, authentication and authorization configuration, eviction thresholds, container runtime endpoint), while critical bootstrap settings like the kubeconfig path and the config file path itself are passed as flags.

The kubelet communicates with the API server over HTTPS using the client certificate and key specified in its kubeconfig file (typically /etc/kubernetes/kubelet.conf in kubeadm clusters). It trusts the API server's certificate using the CA certificate embedded in the same kubeconfig. If these certificate paths are wrong, the certificate files are missing, or the certificates have expired, the kubelet cannot authenticate to the API server and the node will not register or will become NotReady.

The kubelet communicates with the container runtime (containerd) over a Unix socket (typically /run/containerd/containerd.sock). The socket path is configured in the kubelet config file under the `containerRuntimeEndpoint` field. If this path is wrong, the socket file does not exist, or the containerd service is not running, the kubelet cannot manage containers and will report errors in its logs. The node may become NotReady with the condition reason `ContainerRuntimeNotReady`.

Node conditions are the kubelet's health reporting mechanism. The most important condition is Ready, which has three possible values. Ready=True means the kubelet is healthy and ready to accept pods. Ready=False means the kubelet is unhealthy; this is usually accompanied by a reason like KubeletNotReady or RuntimeNotReady. Ready=Unknown means the node controller has not heard from the kubelet in the node-monitor-grace-period (default 40 seconds); this usually indicates the kubelet is stopped, the node is unreachable, or the API server cannot reach the node. Other conditions include MemoryPressure (True when available memory is below the eviction threshold), DiskPressure (True when available disk is below the eviction threshold), PIDPressure (True when available PIDs are below the eviction threshold), and NetworkUnavailable (True when the network is not correctly configured, typically set by the CNI plugin).

## Walkthrough: Diagnosing a Kubelet Binary Path Error

We will intentionally break the kubelet on kind-worker by changing the binary path in its systemd unit from the correct /usr/bin/kubelet to an incorrect /usr/share/bin/kubelet. This is the exact scenario from Killer.sh Simulator B Question 6. The kubelet service will fail to start, the node will become NotReady, and we will diagnose and fix it using the five-step workflow.

### Step 1: Break the Kubelet (Setup)

Access the kind-worker node and back up the current kubelet systemd dropin file, then modify it to point to the wrong binary path.

```bash
nerdctl exec kind-worker bash -c "cp /etc/systemd/system/kubelet.service.d/10-kubeadm.conf /etc/systemd/system/kubelet.service.d/10-kubeadm.conf.backup"
```

Now edit the dropin file to change the ExecStart path.

```bash
nerdctl exec kind-worker bash -c "sed -i 's|/usr/bin/kubelet|/usr/share/bin/kubelet|' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf"
```

Reload systemd to pick up the change and restart the kubelet service to trigger the failure.

```bash
nerdctl exec kind-worker systemctl daemon-reload
nerdctl exec kind-worker systemctl restart kubelet
```

The kubelet will fail to start because /usr/share/bin/kubelet does not exist.

### Step 2: Detect the NotReady Node

From the cluster perspective (outside any node), check node status.

```bash
kubectl get nodes
```

You will see kind-worker with status NotReady. It may take 30 to 60 seconds after the kubelet restart for the node controller to mark the node as NotReady, depending on the node-monitor-grace-period.

### Step 3: Inspect Node Conditions and Events

Use kubectl describe to see detailed node conditions and recent events.

```bash
kubectl describe node kind-worker
```

Look for the Conditions section. You should see Ready=False with reason KubeletNotReady and a message like "kubelet stopped posting node status" or "container runtime is down." The exact message depends on timing; if the kubelet never started, you may see "Kubelet stopped posting node status" because the API server has not received a heartbeat. The Events section at the bottom may show NodeNotReady events logged by the node controller.

The key diagnostic signal here is that the Ready condition is False with reason KubeletNotReady. This tells you the kubelet is the problem, not a control plane issue, not a network partition, and not a scheduling constraint. The next step is to access the node and inspect the kubelet service directly.

### Step 4: Access the Node and Check Kubelet Service Status

Access the kind-worker node using nerdctl exec.

```bash
nerdctl exec kind-worker bash
```

Once inside the node, check the kubelet service status using systemctl.

```bash
systemctl status kubelet
```

You will see output showing the service is inactive (dead) or in a failed state. The key error message will appear in the last few lines of the status output. In this case, you should see something like "kubelet.service: Main process exited, code=exited, status=203/EXEC" or "Failed to execute command: No such file or directory." The status code 203/EXEC specifically indicates that systemd tried to execute the binary path in the ExecStart line but could not find the file.

### Step 5: Read Kubelet Logs

Check the kubelet logs using journalctl to get more context.

```bash
journalctl -u kubelet -n 50 --no-pager
```

The logs will show systemd's attempt to start the kubelet and the failure. Look for lines indicating "Failed at step EXEC spawning /usr/share/bin/kubelet: No such file or directory" or similar. This confirms that the ExecStart path is wrong.

### Step 6: Identify the Root Cause

The diagnostic path so far is:

1. Cluster level: kind-worker is NotReady, condition shows KubeletNotReady.
2. Node level: systemctl status kubelet shows the service is inactive/failed with status code 203/EXEC.
3. Logs: journalctl shows "Failed at step EXEC" because the binary path does not exist.

The root cause is that the systemd unit is trying to execute /usr/share/bin/kubelet, which does not exist. The correct path is /usr/bin/kubelet. Now we need to find where this path is configured. In kubeadm clusters, the kubelet systemd unit is split between a base unit file (/lib/systemd/system/kubelet.service or /usr/lib/systemd/system/kubelet.service depending on the distribution) and a dropin file (/etc/systemd/system/kubelet.service.d/10-kubeadm.conf) that provides the actual ExecStart line with all flags. The dropin file takes precedence.

Inspect the dropin file.

```bash
cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
```

You will see the ExecStart line with /usr/share/bin/kubelet. This is the error. The correct path should be /usr/bin/kubelet.

### Step 7: Fix the Configuration

Restore the backup we made before breaking the configuration.

```bash
cp /etc/systemd/system/kubelet.service.d/10-kubeadm.conf.backup /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
```

Alternatively, if you did not have a backup, you could edit the file directly using vi or sed to change /usr/share/bin/kubelet back to /usr/bin/kubelet.

```bash
sed -i 's|/usr/share/bin/kubelet|/usr/bin/kubelet|' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
```

After changing a systemd unit file, you must reload systemd to pick up the change.

```bash
systemctl daemon-reload
```

Now restart the kubelet service.

```bash
systemctl restart kubelet
```

Check the status again.

```bash
systemctl status kubelet
```

The service should now show active (running). If it is not active, recheck the ExecStart path and the journalctl logs for any other errors.

### Step 8: Verify Node Recovery

Exit the node container.

```bash
exit
```

Back on the host, check the node status.

```bash
kubectl get nodes
```

The kind-worker node should return to Ready status within a few seconds. The kubelet will re-register with the API server, update its heartbeat, and the node controller will mark it Ready.

Check the node conditions in detail.

```bash
kubectl describe node kind-worker | grep -A 10 "Conditions:"
```

All conditions should show healthy values: Ready=True, MemoryPressure=False, DiskPressure=False, PIDPressure=False, NetworkUnavailable=False (assuming your CNI is working).

### Step 9: Verify Pods Can Schedule on the Recovered Node

Create a test pod with a node selector to ensure it schedules on kind-worker.

```bash
kubectl run test-kubelet-recovery --image=nginx:1.27 --restart=Never \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"kind-worker"}}}' \
  -n tutorial-troubleshooting
```

Verify the pod is Running.

```bash
kubectl get pod test-kubelet-recovery -n tutorial-troubleshooting -o wide
```

Expected output shows the pod Running on kind-worker. This confirms the kubelet is fully functional and can manage pod lifecycles.

Delete the test pod.

```bash
kubectl delete pod test-kubelet-recovery -n tutorial-troubleshooting
```

## Common Kubelet Configuration Errors

The tutorial walkthrough covered a systemd unit ExecStart path error. The following sections describe other common kubelet configuration errors you will encounter in the exercises, the symptoms they produce, and how to diagnose them.

### Wrong Kubeconfig Path

The kubelet needs a kubeconfig file to authenticate to the API server. This path is specified with the `--kubeconfig` flag in the systemd ExecStart line. If the path is wrong or the file is missing, the kubelet will start (because the binary exists and executes) but will fail to connect to the API server. Symptoms include the node becoming NotReady with reason KubeletNotReady, and journalctl logs showing errors like "error loading kubeconfig: stat /wrong/path/kubelet.conf: no such file or directory" or "unable to load kubeconfig: couldn't read version of schema object" if the file is not valid YAML. The fix is to correct the `--kubeconfig` flag in the dropin file to point to the correct path (typically /etc/kubernetes/kubelet.conf in kubeadm clusters), reload systemd, and restart kubelet.

### CA Certificate Path Wrong

The kubelet's kubeconfig file contains an embedded CA certificate or a path to a CA certificate file used to verify the API server's TLS certificate. If the CA path is wrong or the file is missing, the kubelet cannot trust the API server and will refuse to connect. Symptoms include the kubelet service running but the node NotReady, and journalctl logs showing TLS errors like "x509: certificate signed by unknown authority" or "unable to verify the API server's certificate." The fix is to ensure the certificate-authority or certificate-authority-data field in the kubeconfig is correct, typically pointing to /etc/kubernetes/pki/ca.crt in kubeadm clusters.

### Container Runtime Endpoint Wrong

The kubelet configuration file (/var/lib/kubelet/config.yaml) specifies the container runtime endpoint under the `containerRuntimeEndpoint` field. For containerd, this is typically unix:///run/containerd/containerd.sock. If the path is wrong or the containerd service is not running, the kubelet cannot manage containers. Symptoms include the node becoming NotReady with condition NetworkUnavailable=True or Ready=False with reason RuntimeNotReady, and journalctl logs showing errors like "failed to connect to containerd: failed to dial endpoint unix:///wrong/path: context deadline exceeded" or "container runtime is not responding." The fix is to correct the containerRuntimeEndpoint in /var/lib/kubelet/config.yaml, verify containerd is running with `systemctl status containerd`, and restart kubelet.

### Kubelet Config File Syntax Error

If the kubelet config file (/var/lib/kubelet/config.yaml) has invalid YAML syntax (missing colon, wrong indentation, unquoted special characters), the kubelet will fail to parse it and refuse to start. Symptoms include the kubelet service failing immediately on start, systemctl status showing exit code 1, and journalctl logs showing errors like "failed to load kubelet config file: error unmarshaling JSON: invalid character" or "yaml: line X: mapping values are not allowed in this context." The fix is to correct the YAML syntax in the config file, validate it with `kubectl --dry-run=client -f /var/lib/kubelet/config.yaml` if kubectl is available, and restart kubelet.

### Static Pod Manifest Directory Wrong

The kubelet config file specifies the directory where it should watch for static pod manifests using the `staticPodPath` field (default /etc/kubernetes/manifests in kubeadm clusters). If this path is wrong or does not exist, static pods on that node will not start. For worker nodes, this typically does not cause NotReady because worker nodes do not usually run static pods (static pods are primarily used for control plane components on the control-plane node). However, if you have custom static pods on a worker node, they will not appear. Symptoms include static pod manifests in the directory but the pods not running, and journalctl logs showing warnings like "failed to read pod manifest from path: no such file or directory." The fix is to create the directory or correct the staticPodPath in the config file.

### Port Already in Use

The kubelet exposes several ports for different purposes. The read-only port (default 10255, deprecated), the main kubelet API port (default 10250), and the healthz port (default 10248). If another process is listening on one of these ports, the kubelet will fail to bind and refuse to start. Symptoms include systemctl status showing the kubelet service failed, and journalctl logs showing errors like "failed to start server: listen tcp :10250: bind: address already in use." The fix is to identify the conflicting process with `lsof -i :10250` or `ss -tlnp | grep 10250`, stop that process, and restart kubelet. Alternatively, if the conflicting port is expected, you can change the kubelet's port in the config file (though changing the main API port 10250 is rarely done in practice).

## Distinguishing Kubelet Issues from Runtime Issues

One of the trickier diagnosis scenarios is determining whether a node failure is a kubelet issue or a container runtime (containerd) issue. Both can cause the node to become NotReady, but the fix is different.

If the kubelet service is not running (systemctl status kubelet shows inactive or failed), the problem is with the kubelet itself: wrong binary path, config file parse error, missing kubeconfig, certificate error, or port conflict. The fix is to correct the kubelet configuration, reload systemd if needed, and restart the kubelet service.

If the kubelet service is running (systemctl status kubelet shows active) but the node is NotReady with reason RuntimeNotReady, the problem is likely with containerd. Check the containerd service status with `systemctl status containerd`. If containerd is stopped or failed, the kubelet cannot manage containers even though the kubelet itself is healthy. Check containerd logs with `journalctl -u containerd`. Common containerd issues include the service stopped unexpectedly, the containerd socket missing or wrong permissions, or a CNI plugin failure causing the runtime to report not ready. The fix is to restart containerd with `systemctl restart containerd`, verify the socket exists at /run/containerd/containerd.sock, and check CNI plugin logs if NetworkUnavailable is True.

You can also test containerd directly using crictl, which is the CLI for interacting with container runtimes via the CRI (Container Runtime Interface). If kubelet is having runtime issues, try running `crictl ps` to list containers. If crictl cannot connect to the runtime, you will see an error like "connect: no such file or directory" or "context deadline exceeded," confirming a runtime problem rather than a kubelet problem.

## Understanding Node Conditions in Detail

The Conditions section in kubectl describe node output is the single most important diagnostic signal for node health. Each condition has a status (True, False, Unknown), a reason (a short programmatic string), and a message (a human-readable explanation). The Ready condition is the primary indicator. Ready=True means the node is healthy. Ready=False means the kubelet is running but reports an unhealthy state (often due to runtime issues). Ready=Unknown means the node controller has not received a status update from the kubelet within the grace period, usually indicating the kubelet is stopped or the node is unreachable.

The other conditions provide additional context. MemoryPressure=True means available memory has dropped below the kubelet's eviction threshold. The kubelet will start evicting pods to free memory. Check the threshold in /var/lib/kubelet/config.yaml under evictionHard or evictionSoft, and check actual memory usage with `free -h` on the node. DiskPressure=True means available disk has dropped below the eviction threshold. Check disk usage with `df -h` and look for large directories or container image bloat (use `crictl images` to list images and `crictl rmi` to remove unused ones). PIDPressure=True means the number of processes has exceeded the eviction threshold, which is rare but can happen with runaway pods creating many processes. NetworkUnavailable=True is set by the CNI plugin and means the pod network is not ready; this is normal briefly after the CNI plugin is installed but should resolve within seconds. If it persists, check the CNI plugin logs (location depends on the CNI, but for Calico it is the calico-node DaemonSet logs).

## Recovery Verification Pattern

Every kubelet fix should follow the same verification pattern to confirm the issue is fully resolved. First, verify the kubelet service is active and running on the node using `systemctl status kubelet`. Second, verify the node appears as Ready in kubectl output. Third, verify the node conditions show healthy values (Ready=True, all pressure conditions False) using `kubectl describe node`. Fourth, verify that pods can schedule on the node by creating a test pod with a node selector targeting that specific node, confirming it reaches Running status, and deleting it afterward. This four-step pattern confirms the kubelet is running, the kubelet is communicating with the API server, the kubelet is reporting healthy conditions, and the kubelet can successfully manage pod lifecycles (which exercises the full runtime integration).

## Systemd Reload Requirement

A common mistake when fixing kubelet systemd unit files is forgetting to run `systemctl daemon-reload` after editing a unit file or dropin. Systemd caches unit configurations in memory. If you edit /etc/systemd/system/kubelet.service.d/10-kubeadm.conf and then immediately run `systemctl restart kubelet`, systemd will restart the kubelet using the old cached configuration, not the edited file. The fix is always to run `systemctl daemon-reload` before restarting the service when you have edited a unit file. The reload is instantaneous and has no effect on running services; it only updates systemd's in-memory cache of unit configurations.

## Cleanup

Delete the tutorial namespace.

```bash
kubectl delete namespace tutorial-troubleshooting
```

Verify all worker nodes are healthy before proceeding to the exercises.

```bash
kubectl get nodes
```

All nodes should show Ready.

## Reference Commands

The table below summarizes the most common commands for kubelet troubleshooting.

| Task | Command |
|------|---------|
| Check node status | `kubectl get nodes` |
| Describe node (conditions and events) | `kubectl describe node <node-name>` |
| Access a kind worker node | `nerdctl exec <node-name> bash` |
| Check kubelet service status | `systemctl status kubelet` |
| View kubelet logs (last 50 lines) | `journalctl -u kubelet -n 50 --no-pager` |
| View kubelet logs (tail live) | `journalctl -u kubelet -f` |
| Restart kubelet service | `systemctl restart kubelet` |
| Reload systemd after editing unit | `systemctl daemon-reload` |
| View kubelet config file | `cat /var/lib/kubelet/config.yaml` |
| View kubelet systemd dropin | `cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf` |
| Check containerd service status | `systemctl status containerd` |
| View containerd logs | `journalctl -u containerd -n 50 --no-pager` |
| Restart containerd | `systemctl restart containerd` |
| Test containerd with crictl | `crictl ps` |
| Check containerd socket exists | `ls -la /run/containerd/containerd.sock` |
| Check memory usage on node | `free -h` |
| Check disk usage on node | `df -h` |
| List container images on node | `crictl images` |
| Check process listening on port | `ss -tlnp \| grep <port>` |
| Create test pod on specific node | `kubectl run <name> --image=<image> --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"<node>"}}}' -n <namespace>` |
| Drain a node for maintenance | `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data` |
| Allow scheduling on drained node | `kubectl uncordon <node>` |
