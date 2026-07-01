# Troubleshooting Runbook: QEMU Virtual Machine

This runbook covers diagnostic and repair procedures for the QEMU/KVM virtual machine layer: VM startup failures, networking and port forwarding, cloud-init, disk issues, and host-side prerequisites.

---

## General Diagnostic Workflow

### Step 1: Is the VM Running?

```bash
# Check for the PID file
cat ~/cka-lab/controlplane-1/controlplane-1.pid 2>/dev/null

# Verify the process is alive
ps -p $(cat ~/cka-lab/controlplane-1/controlplane-1.pid 2>/dev/null) 2>/dev/null

# Or search for the QEMU process directly
ps aux | grep qemu-system-x86_64 | grep -v grep
```

If no QEMU process is running, the VM either was not started or crashed during boot.

### Step 2: Check the Console Log

```bash
tail -100 ~/cka-lab/controlplane-1/controlplane-1-console.log
```

This captures everything the VM writes to its serial console: kernel boot messages, cloud-init output, and the login prompt. If the file is empty or missing, the VM never got far enough to produce output.

### Step 3: Can You SSH In?

```bash
ssh -p 2222 kube@127.0.0.1 -o ConnectTimeout=5
```

If SSH times out, either the VM is not running, networking is not configured, or the SSH service inside the VM has not started yet.

---

## Host Prerequisites

Problems at this layer prevent any VM from starting at all.

### KVM Not Available

```bash
ls -la /dev/kvm
```

If `/dev/kvm` does not exist:

```bash
# Check CPU virtualization support
grep -Eoc '(vmx|svm)' /proc/cpuinfo
# If 0: virtualization is disabled in BIOS/UEFI. Reboot and enable it.

# Check if KVM modules are loaded
lsmod | grep kvm
# If empty:
sudo modprobe kvm
sudo modprobe kvm_intel  # or kvm_amd for AMD CPUs
```

### Permission Denied on /dev/kvm

```bash
groups $USER | grep -E 'kvm|libvirt'
```

If your user is not in the `kvm` group:

```bash
sudo usermod -aG kvm $USER
# Log out and back in, or:
newgrp kvm
```

### QEMU Binary Missing or Broken

```bash
which qemu-system-x86_64
qemu-system-x86_64 --version
```

If missing, reinstall:

```bash
sudo apt install -y qemu-system-x86 qemu-utils
```

---

## VM Startup Failures

### "Could not open disk image: No such file or directory"

The start script cannot find the qcow2 disk or the seed ISO.

```bash
# Check that SCRIPT_DIR resolves correctly in the start script
head -20 ~/cka-lab/controlplane-1/start-controlplane-1.sh
# SCRIPT_DIR should use: $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Verify the files exist
ls -la ~/cka-lab/controlplane-1/controlplane-1.qcow2
ls -la ~/cka-lab/controlplane-1/seed.iso
```

### "Could not open backing image"

The qcow2 disk references a backing file (the Ubuntu cloud image) with a path that does not resolve.

```bash
# Check what backing file the disk points to
qemu-img info ~/cka-lab/controlplane-1/controlplane-1.qcow2 | grep backing

# Verify the backing file exists at that path
ls -la <backing-file-path>
```

If the backing path is relative, recreate the disk with an absolute path:

```bash
qemu-img create -f qcow2 \
  -b "$(realpath ~/cka-lab/images/ubuntu-24.04-server-cloudimg-amd64.img)" \
  -F qcow2 \
  ~/cka-lab/controlplane-1/controlplane-1.qcow2 40G
```

Note: this destroys the existing disk and any data inside the VM. You will need to re-run cloud-init (delete and recreate the seed ISO) or start fresh.

### "-daemonize" Conflicts with "-nographic"

These two flags are incompatible. Use `-display none` instead of `-nographic` when daemonizing:

```bash
# Wrong
-nographic -daemonize

# Correct
-display none -daemonize
```

### "Address already in use" on Port Forwarding

Another process (or a previous QEMU instance) is already listening on one of the forwarded ports.

```bash
# Check which ports are in use
sudo ss -tlnp | grep -E '2222|6443|2379|2380|10250|10257|10259'
```

If a stale QEMU process is holding the ports:

```bash
# Kill it using the PID file
kill $(cat ~/cka-lab/controlplane-1/controlplane-1.pid)

# Or find and kill it manually
ps aux | grep qemu-system-x86_64 | grep -v grep
kill <pid>
```

### VM Starts but Immediately Exits

Check dmesg and syslog on the host for KVM errors:

```bash
dmesg | tail -20
journalctl --no-pager -n 20
```

Common causes:
- Insufficient RAM on the host (VM requests 4GB)
- Another hypervisor (VirtualBox, VMware) is locking `/dev/kvm`
- Corrupted disk image

To test if the disk image is the problem, create a fresh one and try booting:

```bash
qemu-img create -f qcow2 \
  -b "$(realpath ~/cka-lab/images/ubuntu-24.04-server-cloudimg-amd64.img)" \
  -F qcow2 \
  /tmp/test-disk.qcow2 40G
```

---

## Networking and Port Forwarding

### Cannot SSH into the VM

Work through these in order:

```bash
# 1. Is the VM running?
ps aux | grep qemu-system-x86_64 | grep -v grep

# 2. Is port 2222 listening on the host?
ss -tlnp | grep 2222

# 3. Is the SSH forwarding configured in the start script?
grep 'hostfwd.*:22' ~/cka-lab/controlplane-1/start-controlplane-1.sh

# 4. Try with verbose SSH to see where it hangs
ssh -v -p 2222 kube@127.0.0.1 -o ConnectTimeout=10
```

If SSH hangs at "connecting", the VM's network is not up yet (common on first boot while cloud-init runs). Wait 60 to 90 seconds and try again.

If SSH connects but authentication fails:

```bash
# cloud-init may not have completed. Check the console log:
grep -i "cloud-init" ~/cka-lab/controlplane-1/controlplane-1-console.log | tail -10

# Default credentials: user "kube", password "kubeadmin"
# Try with password explicitly:
ssh -p 2222 kube@127.0.0.1 -o PreferredAuthentications=password
```

### Cannot Reach the API Server from the Host

```bash
# 1. Is port 6443 forwarded?
grep 'hostfwd.*6443' ~/cka-lab/controlplane-1/start-controlplane-1.sh

# 2. Is the host-side port open?
ss -tlnp | grep 6443

# 3. Is the API server listening inside the VM?
ssh -p 2222 kube@127.0.0.1 'sudo ss -tlnp | grep 6443'

# 4. Test from the host
curl -k https://127.0.0.1:6443/healthz
```

If the API server is listening inside the VM but the host cannot reach it, the port forwarding in the QEMU start script may be misconfigured. Check the `-netdev` line for the correct `hostfwd` syntax.

### VM Has No Internet Access

QEMU user-mode networking provides outbound internet through NAT. If the VM cannot reach the internet:

```bash
# Inside the VM, check the default route
ip route
# Should show: default via 10.0.2.2 dev enp0s2

# Check DNS resolution
cat /etc/resolv.conf
ping -c 1 8.8.8.8

# If no default route, check if the interface got an IP
ip addr show
```

If the interface has no IP, cloud-init's network config may have interfered. Check:

```bash
cat /etc/netplan/*.yaml 2>/dev/null
cat /etc/network/interfaces 2>/dev/null
```

QEMU user-mode networking provides DHCP automatically. The VM should get `10.0.2.15` without any manual configuration.

---

## Cloud-Init Issues

Cloud-init runs on the first boot to configure the VM. If it fails, the user account, packages, kernel modules, or sysctl settings may not be applied.

### Checking Cloud-Init Status

```bash
# Inside the VM
cloud-init status
# Should show: status: done

# If it shows "running", it has not finished yet. Wait.
# If it shows "error", check the logs:
sudo cat /var/log/cloud-init-output.log | tail -50
sudo cat /var/log/cloud-init.log | tail -50
```

### Cloud-Init Did Not Run

The seed ISO may not have been attached, or it may not have the correct volume label.

```bash
# Check if the seed ISO is attached (from the host, look at the start script)
grep seed.iso ~/cka-lab/controlplane-1/start-controlplane-1.sh

# Verify the ISO has the correct volume label
file ~/cka-lab/controlplane-1/seed.iso
# Should mention "cidata" in the output

# Rebuild the ISO if needed
genisoimage -output ~/cka-lab/controlplane-1/seed.iso \
  -volid cidata -joliet -rock \
  ~/cka-lab/controlplane-1/cloud-init/user-data \
  ~/cka-lab/controlplane-1/cloud-init/meta-data
```

### Cloud-Init Ran but Configuration is Wrong

If the user account, hostname, or packages are not set up correctly, inspect the cloud-init source files:

```bash
cat ~/cka-lab/controlplane-1/cloud-init/user-data
cat ~/cka-lab/controlplane-1/cloud-init/meta-data
```

After fixing the cloud-init files, you need to rebuild the seed ISO and recreate the VM disk to trigger a fresh first boot:

```bash
# Rebuild seed ISO
genisoimage -output ~/cka-lab/controlplane-1/seed.iso \
  -volid cidata -joliet -rock \
  ~/cka-lab/controlplane-1/cloud-init/user-data \
  ~/cka-lab/controlplane-1/cloud-init/meta-data

# Recreate the disk (destroys all data)
qemu-img create -f qcow2 \
  -b "$(realpath ~/cka-lab/images/ubuntu-24.04-server-cloudimg-amd64.img)" \
  -F qcow2 \
  ~/cka-lab/controlplane-1/controlplane-1.qcow2 40G
```

### Re-Running Cloud-Init Without Recreating the Disk

If you want to re-run cloud-init on an existing VM without destroying the disk:

```bash
# Inside the VM
sudo cloud-init clean
sudo reboot
```

This clears cloud-init's state so it runs again on the next boot using the attached seed ISO.

---

## Disk Issues

### Checking Disk Space Inside the VM

```bash
df -h /
```

If the root filesystem is full, Kubernetes components will fail in unpredictable ways (etcd cannot write, container images cannot be pulled, logs cannot be written).

```bash
# Find large files
sudo du -h / --max-depth=3 2>/dev/null | sort -rh | head -20

# Common culprits:
# /var/log/ - old logs
# /var/lib/containerd/ - container images and layers
# /var/lib/etcd/ - etcd data

# Clean up container images
sudo crictl rmi --prune
```

### Disk Image Corruption

If the qcow2 image is corrupted, QEMU will refuse to start or the VM will have filesystem errors.

```bash
# Check image integrity (from the host)
qemu-img check ~/cka-lab/controlplane-1/controlplane-1.qcow2
```

If errors are found, the safest fix is to recreate the disk and start fresh. If you need to preserve data, you can try repairing:

```bash
qemu-img check -r all ~/cka-lab/controlplane-1/controlplane-1.qcow2
```

### Resizing the Disk

If the VM runs out of space and you want to expand the disk:

```bash
# Stop the VM first
~/cka-lab/controlplane-1/stop-controlplane-1.sh

# Resize the qcow2 image (from the host)
qemu-img resize ~/cka-lab/controlplane-1/controlplane-1.qcow2 +20G

# Start the VM
~/cka-lab/controlplane-1/start-controlplane-1.sh

# Inside the VM, expand the partition and filesystem
sudo growpart /dev/vda 1
sudo resize2fs /dev/vda1
df -h /
```

---

## VM Lifecycle

### Stopping a VM That Won't Stop Gracefully

```bash
# Try the stop script first
~/cka-lab/controlplane-1/stop-controlplane-1.sh

# If that does not work, send SIGKILL
kill -9 $(cat ~/cka-lab/controlplane-1/controlplane-1.pid)

# If the PID file is stale, find and kill the process
ps aux | grep qemu-system-x86_64 | grep controlplane-1 | grep -v grep
kill -9 <pid>

# Clean up the PID file
rm ~/cka-lab/controlplane-1/controlplane-1.pid
```

### Starting Fresh

If you want to completely reset the VM to its initial state:

```bash
# Stop the VM
~/cka-lab/controlplane-1/stop-controlplane-1.sh

# Delete the disk (all data lost)
rm ~/cka-lab/controlplane-1/controlplane-1.qcow2

# Recreate the disk
qemu-img create -f qcow2 \
  -b "$(realpath ~/cka-lab/images/ubuntu-24.04-server-cloudimg-amd64.img)" \
  -F qcow2 \
  ~/cka-lab/controlplane-1/controlplane-1.qcow2 40G

# Start the VM (cloud-init will run again on first boot)
~/cka-lab/controlplane-1/start-controlplane-1.sh

# Wait 60-90 seconds for cloud-init to complete and the VM to reboot
tail -f ~/cka-lab/controlplane-1/controlplane-1-console.log
```

---

## Quick Diagnostic Reference

```bash
# 1. Is the VM process running?
ps aux | grep qemu-system-x86_64 | grep -v grep

# 2. Are forwarded ports listening on the host?
ss -tlnp | grep -E '2222|6443|2379'

# 3. Can you SSH in?
ssh -p 2222 kube@127.0.0.1 -o ConnectTimeout=5 'echo ok'

# 4. What does the console log say?
tail -20 ~/cka-lab/controlplane-1/controlplane-1-console.log

# 5. Is KVM available?
ls -la /dev/kvm

# 6. Is the disk healthy?
qemu-img check ~/cka-lab/controlplane-1/controlplane-1.qcow2

# 7. How much space is used inside the VM?
ssh -p 2222 kube@127.0.0.1 'df -h /'

# 8. Did cloud-init complete?
ssh -p 2222 kube@127.0.0.1 'cloud-init status'
```
