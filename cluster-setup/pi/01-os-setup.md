# OS Setup: Raspberry Pi OS Trixie Lite (arm64)

**Purpose:** Flash Raspberry Pi OS Trixie Lite on each Pi, set the hostname, verify
cgroup configuration, and disable swap. Repeat for all three nodes before proceeding
to network setup.

This document runs on each Pi node individually and (for flashing) on the host machine.

---

## Part 0: Wipe a Previously Used NVMe (skip for new drives)

If the NVMe was used before, clear all partition table and filesystem signatures before
flashing. Old LVM, RAID, or partition metadata can cause a non-bootable result.

Run these steps on the **host machine** with the NVMe connected via a USB-to-NVMe
adapter.

```bash
# 1. Identify the device -- match by size, NOT by name
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
# Do NOT proceed until you are certain of the device name.
```

```bash
# 2. Unmount any partitions the OS auto-mounted
sudo umount /dev/sda* 2>/dev/null || true
```

```bash
# 3. Wipe all filesystem and partition table signatures
sudo wipefs -a /dev/sda
```

```bash
# 4. Zero the first 100 MB to remove any residual boot or LVM headers
sudo dd if=/dev/zero of=/dev/sda bs=1M count=100 status=progress
sync
```

```bash
# 5. Verify the drive is clean
sudo wipefs /dev/sda
lsblk /dev/sda
# Expected: single line for the disk, no child partitions listed
```

---

## Part 1: Flash the OS Image

Connect the NVMe via a USB-to-NVMe adapter. Identify the device with `lsblk`, then
flash with `dd`:

```bash
sudo dd if=<image>.img of=/dev/sda bs=4M status=progress conv=fsync
sync
```

Replace `<image>.img` with the full path to your Raspberry Pi OS Trixie Lite image
(e.g. `2026-04-21-raspios-trixie-arm64-lite-patched.img`). Replace `/dev/sda` with
the correct device identified in Part 0.

`conv=fsync` flushes all data to disk before `dd` exits. Wait for the command to
complete fully before removing the adapter.

**After flashing, before removing the adapter**, mount the boot partition and patch
the cloud-init `user-data` to set the keyboard layout to US. The boot partition is
FAT32 (partition 1) and is writable directly from the host:

```bash
sudo mkdir -p /mnt/pi-boot
sudo mount /dev/sda1 /mnt/pi-boot

# Append keyboard config to the existing user-data file
sudo tee -a /mnt/pi-boot/user-data > /dev/null <<'EOF'
keyboard:
  layout: us
  model: pc105
EOF

sudo umount /mnt/pi-boot
```

The `keyboard` cloud-init module writes `/etc/default/keyboard` and runs `setupcon`
on first boot. This replaces the default `gb` layout with `us`.

Repeat for each Pi with its own NVMe drive.

---

## Part 2: First Boot

Insert the NVMe into the Pi, connect Ethernet and power, and wait ~60 seconds for first
boot. The Pi will be accessible via SSH as the `admin` user using the key configured in
the image.

Find the DHCP-assigned IP from your UCG-Fiber DHCP leases, or scan the network:

```bash
# On host -- scan VLAN 200 subnet (requires Pi to be on the correct switch port first)
nmap -sn 192.168.200.0/24 | grep -B 1 "Raspberry"
```

SSH in:

```bash
ssh admin@<dhcp-ip>
```

---

## Part 3: Set Hostname

Set the hostname for each node. This becomes the Kubernetes node name and must be
unique across the cluster.

| Node | Hostname | IP |
|------|----------|----|
| Control plane | `rpi-node-01` | `192.168.200.10` |
| Worker 1 | `rpi-node-02` | `192.168.200.11` |
| Worker 2 | `rpi-node-03` | `192.168.200.12` |

```bash
# Substitute the correct hostname for this node
sudo hostnamectl set-hostname rpi-node-01

# Add the hostname to /etc/hosts for local resolution
# (sudo resolves the hostname and logs a warning if it is not resolvable locally)
echo "127.0.1.1 $(hostname)" | sudo tee -a /etc/hosts

# Verify
hostname
# Expected: rpi-node-01

grep "$(hostname)" /etc/hosts
# Expected: 127.0.1.1  rpi-node-01
```

---

## Part 4: Fix Cgroup Parameters

Kubernetes requires memory cgroup accounting. On Raspberry Pi OS Trixie with a Pi 5,
this is typically enabled by default, but verify before proceeding.

```bash
grep memory /proc/cgroups
# Expected: memory   0   N   1  (the fourth column must be 1)
```

If the fourth column is 0, add the flags to the kernel command line:

```bash
# Check current cmdline
cat /boot/firmware/cmdline.txt

# Append cgroup flags if not present (must remain a single line)
sudo sed -i 's/$/ cgroup_enable=memory cgroup_memory=1/' /boot/firmware/cmdline.txt

# Verify -- must be a single line
cat /boot/firmware/cmdline.txt
```

---

## Part 5: Verify Swap is Disabled

Kubernetes requires swap to be disabled on all nodes. The patched image's cloud-init
disables the zram swap service (`systemd-zram-setup@zram0`) automatically on first
boot. Verify it took effect:

```bash
swapon --show
# Expected: no output
```

If swap is still active (output shows `/dev/zram0`), disable it manually:

```bash
sudo systemctl disable --now systemd-zram-setup@zram0.service
swapon --show
# Expected: no output
```

Note: `swapoff -a` does not work on zram devices and will log `Invalid argument` --
use the systemd service approach above instead.

---

## Part 6: Reboot and Verify

```bash
sudo reboot
```

After reboot, SSH back in:

```bash
ssh admin@<dhcp-ip>

# Verify hostname
hostname
# Expected: rpi-node-01 (or rpi-node-02, rpi-node-03)

# Verify cgroup memory is enabled
grep memory /proc/cgroups
# Expected: memory   0   N   1  (fourth column = 1)

# Verify swap is off
swapon --show
# Expected: no output
```

---

Repeat Parts 1-6 for all three Pi nodes (`rpi-node-01`, `rpi-node-02`, `rpi-node-03`)
before proceeding.

---

← [Previous: Overview](00-overview.md) | [Next: Network Setup →](02-network-setup.md)
