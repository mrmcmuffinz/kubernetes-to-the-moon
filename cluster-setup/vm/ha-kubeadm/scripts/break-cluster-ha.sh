#!/usr/bin/env bash
#
# break-cluster-ha.sh
#
# Introduces a single fault into the HA Kubernetes cluster for troubleshooting
# practice. This script covers HA-specific failure modes: load balancer config,
# etcd quorum, second control plane, and multi-node operational issues.
#
# Usage:
#   ./break-cluster-ha.sh           # Pick a random scenario
#   ./break-cluster-ha.sh 5         # Run scenario 5 specifically
#   ./break-cluster-ha.sh --list    # Show available scenarios
#   ./break-cluster-ha.sh --reset   # Restore all nodes to working state
#
# Configuration:
#   Set CP1_SSH, CP2_SSH, W1_SSH, W2_SSH, W3_SSH to override SSH commands.
#   Defaults assume ~/.ssh/config has entries for each hostname.

set -euo pipefail

TOTAL_SCENARIOS=15

CP1_SSH="${CP1_SSH:-ssh controlplane-1}"
CP2_SSH="${CP2_SSH:-ssh controlplane-2}"
W1_SSH="${W1_SSH:-ssh nodes-1}"
W2_SSH="${W2_SSH:-ssh nodes-2}"
W3_SSH="${W3_SSH:-ssh nodes-3}"

run_on() {
  local node="$1"
  shift
  case "$node" in
    controlplane-1) $CP1_SSH sudo bash <<EOF
$*
EOF
    ;;
    controlplane-2) $CP2_SSH sudo bash <<EOF
$*
EOF
    ;;
    nodes-1) $W1_SSH sudo bash <<EOF
$*
EOF
    ;;
    nodes-2) $W2_SSH sudo bash <<EOF
$*
EOF
    ;;
    nodes-3) $W3_SSH sudo bash <<EOF
$*
EOF
    ;;
    *) echo "Unknown node: $node" >&2; return 1 ;;
  esac
}

backup_if_needed() {
  local node="$1"
  local file="$2"
  run_on "$node" "if [ -f '$file' ] && [ ! -f '${file}.break-backup' ]; then cp '$file' '${file}.break-backup'; fi"
}

show_help() {
  cat <<'EOF'
NAME
    break-cluster-ha.sh - Introduce faults into five-node HA kubeadm cluster

SYNOPSIS
    ./break-cluster-ha.sh [OPTION | SCENARIO]

DESCRIPTION
    Introduces controlled faults into the HA cluster for troubleshooting practice.
    Scenarios cover HA-specific failures: HAProxy, etcd quorum, second control plane,
    and multi-node operational issues.

SCENARIO CATEGORIES
    1-4:   HAProxy and VIP failures (host-side)
    5-8:   etcd and control plane HA failures
    9-12:  Worker node failures
    13-15: Cluster-resource failures
EOF
  exit 0
}

parse_args() {
  [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && show_help
  if [[ "${1:-}" == "--list" ]]; then ACTION="list"; return; fi
  if [[ "${1:-}" == "--reset" ]]; then ACTION="reset"; return; fi
  if [[ -n "${1:-}" ]]; then
    SCENARIO_NUM="$1"
  else
    SCENARIO_NUM=$(( (RANDOM % TOTAL_SCENARIOS) + 1 ))
  fi
  ACTION="scenario"
}

validate_scenario() {
  if [[ "$1" -lt 1 || "$1" -gt "$TOTAL_SCENARIOS" ]]; then
    echo "ERROR: Scenario must be 1-$TOTAL_SCENARIOS." >&2; exit 1
  fi
}

print_banner() {
  echo "============================================="
  echo "  HA Cluster Break Scenario #${1}"
  echo "============================================="
  echo ""
  echo "Something has been broken in your HA cluster."
  echo ""
  echo "  kubectl get nodes -o wide"
  echo "  curl -sk https://192.168.100.100:6443/healthz"
  echo "  curl -su admin:admin http://192.168.100.1:9000/stats"
  echo ""
  echo "To reset: $0 --reset"
  echo "============================================="
}

list_scenarios() {
  echo "$TOTAL_SCENARIOS scenarios available."
  echo "  1-4:   HAProxy/VIP failures"
  echo "  5-8:   etcd/control plane HA failures"
  echo "  9-12:  Worker node failures"
  echo "  13-15: Cluster-resource failures"
  exit 0
}

# -------------------------------------------------------------------
# Scenarios
# Each has: Difficulty | Concept | Symptom
# -------------------------------------------------------------------

# --- HAProxy and VIP failures (host-side) ---

# Difficulty: Beginner | Concept: HAProxy service state | Symptom: VIP stops responding; kubectl fails; direct node access still works
scenario_1() {
  sudo systemctl stop haproxy
}

# Difficulty: Intermediate | Concept: HAProxy backend IP misconfiguration | Symptom: VIP connects but API returns TLS errors; direct access still works
scenario_2() {
  sudo sed -i 's|server controlplane-1 192.168.100.20:6443|server controlplane-1 192.168.100.20:9999|' \
    /etc/haproxy/haproxy.cfg
  sudo systemctl reload haproxy
}

# Difficulty: Advanced | Concept: VIP address removed from host bridge | Symptom: VIP unreachable; direct control plane access still works; kubectl fails
scenario_3() {
  sudo ip addr del 192.168.100.100/32 dev br-vm 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: HAProxy frontend port | Symptom: HAProxy runs but VIP port is wrong; all kubectl commands fail
scenario_4() {
  sudo sed -i 's|bind 192.168.100.100:6443|bind 192.168.100.100:6444|' /etc/haproxy/haproxy.cfg
  sudo systemctl reload haproxy
}

# --- etcd and HA control plane failures ---

# Difficulty: Advanced | Concept: etcd quorum (two-member cluster) | Symptom: reads work; writes fail; cluster appears healthy but hangs on create
scenario_5() {
  backup_if_needed controlplane-2 /etc/kubernetes/manifests/etcd.yaml
  run_on controlplane-2 "mv /etc/kubernetes/manifests/etcd.yaml /tmp/etcd.yaml.hidden"
}

# Difficulty: Intermediate | Concept: second API server advertise address | Symptom: controlplane-2 API server crashes; controlplane-1 still handles traffic
scenario_6() {
  backup_if_needed controlplane-2 /etc/kubernetes/manifests/kube-apiserver.yaml
  run_on controlplane-2 "sed -i 's|--advertise-address=192.168.100.21|--advertise-address=192.168.100.99|' \
    /etc/kubernetes/manifests/kube-apiserver.yaml"
}

# Difficulty: Advanced | Concept: etcd data directory permissions on controlplane-1 | Symptom: controlplane-1 etcd crashes; quorum lost; cluster read-only
scenario_7() {
  run_on controlplane-1 "chmod 000 /var/lib/etcd"
}

# Difficulty: Intermediate | Concept: controller-manager leader election kubeconfig | Symptom: controller-manager on controlplane-1 fails; controlplane-2 takes over election
scenario_8() {
  backup_if_needed controlplane-1 /etc/kubernetes/manifests/kube-controller-manager.yaml
  run_on controlplane-1 "sed -i 's|--kubeconfig=/etc/kubernetes/controller-manager.conf|--kubeconfig=/etc/kubernetes/wrong.conf|' \
    /etc/kubernetes/manifests/kube-controller-manager.yaml"
}

# --- Worker node failures ---

# Difficulty: Beginner | Concept: kubelet kubeconfig server URL | Symptom: nodes-1 goes NotReady; other workers unaffected
scenario_9() {
  backup_if_needed nodes-1 /etc/kubernetes/kubelet.conf
  run_on nodes-1 "sed -i 's|server: https://192.168.100.100:6443|server: https://192.168.100.100:7777|' \
    /etc/kubernetes/kubelet.conf && systemctl restart kubelet"
}

# Difficulty: Beginner | Concept: container runtime stopped | Symptom: nodes-2 drops to NotReady; containers on nodes-2 stop
scenario_10() {
  run_on nodes-2 "systemctl stop containerd"
}

# Difficulty: Intermediate | Concept: CRI socket path mismatch | Symptom: nodes-3 NotReady; kubelet logs "failed to connect to container runtime"
scenario_11() {
  backup_if_needed nodes-3 /var/lib/kubelet/config.yaml
  run_on nodes-3 "sed -i 's|containerRuntimeEndpoint: unix:///run/containerd/containerd.sock|containerRuntimeEndpoint: unix:///run/containerd/wrong.sock|' \
    /var/lib/kubelet/config.yaml && systemctl restart kubelet"
}

# Difficulty: Advanced | Concept: sysctl on worker | Symptom: pods on nodes-3 cannot reach Service ClusterIPs; pod IPs still reachable
scenario_12() {
  run_on nodes-3 "sysctl -w net.bridge.bridge-nf-call-iptables=0"
}

# --- Cluster-resource failures ---

# Difficulty: Intermediate | Concept: DaemonSet image reference | Symptom: kube-proxy CrashLoopBackOff on all nodes; Service routing breaks
scenario_13() {
  $CP1_SSH "kubectl -n kube-system patch daemonset kube-proxy --type='json' \
    -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/image\",\"value\":\"registry.k8s.io/kube-proxy:v9.99.99\"}]'" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: CNI DaemonSet image | Symptom: calico-node pods crash; cross-node traffic fails
scenario_14() {
  $CP1_SSH "kubectl -n calico-system patch daemonset calico-node --type='json' \
    -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/image\",\"value\":\"docker.io/calico/node:v9.99.99\"}]'" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: NetworkPolicy deny-all | Symptom: all pods in default namespace unreachable from inside cluster
scenario_15() {
  $CP1_SSH "kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-everything-break
  namespace: default
spec:
  podSelector: {}
  policyTypes: [Ingress]
EOF" 2>/dev/null || true
}

# -------------------------------------------------------------------
# Reset function
# -------------------------------------------------------------------
reset_all() {
  echo "=== Restoring HA cluster ==="

  # Restore HAProxy
  echo "--- Restoring HAProxy ---"
  sudo sed -i 's|server controlplane-1 192.168.100.20:9999|server controlplane-1 192.168.100.20:6443|' \
    /etc/haproxy/haproxy.cfg 2>/dev/null || true
  sudo sed -i 's|bind 192.168.100.100:6444|bind 192.168.100.100:6443|' \
    /etc/haproxy/haproxy.cfg 2>/dev/null || true
  sudo ip addr add 192.168.100.100/32 dev br-vm 2>/dev/null || true
  sudo systemctl start haproxy 2>/dev/null || true
  sudo systemctl reload haproxy 2>/dev/null || true

  # Restore controlplane-1
  $CP1_SSH "sudo bash" <<'REMOTE'
for f in /etc/kubernetes/manifests/etcd.yaml \
         /etc/kubernetes/manifests/kube-apiserver.yaml \
         /etc/kubernetes/manifests/kube-controller-manager.yaml; do
  [ -f "${f}.break-backup" ] && cp "${f}.break-backup" "$f" && echo "  Restored: $f"
done
chmod 700 /var/lib/etcd 2>/dev/null || true
systemctl restart kubelet
REMOTE

  # Restore controlplane-2
  $CP2_SSH "sudo bash" <<'REMOTE'
for f in /etc/kubernetes/manifests/etcd.yaml \
         /etc/kubernetes/manifests/kube-apiserver.yaml; do
  [ -f "${f}.break-backup" ] && cp "${f}.break-backup" "$f" && echo "  Restored: $f"
  [ -f "/tmp/etcd.yaml.hidden" ] && mv /tmp/etcd.yaml.hidden /etc/kubernetes/manifests/etcd.yaml && echo "  Restored hidden etcd manifest"
done
systemctl restart kubelet
REMOTE

  # Restore workers
  for W in "$W1_SSH" "$W2_SSH" "$W3_SSH"; do
    $W "sudo bash" <<'REMOTE'
for f in /etc/kubernetes/kubelet.conf /var/lib/kubelet/config.yaml; do
  [ -f "${f}.break-backup" ] && cp "${f}.break-backup" "$f" && echo "  Restored: $f"
done
sysctl -w net.bridge.bridge-nf-call-iptables=1 >/dev/null 2>&1 || true
systemctl start containerd 2>/dev/null || true
systemctl restart kubelet
REMOTE
  done

  # Cluster-side resets
  $CP1_SSH "kubectl -n kube-system patch daemonset kube-proxy --type='json' \
    -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/image\",\"value\":\"registry.k8s.io/kube-proxy:v1.35.3\"}]'" 2>/dev/null || true
  $CP1_SSH "kubectl -n calico-system patch daemonset calico-node --type='json' \
    -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/image\",\"value\":\"docker.io/calico/node:v3.31.0\"}]'" 2>/dev/null || true
  $CP1_SSH "kubectl delete networkpolicy -n default deny-everything-break" 2>/dev/null || true
  $CP1_SSH "kubectl uncordon controlplane-1 controlplane-2 nodes-1 nodes-2 nodes-3" 2>/dev/null || true

  echo ""
  echo "=== Waiting 20 seconds... ==="
  sleep 20

  echo "=== Cluster status ==="
  curl -sk https://192.168.100.100:6443/healthz && echo " (VIP ok)" || echo " (VIP still recovering)"
  $CP1_SSH "kubectl get nodes -o wide" 2>/dev/null || echo "  apiserver not yet ready"
}

# -------------------------------------------------------------------
# Main
# -------------------------------------------------------------------
main() {
  parse_args "$@"
  case "$ACTION" in
    list)     list_scenarios ;;
    reset)    reset_all; exit 0 ;;
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
