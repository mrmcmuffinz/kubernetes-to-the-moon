# OS Setup: Ubuntu Server 24.04 ARM64

**Purpose:** Flash Ubuntu Server 24.04 LTS ARM64 on each Pi, complete first-boot
configuration, fix the cgroup kernel parameter for kubelet, disable swap, and set the
hostname. Repeat for all three nodes before proceeding to network setup.

This document runs on each Pi node individually and (for flashing) on the host machine.

---

## Part 1: Flash the OS Image

Use **Raspberry Pi Imager** (available for Linux, macOS, Windows from `raspberrypi.com/software`).

1. Open Raspberry Pi Imager.
2. **Choose Device:** Raspberry Pi 5.
3. **Choose OS:** Other general-purpose OS → Ubuntu → Ubuntu Server 24.04 LTS (64-bit).
4. **Choose Storage:** Select the target SD card or NVMe drive.
5. Click the settings gear icon (**Edit Settings**) before writing:
   - Hostname: `pi-cp` (for the control plane) or `pi-w1`, `pi-w2` (for workers)
   - Enable SSH: checked; use your public key for authentication
   - Username: `kube`
   - Password: `kubeadmin` (or whatever you prefer)
   - Do not configure Wi-Fi (use wired Ethernet only)
6. Click **Save**, then **Write**.

Repeat for each Pi with its respective hostname.

**NVMe note:** If using NVMe via a PCIe HAT, ensure your Pi 5 firmware supports NVMe boot. Flash the NVMe with Raspberry Pi Imager using a USB-to-NVMe adapter, or boot from SD and copy the OS to NVMe manually. Refer to the official Pi 5 NVMe boot guide.

---

## Part 2: First Boot

Insert the flashed media, connect the Pi to power and Ethernet, and wait ~2 minutes for first boot to complete. SSH in using the IP assigned by DHCP (check your router's DHCP leases or use `nmap` to discover it):

```bash
# On host — discover Pi IP (adjust subnet to your VLAN 200 range if DHCP is active)
nmap -sn 192.168.200.0/24 | grep -A 1 "Raspberry"

# Or check DHCP leases in UCG-Fiber UI
```

Once you find the IP, SSH in:

```bash
ssh kube@<dhcp-ip>
```

The hostname should match what you set in Imager. If it does not, set it manually:

```bash
sudo hostnamectl set-hostname pi-cp   # or pi-w1, pi-w2
```

---

## Part 3: Fix Cgroup Parameters

Ubuntu Server 24.04 on Raspberry Pi 5 may not have memory cgroup accounting enabled by
default. `kubeadm preflight` checks for this and will fail if cgroups are not set up
correctly. Add the required flags to the kernel command line.

```bash
# Check if cgroup memory is already enabled
grep cgroup /proc/cgroups | grep memory
# Expected: memory   0   1   1   (the third column must be 1)
```

If the third column is 0, or if `cgroup_memory` is not shown, add the flags:

```bash
# The cmdline.txt file is in the boot partition
sudo grep "cgroup" /boot/firmware/cmdline.txt
```

If `cgroup_enable=memory` and `cgroup_memory=1` are not present, append them to the end
of the single line in `cmdline.txt`:

```bash
# Read the current line
cat /boot/firmware/cmdline.txt

# Append cgroup flags (add to end of existing line, not a new line)
sudo sed -i 's/$/ cgroup_enable=memory cgroup_memory=1/' /boot/firmware/cmdline.txt

# Verify: must remain a single line with the flags appended
cat /boot/firmware/cmdline.txt
```

The file must remain a single line -- multiple lines in `cmdline.txt` causes boot failures.

---

## Part 4: Disable Swap

Kubernetes requires swap to be disabled on all nodes.

```bash
# Check for active swap
swapon --show

# Disable immediately
sudo swapoff -a

# Prevent re-enable at boot: comment out any swap entries in fstab
sudo sed -i '/swap/s/^/#/' /etc/fstab

# Verify
swapon --show
# Expected: no output
```

On Ubuntu Server 24.04, swap is typically configured via a swap file. Check:

```bash
cat /etc/fstab | grep swap
# If a swap entry exists and is not commented out, the sed command above fixed it
```

---

## Part 5: Reboot and Verify

```bash
sudo reboot
```

After reboot, SSH back in:

```bash
ssh kube@<dhcp-ip>

# Verify hostname
hostname
# Expected: pi-cp (or pi-w1, pi-w2)

# Verify cgroup memory is enabled
grep memory /proc/cgroups
# Expected: memory   0   N   1  (third column = 1)

# Verify swap is off
swapon --show
# Expected: no output
```

---

Repeat Parts 1-5 for all three Pi nodes (`pi-cp`, `pi-w1`, `pi-w2`) before proceeding.

---

← [Previous: Overview](00-overview.md) | [Next: Network Setup →](02-network-setup.md)
