# Host Network Setup and HAProxy Load Balancer

**Based on:** [`../00-vlan-host-network-setup.md`](../00-vlan-host-network-setup.md)

**Purpose:** Confirm the VLAN-isolated bridge (`br-vm`) is configured on the host and add a HAProxy load balancer that serves the control plane VIP (`192.168.100.100:6443`). The VIP is an additional IP alias on the host's `br-vm` interface.

---

## Prerequisites

This step runs on the host, not inside any VM.

## Part 1: Bridge Setup

If `br-vm` is already configured from a previous guide, skip to Part 2.

Follow [`../00-vlan-host-network-setup.md`](../00-vlan-host-network-setup.md) in full (all three parts: UCG-Fiber, US-24, Linux host).

---

## Part 2: Add the VIP Address to the Host Bridge

The HAProxy VIP is a static IP alias on the host's `br-vm` interface. VMs can reach it at `192.168.100.100` through the bridge.

Update the Netplan bridge config to include the VIP address alongside the host management address:

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
        - 192.168.100.100/32
      parameters:
        stp: false
      optional: true
EOF
sudo chmod 600 /etc/netplan/10-br-vm.yaml
sudo netplan apply

# Verify both addresses are present
ip addr show br-vm | grep '192.168.100'
# Expected: inet 192.168.100.2/24 and inet 192.168.100.100/32
```

Replace `eno1` with your actual NIC name if different.

---

## Part 3: Install HAProxy

```bash
sudo apt update
sudo apt install -y haproxy
```

---

## Part 4: Configure HAProxy

HAProxy listens on the VIP (`192.168.100.100:6443`) and load balances connections to both control plane API servers. Health checks use a TCP connect check so HAProxy removes a failing API server from the pool automatically.

```bash
sudo tee /etc/haproxy/haproxy.cfg > /dev/null <<'EOF'
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5s
    timeout client  50s
    timeout server  50s

frontend k8s-api
    bind 192.168.100.100:6443
    default_backend k8s-api-backend

backend k8s-api-backend
    balance roundrobin
    option  tcp-check
    server controlplane-1 192.168.100.20:6443 check fall 3 rise 2
    server controlplane-2 192.168.100.21:6443 check fall 3 rise 2
EOF
```

Enable and start:

```bash
sudo systemctl enable haproxy
sudo systemctl restart haproxy
sudo systemctl status haproxy
```

---

## Part 5: Verification

After completing all parts:

```bash
# Bridge has both management IP and VIP
ip addr show br-vm | grep '192.168.100'
# Expected: inet 192.168.100.2/24 and inet 192.168.100.100/32

# HAProxy is listening on the VIP
ss -tlnp | grep ':6443'
# Expected: LISTEN ... 192.168.100.100:6443

# HAProxy is running
sudo systemctl is-active haproxy
# Expected: active

# qemu-bridge-helper is setuid
ls -la /usr/lib/qemu/qemu-bridge-helper | grep '^-rws'

# Bridge is in the allow-list
sudo cat /etc/qemu/bridge.conf
# Expected: allow br-vm
```

Once the control plane API servers are running (after document 05), test the VIP:

```bash
curl -k https://192.168.100.100:6443/healthz
# Expected: ok
```

---

← [Previous: HA Kubernetes Cluster Overview](00-overview.md) | [Next: VM Provisioning →](02-vm-provisioning.md)
