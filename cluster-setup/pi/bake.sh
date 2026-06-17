#!/bin/bash
# Usage: sudo ./bake_rpi.sh <image_file>
# Example: sudo ./bake_rpi.sh raspios.img
#          sudo ./bake_rpi.sh raspios.img.xz
#
# Prepares a Raspberry Pi OS image with:
#   - OS-level prerequisites for Kubernetes (cgroup, swap disabled, etc.)
#   - cloud-init configured for NoCloud datasource
#   - Basic tooling
#
# Accepts compressed (.img.xz) or uncompressed (.img) images.
# If a compressed image is provided, it will be decompressed before baking
# and recompressed when done.
#
# Per-node configuration is handled via three cloud-init files written to the
# boot partition after flashing: meta-data (instance-id and hostname),
# network-config (static IP), and user-data (users, packages, sysctls, swap).
# Kubernetes installation (kubeadm, kubelet, kubectl, container runtime) is
# handled post-boot on the node.

set -euo pipefail

INPUT=$1
MOUNT_POINT="/mnt/rpi_root"
COMPRESSED=false
IMAGE=""

# ─── Preflight checks ────────────────────────────────────────────────────────

if [[ $EUID -ne 0 ]]; then
  echo "Error: this script must be run as root (sudo)" >&2
  exit 1
fi

if [[ -z "${INPUT:-}" ]]; then
  echo "Usage: sudo $0 <image_file|image_file.xz>" >&2
  exit 1
fi

if [[ ! -f "$INPUT" ]]; then
  echo "Error: file '$INPUT' not found" >&2
  exit 1
fi

if ! command -v qemu-aarch64-static &>/dev/null; then
  echo "Error: qemu-aarch64-static not found. Install with: apt install qemu-user-static" >&2
  exit 1
fi

# ─── Decompress if needed ────────────────────────────────────────────────────

if [[ "$INPUT" == *.xz ]]; then
  COMPRESSED=true
  IMAGE="${INPUT%.xz}"
  PATCHED_IMAGE="${IMAGE%.img}-patched.img"
  if [[ -f "$IMAGE" ]]; then
    echo "Found existing decompressed image at $IMAGE, skipping decompression..."
  else
    echo "Decompressing $INPUT..."
    if ! command -v xz &>/dev/null; then
      echo "Error: xz not found. Install with: apt install xz-utils" >&2
      exit 1
    fi
    # --keep preserves the original .xz file
    xz --decompress --keep "$INPUT"
    echo "Decompressed to $IMAGE"
  fi
  # Work on a copy so the original decompressed image is preserved
  echo "Creating working copy as $PATCHED_IMAGE..."
  cp "$IMAGE" "$PATCHED_IMAGE"
  IMAGE="$PATCHED_IMAGE"
else
  PATCHED_IMAGE="${INPUT%.img}-patched.img"
  echo "Creating working copy as $PATCHED_IMAGE..."
  cp "$INPUT" "$PATCHED_IMAGE"
  IMAGE="$PATCHED_IMAGE"
fi

# ─── Cleanup trap ────────────────────────────────────────────────────────────

cleanup() {
  echo "Cleaning up..."

  # Remove QEMU binary from image before unmounting. It is an x86 host binary
  # and must not be present in the final ARM image
  rm -f "$MOUNT_POINT/usr/bin/qemu-aarch64-static" 2>/dev/null || true

  umount "$MOUNT_POINT/dev" "$MOUNT_POINT/proc" "$MOUNT_POINT/sys" \
         "$MOUNT_POINT/boot" "$MOUNT_POINT" 2>/dev/null || true

  if [[ -n "${LOOP_DEV:-}" ]]; then
    losetup -d "$LOOP_DEV" 2>/dev/null || true
  fi

  # Note: patched image files are intentional outputs and are not removed

}
trap cleanup EXIT

# ─── Mount image ─────────────────────────────────────────────────────────────

echo "Setting up loop device for $IMAGE..."
LOOP_DEV=$(losetup -fP --show "$IMAGE")
mkdir -p "$MOUNT_POINT"
mount "${LOOP_DEV}p2" "$MOUNT_POINT"
mount "${LOOP_DEV}p1" "$MOUNT_POINT/boot"

# ─── cgroup kernel parameters (required by Kubernetes on Pi OS) ───────────────

echo "Patching /boot/cmdline.txt for cgroup support..."
CMDLINE="$MOUNT_POINT/boot/cmdline.txt"
if ! grep -q "cgroup_memory=1" "$CMDLINE"; then
  sed -i 's/$/ cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1/' "$CMDLINE"
fi

# ─── Enable PCIe Gen 3 ───────────────────────────────────────────────────────

echo "Enabling PCIe Gen 3..."
CONFIG="$MOUNT_POINT/boot/config.txt"
if ! grep -q "pciex1_gen=3" "$CONFIG"; then
  echo "dtparam=pciex1_gen=3" >> "$CONFIG"
fi

# ─── Disable swap (zram on Pi OS Trixie) ─────────────────────────────────────
#
# Pi OS Trixie uses systemd-zram-generator for swap, not dphys-swapfile, and
# swap is no longer an fstab entry. A comment-only zram-generator.conf makes
# the generator build no zram0 device; the mask is defense-in-depth.

echo "Disabling swap..."
cat > "$MOUNT_POINT/etc/systemd/zram-generator.conf" << 'ZRAM'
# zram swap disabled (Kubernetes does not permit swap)
ZRAM
ln -sf /dev/null "$MOUNT_POINT/etc/systemd/system/systemd-zram-setup@zram0.service" 2>/dev/null || true

# ─── Seed cloud-init NoCloud datasource ──────────────────────────────────────
#
# cloud-init requires user-data and meta-data files in the boot partition to
# activate the NoCloud datasource. These are placeholders, along with a
# network-config that brings up eth0 via DHCP so an unconfigured image is still
# reachable on the network. The real per-node configuration (meta-data,
# network-config, user-data) is written after flashing, one set per node.
#
# See the cluster setup guide (k8s-cluster-setup.md) for the per-node templates.

echo "Seeding cloud-init NoCloud datasource..."
cat > "$MOUNT_POINT/boot/meta-data" << 'EOF'
instance-id: unconfigured
EOF

cat > "$MOUNT_POINT/boot/network-config" << 'EOF'
version: 2
ethernets:
  eth0:
    dhcp4: true
EOF

cat > "$MOUNT_POINT/boot/user-data" << 'EOF'
#cloud-config
# Placeholder. Replace with per-node configuration after flashing.
# See k8s-cluster-setup.md for the full templates.
EOF

# ─── Prepare chroot ──────────────────────────────────────────────────────────

cp /usr/bin/qemu-aarch64-static "$MOUNT_POINT/usr/bin/"
mount --bind /dev  "$MOUNT_POINT/dev"
mount --bind /proc "$MOUNT_POINT/proc"
mount --bind /sys  "$MOUNT_POINT/sys"

# ─── Install OS prerequisites inside chroot ──────────────────────────────────

echo "Installing OS prerequisites in chroot..."
chroot "$MOUNT_POINT" /bin/bash <<'EOF'
set -e

# Remove armhf foreign architecture. Trixie Debian mirrors do not carry
# armhf packages, and apt-get update will fail trying to fetch them
dpkg --remove-architecture armhf 2>/dev/null || true

apt-get update -qq

# cloud-init (idempotent if already present)
apt-get install -y \
    apt-transport-https \
    bash-completion \
    bridge-utils \
    ca-certificates \
    chrony \
    cloud-init \
    conntrack \
    curl \
    git \
    gnupg \
    ipset \
    iptables-persistent \
    jq \
    lsb-release \
    net-tools \
    nfs-common \
    open-iscsi \
    openssh-server \
    socat \
    vim

# Harden SSH (disable root login and password auth)
cat > /etc/ssh/sshd_config.d/99-hardening.conf << 'SSHD'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
SSHD

systemctl enable ssh

# Disable Pi OS first-boot wizard so cloud-init runs cleanly
# These services prompt for user creation, keyboard layout, etc. and race
# with or block cloud-init from completing
systemctl disable userconfig.service 2>/dev/null || true
systemctl mask userconfig.service 2>/dev/null || true
systemctl disable userconfig 2>/dev/null || true

# Remove first-boot scripts that print interactive warnings on login
rm -f /etc/profile.d/wifi-check.sh 2>/dev/null || true
rm -f /etc/profile.d/sshpwd.sh 2>/dev/null || true

# Remove the systemd unit that triggers the first-boot wizard via tty1
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf 2>/dev/null || true

apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

# ─── Recompress image if input was compressed ────────────────────────────────

if [[ "$COMPRESSED" == true ]]; then
  echo "Compressing patched image to ${IMAGE}.xz (this may take a while)..."
  xz --compress --keep --threads=0 "$IMAGE"
  echo "Compressed to ${IMAGE}.xz"
fi

echo ""
echo "Done."
if [[ "$COMPRESSED" == true ]]; then
  echo "Patched image (uncompressed): $IMAGE"
  echo "Patched image (compressed):   ${IMAGE}.xz"
else
  echo "Patched image: $IMAGE"
fi
echo ""
echo "Next steps per node:"
echo "  1. Flash image to NVMe"
echo "  2. Mount the boot partition and write the three per-node cloud-init files:"
echo "     meta-data (instance-id, hostname), network-config (static IP), user-data"
echo "     (see k8s-cluster-setup.md for the templates)"
echo "  3. Unmount and boot the node"
echo "  4. SSH in and install Kubernetes (kubeadm/kubelet/kubectl + container runtime)"