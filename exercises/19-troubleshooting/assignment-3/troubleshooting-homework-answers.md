# Node and Kubelet Troubleshooting Homework Answers

Complete solutions for all 15 exercises. Every debugging exercise follows the three-stage structure: Diagnosis (commands to run and what to look for), Explanation (what is broken and why), and Fix (corrected configuration and verification).

---

## Exercise 1.1 Solution

### Diagnosis

Check node status from the cluster perspective.

```bash
kubectl get nodes
```

Output shows kind-worker with status NotReady. Check the node conditions and events.

```bash
kubectl describe node kind-worker
```

Look for the Conditions section. You will see Ready=Unknown or Ready=False with reason KubeletNotReady and a message like "kubelet stopped posting node status." This indicates the kubelet is not running.

Access the kind-worker node to inspect the kubelet service.

```bash
nerdctl exec kind-worker bash
```

Check the kubelet service status.

```bash
systemctl status kubelet
```

Output shows the service is inactive (dead). The service was explicitly stopped, so there are no error messages, just that it is not running.

### Explanation

The kubelet service was stopped using `systemctl stop kubelet`. When the kubelet is not running, it cannot send heartbeats to the API server, so the node controller marks the node as NotReady after the node-monitor-grace-period (default 40 seconds). The kubelet is the only component responsible for reporting node status, so when it stops, the node immediately becomes unhealthy from the cluster perspective.

### Fix

Start the kubelet service.

```bash
systemctl start kubelet
```

Verify the service is now running.

```bash
systemctl status kubelet
```

Output should show active (running). Exit the node.

```bash
exit
```

Verify the node returns to Ready status.

```bash
kubectl get nodes
```

The kind-worker node should show Ready within a few seconds as the kubelet re-registers with the API server.

---

## Exercise 1.2 Solution

### Diagnosis

Check node status.

```bash
kubectl get nodes
```

Output shows kind-worker2 with status NotReady. Describe the node to see conditions.

```bash
kubectl describe node kind-worker2
```

The Ready condition is False or Unknown with reason KubeletNotReady. Access the node.

```bash
nerdctl exec kind-worker2 bash
```

Check kubelet service status.

```bash
systemctl status kubelet
```

Output shows the service is failed with exit code 203/EXEC. This specific exit code indicates systemd tried to execute the binary specified in the ExecStart line but could not find the file. The error message will include "Failed at step EXEC spawning /usr/local/bin/kubelet: No such file or directory."

Check the systemd dropin file to see the ExecStart line.

```bash
cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf | grep ExecStart
```

Output shows ExecStart=/usr/local/bin/kubelet with additional flags. The correct path should be /usr/bin/kubelet.

### Explanation

The systemd unit is configured to execute /usr/local/bin/kubelet, but the kubelet binary is actually located at /usr/bin/kubelet. When systemd tries to start the service, it cannot find the binary at the configured path and fails with exit code 203/EXEC. This is the exact scenario from Killer.sh Simulator B Question 6. The wrong path could have been introduced by a manual edit error, an incorrect automation script, or a copy-paste mistake from another system where kubelet is installed in a non-standard location.

### Fix

Restore the correct systemd dropin from the backup created during setup.

```bash
cp /etc/systemd/system/kubelet.service.d/10-kubeadm.conf.bak /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
```

Alternatively, fix the path using sed.

```bash
sed -i 's|/usr/local/bin/kubelet|/usr/bin/kubelet|' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
```

After editing a systemd unit file, reload systemd.

```bash
systemctl daemon-reload
```

Restart the kubelet.

```bash
systemctl restart kubelet
```

Verify the service is running.

```bash
systemctl status kubelet
```

Exit the node.

```bash
exit
```

Verify the node is Ready.

```bash
kubectl get nodes
```

---

## Exercise 1.3 Solution

### Diagnosis

Check node status.

```bash
kubectl get nodes
```

Output shows kind-worker3 with status NotReady. Describe the node.

```bash
kubectl describe node kind-worker3
```

The Ready condition shows KubeletNotReady. Access the node.

```bash
nerdctl exec kind-worker3 bash
```

Check kubelet status.

```bash
systemctl status kubelet
```

Output shows the service is failed. Check the kubelet logs.

```bash
journalctl -u kubelet -n 50 --no-pager
```

Look for errors related to the config file. You will see messages like "failed to load kubelet config file: open /var/lib/kubelet/config.yaml: no such file or directory" or similar errors indicating the config file cannot be read.

Verify the config file is missing.

```bash
ls -la /var/lib/kubelet/config.yaml
```

Output shows "No such file or directory." The backup file exists.

```bash
ls -la /var/lib/kubelet/config.yaml.backup
```

### Explanation

The kubelet configuration file (/var/lib/kubelet/config.yaml) was moved to a backup location, and the kubelet cannot start without this file. The config file path is specified with the `--config` flag in the systemd unit. The kubelet reads this file to get settings like cluster DNS, cluster domain, authentication and authorization configuration, eviction thresholds, and the container runtime endpoint. Without the config file, the kubelet cannot determine how to operate and refuses to start.

### Fix

Restore the config file from the backup.

```bash
mv /var/lib/kubelet/config.yaml.backup /var/lib/kubelet/config.yaml
```

Restart the kubelet.

```bash
systemctl restart kubelet
```

Verify the service is running.

```bash
systemctl status kubelet
```

Exit the node.

```bash
exit
```

Verify the node is Ready.

```bash
kubectl get nodes
```

---

## Exercise 2.1 Solution

### Diagnosis

Check node status.

```bash
kubectl get nodes
```

Output shows kind-worker with status NotReady. Describe the node.

```bash
kubectl describe node kind-worker
```

Access the node.

```bash
nerdctl exec kind-worker bash
```

Check kubelet status.

```bash
systemctl status kubelet
```

Output shows the service is failed. Check the logs.

```bash
journalctl -u kubelet -n 50 --no-pager
```

Look for YAML parsing errors. You will see messages like "failed to load kubelet config file: error unmarshaling JSON: yaml: line 5: mapping values are not allowed in this context" or similar errors indicating the YAML syntax is invalid.

Inspect the config file.

```bash
cat /var/lib/kubelet/config.yaml | head -10
```

Look at line 5 (or the line number from the error message). You will see a line missing the colon after the key, making it invalid YAML. For example, `authentication` instead of `authentication:`.

### Explanation

The kubelet config file has a YAML syntax error where a colon was removed from a key-value pair. YAML requires `key: value` format with the colon. When the colon is missing, the YAML parser cannot interpret the file structure and the kubelet fails to load the config. The error message usually identifies the specific line number, making it straightforward to locate the problem once you know to look for a syntax error.

### Fix

Restore the good config file from the backup.

```bash
cp /var/lib/kubelet/config.yaml.good /var/lib/kubelet/config.yaml
```

Alternatively, manually add the missing colon back to line 5 using vi or sed. Restart the kubelet.

```bash
systemctl restart kubelet
```

Verify the service is running.

```bash
systemctl status kubelet
```

Exit the node.

```bash
exit
```

Verify the node is Ready.

```bash
kubectl get nodes
```

---

## Exercise 2.2 Solution

### Diagnosis

Check node status.

```bash
kubectl get nodes
```

Output shows kind-worker2 with status NotReady. Describe the node.

```bash
kubectl describe node kind-worker2
```

Access the node.

```bash
nerdctl exec kind-worker2 bash
```

Check kubelet status.

```bash
systemctl status kubelet
```

Output may show the service is running or failed depending on timing. Check the logs.

```bash
journalctl -u kubelet -n 50 --no-pager
```

Look for errors related to loading the kubeconfig. You will see messages like "error loading kubeconfig: stat /etc/kubernetes/kubelet-wrong.conf: no such file or directory" or "unable to load kubeconfig."

Check the systemd dropin to see the kubeconfig flag.

```bash
cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf | grep kubeconfig
```

Output shows `--kubeconfig=/etc/kubernetes/kubelet-wrong.conf`. The correct path should be `/etc/kubernetes/kubelet.conf`.

### Explanation

The `--kubeconfig` flag in the systemd unit points to a file that does not exist. The kubeconfig file contains the client certificate, client key, and CA certificate the kubelet uses to authenticate to the API server. Without a valid kubeconfig, the kubelet cannot communicate with the API server, cannot register the node, and cannot report status. The node becomes NotReady because the kubelet is either not running or running but unable to connect to the control plane.

### Fix

Restore the correct systemd dropin from the backup (if you made one before the setup, which is not shown in this exercise, so use sed).

```bash
sed -i 's|--kubeconfig=/etc/kubernetes/kubelet-wrong.conf|--kubeconfig=/etc/kubernetes/kubelet.conf|' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
```

Reload systemd.

```bash
systemctl daemon-reload
```

Restart the kubelet.

```bash
systemctl restart kubelet
```

Verify the service is running.

```bash
systemctl status kubelet
```

Exit the node.

```bash
exit
```

Verify the node is Ready.

```bash
kubectl get nodes
```

---

## Exercise 2.3 Solution

### Diagnosis

Check node status.

```bash
kubectl get nodes
```

Output shows kind-worker3 with status NotReady. Describe the node.

```bash
kubectl describe node kind-worker3
```

You may see Ready=False with reason RuntimeNotReady or KubeletNotReady depending on how the kubelet reports the runtime connectivity failure. Access the node.

```bash
nerdctl exec kind-worker3 bash
```

Check kubelet status.

```bash
systemctl status kubelet
```

The service may be running but not healthy. Check the logs.

```bash
journalctl -u kubelet -n 50 --no-pager
```

Look for errors about connecting to the container runtime. You will see messages like "failed to connect to containerd: failed to dial endpoint unix:///run/containerd/wrong.sock: context deadline exceeded" or "container runtime is not responding."

Check the kubelet config file for the container runtime endpoint.

```bash
grep containerRuntimeEndpoint /var/lib/kubelet/config.yaml
```

Output shows `containerRuntimeEndpoint: unix:///run/containerd/wrong.sock`. The correct path should be `unix:///run/containerd/containerd.sock`.

### Explanation

The kubelet is configured to communicate with the container runtime (containerd) over a Unix socket. The socket path is wrong, pointing to /run/containerd/wrong.sock which does not exist. When the kubelet tries to connect to this socket, the connection times out. Without a working connection to the container runtime, the kubelet cannot start or stop containers, cannot run pods, and reports the runtime as not ready. The node becomes NotReady with the condition RuntimeNotReady.

### Fix

Restore the correct config file from the backup.

```bash
cp /var/lib/kubelet/config.yaml.orig /var/lib/kubelet/config.yaml
```

Alternatively, fix the socket path using sed.

```bash
sed -i 's|unix:///run/containerd/wrong.sock|unix:///run/containerd/containerd.sock|' /var/lib/kubelet/config.yaml
```

Restart the kubelet.

```bash
systemctl restart kubelet
```

Verify the service is running and can connect to the runtime.

```bash
systemctl status kubelet
```

Test the runtime directly with crictl.

```bash
crictl ps
```

Output should show running containers (or an empty list if no pods are scheduled yet), not a connection error. Exit the node.

```bash
exit
```

Verify the node is Ready.

```bash
kubectl get nodes
```

---

## Exercise 3.1 Solution

### Diagnosis

Check node status.

```bash
kubectl get nodes
```

Output shows kind-worker with status NotReady. Describe the node.

```bash
kubectl describe node kind-worker
```

Access the node.

```bash
nerdctl exec kind-worker bash
```

Check kubelet status.

```bash
systemctl status kubelet
```

The service may be running but failing to authenticate. Check the logs.

```bash
journalctl -u kubelet -n 50 --no-pager
```

Look for authentication errors. You will see messages like "failed to create kubelet client: unable to load client cert" or errors indicating the client certificate is missing or cannot be read.

Inspect the kubeconfig file.

```bash
cat /etc/kubernetes/kubelet.conf
```

Look for the `client-certificate-data` field under the `user` section. You will notice it is missing. The field should contain a base64-encoded client certificate.

### Explanation

The kubelet kubeconfig file is missing the `client-certificate-data` field, which provides the client certificate the kubelet uses to authenticate to the API server. Without this certificate, the kubelet cannot prove its identity to the API server. The API server rejects the kubelet's connection attempts, and the kubelet cannot register the node or report status. The node becomes NotReady.

### Fix

Restore the correct kubeconfig from the backup.

```bash
cp /etc/kubernetes/kubelet.conf.backup /etc/kubernetes/kubelet.conf
```

Restart the kubelet.

```bash
systemctl restart kubelet
```

Verify the service is running.

```bash
systemctl status kubelet
```

Exit the node.

```bash
exit
```

Verify the node is Ready.

```bash
kubectl get nodes
```

---

## Exercise 3.2 Solution

### Diagnosis

Check node status.

```bash
kubectl get nodes
```

Output shows kind-worker2 with status NotReady. Describe the node.

```bash
kubectl describe node kind-worker2
```

Access the node.

```bash
nerdctl exec kind-worker2 bash
```

Check kubelet status.

```bash
systemctl status kubelet
```

The service may be running. Check the logs.

```bash
journalctl -u kubelet -n 50 --no-pager
```

Look for errors about loading the kubeconfig or unmarshaling the YAML. You will see messages like "error loading kubeconfig: error unmarshaling kubeconfig: yaml: unmarshal errors" or "unknown field certificate-authority-data-wrong."

Inspect the kubeconfig file.

```bash
cat /etc/kubernetes/kubelet.conf
```

Look for the field that should be `certificate-authority-data` under the `cluster` section. You will see `certificate-authority-data-wrong` instead, which is not a recognized field name.

### Explanation

The field name `certificate-authority-data` was corrupted to `certificate-authority-data-wrong`. This is not a valid field in the kubeconfig schema. When the kubelet tries to parse the kubeconfig, it fails because the YAML contains an unrecognized field. The kubelet cannot load the kubeconfig and cannot authenticate to the API server. The node becomes NotReady.

### Fix

Restore the correct kubeconfig from the backup.

```bash
cp /etc/kubernetes/kubelet.conf.save /etc/kubernetes/kubelet.conf
```

Alternatively, fix the field name using sed.

```bash
sed -i 's|certificate-authority-data-wrong:|certificate-authority-data:|' /etc/kubernetes/kubelet.conf
```

Restart the kubelet.

```bash
systemctl restart kubelet
```

Verify the service is running.

```bash
systemctl status kubelet
```

Exit the node.

```bash
exit
```

Verify the node is Ready.

```bash
kubectl get nodes
```

---

## Exercise 3.3 Solution

### Diagnosis

Check node status.

```bash
kubectl get nodes
```

Output shows kind-worker3 with status NotReady. Describe the node.

```bash
kubectl describe node kind-worker3
```

You may see Ready=False with reason RuntimeNotReady or a message about the container runtime not being available. Access the node.

```bash
nerdctl exec kind-worker3 bash
```

Check kubelet status.

```bash
systemctl status kubelet
```

The kubelet service is running. This is important: the kubelet itself is not the problem. Check the kubelet logs.

```bash
journalctl -u kubelet -n 50 --no-pager
```

Look for errors about connecting to the container runtime. You will see messages like "container runtime is not responding" or "failed to connect to containerd."

Check the containerd service status.

```bash
systemctl status containerd
```

Output shows the service is inactive (dead). This is the root cause.

### Explanation

The containerd service was stopped. The kubelet service is running and healthy, but it cannot perform its job because it cannot communicate with the container runtime. Containerd is responsible for actually managing container lifecycles (pull images, start containers, stop containers). When containerd is stopped, the kubelet has no runtime to delegate work to. The kubelet reports the runtime as not ready, and the node becomes NotReady with condition RuntimeNotReady. This is an example of distinguishing kubelet issues from runtime issues: the kubelet is running, but the runtime is the problem.

### Fix

Start the containerd service.

```bash
systemctl start containerd
```

Verify containerd is running.

```bash
systemctl status containerd
```

The kubelet should automatically detect that the runtime is now available and update the node status. You do not need to restart the kubelet in this case, but restarting it will not hurt and may speed up the recovery.

```bash
systemctl restart kubelet
```

Verify both services are running.

```bash
systemctl status kubelet
systemctl status containerd
```

Exit the node.

```bash
exit
```

Verify the node is Ready.

```bash
kubectl get nodes
```

---

## Exercise 4.1 Solution

### Diagnosis

Check node status.

```bash
kubectl get nodes
```

Output shows kind-worker with status NotReady. Describe the node.

```bash
kubectl describe node kind-worker
```

Access the node.

```bash
nerdctl exec kind-worker bash
```

Check kubelet status.

```bash
systemctl status kubelet
```

Output shows the service is failed. Check the logs.

```bash
journalctl -u kubelet -n 50 --no-pager
```

Look for errors. You will see messages like "failed to load kubelet config file: open /var/lib/kubelet/config-wrong.yaml: no such file or directory." This tells you the config file path is wrong.

Check the systemd dropin to see the config flag.

```bash
cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf | grep config
```

Output shows `--config=/var/lib/kubelet/config-wrong.yaml`. This is the first issue. Even if you fix this, you need to check if the config file itself has issues.

Check the actual config file (the one that exists, even though it is not being used currently).

```bash
cat /var/lib/kubelet/config.yaml | grep -i dns
```

You will see `clusterDNSWrong:` instead of `clusterDNS:`. This is the second issue.

### Explanation

There are two separate issues. First, the systemd unit points to a config file that does not exist (/var/lib/kubelet/config-wrong.yaml instead of /var/lib/kubelet/config.yaml). Second, the actual config file has a field name corruption (`clusterDNSWrong` instead of `clusterDNS`). You must fix the systemd unit first so the kubelet can find the config file, then fix the config file itself so the kubelet can parse it correctly.

### Fix

Fix the systemd unit to point to the correct config file.

```bash
sed -i 's|--config=/var/lib/kubelet/config-wrong.yaml|--config=/var/lib/kubelet/config.yaml|' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
```

Reload systemd.

```bash
systemctl daemon-reload
```

Now fix the config file field name.

```bash
sed -i 's|clusterDNSWrong:|clusterDNS:|' /var/lib/kubelet/config.yaml
```

Restart the kubelet.

```bash
systemctl restart kubelet
```

Verify the service is running.

```bash
systemctl status kubelet
```

Exit the node.

```bash
exit
```

Verify the node is Ready.

```bash
kubectl get nodes
```

---

## Exercise 4.2 Solution

### Diagnosis

Check node status.

```bash
kubectl get nodes
```

Output shows kind-worker2 with status NotReady. Describe the node.

```bash
kubectl describe node kind-worker2
```

Access the node.

```bash
nerdctl exec kind-worker2 bash
```

Check kubelet status.

```bash
systemctl status kubelet
```

Output shows the service is failed. Check the logs.

```bash
journalctl -u kubelet -n 50 --no-pager
```

Look for errors about the config file. You will see "failed to load kubelet config file: open /var/lib/kubelet/missing.yaml: no such file or directory." This is the first issue.

Check the systemd dropin.

```bash
cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf | grep config
```

Output shows `--config=/var/lib/kubelet/missing.yaml`. Fix this first, then check for other issues.

After fixing the config path (or suspecting there may be more issues), check the containerd socket permissions.

```bash
ls -la /run/containerd/containerd.sock
```

Output shows permissions `----------` (chmod 000), meaning no one can access the socket. This is the second issue.

### Explanation

There are two issues. First, the kubelet systemd unit points to a config file that does not exist. Second, the containerd socket has been set to chmod 000, removing all permissions. Even if the kubelet starts, it will not be able to communicate with containerd because it cannot access the socket. You must fix both the config path and restore the socket permissions.

### Fix

Fix the systemd unit config path.

```bash
sed -i 's|--config=/var/lib/kubelet/missing.yaml|--config=/var/lib/kubelet/config.yaml|' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
```

Reload systemd.

```bash
systemctl daemon-reload
```

Fix the containerd socket permissions.

```bash
chmod 660 /run/containerd/containerd.sock
```

Restart the kubelet.

```bash
systemctl restart kubelet
```

Verify the service is running.

```bash
systemctl status kubelet
```

Verify the socket permissions are correct.

```bash
ls -la /run/containerd/containerd.sock
```

Exit the node.

```bash
exit
```

Verify the node is Ready.

```bash
kubectl get nodes
```

---

## Exercise 4.3 Solution

### Diagnosis

Check node status.

```bash
kubectl get nodes
```

Output shows kind-worker3 with status NotReady. Describe the node.

```bash
kubectl describe node kind-worker3
```

Access the node.

```bash
nerdctl exec kind-worker3 bash
```

Check kubelet status.

```bash
systemctl status kubelet
```

Output shows the service is failed. Check the logs.

```bash
journalctl -u kubelet -n 50 --no-pager
```

Look for YAML parsing errors. You will see messages like "failed to load kubelet config file: error unmarshaling JSON: yaml: line 3: mapping values are not allowed in this context" or similar. This indicates a syntax error on line 3.

Inspect the config file around line 3.

```bash
cat /var/lib/kubelet/config.yaml | head -10
```

You will see line 3 has an extra space before the colon, making it invalid YAML (for example, `key :` instead of `key:`). This is the first issue.

After fixing the syntax error (or checking for more issues), look for the containerRuntimeEndpoint field.

```bash
grep -i runtime /var/lib/kubelet/config.yaml
```

You will see `containerRuntimeEndpointBroken:` instead of `containerRuntimeEndpoint:`. This is the second issue.

### Explanation

There are two issues in the kubelet config file. First, a YAML syntax error on line 3 where an extra space was inserted before the colon, breaking the key-value pair format. Second, the field name `containerRuntimeEndpoint` was corrupted to `containerRuntimeEndpointBroken`, which is not a recognized field. Both issues prevent the kubelet from parsing the config file.

### Fix

Restore the original config file from the backup (if available, which the setup did not create, so fix manually).

Fix the syntax error on line 3. Use vi or sed to remove the extra space before the colon.

```bash
sed -i '3s/ :/:/' /var/lib/kubelet/config.yaml
```

Fix the field name.

```bash
sed -i 's|containerRuntimeEndpointBroken:|containerRuntimeEndpoint:|' /var/lib/kubelet/config.yaml
```

Restart the kubelet.

```bash
systemctl restart kubelet
```

Verify the service is running.

```bash
systemctl status kubelet
```

Exit the node.

```bash
exit
```

Verify the node is Ready.

```bash
kubectl get nodes
```

---

## Exercise 5.1 Solution

### Diagnosis

Check node status.

```bash
kubectl get nodes
```

Output shows kind-worker with status NotReady. Describe the node.

```bash
kubectl describe node kind-worker
```

Access the node.

```bash
nerdctl exec kind-worker bash
```

Check kubelet status.

```bash
systemctl status kubelet
```

Output shows the service is failed with exit code 203/EXEC. This indicates the binary path is wrong. Check the logs.

```bash
journalctl -u kubelet -n 50 --no-pager
```

Look for "Failed at step EXEC spawning /bin/kubelet: No such file or directory." This confirms the binary path is wrong.

Check the systemd dropin.

```bash
cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf | grep ExecStart
```

You will see the ExecStart line has `/bin/kubelet` instead of `/usr/bin/kubelet`. This is the first issue.

Also check the kubeconfig flag in the same ExecStart line. You will see `--kubeconfig=/etc/kubernetes/missing.conf`. This is the second issue.

Check the kubelet config file for any issues.

```bash
cat /var/lib/kubelet/config.yaml | head -5
```

You will see `apiVersionWrong:` instead of `apiVersion:`. This is the third issue.

### Explanation

There are three distinct issues. First, the kubelet binary path in the systemd ExecStart is /bin/kubelet instead of /usr/bin/kubelet, so systemd cannot find the binary. Second, the kubeconfig path is /etc/kubernetes/missing.conf instead of /etc/kubernetes/kubelet.conf, so even if the kubelet starts it cannot authenticate. Third, the config file has `apiVersionWrong` instead of `apiVersion`, making it invalid YAML. You must fix all three issues for the kubelet to start and function correctly.

### Fix

Fix the binary path and kubeconfig path in the systemd dropin.

```bash
sed -i 's|/bin/kubelet|/usr/bin/kubelet|' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sed -i 's|--kubeconfig=/etc/kubernetes/missing.conf|--kubeconfig=/etc/kubernetes/kubelet.conf|' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
```

Reload systemd.

```bash
systemctl daemon-reload
```

Fix the config file field name.

```bash
sed -i 's|apiVersionWrong:|apiVersion:|' /var/lib/kubelet/config.yaml
```

Restart the kubelet.

```bash
systemctl restart kubelet
```

Verify the service is running.

```bash
systemctl status kubelet
```

Exit the node.

```bash
exit
```

Verify the node is Ready.

```bash
kubectl get nodes
```

---

## Exercise 5.2 Solution

### Diagnosis

Check node status.

```bash
kubectl get nodes
```

Output shows kind-worker2 with status NotReady. Describe the node.

```bash
kubectl describe node kind-worker2
```

Access the node.

```bash
nerdctl exec kind-worker2 bash
```

Check kubelet status.

```bash
systemctl status kubelet
```

Output shows the service is inactive (dead). The kubelet was stopped. Check the systemd dropin for config issues before restarting.

```bash
cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf | grep bootstrap
```

You will see `--bootstrap-kubeconfig=/etc/kubernetes/missing-bootstrap.conf`. This is a configuration issue that will prevent the kubelet from starting correctly even if you start the service.

Check the containerd service status.

```bash
systemctl status containerd
```

Output shows containerd is also inactive (dead). This is the second issue.

### Explanation

There are two issues. First, both the kubelet and containerd services were stopped. Second, the systemd unit has a wrong path for the bootstrap-kubeconfig flag (though this flag is only used during initial node joining and may not cause immediate failure on an already-joined node, it should still be fixed). The kubelet cannot manage pods when it is not running, and even if the kubelet were running, it could not manage containers because containerd is not running. You must fix the config and start both services.

### Fix

Fix the bootstrap-kubeconfig path in the systemd dropin.

```bash
sed -i 's|--bootstrap-kubeconfig=/etc/kubernetes/missing-bootstrap.conf|--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf|' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
```

Reload systemd.

```bash
systemctl daemon-reload
```

Start containerd first (the kubelet depends on the runtime being available).

```bash
systemctl start containerd
```

Verify containerd is running.

```bash
systemctl status containerd
```

Now start the kubelet.

```bash
systemctl start kubelet
```

Verify the kubelet is running.

```bash
systemctl status kubelet
```

Exit the node.

```bash
exit
```

Verify the node is Ready.

```bash
kubectl get nodes
```

---

## Exercise 5.3 Solution

### Diagnosis

Check node status.

```bash
kubectl get nodes
```

Output shows kind-worker3 with status NotReady. Describe the node.

```bash
kubectl describe node kind-worker3
```

Access the node.

```bash
nerdctl exec kind-worker3 bash
```

Check kubelet status.

```bash
systemctl status kubelet
```

Output shows the service is failed. Check the logs.

```bash
journalctl -u kubelet -n 50 --no-pager
```

Look for systemd errors. You may see messages like "kubelet.service lacks both ExecStart= and ExecStart= settings" or "Service has no ExecStart=, refusing." This indicates the systemd unit is broken.

Inspect the systemd dropin.

```bash
cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf | grep Exec
```

You will see `ExecStartWrong=` instead of `ExecStart=`. This is the first issue.

After fixing the systemd issue (or checking for more issues), inspect the kubelet config file.

```bash
cat /var/lib/kubelet/config.yaml | grep kind
```

You will see `kind: KubeletConfigurationBroken` instead of `kind: KubeletConfiguration`. This is the second issue.

Check the kubeconfig file.

```bash
cat /etc/kubernetes/kubelet.conf | grep client-key
```

You will notice the `client-key-data` field is missing. This is the third issue.

### Explanation

There are three issues across three different configuration files. First, the systemd dropin has `ExecStartWrong=` instead of `ExecStart=`, making it an invalid systemd unit (systemd does not recognize `ExecStartWrong` as a valid directive). Second, the kubelet config file has `kind: KubeletConfigurationBroken` instead of `kind: KubeletConfiguration`, which causes the kubelet to reject the config file as not being a valid KubeletConfiguration object. Third, the kubeconfig file is missing the `client-key-data` field, which provides the private key corresponding to the client certificate; without this, the kubelet cannot authenticate to the API server. You must fix all three issues.

### Fix

Fix the systemd dropin.

```bash
sed -i 's|ExecStartWrong=|ExecStart=|' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
```

Reload systemd.

```bash
systemctl daemon-reload
```

Fix the kubelet config file.

```bash
sed -i 's|kind: KubeletConfigurationBroken|kind: KubeletConfiguration|' /var/lib/kubelet/config.yaml
```

Restore the kubeconfig file from a backup (the setup did not create one, so in a real scenario you would restore from etcd backup or recreate the kubeconfig). For this exercise, assume a backup exists or the original was saved elsewhere.

```bash
# If backup exists:
# cp /etc/kubernetes/kubelet.conf.backup /etc/kubernetes/kubelet.conf

# If no backup, you would need to regenerate the kubeconfig, which is beyond this exercise.
# For the exercise, assume you restore it from the implicit backup created during setup.
```

If the kubeconfig cannot be restored from backup, you would need to use `kubeadm kubeconfig user --client-name=system:node:kind-worker3 --org=system:nodes` to regenerate it, but this is typically done from the control-plane node and is an advanced recovery step.

For this exercise, assume the restore works. Restart the kubelet.

```bash
systemctl restart kubelet
```

Verify the service is running.

```bash
systemctl status kubelet
```

Exit the node.

```bash
exit
```

Verify the node is Ready.

```bash
kubectl get nodes
```

---

## Common Mistakes

### Not Reloading Systemd After Editing Unit Files

When you edit a systemd unit file or dropin (such as /etc/systemd/system/kubelet.service.d/10-kubeadm.conf), systemd does not automatically reload the configuration. If you run `systemctl restart kubelet` without first running `systemctl daemon-reload`, systemd will restart the service using the old cached configuration, and your fix will not take effect. Always run `systemctl daemon-reload` after editing a systemd unit file, then restart the service. This is one of the most common mistakes in kubelet troubleshooting and is frequently tested in the exam.

### Not Restarting the Kubelet After Fixing the Config File

When you fix an error in the kubelet config file (/var/lib/kubelet/config.yaml) or the kubeconfig file (/etc/kubernetes/kubelet.conf), the kubelet does not automatically reload the file. The kubelet reads these files only at startup. If you fix the config file but do not restart the kubelet, the service will continue running with the old configuration in memory (if it was running) or will remain failed (if it could not start). Always restart the kubelet with `systemctl restart kubelet` after fixing a config file.

### Checking the Wrong Node

In a multi-node cluster, it is easy to access the wrong node when troubleshooting. Always verify which node is NotReady from the kubectl output before using `nerdctl exec` to access a node. If you access kind-worker but the problem is on kind-worker2, you will waste time inspecting a healthy kubelet. Double-check the node name in the kubectl output and the `nerdctl exec` command.

### Confusing Kubelet Issues with Runtime Issues

If the kubelet service status shows active (running) but the node is NotReady, the problem is likely with the container runtime (containerd), not the kubelet itself. Check `systemctl status containerd` and the containerd logs with `journalctl -u containerd`. A common mistake is spending time looking for kubelet config errors when the kubelet is actually healthy and the runtime is the problem. Similarly, if the kubelet service is failed or inactive, the problem is with the kubelet, not the runtime. Distinguish between these two scenarios by checking the kubelet service status first.

### Fixing Only One of Multiple Issues

When there are multiple issues (as in the Level 4 and Level 5 exercises), fixing only one issue may not bring the node back to Ready. For example, if the systemd unit has the wrong config file path and the config file itself has a syntax error, you must fix both the path and the syntax. After fixing the first issue, the kubelet may fail for a different reason. Always check the logs again after each fix to see if there are additional errors. Do not assume the node is fixed after correcting the first issue you find.

### Not Verifying the Fix with a Test Pod

After bringing a node back to Ready status, always verify that the kubelet can actually manage pods by creating a test pod with a node selector targeting that specific node. A node can appear Ready in kubectl output but still have subtle issues that prevent pods from starting (for example, the runtime is partially working but cannot pull images, or the CNI is misconfigured). Creating a test pod and confirming it reaches Running status is the final verification step that confirms the node is fully functional.

### Forgetting to Check Events in kubectl describe node

The Events section at the bottom of `kubectl describe node` output often contains critical clues about what is failing. Events like "NodeNotReady" with messages about the kubelet stopping, runtime issues, or certificate problems can save you time by pointing you directly to the problem area. Many candidates jump straight to accessing the node without reading the events, missing valuable diagnostic information that would speed up the troubleshooting process.

## Verification Commands Cheat Sheet

| Task | Command | Expected Output |
|------|---------|-----------------|
| Check all node status | `kubectl get nodes` | All nodes show Ready |
| Describe node conditions | `kubectl describe node <node-name>` | Ready=True, all pressure conditions False |
| Check node events | `kubectl describe node <node-name> \| grep -A 20 Events` | No error events |
| Access kind worker node | `nerdctl exec <node-name> bash` | Shell prompt inside node |
| Check kubelet service status | `systemctl status kubelet` | active (running) |
| View kubelet logs (last 50 lines) | `journalctl -u kubelet -n 50 --no-pager` | No errors after fix |
| View kubelet logs (live tail) | `journalctl -u kubelet -f` | Live stream of logs |
| Restart kubelet | `systemctl restart kubelet` | No output (success) |
| Reload systemd after editing unit | `systemctl daemon-reload` | No output (success) |
| Check containerd service status | `systemctl status containerd` | active (running) |
| View containerd logs | `journalctl -u containerd -n 50 --no-pager` | No errors |
| Restart containerd | `systemctl restart containerd` | No output (success) |
| Test containerd with crictl | `crictl ps` | List of containers (or empty if no pods) |
| Check containerd socket | `ls -la /run/containerd/containerd.sock` | srw-rw---- (socket file exists) |
| View kubelet config file | `cat /var/lib/kubelet/config.yaml` | Valid YAML |
| View systemd dropin | `cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf` | Valid ExecStart line |
| Create test pod on specific node | `kubectl run test --image=nginx:1.27 --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"<node>"}}}' -n default` | Pod created |
| Check test pod is Running | `kubectl get pod test -o jsonpath='{.status.phase}'` | Running |
| Check test pod is on target node | `kubectl get pod test -o jsonpath='{.spec.nodeName}'` | Expected node name |
| Delete test pod | `kubectl delete pod test` | pod "test" deleted |
