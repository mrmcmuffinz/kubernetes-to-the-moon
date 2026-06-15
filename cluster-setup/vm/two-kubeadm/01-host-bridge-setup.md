# Host Network Setup for Two-Node Cluster

**Based on:** [`../00-vlan-host-network-setup.md`](../00-vlan-host-network-setup.md)

**Purpose:** Configure the VLAN-isolated bridge (`br-vm`) that both VMs will attach to. This replaces the earlier NAT bridge approach (`br0` at `192.168.122.0/24`).

---

## Prerequisites

This step runs on the host, not inside any VM.

## Setup

Follow [`../00-vlan-host-network-setup.md`](../00-vlan-host-network-setup.md) in full. All three parts apply:

1. **Part 1 (UCG-Fiber):** Create the Lab-VMs network (VLAN 100, `192.168.100.0/24`) and Lab-Pi network (VLAN 200, `192.168.200.0/24`) if not already done.
2. **Part 2 (US-24):** Apply the `Lab-VM-Trunk` profile to the QEMU host port.
3. **Part 3 (Host):** Create the `eno1.100` VLAN subinterface, the `br-vm` bridge, configure `qemu-bridge-helper`, and exclude TAP interfaces from NetworkManager.

If `br-vm` is already configured from a previous guide, skip to verification below.

## Verification

After completing the setup:

```bash
# VLAN subinterface and bridge are up
ip addr show br-vm | grep '192.168.100.2'
# Expected: inet 192.168.100.2/24

# VLAN subinterface is a bridge member
bridge link show
# Expected: eno1.100: <...> master br-vm

# qemu-bridge-helper is setuid
ls -la /usr/lib/qemu/qemu-bridge-helper | grep '^-rws'

# Bridge is in the allow-list
sudo cat /etc/qemu/bridge.conf
# Expected: allow br-vm
```

**Result:** `br-vm` is up at `192.168.100.2/24`, the QEMU bridge helper is configured, and TAP interfaces are excluded from NetworkManager.

---

← [Previous: Two-Node Kubernetes Cluster: Overview](00-overview.md) | [Next: VM Provisioning for Two-Node Cluster →](02-vm-provisioning.md)
