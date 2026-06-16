# Network Setup: Static IPs on VLAN 200

**Purpose:** Assign a static IP to each Pi node in VLAN 200 (`192.168.200.0/24`),
populate `/etc/hosts` for cluster name resolution, and verify SSH connectivity between
all nodes and from the host.

This document runs on each Pi node individually. Run it after document 01 (OS Setup) on
all three nodes.

---

## Prerequisites

- VLAN 200 is configured on UCG-Fiber and the US-24 switch (per
  [`../vm/00-vlan-host-network-setup.md`](../vm/00-vlan-host-network-setup.md) Parts 1
  and 2 -- the UCG-Fiber "Lab-Pi" network and the `Lab-Pi-Access` port profile on
  Pi-facing ports).
- Each Pi is connected via Ethernet to a VLAN 200 access port on the US-24.
- You can SSH into each Pi using its DHCP-assigned IP (from document 01).

---

## Part 1: Static IP via nmcli

Raspberry Pi OS Trixie uses NetworkManager. The wired interface is `eth0`. Run the
following on each Pi, substituting the correct IP for that node.

```bash
# Find the active connection name
nmcli connection show
# Look for the connection on eth0 (e.g. "Wired connection 1" or "eth0")
```

Set the static IP (substitute `<CONNECTION>` with the name shown above and `<IP>` with
the node's address):

| Node | IP |
|------|----|
| `rpi-node-01` | `192.168.200.10` |
| `rpi-node-02` | `192.168.200.11` |
| `rpi-node-03` | `192.168.200.12` |

```bash
sudo nmcli connection modify "<CONNECTION>" \
  ipv4.method manual \
  ipv4.addresses "<IP>/24" \
  ipv4.gateway "192.168.200.1" \
  ipv4.dns "192.168.200.1,8.8.8.8" \
  connection.autoconnect yes

sudo nmcli connection up "<CONNECTION>"
```

Verify:

```bash
ip addr show eth0 | grep '192.168.200'
# Expected: inet 192.168.200.10/24 (or .11/.12 per node)

ip route show default
# Expected: default via 192.168.200.1 dev eth0
```

---

## Part 2: DNS and Hostname Resolution

Kubernetes components need to resolve cluster hostnames. Populate `/etc/hosts` on all
three nodes with the static IPs. Run this block on each Pi:

```bash
sudo tee -a /etc/hosts > /dev/null <<'EOF'

# Kubernetes cluster nodes
192.168.200.10  rpi-node-01
192.168.200.11  rpi-node-02
192.168.200.12  rpi-node-03
EOF

# Verify
cat /etc/hosts | grep rpi-node
```

---

## Part 3: SSH Key Distribution

The control plane (`rpi-node-01`) needs to be accessible from the host machine without
password prompts for cluster management. The SSH key is pre-configured in the image.
Verify connectivity to each node:

```bash
# From the host
ssh admin@192.168.200.10 hostname
# Expected: rpi-node-01

ssh admin@192.168.200.11 hostname
# Expected: rpi-node-02

ssh admin@192.168.200.12 hostname
# Expected: rpi-node-03
```

Add the following to `~/.ssh/config` on the host for short-form SSH access:

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

From `rpi-node-01`, verify it can reach both workers:

```bash
ssh rpi-node-01  # SSH into control plane

# Ping both workers
ping -c 2 rpi-node-02
ping -c 2 rpi-node-03

# Verify internet access
ping -c 2 8.8.8.8
```

All three pings should succeed. Internet access confirms the UCG-Fiber is routing VLAN
200 traffic correctly.

---

**Result:** All three Pi nodes have static IPs on `192.168.200.0/24`, resolve each
other by hostname, and are SSH-reachable from the host.

---

← [Previous: OS Setup](01-os-setup.md) | [Next: Node Prerequisites →](03-node-prerequisites.md)
