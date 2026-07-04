# Network Setup: Verify and Complete Cluster Networking

**Purpose:** Verify the static IP and hostname set by cloud-init, add cluster node
entries to `/etc/hosts` on each node, and confirm SSH and inter-node connectivity.

Run this document on each Pi node after completing document 01 (OS Setup) on all three.

---

## Part 1: Verify Static IP and Hostname

Cloud-init wrote `network-config` and set the hostname. Confirm both are in effect:

```bash
# Static IP on eth0
ip addr show eth0 | grep '192.168.200'
# Expected: inet 192.168.200.10/24  (or .11/.12 per node)

# Default route
ip route show default
# Expected: default via 192.168.200.1 dev eth0

# Hostname
hostname
# Expected: rpi-node-01  (or rpi-node-02/03 per node)

# Internet connectivity
ping -c 2 1.1.1.1
```

If the IP or hostname is wrong, check the cloud-init files on the boot partition and
re-run cloud-init (see `../vm/cloud-init-reference.md`).

---

## Part 2: Add Cluster Node /etc/hosts Entries

`manage_etc_hosts: true` in cloud-init writes the `127.0.1.1` loopback entry for the
local hostname, but it does not add the other cluster nodes. Add them manually on
each Pi so Kubernetes components can resolve peer hostnames:

```bash
sudo tee -a /etc/hosts > /dev/null <<'EOF'

# Kubernetes cluster nodes
192.168.200.10  rpi-node-01
192.168.200.11  rpi-node-02
192.168.200.12  rpi-node-03
EOF

# Verify
grep rpi-node /etc/hosts
```

Expected output includes both the loopback entry (from cloud-init) and the three
cluster entries:

```
127.0.1.1       rpi-node-01
192.168.200.10  rpi-node-01
192.168.200.11  rpi-node-02
192.168.200.12  rpi-node-03
```

---

## Part 3: SSH Connectivity from Host

The `admin` SSH key was configured by cloud-init. Verify each node is reachable from
the host:

```bash
ssh admin@192.168.200.10 hostname   # Expected: rpi-node-01
ssh admin@192.168.200.11 hostname   # Expected: rpi-node-02
ssh admin@192.168.200.12 hostname   # Expected: rpi-node-03
```

Add short-form aliases to `~/.ssh/config` on the host:

```ssh-config
Host rpi-node-01
    HostName 192.168.200.10
    User admin
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new

Host rpi-node-02
    HostName 192.168.200.11
    User admin
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new

Host rpi-node-03
    HostName 192.168.200.12
    User admin
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
```

After adding this, `ssh rpi-node-01` resolves without flags.

---

## Part 4: Inter-Node Connectivity

From the control plane node, verify it can reach both workers and the internet:

```bash
ssh rpi-node-01

ping -c 2 rpi-node-02
ping -c 2 rpi-node-03
ping -c 2 1.1.1.1
```

All three should succeed. Internet access confirms UCG-Fiber is routing VLAN 200
traffic correctly.

---

**Result:** All three Pi nodes have verified static IPs, resolve each other by hostname,
and are SSH-reachable from the host and from each other.

---

← [Previous: OS Setup](01-os-setup.md) | [Next: Node Prerequisites →](03-node-prerequisites.md)
