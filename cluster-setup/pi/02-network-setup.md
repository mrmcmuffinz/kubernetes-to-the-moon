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

## Part 1: Static IP via Netplan

Ubuntu 24.04 uses Netplan for network configuration. The Pi's wired interface is
typically `eth0` but may differ (check with `ip -brief link show`).

Run the following on each Pi, substituting the correct hostname and IP:

**On `pi-cp`** (`192.168.200.10`):

```bash
sudo tee /etc/netplan/10-static.yaml > /dev/null <<'EOF'
network:
  version: 2
  renderer: networkd
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
          - 8.8.8.8
EOF
sudo chmod 600 /etc/netplan/10-static.yaml
```

**On `pi-w1`** (`192.168.200.11`): Same file, change address to `192.168.200.11/24`.

**On `pi-w2`** (`192.168.200.12`): Same file, change address to `192.168.200.12/24`.

For all three nodes, also remove or disable any existing cloud-init-generated Netplan
files that have DHCP configured:

```bash
# Check what's there
ls /etc/netplan/

# If there is a 50-cloud-init.yaml or similar with dhcp4: true, disable it
sudo mv /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.disabled 2>/dev/null || true
```

Apply the new config:

```bash
sudo netplan apply

# Verify
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
192.168.200.10  pi-cp
192.168.200.11  pi-w1
192.168.200.12  pi-w2
EOF

# Verify
cat /etc/hosts | grep pi-
```

---

## Part 3: SSH Key Distribution

The control plane (`pi-cp`) needs to be accessible from the host machine without
password prompts for cluster management. Add the host's public key to each Pi (if you
used Raspberry Pi Imager's SSH settings in document 01, this is already done). Verify:

```bash
# From the host
ssh kube@192.168.200.10 hostname
# Expected: pi-cp

ssh kube@192.168.200.11 hostname
# Expected: pi-w1

ssh kube@192.168.200.12 hostname
# Expected: pi-w2
```

Add the following to `~/.ssh/config` on the host for short-form SSH access:

```ssh-config
Host pi-cp
    HostName 192.168.200.10
    User kube
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new

Host pi-w1
    HostName 192.168.200.11
    User kube
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new

Host pi-w2
    HostName 192.168.200.12
    User kube
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
```

After adding this, `ssh pi-cp` resolves without flags.

---

## Part 4: Inter-Node Connectivity

From `pi-cp`, verify it can reach both workers:

```bash
ssh pi-cp  # SSH into control plane

# Ping both workers
ping -c 2 pi-w1
ping -c 2 pi-w2

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
