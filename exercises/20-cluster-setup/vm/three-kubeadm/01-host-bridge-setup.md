# Host Network Setup for Three-Node Cluster

**Based on:** [`../00-vlan-host-network-setup.md`](../00-vlan-host-network-setup.md)

**Purpose:** Confirm the VLAN-isolated bridge (`br-vm`) is configured on the host. This setup is identical to the two-node guide. If `br-vm` is already configured from the two-node guide or a previous run, skip this document entirely and proceed to [02 - VM Provisioning](02-vm-provisioning.md).

---

## Prerequisites

This step runs on the host, not inside any VM.

## Setup

Follow [`../00-vlan-host-network-setup.md`](../00-vlan-host-network-setup.md) in full. All three parts apply:

1. **Part 1 (UCG-Fiber):** Create the Lab-VMs network (VLAN 100, `192.168.100.0/24`) if not already done.
2. **Part 2 (US-24):** Confirm the `Lab-VM-Trunk` profile is applied to the QEMU host port.
3. **Part 3 (Host):** Create the `eno1.100` VLAN subinterface and `br-vm` bridge, configure `qemu-bridge-helper`, and exclude TAP interfaces from NetworkManager.

## Verification

After completing the bridge setup:

```bash
# Bridge exists with the host IP
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

**Result:** `br-vm` is up at `192.168.100.2/24` and the QEMU bridge helper is configured.

---

← [Previous: Three-Node Kubernetes Cluster: Overview](00-overview.md) | [Next: VM Provisioning: Three Nodes →](02-vm-provisioning.md)
