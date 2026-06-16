# OS Setup: Raspberry Pi OS Trixie Lite (arm64)

**Purpose:** Flash Raspberry Pi OS Trixie Lite on each Pi and write per-node cloud-init
files to the boot partition. Cloud-init handles hostname, static IP, user creation,
keyboard layout, kernel modules, sysctl, package prerequisites, swap disable, and
auto-reboot on first boot. Nothing needs to be configured manually on the node after
SSH in.

Run this document on the **host machine** for each Pi node. The only per-node
differences are in `meta-data`, `user-data` (hostname field), and `network-config`
(IP address).

---

## Part 0: Wipe a Previously Used NVMe (skip for new drives)

If the NVMe was used before, clear all partition table and filesystem signatures before
flashing. Old LVM, RAID, or partition metadata can cause a non-bootable result.

Run these steps on the host machine with the NVMe connected via a USB-to-NVMe adapter.

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

## Part 1: Flash the Image

```bash
sudo dd if=<image>.img of=/dev/sda bs=4M status=progress conv=fsync
sync
```

Replace `<image>.img` with the full path to your Raspberry Pi OS Trixie Lite image
(e.g. `2026-04-21-raspios-trixie-arm64-lite.img`). Replace `/dev/sda` with the device
identified in Part 0.

`conv=fsync` flushes all data before `dd` exits. Wait for the command to complete fully
before proceeding.

---

## Part 2: Write Cloud-Init Files

Mount the boot partition (FAT32, partition 1) and write three files. All three are
read by cloud-init DataSourceNoCloud on first boot.

```bash
sudo mkdir -p /mnt/pi-boot
sudo mount /dev/sda1 /mnt/pi-boot
```

**meta-data** sets the instance ID and local hostname:

```bash
sudo tee /mnt/pi-boot/meta-data > /dev/null <<'EOF'
instance-id: rpi-node-01
local-hostname: rpi-node-01
EOF
```

**user-data** is the full node configuration. The only per-node field is `hostname`;
everything else is identical across all three nodes. Replace `<YOUR_SSH_PUBLIC_KEY>`
with the public key the `admin` user should accept:

```bash
sudo tee /mnt/pi-boot/user-data > /dev/null <<'EOF'
#cloud-config
hostname: rpi-node-01
timezone: America/Chicago
ssh_pwauth: false
manage_etc_hosts: true

keyboard:
  layout: us
  model: pc105

write_files:
  - path: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter
  - path: /etc/sysctl.d/k8s.conf
    content: |
      net.bridge.bridge-nf-call-iptables  = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward                 = 1
  - path: /etc/systemd/zram-generator.conf
    content: |
      # zram swap disabled (Kubernetes does not permit swap)

users:
  - name: admin
    groups: sudo
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - <YOUR_SSH_PUBLIC_KEY>

runcmd:
  # Remove fake-hwclock (Trixie bug: rewinds clock and defeats apt signature verification)
  - apt-get remove -y fake-hwclock || true
  - rm -f /etc/fake-hwclock.data

  # Force NTP sync before any apt operations
  - timedatectl set-ntp true
  - systemctl restart systemd-timesyncd
  - |
    for i in $(seq 1 30); do
      if timedatectl show -p NTPSynchronized --value | grep -q yes; then
        echo "Clock synced after ${i} attempts"
        break
      fi
      sleep 2
    done
  - timedatectl status

  # Package work (safe now that clock is synced)
  - apt-get update
  - DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
  - |
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      apt-transport-https bash-completion bridge-utils ca-certificates \
      chrony conntrack curl gnupg ipset iptables-persistent jq \
      lsb-release net-tools socat vim

  # Enable services
  - systemctl enable --now chrony
  - systemctl enable ssh
  - systemctl start ssh

  # Disable swap (fstab and zram)
  - swapoff -a
  - sed -i '/\sswap\s/s/^/#/' /etc/fstab
  - swapoff /dev/zram0 || true
  - systemctl mask 'systemd-zram-setup@zram0.service'
  - systemctl disable --now rpi-zram-writeback.timer || true

power_state:
  mode: reboot
  message: "Cloud-init complete. Rebooting to apply all configuration."
  timeout: 30
  condition: true
EOF
```

**network-config** sets the static IP for this node (Netplan v2 format, applied by
cloud-init via NetworkManager):

```bash
sudo tee /mnt/pi-boot/network-config > /dev/null <<'EOF'
version: 2
ethernets:
  eth0:
    dhcp4: false
    addresses:
      - 192.168.200.10/24
    routes:
      - to: default
        via: 192.168.200.1
    nameservers:
      addresses:
        - 192.168.200.1
        - 1.1.1.1
EOF
```

Unmount before removing the adapter:

```bash
sudo umount /mnt/pi-boot
```

Per-node substitution table -- the only values that change across nodes:

| Node | `instance-id` / `hostname` | `addresses` |
|------|---------------------------|-------------|
| `rpi-node-01` | `rpi-node-01` | `192.168.200.10/24` |
| `rpi-node-02` | `rpi-node-02` | `192.168.200.11/24` |
| `rpi-node-03` | `rpi-node-03` | `192.168.200.12/24` |

---

## Part 3: First Boot

Insert the NVMe into the Pi, connect Ethernet to a VLAN 200 access port, and connect
power. Cloud-init runs automatically and reboots when done. The `runcmd` block does a
full `apt upgrade` plus package installs, so expect 3-5 minutes before the node comes
back up.

SSH in at the static IP from `network-config` -- no need to find a DHCP address:

```bash
ssh admin@192.168.200.10   # rpi-node-01
ssh admin@192.168.200.11   # rpi-node-02
ssh admin@192.168.200.12   # rpi-node-03
```

---

## Part 4: Verify

Confirm cloud-init applied everything correctly:

```bash
# Hostname
hostname
# Expected: rpi-node-01

# 127.0.1.1 entry (written by manage_etc_hosts: true)
grep "$(hostname)" /etc/hosts
# Expected: 127.0.1.1  rpi-node-01

# Static IP on eth0
ip addr show eth0 | grep '192.168.200'
# Expected: inet 192.168.200.10/24

# Default route
ip route show default
# Expected: default via 192.168.200.1 dev eth0

# Swap off
swapon --show
# Expected: no output

# cgroup memory enabled
grep memory /proc/cgroups
# Expected: memory   0   N   1  (fourth column = 1)

# Kernel modules loaded
lsmod | grep -E 'overlay|br_netfilter'

# sysctl
sysctl net.ipv4.ip_forward
# Expected: net.ipv4.ip_forward = 1
```

If any check fails, inspect the cloud-init log:

```bash
sudo journalctl -u cloud-init --no-pager | tail -50
sudo cat /var/log/cloud-init-output.log | tail -50
```

---

Repeat Parts 0-4 for all three Pi nodes before proceeding.

---

← [Previous: Overview](00-overview.md) | [Next: Network Setup →](02-network-setup.md)
