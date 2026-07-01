#!/usr/bin/env bash
#
# break-cluster-multinode.sh
#
# Introduces a single fault into the three-node Kubernetes cluster for
# troubleshooting practice. Run from the QEMU host. The script SSHes into
# one of the three nodes to apply the break.
#
# Usage:
#   ./break-cluster-multinode.sh           # Pick a random scenario
#   ./break-cluster-multinode.sh 5         # Run scenario 5 specifically
#   ./break-cluster-multinode.sh --list    # Show available scenarios
#   ./break-cluster-multinode.sh --reset   # Restore all nodes to working state
#
# Configuration:
#   Set CP_SSH, W1_SSH, W2_SSH to override the default SSH commands.
#   Defaults assume "ssh controlplane-1", "ssh nodes-1", "ssh nodes-2"
#   resolve via ~/.ssh/config.

set -euo pipefail

TOTAL_SCENARIOS=18

# -------------------------------------------------------------------
# SSH configuration
# -------------------------------------------------------------------
CP_SSH="${CP_SSH:-ssh controlplane-1}"
W1_SSH="${W1_SSH:-ssh nodes-1}"
W2_SSH="${W2_SSH:-ssh nodes-2}"

run_on() {
  local node="$1"
  shift
  case "$node" in
    controlplane-1) $CP_SSH sudo bash <<EOF
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
    *) echo "Unknown node: $node" >&2; return 1 ;;
  esac
}

backup_if_needed() {
  local node="$1"
  local file="$2"
  run_on "$node" "if [ -f '$file' ] && [ ! -f '${file}.break-backup' ]; then cp '$file' '${file}.break-backup'; fi"
}

# -------------------------------------------------------------------
# Help and Argument Parsing
# -------------------------------------------------------------------
show_help() {
  cat <<'EOF'
NAME
    break-cluster-multinode.sh - Introduce faults into three-node kubeadm cluster

SYNOPSIS
    ./break-cluster-multinode.sh [OPTION | SCENARIO]

DESCRIPTION
    Introduces a single controlled fault into your three-node kubeadm Kubernetes
    cluster for troubleshooting practice. Run from the QEMU host.

OPTIONS
    -h, --help      Display this help message.
    --list          Show available scenarios without spoilers.
    --reset         Restore all nodes to working state.
    SCENARIO        A number 1-18. Omit for random.

SCENARIO CATEGORIES
    1-5:   Control plane failures (controlplane-1)
    6-10:  Single worker failures (nodes-1 or nodes-2)
    11-15: Cluster-resource failures (DaemonSet, Deployment, NetworkPolicy)
    16-18: Multi-node operational (cordon, drain, token)

DIAGNOSTIC COMMANDS
    kubectl get nodes -o wide
    kubectl get pods -A -o wide
    ssh controlplane-1 'sudo journalctl -u kubelet -n 50'
    ssh nodes-1 'sudo systemctl status kubelet containerd'
    ssh nodes-2 'sudo systemctl status kubelet containerd'
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
  local scenario="$1"
  if [[ "$scenario" -lt 1 || "$scenario" -gt "$TOTAL_SCENARIOS" ]]; then
    echo "ERROR: Scenario must be between 1 and $TOTAL_SCENARIOS." >&2
    exit 1
  fi
}

print_banner() {
  local scenario="$1"
  echo "============================================="
  echo "  Three-Node Cluster Break Scenario #${scenario}"
  echo "============================================="
  echo ""
  echo "Something has been broken in your cluster."
  echo "Diagnose and fix it."
  echo ""
  echo "  ssh controlplane-1    # control plane"
  echo "  ssh nodes-1           # worker 1"
  echo "  ssh nodes-2           # worker 2"
  echo ""
  echo "Starting points:"
  echo "  kubectl get nodes -o wide"
  echo "  kubectl get pods -A -o wide"
  echo ""
  echo "To reset: $0 --reset"
  echo "============================================="
}

list_scenarios() {
  echo "$TOTAL_SCENARIOS scenarios available."
  echo "Usage: $0 [1-$TOTAL_SCENARIOS] or $0 for random."
  echo ""
  echo "Categories:"
  echo "  1-5:   Control plane failures"
  echo "  6-10:  Single worker failures"
  echo "  11-15: Cluster-resource failures"
  echo "  16-18: Multi-node operational"
  exit 0
}

# -------------------------------------------------------------------
# Scenarios
# Each scenario has a header: Difficulty | Concept | Symptom
# Difficulty: Beginner = obvious logs / single service
#             Intermediate = cross-component reasoning required
#             Advanced = subtle, non-obvious symptom
# -------------------------------------------------------------------

# --- Control plane scenarios ---

# Difficulty: Beginner | Concept: etcd data directory path in static pod manifest | Symptom: etcd pod crashes; API server loses cluster state
scenario_1() {
  backup_if_needed controlplane-1 /etc/kubernetes/manifests/etcd.yaml
  run_on controlplane-1 "sed -i 's|--data-dir=/var/lib/etcd|--data-dir=/var/lib/etcd-bad|' /etc/kubernetes/manifests/etcd.yaml"
}

# Difficulty: Beginner | Concept: API server TLS cert path | Symptom: apiserver pod fails to start; logs show "no such file"
scenario_2() {
  backup_if_needed controlplane-1 /etc/kubernetes/manifests/kube-apiserver.yaml
  run_on controlplane-1 "sed -i 's|--tls-cert-file=/etc/kubernetes/pki/apiserver.crt|--tls-cert-file=/etc/kubernetes/pki/missing.crt|' /etc/kubernetes/manifests/kube-apiserver.yaml"
}

# Difficulty: Intermediate | Concept: controller-manager kubeconfig path | Symptom: API server up; deployments stop reconciling; pods not replaced
scenario_3() {
  backup_if_needed controlplane-1 /etc/kubernetes/manifests/kube-controller-manager.yaml
  run_on controlplane-1 "sed -i 's|--kubeconfig=/etc/kubernetes/controller-manager.conf|--kubeconfig=/etc/kubernetes/wrong.conf|' /etc/kubernetes/manifests/kube-controller-manager.yaml"
}

# Difficulty: Advanced | Concept: service CIDR in API server | Symptom: existing services work; new services get wrong ClusterIPs
scenario_4() {
  backup_if_needed controlplane-1 /etc/kubernetes/manifests/kube-apiserver.yaml
  run_on controlplane-1 "sed -i 's|--service-cluster-ip-range=10.96.0.0/16|--service-cluster-ip-range=10.99.0.0/16|' /etc/kubernetes/manifests/kube-apiserver.yaml"
}

# Difficulty: Advanced | Concept: etcd data directory permissions | Symptom: etcd pod crashes; API server loses ability to read/write state
scenario_5() {
  run_on controlplane-1 "chmod 000 /var/lib/etcd"
}

# --- Single worker failures ---

# Difficulty: Beginner | Concept: kubelet kubeconfig server URL on nodes-1 | Symptom: nodes-1 goes NotReady; controlplane-1 and nodes-2 unaffected
scenario_6() {
  backup_if_needed nodes-1 /etc/kubernetes/kubelet.conf
  run_on nodes-1 "sed -i 's|server: https://192.168.100.10:6443|server: https://192.168.100.10:7777|' /etc/kubernetes/kubelet.conf && systemctl restart kubelet"
}

# Difficulty: Beginner | Concept: container runtime service state on nodes-2 | Symptom: nodes-2 drops to NotReady; all containers on nodes-2 stop
scenario_7() {
  run_on nodes-2 "systemctl stop containerd"
}

# Difficulty: Intermediate | Concept: cgroup driver mismatch on nodes-1 | Symptom: nodes-1 NotReady; kubelet logs show cgroup errors; new pods cannot start
scenario_8() {
  backup_if_needed nodes-1 /var/lib/kubelet/config.yaml
  run_on nodes-1 "sed -i 's|cgroupDriver: systemd|cgroupDriver: cgroupfs|' /var/lib/kubelet/config.yaml && systemctl restart kubelet"
}

# Difficulty: Intermediate | Concept: CRI socket path on nodes-2 | Symptom: nodes-2 NotReady; kubelet logs "failed to connect to container runtime"
scenario_9() {
  backup_if_needed nodes-2 /var/lib/kubelet/config.yaml
  run_on nodes-2 "sed -i 's|containerRuntimeEndpoint: unix:///run/containerd/containerd.sock|containerRuntimeEndpoint: unix:///run/containerd/wrong.sock|' /var/lib/kubelet/config.yaml && systemctl restart kubelet"
}

# Difficulty: Advanced | Concept: sysctl bridge-nf-call-iptables on nodes-2 | Symptom: pods on nodes-2 cannot reach Service ClusterIPs; pod IPs still work
scenario_10() {
  run_on nodes-2 "sysctl -w net.bridge.bridge-nf-call-iptables=0"
}

# --- Cluster-resource failures ---

# Difficulty: Intermediate | Concept: DaemonSet image reference | Symptom: kube-proxy pods CrashLoopBackOff; Service routing broken cluster-wide
scenario_11() {
  $CP_SSH "kubectl -n kube-system patch daemonset kube-proxy --type='json' \
    -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/image\",\"value\":\"registry.k8s.io/kube-proxy:v9.99.99\"}]'" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: CNI DaemonSet image reference | Symptom: calico-node pods crash; cross-node pod traffic fails
scenario_12() {
  $CP_SSH "kubectl -n calico-system patch daemonset calico-node --type='json' \
    -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/image\",\"value\":\"docker.io/calico/node:v9.99.99\"}]'" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: NetworkPolicy deny-all | Symptom: all pods in default namespace unreachable from inside the cluster
scenario_13() {
  $CP_SSH "kubectl apply -f - <<'EOF'
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

# Difficulty: Advanced | Concept: kube-proxy clusterCIDR | Symptom: Service routing broken cluster-wide; pod IPs still reachable directly
scenario_14() {
  $CP_SSH "kubectl -n kube-system get cm kube-proxy -o yaml > /tmp/kp.yaml \
    && sed -i 's|clusterCIDR: 10.244.0.0/16|clusterCIDR: 10.99.0.0/16|' /tmp/kp.yaml \
    && kubectl apply -f /tmp/kp.yaml \
    && kubectl -n kube-system delete pods -l k8s-app=kube-proxy" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: pod scheduling node selector | Symptom: CoreDNS pods stay Pending; all cluster DNS lookups time out
scenario_15() {
  $CP_SSH "kubectl -n kube-system patch deployment coredns --type='json' \
    -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/nodeSelector\",\"value\":{\"disktype\":\"ssd-fast\"}}]'" 2>/dev/null || true
}

# --- Multi-node operational ---

# Difficulty: Beginner | Concept: node scheduling state (cordon) | Symptom: new pods refused on nodes-1; existing pods keep running
scenario_16() {
  $CP_SSH "kubectl cordon nodes-1" 2>/dev/null || true
}

# Difficulty: Beginner | Concept: node scheduling state (cordon) | Symptom: new pods refused on nodes-2; existing pods keep running
scenario_17() {
  $CP_SSH "kubectl cordon nodes-2" 2>/dev/null || true
}

# Difficulty: Beginner | Concept: kubeadm join token validity | Symptom: no immediate visible symptom; no new worker can join the cluster
scenario_18() {
  $CP_SSH "kubeadm token list -o jsonpath='{range .items[*]}{.token}{\"\n\"}{end}' \
    | xargs -I {} kubeadm token delete {}" 2>/dev/null || true
}

# -------------------------------------------------------------------
# Reset function
# -------------------------------------------------------------------
reset_all() {
  echo "=== Restoring all nodes ==="

  # Restore nodes-1
  $W1_SSH "sudo bash" <<'REMOTE'
for f in /etc/kubernetes/kubelet.conf /var/lib/kubelet/config.yaml /etc/hosts; do
  [ -f "${f}.break-backup" ] && cp "${f}.break-backup" "$f" && echo "  Restored: $f"
done
sysctl -w net.bridge.bridge-nf-call-iptables=1 >/dev/null 2>&1 || true
systemctl start containerd 2>/dev/null || true
systemctl restart kubelet
REMOTE

  # Restore nodes-2
  $W2_SSH "sudo bash" <<'REMOTE'
for f in /etc/kubernetes/kubelet.conf /var/lib/kubelet/config.yaml /etc/hosts; do
  [ -f "${f}.break-backup" ] && cp "${f}.break-backup" "$f" && echo "  Restored: $f"
done
sysctl -w net.bridge.bridge-nf-call-iptables=1 >/dev/null 2>&1 || true
systemctl start containerd 2>/dev/null || true
systemctl restart kubelet
REMOTE

  # Restore controlplane-1
  $CP_SSH "sudo bash" <<'REMOTE'
for f in /etc/kubernetes/manifests/etcd.yaml \
         /etc/kubernetes/manifests/kube-apiserver.yaml \
         /etc/kubernetes/manifests/kube-controller-manager.yaml \
         /etc/kubernetes/manifests/kube-scheduler.yaml; do
  [ -f "${f}.break-backup" ] && cp "${f}.break-backup" "$f" && echo "  Restored: $f"
done
chmod 700 /var/lib/etcd 2>/dev/null || true
systemctl restart kubelet
REMOTE

  # Cluster-side resets
  $CP_SSH "kubectl -n kube-system patch daemonset kube-proxy --type='json' \
    -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/image\",\"value\":\"registry.k8s.io/kube-proxy:v1.35.3\"}]'" 2>/dev/null || true
  $CP_SSH "kubectl -n calico-system patch daemonset calico-node --type='json' \
    -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/image\",\"value\":\"docker.io/calico/node:v3.31.0\"}]'" 2>/dev/null || true
  $CP_SSH "kubectl -n kube-system patch deployment coredns --type='json' \
    -p='[{\"op\":\"remove\",\"path\":\"/spec/template/spec/nodeSelector\"}]'" 2>/dev/null || true
  $CP_SSH "kubectl uncordon controlplane-1 nodes-1 nodes-2" 2>/dev/null || true
  $CP_SSH "kubectl delete networkpolicy -n default deny-everything-break" 2>/dev/null || true
  $CP_SSH "kubectl -n kube-system get cm kube-proxy -o yaml \
    | sed 's|clusterCIDR: 10.99.0.0/16|clusterCIDR: 10.244.0.0/16|' \
    | kubectl apply -f - \
    && kubectl -n kube-system delete pods -l k8s-app=kube-proxy" 2>/dev/null || true

  echo ""
  echo "=== Waiting 20 seconds for components to stabilize... ==="
  sleep 20

  echo ""
  echo "=== Cluster status ==="
  $CP_SSH "kubectl get nodes -o wide" 2>/dev/null || echo "  apiserver not yet ready"
  echo ""
  $CP_SSH "kubectl get pods -A | grep -Ev 'Running|Completed'" 2>/dev/null || echo "  (all pods Running)"
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
