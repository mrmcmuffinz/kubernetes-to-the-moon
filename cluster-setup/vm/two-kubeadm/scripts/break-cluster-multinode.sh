#!/usr/bin/env bash
#
# break-cluster-multinode.sh
#
# Introduces a single fault into the two-node Kubernetes cluster for
# troubleshooting practice. Run from the QEMU host. The script SSHes into
# either controlplane-1 or nodes-1 to apply the break.
#
# This is the multi-node companion to break-cluster.sh. The single-node script
# focuses on manual systemd-unit and binary misconfigurations. This script
# covers kubeadm-style cluster operations: join token issues, kubelet config
# drift, CNI failures across nodes, kube-proxy issues, certificate problems
# on the control plane, drain/cordon edge cases, and bridge networking faults.
#
# Usage:
#   ./break-cluster-multinode.sh           # Pick a random scenario
#   ./break-cluster-multinode.sh 5         # Run scenario 5 specifically
#   ./break-cluster-multinode.sh --list    # Show how many scenarios are available
#   ./break-cluster-multinode.sh --reset   # Restore both nodes to working state
#
# Configuration:
#   Set NODE1_SSH and NODE2_SSH to override the default SSH commands.
#   Defaults assume "ssh controlplane-1" and "ssh nodes-1" work via ~/.ssh/config.
#
# After running, SSH into either node and use kubectl, systemctl, journalctl,
# and your knowledge of the cluster to diagnose and fix the problem.

set -euo pipefail

TOTAL_SCENARIOS=15

# -------------------------------------------------------------------
# SSH configuration
# -------------------------------------------------------------------
NODE1_SSH="${NODE1_SSH:-ssh controlplane-1}"
NODE2_SSH="${NODE2_SSH:-ssh nodes-1}"

run_on() {
  local node="$1"
  shift
  case "$node" in
    controlplane-1) $NODE1_SSH sudo bash <<EOF
$*
EOF
    ;;
    nodes-1) $NODE2_SSH sudo bash <<EOF
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
    break-cluster-multinode.sh - Introduce faults into two-node kubeadm Kubernetes cluster

SYNOPSIS
    ./break-cluster-multinode.sh [OPTION | SCENARIO]

DESCRIPTION
    Introduces a single controlled fault into your two-node, kubeadm-installed
    Kubernetes cluster for troubleshooting practice. Run this from the QEMU host.
    The script SSHes into either controlplane-1 or nodes-1 to apply the break.

    This variant covers kubeadm cluster operations across two nodes: join token
    issues, kubelet config drift, CNI failures, kube-proxy issues, certificate
    problems, and bridge networking faults.

OPTIONS
    -h, --help
        Display this help message and exit.

    --list
        Show how many scenarios are available without spoilers.

    --reset
        Restore all cluster components to working state. This reverses any
        changes made by previous scenario runs.

    SCENARIO
        A number between 1 and 15. If omitted, picks a random scenario.

CONFIGURATION
    NODE1_SSH
        SSH command for controlplane-1. Default: ssh controlplane-1

    NODE2_SSH
        SSH command for nodes-1. Default: ssh nodes-1

    Examples:
        export NODE1_SSH="ssh kube@192.168.100.10"
        export NODE2_SSH="ssh kube@192.168.100.11"

EXAMPLES
    Run a random scenario:
        ./break-cluster-multinode.sh

    Run scenario 8 specifically:
        ./break-cluster-multinode.sh 8

    List available scenarios:
        ./break-cluster-multinode.sh --list

    Reset cluster to working state:
        ./break-cluster-multinode.sh --reset

    SSH into either node:
        ssh controlplane-1    # control plane
        ssh nodes-1    # worker

DIAGNOSTIC COMMANDS
    After a scenario runs, SSH into either node and diagnose the problem:

        kubectl get nodes -o wide
        kubectl get pods -A -o wide
        kubectl describe node <name>
        ssh controlplane-1 'sudo systemctl status kubelet containerd'
        ssh nodes-1 'sudo systemctl status kubelet containerd'
        ssh controlplane-1 'sudo journalctl -u kubelet -n 50'
        ssh nodes-1 'sudo journalctl -u kubelet -n 50'

SCENARIO CATEGORIES
    1-3:   Single-node configuration failures (kubelet, containerd)
    4-7:   Cluster-level resource failures (DaemonSet, Deployment)
    8-15:  Multi-node operational issues (cordon, policy, routing)

FILES
    controlplane-1:
        /etc/kubernetes/manifests/kube-apiserver.yaml
        /etc/kubernetes/manifests/etcd.yaml

    nodes-1:
        /etc/kubernetes/kubelet.conf
        /var/lib/kubelet/config.yaml
        /etc/hosts

EXIT STATUS
    0   Success
    1   Invalid scenario number or other error

SEE ALSO
    kubectl(1), systemctl(1), journalctl(1), crictl(1), kubeadm(1)
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
  echo "  Multi-Node Cluster Break Scenario #${scenario}"
  echo "============================================="
  echo ""
  echo "Something has been broken in your cluster."
  echo "SSH into either node and use kubectl, systemctl,"
  echo "journalctl, and your knowledge of the cluster"
  echo "to find and fix the problem."
  echo ""
  echo "  ssh controlplane-1    # control plane"
  echo "  ssh nodes-1    # worker"
  echo ""
  echo "Diagnostic starting points:"
  echo "  kubectl get nodes -o wide"
  echo "  kubectl get pods -A -o wide"
  echo "  kubectl describe node <name>"
  echo "  ssh controlplane-1 'sudo systemctl status kubelet containerd'"
  echo "  ssh nodes-1 'sudo systemctl status kubelet containerd'"
  echo "  ssh controlplane-1 'sudo journalctl -u kubelet -n 50'"
  echo ""
  echo "To reset: $0 --reset"
  echo "============================================="
}

list_scenarios() {
  echo "$TOTAL_SCENARIOS scenarios available."
  echo "Usage: $0 [1-$TOTAL_SCENARIOS] or $0 for random."
  exit 0
}

# -------------------------------------------------------------------
# Scenarios
# -------------------------------------------------------------------

# Difficulty: Beginner | Concept: kubelet kubeconfig server URL | Symptom: nodes-1 goes NotReady; kubelet cannot reach API server
scenario_1() {
  backup_if_needed nodes-1 /etc/kubernetes/kubelet.conf
  run_on nodes-1 "sed -i 's|server: https://192.168.100.10:6443|server: https://192.168.100.10:7777|' /etc/kubernetes/kubelet.conf && systemctl restart kubelet" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: cgroup driver consistency | Symptom: nodes-1 NotReady; kubelet logs show cgroup errors, containers fail to start
scenario_2() {
  backup_if_needed nodes-1 /var/lib/kubelet/config.yaml
  run_on nodes-1 "sed -i 's|cgroupDriver: systemd|cgroupDriver: cgroupfs|' /var/lib/kubelet/config.yaml && systemctl restart kubelet" 2>/dev/null || true
}

# Difficulty: Beginner | Concept: container runtime service state | Symptom: nodes-1 drops to NotReady; all running containers on that node stop
scenario_3() {
  run_on nodes-1 "systemctl stop containerd" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: DaemonSet image reference | Symptom: kube-proxy pods CrashLoopBackOff; all Service ClusterIPs stop routing
scenario_4() {
  $NODE1_SSH "kubectl -n kube-system patch daemonset kube-proxy --type='json' -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/image\",\"value\":\"registry.k8s.io/kube-proxy:v9.99.99\"}]'" 2>/dev/null || true
}

# Difficulty: Advanced | Concept: API server advertise address | Symptom: static pod restarts; workers lose API connectivity; new joins fail
scenario_5() {
  backup_if_needed controlplane-1 /etc/kubernetes/manifests/kube-apiserver.yaml
  run_on controlplane-1 "sed -i 's|--advertise-address=192.168.100.10|--advertise-address=192.168.100.99|' /etc/kubernetes/manifests/kube-apiserver.yaml" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: CNI DaemonSet image reference | Symptom: calico-node pods crash; cross-node pod traffic fails; nodes may go NotReady
scenario_6() {
  $NODE1_SSH "kubectl -n calico-system patch daemonset calico-node --type='json' -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/image\",\"value\":\"docker.io/calico/node:v9.99.99\"}]'" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: pod scheduling node selector | Symptom: CoreDNS pods stay Pending; all cluster DNS lookups time out
scenario_7() {
  $NODE1_SSH "kubectl -n kube-system patch deployment coredns --type='json' -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/nodeSelector\",\"value\":{\"disktype\":\"ssd-fast\"}}]'" 2>/dev/null || true
}

# Difficulty: Beginner | Concept: node scheduling state (cordon) | Symptom: new pods refuse to schedule on nodes-1; existing pods keep running
scenario_8() {
  $NODE1_SSH "kubectl cordon nodes-1" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: staticPodPath in kubelet config | Symptom: nodes-1 kubelet restarts; static pods on worker are not managed correctly
scenario_9() {
  backup_if_needed nodes-1 /var/lib/kubelet/config.yaml
  run_on nodes-1 "sed -i 's|staticPodPath: /etc/kubernetes/manifests|staticPodPath: /etc/kubernetes/no-such-dir|' /var/lib/kubelet/config.yaml && systemctl restart kubelet" 2>/dev/null || true
}

# Difficulty: Advanced | Concept: etcd directory permissions | Symptom: etcd pod restarts; API server loses ability to read/write cluster state
scenario_10() {
  run_on controlplane-1 "chmod 000 /var/lib/etcd" 2>/dev/null || true
}

# Difficulty: Advanced | Concept: kube-proxy clusterCIDR | Symptom: Service routing broken cluster-wide; pod IPs still reachable directly
scenario_11() {
  $NODE1_SSH "kubectl -n kube-system get cm kube-proxy -o yaml > /tmp/kp.yaml && sed -i 's|clusterCIDR: 10.244.0.0/16|clusterCIDR: 10.99.0.0/16|' /tmp/kp.yaml && kubectl apply -f /tmp/kp.yaml && kubectl -n kube-system delete pods -l k8s-app=kube-proxy" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: NetworkPolicy deny-all | Symptom: all pods in default namespace unreachable from inside the cluster
scenario_12() {
  $NODE1_SSH "kubectl apply -f - <<'EOF'
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

# Difficulty: Advanced | Concept: kernel sysctl bridge-nf-call-iptables | Symptom: pods on nodes-1 cannot reach Service ClusterIPs; pod IPs still work
scenario_13() {
  run_on nodes-1 "sysctl -w net.bridge.bridge-nf-call-iptables=0" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: /etc/hosts hostname resolution | Symptom: nodes-1 kubelet logs show "no such host" for controlplane-1
scenario_14() {
  backup_if_needed nodes-1 /etc/hosts
  run_on nodes-1 "sed -i '/controlplane-1/d' /etc/hosts" 2>/dev/null || true
}

# Difficulty: Beginner | Concept: kubeadm join token validity | Symptom: no immediate visible symptom; cluster is normal but no worker can re-join
scenario_15() {
  $NODE1_SSH "kubeadm token list -o jsonpath='{range .items[*]}{.token}{\"\n\"}{end}' | xargs -I {} kubeadm token delete {}" 2>/dev/null || true
}

# -------------------------------------------------------------------
# Reset function
# -------------------------------------------------------------------
reset_all() {
  echo "=== Restoring both nodes ==="

  # Restore backed-up files on nodes-1
  $NODE2_SSH "sudo bash" <<'REMOTE'
files=(
  /etc/kubernetes/kubelet.conf
  /var/lib/kubelet/config.yaml
  /etc/hosts
)
for file in "${files[@]}"; do
  if [ -f "${file}.break-backup" ]; then
    cp "${file}.break-backup" "$file"
    echo "  Restored: $file"
  fi
done
sysctl -w net.bridge.bridge-nf-call-iptables=1 >/dev/null 2>&1 || true
systemctl start containerd 2>/dev/null || true
systemctl restart kubelet
REMOTE

  # Restore backed-up files on controlplane-1
  $NODE1_SSH "sudo bash" <<'REMOTE'
files=(
  /etc/kubernetes/manifests/kube-apiserver.yaml
)
for file in "${files[@]}"; do
  if [ -f "${file}.break-backup" ]; then
    cp "${file}.break-backup" "$file"
    echo "  Restored: $file"
  fi
done
chmod 700 /var/lib/etcd 2>/dev/null || true
systemctl restart kubelet
REMOTE

  # Cluster-side resets
  $NODE1_SSH "kubectl -n kube-system patch daemonset kube-proxy --type='json' -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/image\",\"value\":\"registry.k8s.io/kube-proxy:v1.35.3\"}]'" 2>/dev/null || true
  $NODE1_SSH "kubectl -n calico-system patch daemonset calico-node --type='json' -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/image\",\"value\":\"docker.io/calico/node:v3.31.0\"}]'" 2>/dev/null || true
  $NODE1_SSH "kubectl -n kube-system patch deployment coredns --type='json' -p='[{\"op\":\"remove\",\"path\":\"/spec/template/spec/nodeSelector\"}]'" 2>/dev/null || true
  $NODE1_SSH "kubectl uncordon controlplane-1 nodes-1" 2>/dev/null || true
  $NODE1_SSH "kubectl delete networkpolicy -n default deny-everything-break" 2>/dev/null || true

  # Restore kube-proxy clusterCIDR
  $NODE1_SSH "kubectl -n kube-system get cm kube-proxy -o yaml | sed 's|clusterCIDR: 10.99.0.0/16|clusterCIDR: 10.244.0.0/16|' | kubectl apply -f - && kubectl -n kube-system delete pods -l k8s-app=kube-proxy" 2>/dev/null || true

  echo ""
  echo "=== Waiting 15 seconds for components to stabilize... ==="
  sleep 15

  echo ""
  echo "=== Cluster status ==="
  $NODE1_SSH "kubectl get nodes -o wide" 2>/dev/null || echo "  apiserver not yet ready"
  echo ""
  $NODE1_SSH "kubectl get pods -A | grep -Ev 'Running|Completed'" 2>/dev/null || echo "  (all pods Running)"
  echo ""
  echo "If components are still not Ready after a minute, check:"
  echo "  ssh controlplane-1 'sudo systemctl status kubelet'"
  echo "  ssh nodes-1 'sudo systemctl status kubelet'"
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
