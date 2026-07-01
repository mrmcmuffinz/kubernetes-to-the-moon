#!/usr/bin/env bash
#
# break-cluster.sh
#
# Introduces a single fault into the two-node, from-scratch, systemd-managed
# Kubernetes cluster for troubleshooting practice. Run this from the QEMU host.
# The script SSHes into one or both VMs to apply the break.
#
# This script extends the single-systemd break-cluster.sh with multi-node-
# specific failure modes: missing cross-node pod routes, per-node CIDR
# mismatches, kube-proxy configuration drift on one node only, and apiserver
# cert SAN list damage that breaks nodes-1 but not controlplane-1.
#
# Usage:
#   ./break-cluster.sh          # Pick a random scenario
#   ./break-cluster.sh 7        # Run scenario 7 specifically
#   ./break-cluster.sh --list   # Show how many scenarios are available
#   ./break-cluster.sh --reset  # Restore both nodes to working state
#
# Configuration:
#   Set BREAK_NODE1 and BREAK_NODE2 to override default SSH commands.
#   Defaults assume ~/.ssh/config has Host entries for controlplane-1 and nodes-1.
#   Example:
#     export BREAK_NODE1="ssh controlplane-1"
#     export BREAK_NODE2="ssh nodes-1"

set -euo pipefail

TOTAL_SCENARIOS=18

# -------------------------------------------------------------------
# SSH configuration
# -------------------------------------------------------------------
NODE1_SSH="${BREAK_NODE1:-ssh controlplane-1}"
NODE2_SSH="${BREAK_NODE2:-ssh nodes-1}"

run_on_controlplane1() {
  $NODE1_SSH sudo bash <<EOF
$1
EOF
}

run_on_nodes1() {
  $NODE2_SSH sudo bash <<EOF
$1
EOF
}

# -------------------------------------------------------------------
# Backup helpers
# -------------------------------------------------------------------
backup_on_controlplane1() {
  local file="$1"
  run_on_controlplane1 "if [ -f '$file' ] && [ ! -f '${file}.break-backup' ]; then cp '$file' '${file}.break-backup'; fi"
}

backup_on_nodes1() {
  local file="$1"
  run_on_nodes1 "if [ -f '$file' ] && [ ! -f '${file}.break-backup' ]; then cp '$file' '${file}.break-backup'; fi"
}

# -------------------------------------------------------------------
# Help and Argument Parsing
# -------------------------------------------------------------------
show_help() {
  cat <<'EOF'
NAME
    break-cluster.sh - Introduce faults into two-node systemd Kubernetes cluster

SYNOPSIS
    ./break-cluster.sh [OPTION | SCENARIO]

DESCRIPTION
    Introduces a single controlled fault into your two-node, from-scratch,
    systemd-managed Kubernetes cluster for troubleshooting practice. Run this
    from the QEMU host. The script SSHes into one or both VMs to apply the break.

    This variant extends single-systemd with multi-node failure modes: cross-node
    pod routing, per-node CIDR mismatches, kube-proxy drift, and apiserver
    certificate SAN issues.

OPTIONS
    -h, --help
        Display this help message and exit.

    --list
        Show how many scenarios are available without spoilers.

    --reset
        Restore all cluster components to working state. This reverses any
        changes made by previous scenario runs.

    SCENARIO
        A number between 1 and 18. If omitted, picks a random scenario.

CONFIGURATION
    BREAK_NODE1
        SSH command for controlplane-1. Default: ssh controlplane-1

    BREAK_NODE2
        SSH command for nodes-1. Default: ssh nodes-1

    Examples:
        export BREAK_NODE1="ssh -p 2222 kube@192.168.122.10"
        export BREAK_NODE2="ssh -p 2223 kube@192.168.122.11"

EXAMPLES
    Run a random scenario:
        ./break-cluster.sh

    Run scenario 14 specifically:
        ./break-cluster.sh 14

    List available scenarios:
        ./break-cluster.sh --list

    Reset cluster to working state:
        ./break-cluster.sh --reset

    SSH into either node:
        ssh controlplane-1
        ssh nodes-1

DIAGNOSTIC COMMANDS
    After a scenario runs, SSH into either node and diagnose the problem:

        kubectl get nodes -o wide
        kubectl get pods -A -o wide
        systemctl status <service>
        journalctl -u <service> -n 50
        ip route | grep 10.244
        curl --cacert /etc/etcd/ca.pem https://192.168.122.10:6443/healthz

    Multi-node hint: If a problem affects pods on only one node, the fault is
    likely on that specific node. Check which node the misbehaving pod runs on first.

SCENARIO CATEGORIES
    Scenarios 1-10: Control plane issues on controlplane-1
    Scenarios 11-13: Worker issues on nodes-1
    Scenarios 14-18: Multi-node networking (routing, CIDR, sysctls)

FILES
    controlplane-1:
        /etc/systemd/system/etcd.service
        /etc/systemd/system/kube-apiserver.service
        /etc/systemd/system/kube-controller-manager.service
        /etc/systemd/system/kube-scheduler.service

    nodes-1:
        /var/lib/kubelet/kubelet-config.yaml
        /var/lib/kube-proxy/kube-proxy-config.yaml
        /etc/cni/net.d/10-bridge.conf

EXIT STATUS
    0   Success
    1   Invalid scenario number or other error

SEE ALSO
    kubectl(1), systemctl(1), journalctl(1), ip(8), iptables(8)
EOF
  exit 0
}

parse_args() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
  fi

  if [[ "${1:-}" == "--list" ]]; then
    ACTION="list"
    return
  fi

  if [[ "${1:-}" == "--reset" ]]; then
    ACTION="reset"
    return
  fi

  if [[ -n "${1:-}" ]]; then
    SCENARIO_NUM="$1"
  else
    SCENARIO_NUM=$(( (RANDOM % TOTAL_SCENARIOS) + 1 ))
  fi

  ACTION="scenario"
}

validate_scenario() {
  local scenario="$1"

  if [[ "$scenario" -lt 1 || "$scenario" -gt "$TOTAL_SCENARIOS" ]]; then
    echo "ERROR: Scenario must be between 1 and $TOTAL_SCENARIOS." >&2
    exit 1
  fi
}

print_banner() {
  local scenario="$1"

  echo "============================================="
  echo "  Cluster Break Scenario #${scenario}"
  echo "  (two-systemd)"
  echo "============================================="
  echo ""
  echo "Something has been broken in your cluster."
  echo "SSH into either node and use kubectl, systemctl,"
  echo "journalctl, ip, and iptables to find the problem."
  echo ""
  echo "  ssh controlplane-1"
  echo "  ssh nodes-1"
  echo ""
  echo "Diagnostic starting points:"
  echo "  kubectl get nodes -o wide"
  echo "  kubectl get pods -A -o wide"
  echo "  systemctl status <service>"
  echo "  journalctl -u <service> -n 50"
  echo "  ip route | grep 10.244"
  echo "  curl --cacert /etc/etcd/ca.pem https://192.168.122.10:6443/healthz"
  echo ""
  echo "Multi-node hint: if a problem only affects pods on one node, the"
  echo "fault is probably on that node. Ask which node the misbehaving pod"
  echo "lives on first."
  echo ""
  echo "To reset: $0 --reset"
  echo "============================================="
}

list_scenarios() {
  echo "$TOTAL_SCENARIOS scenarios available."
  echo "Usage: $0 [1-$TOTAL_SCENARIOS] or $0 for random."
  echo ""
  echo "Scenarios 1-10: control plane on controlplane-1"
  echo "Scenarios 11-13: worker problems on nodes-1"
  echo "Scenarios 14-18: multi-node-specific (routing, CIDR, sysctls)"
  exit 0
}

# -------------------------------------------------------------------
# Scenarios
# 1-10: Reuse single-systemd patterns, scoped to controlplane-1's control plane
# 11-18: Multi-node-specific failure modes
# -------------------------------------------------------------------

# --- Control plane scenarios (controlplane-1 only) ---

# Difficulty: Beginner | Concept: etcd data directory path | Symptom: etcd fails to start; API server loses connection to etcd
scenario_1() {
  backup_on_controlplane1 /etc/systemd/system/etcd.service
  run_on_controlplane1 "sed -i 's|--data-dir=/var/lib/etcd|--data-dir=/var/lib/etcd-bad|' /etc/systemd/system/etcd.service && systemctl daemon-reload && systemctl restart etcd" 2>/dev/null || true
}

# Difficulty: Beginner | Concept: etcd endpoint URL in kube-apiserver | Symptom: API server starts then crashes; cannot reach etcd on wrong port
scenario_2() {
  backup_on_controlplane1 /etc/systemd/system/kube-apiserver.service
  run_on_controlplane1 "sed -i 's|--etcd-servers=https://127.0.0.1:2379|--etcd-servers=https://127.0.0.1:9999|' /etc/systemd/system/kube-apiserver.service && systemctl daemon-reload && systemctl restart kube-apiserver" 2>/dev/null || true
}

# Difficulty: Beginner | Concept: TLS certificate file path | Symptom: API server crashes; logs show "no such file or directory"
scenario_3() {
  backup_on_controlplane1 /etc/systemd/system/kube-apiserver.service
  run_on_controlplane1 "sed -i 's|--tls-cert-file=/var/lib/kubernetes/kubernetes.pem|--tls-cert-file=/var/lib/kubernetes/missing.pem|' /etc/systemd/system/kube-apiserver.service && systemctl daemon-reload && systemctl restart kube-apiserver" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: controller-manager kubeconfig path | Symptom: API server up; deployments stop reconciling; failed pods not replaced
scenario_4() {
  backup_on_controlplane1 /etc/systemd/system/kube-controller-manager.service
  run_on_controlplane1 "sed -i 's|--kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig|--kubeconfig=/var/lib/kubernetes/wrong.kubeconfig|' /etc/systemd/system/kube-controller-manager.service && systemctl daemon-reload && systemctl restart kube-controller-manager" 2>/dev/null || true
}

# Difficulty: Beginner | Concept: systemd service enabled/disabled state | Symptom: kubectl completely unresponsive
scenario_5() {
  run_on_controlplane1 "systemctl stop kube-apiserver && systemctl disable kube-apiserver" 2>/dev/null || true
}

# Difficulty: Advanced | Concept: service CIDR consistency across components | Symptom: new services get wrong ClusterIPs; CoreDNS breaks
scenario_6() {
  backup_on_controlplane1 /etc/systemd/system/kube-apiserver.service
  run_on_controlplane1 "sed -i 's|--service-cluster-ip-range=10.96.0.0/16|--service-cluster-ip-range=10.99.0.0/16|' /etc/systemd/system/kube-apiserver.service && systemctl daemon-reload && systemctl restart kube-apiserver" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: API server authorization mode | Symptom: API server starts; every request returns 403 Forbidden
scenario_7() {
  backup_on_controlplane1 /etc/systemd/system/kube-apiserver.service
  run_on_controlplane1 "sed -i 's|--authorization-mode=Node,RBAC|--authorization-mode=AlwaysDeny|' /etc/systemd/system/kube-apiserver.service && systemctl daemon-reload && systemctl restart kube-apiserver" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: etcd client URL scheme (http vs https) | Symptom: etcd starts; API server fails with TLS handshake error
scenario_8() {
  backup_on_controlplane1 /etc/systemd/system/etcd.service
  run_on_controlplane1 "sed -i 's|--listen-client-urls=https://|--listen-client-urls=http://|g' /etc/systemd/system/etcd.service && systemctl daemon-reload && systemctl restart etcd" 2>/dev/null || true
}

# Difficulty: Advanced | Concept: cluster CIDR in controller-manager | Symptom: existing pods keep IPs; no CIDR allocated to newly joined nodes
scenario_9() {
  backup_on_controlplane1 /etc/systemd/system/kube-controller-manager.service
  run_on_controlplane1 "sed -i 's|--cluster-cidr=10.244.0.0/16|--cluster-cidr=10.250.0.0/16|' /etc/systemd/system/kube-controller-manager.service && systemctl daemon-reload && systemctl restart kube-controller-manager" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: scheduler config file path | Symptom: existing pods keep running; new pods stay Pending indefinitely
scenario_10() {
  backup_on_controlplane1 /etc/systemd/system/kube-scheduler.service
  run_on_controlplane1 "sed -i 's|--config=/etc/kubernetes/config/kube-scheduler.yaml|--config=/etc/kubernetes/config/missing.yaml|' /etc/systemd/system/kube-scheduler.service && systemctl daemon-reload && systemctl restart kube-scheduler" 2>/dev/null || true
}

# --- Worker scenarios ---

# Difficulty: Beginner | Concept: node-specific kubelet state | Symptom: nodes-1 goes NotReady; controlplane-1 is unaffected
scenario_11() {
  run_on_nodes1 "systemctl stop kubelet && systemctl disable kubelet" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: CRI socket path in kubelet config | Symptom: nodes-1 NotReady; kubelet logs "failed to connect to container runtime"
scenario_12() {
  backup_on_nodes1 /var/lib/kubelet/kubelet-config.yaml
  run_on_nodes1 "sed -i 's|containerRuntimeEndpoint: \"unix:///var/run/containerd/containerd.sock\"|containerRuntimeEndpoint: \"unix:///var/run/containerd/wrong.sock\"|' /var/lib/kubelet/kubelet-config.yaml && systemctl restart kubelet" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: kube-proxy clusterCIDR on worker | Symptom: Service IPs work from controlplane-1 but not from nodes-1 pods
scenario_13() {
  backup_on_nodes1 /var/lib/kube-proxy/kube-proxy-config.yaml
  run_on_nodes1 "sed -i 's|clusterCIDR: \"10.244.0.0/16\"|clusterCIDR: \"10.250.0.0/16\"|' /var/lib/kube-proxy/kube-proxy-config.yaml && systemctl restart kube-proxy" 2>/dev/null || true
}

# --- Multi-node-specific scenarios ---

# Difficulty: Advanced | Concept: host routing table (pod CIDR routes) | Symptom: pods on controlplane-1 cannot reach pods on nodes-1; reverse works
scenario_14() {
  run_on_controlplane1 "ip route del 10.244.1.0/24 via 192.168.122.11 2>/dev/null" 2>/dev/null || true
  echo "  (route deleted on controlplane-1; persistent config in systemd-networkd may add it back on next networkd reload)"
}

# Difficulty: Advanced | Concept: host routing table (asymmetric) | Symptom: pings from controlplane-1 reach nodes-1 pods but replies are dropped
scenario_15() {
  run_on_nodes1 "ip route del 10.244.0.0/24 via 192.168.122.10 2>/dev/null" 2>/dev/null || true
  echo "  (route deleted on nodes-1; pings from controlplane-1 to nodes-1 pods get there but replies are dropped)"
}

# Difficulty: Advanced | Concept: per-node pod CIDR subnet in CNI config | Symptom: nodes-1 pods get IPs from 10.244.0.0/24 (collision with controlplane-1)
scenario_16() {
  backup_on_nodes1 /etc/cni/net.d/10-bridge.conf
  run_on_nodes1 "sed -i 's|\"subnet\": \"10.244.1.0/24\"|\"subnet\": \"10.244.0.0/24\"|' /etc/cni/net.d/10-bridge.conf && rm -rf /var/lib/cni/networks/bridge/* 2>/dev/null && systemctl restart kubelet" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: CNI config file presence on worker | Symptom: nodes-1 goes NotReady; kubelet reports "network plugin not ready"
scenario_17() {
  run_on_nodes1 "if [ -f /etc/cni/net.d/10-bridge.conf ]; then mv /etc/cni/net.d/10-bridge.conf /etc/cni/net.d/10-bridge.conf.hidden && systemctl restart kubelet; fi" 2>/dev/null || true
}

# Difficulty: Advanced | Concept: kernel sysctl ip_forward | Symptom: cross-node traffic silently fails even with routes in place
scenario_18() {
  backup_on_nodes1 /etc/sysctl.d/99-kubernetes-cri.conf
  run_on_nodes1 "sysctl -w net.ipv4.ip_forward=0" 2>/dev/null || true
  echo "  (IP forwarding disabled on nodes-1 in-memory; sysctl files unchanged)"
}

# -------------------------------------------------------------------
# Reset function
# -------------------------------------------------------------------
reset_all() {
  echo "=== Restoring controlplane-1 ==="

  $NODE1_SSH "sudo bash" << 'NODE1'
files=(
  /etc/systemd/system/etcd.service
  /etc/systemd/system/kube-apiserver.service
  /etc/systemd/system/kube-controller-manager.service
  /etc/systemd/system/kube-scheduler.service
)

for file in "${files[@]}"; do
  if [ -f "${file}.break-backup" ]; then
    cp "${file}.break-backup" "$file"
    echo "  Restored: $file"
  fi
done

# Re-add cross-node route if missing
if ! ip route | grep -q "10.244.1.0/24"; then
  ip route add 10.244.1.0/24 via 192.168.122.11 2>/dev/null || true
  echo "  Re-added route: 10.244.1.0/24 via 192.168.122.11"
fi

systemctl daemon-reload
systemctl enable etcd kube-apiserver kube-controller-manager kube-scheduler 2>/dev/null || true
systemctl restart etcd
sleep 3
systemctl restart kube-apiserver
sleep 2
systemctl restart kube-controller-manager
systemctl restart kube-scheduler
NODE1

  echo ""
  echo "=== Restoring nodes-1 ==="

  $NODE2_SSH "sudo bash" << 'NODE2'
files=(
  /var/lib/kubelet/kubelet-config.yaml
  /var/lib/kube-proxy/kube-proxy-config.yaml
  /etc/cni/net.d/10-bridge.conf
)

for file in "${files[@]}"; do
  if [ -f "${file}.break-backup" ]; then
    cp "${file}.break-backup" "$file"
    echo "  Restored: $file"
  fi
done

# Restore CNI config if hidden
if [ -f /etc/cni/net.d/10-bridge.conf.hidden ]; then
  mv /etc/cni/net.d/10-bridge.conf.hidden /etc/cni/net.d/10-bridge.conf
  echo "  Unhidden: /etc/cni/net.d/10-bridge.conf"
fi

# Clear stale CNI IPAM state in case scenario 16 was used
rm -rf /var/lib/cni/networks/bridge/* 2>/dev/null || true

# Re-enable IP forwarding
sysctl -w net.ipv4.ip_forward=1 > /dev/null

# Re-add cross-node route if missing
if ! ip route | grep -q "10.244.0.0/24"; then
  ip route add 10.244.0.0/24 via 192.168.122.10 2>/dev/null || true
  echo "  Re-added route: 10.244.0.0/24 via 192.168.122.10"
fi

systemctl enable containerd kubelet kube-proxy 2>/dev/null || true
systemctl restart containerd
sleep 2
systemctl restart kubelet
systemctl restart kube-proxy
NODE2

  echo ""
  echo "=== Reset complete. Waiting 15 seconds for both nodes to stabilize... ==="
  sleep 15

  echo ""
  echo "=== Service status ==="
  echo "controlplane-1:"
  $NODE1_SSH 'for svc in etcd kube-apiserver kube-controller-manager kube-scheduler containerd kubelet kube-proxy; do printf "  %-30s %s\n" "$svc" "$(systemctl is-active $svc 2>/dev/null)"; done'
  echo ""
  echo "nodes-1:"
  $NODE2_SSH 'for svc in containerd kubelet kube-proxy; do printf "  %-30s %s\n" "$svc" "$(systemctl is-active $svc 2>/dev/null)"; done'

  echo ""
  echo "=== Cross-node routes ==="
  echo "controlplane-1: $($NODE1_SSH "ip route | grep '10.244.1' || echo MISSING")"
  echo "nodes-1: $($NODE2_SSH "ip route | grep '10.244.0' || echo MISSING")"

  echo ""
  echo "=== Node status ==="
  $NODE1_SSH 'kubectl get nodes 2>/dev/null' || echo "  apiserver not responding yet"
}

# -------------------------------------------------------------------
# Main
# -------------------------------------------------------------------

main() {
  parse_args "$@"

  case "$ACTION" in
    list)
      list_scenarios
      ;;
    reset)
      reset_all
      exit 0
      ;;
    scenario)
      validate_scenario "$SCENARIO_NUM"
      print_banner "$SCENARIO_NUM"
      "scenario_${SCENARIO_NUM}"
      echo ""
      echo "Break applied. Good luck."
      ;;
  esac
}

main "$@"
