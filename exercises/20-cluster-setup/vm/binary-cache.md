# Binary Archive Cache via QEMU 9p Filesystem Share (Optional)

The `single-systemd` and `two-systemd` guides install every Kubernetes component from
raw binaries fetched directly from GitHub and `dl.k8s.io`. On each cluster rebuild,
the install scripts download approximately 10 archives (etcd, containerd, runc, crictl,
CNI plugins, and five Kubernetes binaries). These are large files served over HTTPS with
no caching layer, so every rebuild pays the full download cost.

This guide sets up a shared directory on the host that the VM accesses as a mounted
filesystem. The install scripts are run from that shared directory. `wget --timestamping`
(already used by the install scripts) skips files that are already present and current,
so after the first download the archives live on the host and are served locally on every
subsequent rebuild.

**Which guides benefit:** The binary cache is useful for `single-systemd` and
`two-systemd`, which download raw binaries. The kubeadm-based guides (`single-kubeadm`,
`two-kubeadm`, `three-kubeadm`, `ha-kubeadm`) install components via apt, so the
[apt caching proxy](apt-cache-proxy.md) is the right tool for those.

**How it works:** QEMU's virtfs feature exposes a host directory to the VM as a 9p
filesystem over the virtio transport. The VM sees it as a mountable block device and
can read from and write to it transparently. Files written to the mount from inside the
VM land on the host disk and persist after the VM is destroyed.

## Prerequisites

- Ubuntu 24.04 LTS host with QEMU/KVM installed (the `single-systemd` or `two-systemd`
  guide prerequisites already cover this).
- The `qemu-system-x86_64` binary on the host must have been compiled with 9p support,
  which it is in the Ubuntu 24.04 `qemu-system-x86` package.
- The Ubuntu 24.04 VM image includes the `9p` and `9pnet_virtio` kernel modules.

## Part 1: Create the Cache Directory on the Host

Create the cache directory inside the existing `cka-lab` working tree so it coexists
with the VM images and disk files:

```bash
mkdir -p ~/cka-lab/binary-cache
```

## Part 2: Add the 9p Share to the QEMU Launch Command

The `create-node.sh` script generates a `start-${NODE_NAME}.sh` file in the node
directory. That file contains the `qemu-system-x86_64` command that starts the VM. To
expose the binary cache to the VM, add a `-virtfs` flag to the qemu command.

Open `cluster-setup/vm/single-systemd/scripts/create-node.sh` and locate the heredoc
block that generates `start-${NODE_NAME}.sh` (it starts with
`cat > "$NODE_DIR/start-${NODE_NAME}.sh" <<STARTSCRIPT`). Inside that block, the qemu
command ends with these two lines:

```bash
    -pidfile "\$SCRIPT_DIR/${NODE_NAME}.pid" \\
    "\$@"
```

Add the `-virtfs` flag between those two lines:

```bash
    -pidfile "\$SCRIPT_DIR/${NODE_NAME}.pid" \\
    -virtfs local,path="${HOME}/cka-lab/binary-cache",mount_tag=bincache,security_model=none,id=bincache \\
    "\$@"
```

`security_model=none` is the simplest mode for single-user setups: file ownership and
permissions are not remapped, so the VM can write to the share without uid/gid
translation. The `mount_tag=bincache` value is the name the VM uses to identify the
device when mounting.

After editing `create-node.sh`, re-run it to regenerate the start script, or edit the
`start-${NODE_NAME}.sh` file directly if the VM has already been created and you do not
want to reprovision.

## Part 3: Mount the Share Inside the VM

The 9p modules must be loaded before the filesystem can be mounted. This can be done
manually after boot or automatically via cloud-init when creating a new VM.

### Option A: Manual (After Boot)

SSH into the VM and run:

```bash
sudo modprobe 9p 9pnet_virtio
sudo mkdir -p /mnt/bincache
sudo mount -t 9p -o trans=virtio,version=9p2000.L bincache /mnt/bincache
```

Confirm the mount is present:

```bash
mountpoint /mnt/bincache
ls /mnt/bincache
```

The mount does not persist across VM reboots. If the VM is rebooted (rather than
destroyed and recreated), run the mount command again or use Option B.

### Option B: Automatic via cloud-init (New VMs)

For fresh VMs where the binary cache should be ready from first boot, add two entries
to the `user-data` cloud-init file.

First, add a `write_files` entry to load the 9p kernel modules on every boot (place this
after the existing `modules-load.d/k8s.conf` entry):

```yaml
  - path: /etc/modules-load.d/9p.conf
    content: |
      9p
      9pnet_virtio
    permissions: '0644'
```

Second, add a `mounts:` section to the `user-data` file (as a top-level key alongside
`packages:` and `write_files:`):

```yaml
mounts:
  - [bincache, /mnt/bincache, 9p, "trans=virtio,version=9p2000.L,nofail,_netdev", "0", "0"]
```

`nofail` means the VM boots normally even if the mount device is not present (useful if
you start the VM without the `-virtfs` flag). `_netdev` signals to systemd that this
mount should be ordered after virtual devices are initialized.

After modifying `user-data`, regenerate the cloud-init seed ISO by re-running
`create-node.sh`, or use `genisoimage` to rebuild `seed.iso` from the updated
`user-data` and `meta-data` files.

## Part 4: Run Install Scripts from the Cache Directory

The cache works by using the shared host directory as the working directory when running
the install scripts. `wget --timestamping` (the flag already used in every install
script) checks whether a file with the same name already exists in the working directory
and whether its local modification time is newer than the server's `Last-Modified`
header. If the local file is current, the download is skipped entirely.

After mounting the share, transfer the `scripts/` directory to the cache mount (this is
a one-time setup that copies the scripts themselves to the persistent location):

```bash
# On the VM, after mounting /mnt/bincache
cp -r ~/scripts/* /mnt/bincache/
```

Then run install scripts from the mount:

```bash
cd /mnt/bincache
source env
./install_cr.sh
./install_etcd.sh
./install_k_api.sh
./install_k_ctr_mgr.sh
./install_k_sch.sh
./install_kubelet.sh
./install_k_proxy.sh
./install_cni.sh
```

On the first run, `wget` downloads each archive to `/mnt/bincache/`. Those files land
on the host at `~/cka-lab/binary-cache/` and persist after the VM is destroyed. On every
subsequent rebuild, the same `cd /mnt/bincache && source env && ./install_*.sh` sequence
runs but `wget --timestamping` finds current files in the working directory and skips all
downloads.

## Part 5: Pre-Warming the Cache (Optional)

If you want to populate the cache before creating any VMs (for example, to prepare for
offline lab work), you can download the binary archives directly on the host. The
download commands below use the same version variables as the `env` file.

```bash
cd ~/cka-lab/binary-cache
source /path/to/cluster-setup/vm/single-systemd/scripts/env

# Container runtime components
arch=amd64
wget --https-only --timestamping \
  "https://github.com/containerd/containerd/releases/download/v${containerd_version}/containerd-${containerd_version}-linux-${arch}.tar.gz" \
  "https://github.com/opencontainers/runc/releases/download/v${runc_version}/runc.${arch}" \
  "https://github.com/kubernetes-sigs/cri-tools/releases/download/v${cri_version}/crictl-v${cri_version}-linux-${arch}.tar.gz"

# etcd
wget --https-only --timestamping \
  "https://github.com/etcd-io/etcd/releases/download/v${etcd_version}/etcd-v${etcd_version}-linux-${arch}.tar.gz"

# CNI plugins
wget --https-only --timestamping \
  "https://github.com/containernetworking/plugins/releases/download/v${cni_plugins_version}/cni-plugins-linux-${arch}-v${cni_plugins_version}.tgz"

# Kubernetes binaries
for bin in kube-apiserver kube-controller-manager kube-scheduler kubelet kube-proxy; do
  wget --https-only --timestamping \
    "https://dl.k8s.io/release/v${k8s_version}/bin/linux/${arch}/${bin}"
done
```

After pre-warming, the total cache size is roughly 500-700 MB. When the VM mounts the
share and runs the install scripts from `/mnt/bincache/`, all downloads are skipped on
the first run as well.

## Troubleshooting

**Mount fails with "No such file or directory" or "unknown filesystem type '9p'."** The
9p kernel modules are not loaded in the VM. Run `sudo modprobe 9p 9pnet_virtio` before
attempting the mount. If `modprobe` fails with "Module not found", the VM kernel may
not include 9p support, which is uncommon for Ubuntu 24.04 but can happen with
custom-built kernels.

**Mount succeeds but files appear read-only.** `security_model=none` allows writes when
the host directory is writable. Check that `~/cka-lab/binary-cache/` on the host is owned
by your user and is not mounted on a read-only filesystem (`ls -la ~/cka-lab/`). Also
confirm the QEMU flag uses `security_model=none`, not `security_model=mapped` (which
remaps uids and can cause apparent permission failures).

**The VM starts but the 9p mount is missing (cloud-init path).** Confirm that the
`/etc/modules-load.d/9p.conf` file exists inside the VM with `9p` and `9pnet_virtio` on
separate lines, and that the `mounts:` entry appears in `user-data`. Also confirm the
QEMU command in `start-${NODE_NAME}.sh` includes the `-virtfs` flag. The `nofail`
option in the mount entry means a missing device is silently skipped at boot rather than
causing a boot failure, so a missing mount does not appear as an error in the console log.

**`wget --timestamping` still re-downloads files.** `--timestamping` skips the download
when the local file exists and its modification time is newer than the server's
`Last-Modified` response header. If the server returns no `Last-Modified` header (unusual
for GitHub releases but possible if the URL structure changes), wget treats the file as
stale and re-downloads. In that case, check the downloaded file sizes: if the local and
remote files are the same size and the binary runs correctly, the duplicate download is
harmless. To force a cache hit regardless of server headers, create an empty file with
the same name and a future timestamp (`touch -d "next year" filename`) before running
the install script, though this is a workaround, not a fix.

**The `two-systemd` guide uses a separate VM for the worker node.** The worker node is
created with its own QEMU command (via `create-node.sh` or a separate start script). Add
the same `-virtfs` flag to the worker node's start script, using the same host cache
directory. Both VMs can share the same `~/cka-lab/binary-cache/` directory
simultaneously; the binaries are read-only from the install scripts' perspective
(after the initial download), so concurrent access is safe.

## Summary

| Item | Value |
|------|-------|
| Share type | QEMU virtio 9p filesystem (virtfs) |
| Host cache directory | `~/cka-lab/binary-cache/` |
| QEMU flag | `-virtfs local,path="${HOME}/cka-lab/binary-cache",mount_tag=bincache,security_model=none,id=bincache` |
| Guest mount point | `/mnt/bincache` |
| Guest mount command | `sudo mount -t 9p -o trans=virtio,version=9p2000.L bincache /mnt/bincache` |
| Guest kernel modules | `9p`, `9pnet_virtio` |
| Applicable guides | `single-systemd`, `two-systemd` (raw binary installs) |
| Cache hit mechanism | `wget --timestamping` skips files with current modification time |
| Pre-warm size | ~500-700 MB for all component versions in `env` |
