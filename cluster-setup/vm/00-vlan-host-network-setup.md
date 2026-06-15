# VLAN Host Network Setup

**Purpose:** Configure the UniFi network and the QEMU host's Linux bridge so that lab VMs sit on an isolated VLAN away from the home LAN. This document is the prerequisite for all multi-node QEMU guides (`two-kubeadm`, `three-kubeadm`, `ha-kubeadm`).

---

## Network Design

| VLAN | Name | Subnet | Gateway (UCG-Fiber) | Used By |
|------|------|--------|---------------------|---------|
| 100 | Lab-VMs | `192.168.100.0/24` | `192.168.100.1` | All QEMU/KVM virtual machines |
| 200 | Lab-Pi | `192.168.200.0/24` | `192.168.200.1` | Raspberry Pi kubeadm cluster |

Home LAN (`192.168.2.0/24`) is unchanged. Lab VMs can reach the internet via the UCG-Fiber's VLAN routing. VMs cannot see home LAN devices at L2 (separate broadcast domain), which prevents IP and DHCP conflicts.

---

## Part 1: UCG-Fiber -- Create Lab Networks

These steps run in the **UniFi Network** web UI (or app). The UCG-Fiber acts as the gateway and routes traffic for both lab VLANs.

### Create Lab-VMs Network (VLAN 100)

1. Settings → Networks → **Create New Network**
2. Fill in:
   - **Name:** `Lab-VMs`
   - **Purpose:** Corporate
   - **VLAN ID:** `100`
   - **Gateway IP/Subnet:** `192.168.100.1/24`
   - **DHCP Mode:** Disabled (VMs use static IPs set in cloud-init)
3. Save.

### Create Lab-Pi Network (VLAN 200)

1. Settings → Networks → **Create New Network**
2. Fill in:
   - **Name:** `Lab-Pi`
   - **Purpose:** Corporate
   - **VLAN ID:** `200`
   - **Gateway IP/Subnet:** `192.168.200.1/24`
   - **DHCP Mode:** Disabled (Pis use static IPs set in Netplan)
3. Save.

**Verification:** After saving, both networks should appear in the Networks list with their VLAN IDs. You can verify the UCG-Fiber has acquired the gateway IPs by checking Settings → Networks and confirming the subnets show as "Active."

---

## Part 2: US-24 -- Configure Port Profiles and Assign Ports

These steps run in **UniFi Network** under the US-24 switch device.

### Create Port Profiles

1. Devices → Select the US-24 → **Port Manager** (or Profiles tab in older UI)
2. Create profile **"Lab-VM-Trunk"**:
   - Native VLAN: `Default` (your home LAN, carries untagged home LAN traffic)
   - Tagged VLANs: `100` (Lab-VMs)
   - Purpose: The QEMU host port carries both home LAN traffic (untagged) and VLAN 100 traffic (tagged)
3. Create profile **"Lab-Pi-Access"**:
   - Native VLAN: `200` (Lab-Pi)
   - Tagged VLANs: (none)
   - Purpose: Pi nodes connect as plain access-port clients; they receive only VLAN 200 frames with no 802.1Q tag

### Assign Profiles to Ports

In the US-24 port manager, assign:

| Port | Device | Profile |
|------|--------|---------|
| (QEMU host port) | Desktop / workstation running QEMU | `Lab-VM-Trunk` |
| (Pi port 1) | `pi-cp` (control plane) | `Lab-Pi-Access` |
| (Pi port 2) | `pi-w1` (worker 1) | `Lab-Pi-Access` |
| (Pi port 3) | `pi-w2` (worker 2) | `Lab-Pi-Access` |

Save the port assignments.

**Verification:** In the port manager, confirm each port shows the correct profile. Ports on Lab-Pi-Access should show VLAN 200 as the native VLAN.

---

## Part 3: QEMU Host -- VLAN Subinterface and Bridge

These steps run on the host machine (Ubuntu 24.04) that runs the QEMU/KVM VMs. The host port on the US-24 is now in trunk mode (carries native home LAN VLAN untagged plus VLAN 100 tagged). These steps create a VLAN 100 subinterface and a bridge for VMs to attach to.

This document runs on the host, not inside any VM.

### Step 1: Identify the Host NIC

```bash
ip -brief link show
```

Example output (names vary by hardware):
```
lo        UNKNOWN   127.0.0.1/8
eno1      UP        192.168.2.50/24
```

The NIC with a home LAN IP is the trunk NIC. Note the name (here `eno1`). Substitute it in all commands below.

### Step 2: Install Prerequisites

```bash
sudo apt update
sudo apt install -y bridge-utils
```

### Step 3: Create VLAN Subinterface and Bridge via Netplan

Write a single Netplan file that defines the VLAN 100 subinterface and the `br-vm` bridge. Replace `eno1` with your actual NIC name in both the `vlans:` and `ethernets:` entries.

```bash
sudo tee /etc/netplan/10-br-vm.yaml > /dev/null <<'EOF'
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    eno1:
      dhcp4: true
  vlans:
    eno1.100:
      id: 100
      link: eno1
      dhcp4: false
  bridges:
    br-vm:
      dhcp4: false
      interfaces:
        - eno1.100
      addresses:
        - 192.168.100.2/24
      parameters:
        stp: false
      optional: true
EOF
sudo chmod 600 /etc/netplan/10-br-vm.yaml
```

Notes:
- `192.168.100.2/24` is the host's IP on the lab VLAN. VMs use `192.168.100.1` (UCG-Fiber) as their gateway, not the host.
- `stp: false` removes the 30-second Spanning Tree forwarding delay on TAP attach events.
- `optional: true` prevents the bridge from blocking boot while waiting for VMs to attach.
- If NetworkManager is not installed (Ubuntu Server minimal), change `renderer: NetworkManager` to `renderer: networkd` and run `sudo systemctl enable --now systemd-networkd`.
- If `eno1` already appears in another Netplan file (e.g., the system default in `/etc/netplan/`), remove or comment out the `ethernets: eno1:` block from this file to avoid conflicts.

Apply:
```bash
sudo netplan apply

# Verify both the VLAN interface and the bridge came up
ip addr show eno1.100
ip addr show br-vm | grep '192.168.100.2'
```

Both should show as UP. If `netplan apply` produces errors, run `sudo netplan try` to see them.

### Step 4: Configure qemu-bridge-helper

QEMU includes a setuid helper binary that creates and attaches TAP interfaces for unprivileged users. It checks an allow-list before attaching to a bridge.

```bash
sudo mkdir -p /etc/qemu
sudo tee /etc/qemu/bridge.conf > /dev/null <<'EOF'
allow br-vm
EOF
sudo chown root:kvm /etc/qemu/bridge.conf
sudo chmod 0640 /etc/qemu/bridge.conf

# Set the setuid bit (Ubuntu QEMU packages often omit this)
sudo chmod u+s /usr/lib/qemu/qemu-bridge-helper

# Verify
ls -la /usr/lib/qemu/qemu-bridge-helper
# Expected: -rwsr-xr-x ... root root
```

The `s` in `-rwsr-xr-x` is the setuid bit. Without it the helper cannot create TAP interfaces.

### Step 5: Exclude QEMU TAP Interfaces from NetworkManager

QEMU creates TAP interfaces (`tap0`, `tap1`, etc.) dynamically when VMs start and attaches them to `br-vm`. NetworkManager will try to configure them unless told not to.

```bash
if systemctl is-active --quiet NetworkManager; then
  sudo tee /etc/NetworkManager/conf.d/10-unmanaged-tap.conf > /dev/null <<'EOF'
[keyfile]
unmanaged-devices=interface-name:tap*
EOF
  sudo systemctl reload NetworkManager
fi
```

The `if` block is a no-op on systems without NetworkManager.

### Step 6: Verification

```bash
# VLAN subinterface exists
ip link show eno1.100
# Expected: eno1.100@eno1: <...> state UP

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

All five checks should produce output. If any fail, fix that step before continuing to the VM provisioning document.

### Summary

| Component | Path | Purpose |
|-----------|------|---------|
| Netplan config | `/etc/netplan/10-br-vm.yaml` | Defines `eno1.100` VLAN subinterface and `br-vm` bridge |
| QEMU helper allow-list | `/etc/qemu/bridge.conf` | Permits unprivileged attach to `br-vm` |
| QEMU helper binary | `/usr/lib/qemu/qemu-bridge-helper` | setuid root, creates TAP interfaces |
| NM TAP exclusion | `/etc/NetworkManager/conf.d/10-unmanaged-tap.conf` | Prevents NM from managing QEMU TAP interfaces |

The host is now ready for VM creation. Proceed to the VM provisioning document for whichever cluster topology you are building:

- [two-kubeadm: VM Provisioning](two-kubeadm/02-vm-provisioning.md)
- [three-kubeadm: VM Provisioning](three-kubeadm/02-vm-provisioning.md)
- [ha-kubeadm: VM Provisioning](ha-kubeadm/02-vm-provisioning.md)

---

## Routing and Internet Access

The UCG-Fiber routes traffic for both lab VLANs. VMs set `192.168.100.1` (or `192.168.200.1` for Pi nodes) as their default gateway in their network config. Internet traffic flows VM → br-vm (L2) → VLAN 100 trunk → US-24 → UCG-Fiber → WAN. The host does not perform NAT.

If firewall rules on the UCG-Fiber block internet access from lab VLANs by default (depends on your UniFi configuration), add outbound allow rules in Settings → Firewall & Security → Rules for the Lab-VMs and Lab-Pi networks.
