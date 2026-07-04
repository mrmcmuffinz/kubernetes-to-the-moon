#!/usr/bin/env bash
#
# break-cluster.sh
#
# Introduces a single fault into the kubeadm-installed single-node Kubernetes
# cluster for troubleshooting practice. Run this from the QEMU host. The script
# SSHes into the VM to apply the break.
#
# Unlike the single-systemd version (which targets systemd unit files), this
# script targets the kubeadm-specific surface: static pod manifests in
# /etc/kubernetes/manifests/, the Tigera operator and Calico installation,
# kubelet config, and apt-pinned package state.
#
# Usage:
#   ./break-cluster.sh          # Pick a random scenario
#   ./break-cluster.sh 3        # Run scenario 3 specifically
#   ./break-cluster.sh --list   # Show how many scenarios are available (no spoilers)
#   ./break-cluster.sh --reset  # Attempt to restore all components to working state
#
# Configuration:
#   Set BREAK_SSH_CMD to override the default SSH command.
#   Example: export BREAK_SSH_CMD="ssh controlplane-1"
#
# After running, SSH into the VM and use kubectl, systemctl, journalctl, crictl,
# and your knowledge of the cluster to diagnose and fix the problem.

set -euo pipefail

TOTAL_SCENARIOS=15

# -------------------------------------------------------------------
# SSH configuration
# Adjust if your SSH config differs.
# If you have a Host entry in ~/.ssh/config, set BREAK_SSH_CMD="ssh controlplane-1".
# -------------------------------------------------------------------
SSH_CMD="${BREAK_SSH_CMD:-ssh -p 2222 kube@127.0.0.1}"

run_on_vm() {
  $SSH_CMD sudo bash <<EOF
$1
EOF
}

# -------------------------------------------------------------------
# Backup helper (runs on VM)
# -------------------------------------------------------------------
backup_if_needed() {
  local file="$1"
  run_on_vm "if [ -f '$file' ] && [ ! -f '${file}.break-backup' ]; then cp '$file' '${file}.break-backup'; fi"
}

# -------------------------------------------------------------------
# Help and Argument Parsing
# -------------------------------------------------------------------
show_help() {
  cat <<'EOF'
NAME
    break-cluster.sh - Introduce faults into single-node kubeadm Kubernetes cluster

SYNOPSIS
    ./break-cluster.sh [OPTION | SCENARIO]

DESCRIPTION
    Introduces a single controlled fault into your single-node, kubeadm-installed
    Kubernetes cluster for troubleshooting practice. Run this from the QEMU host.
    The script SSHes into the VM to apply the break.

    This variant targets kubeadm-specific components: static pod manifests in
    /etc/kubernetes/manifests/, the Tigera operator, Calico installation, kubelet
    config, and containerd configuration.

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
    BREAK_SSH_CMD
        Override the default SSH command. Default: ssh -p 2222 kube@127.0.0.1

        Examples:
            export BREAK_SSH_CMD="ssh controlplane-1"
            export BREAK_SSH_CMD="ssh -p 2222 kube@127.0.0.1"

EXAMPLES
    Run a random scenario:
        ./break-cluster.sh

    Run scenario 5 specifically:
        ./break-cluster.sh 5

    List available scenarios:
        ./break-cluster.sh --list

    Reset cluster to working state:
        ./break-cluster.sh --reset

    SSH into the VM after running a scenario:
        ssh -p 2222 kube@127.0.0.1

DIAGNOSTIC COMMANDS
    After a scenario runs, SSH into the VM and diagnose the problem:

        systemctl status kubelet containerd
        journalctl -u kubelet -n 50
        sudo crictl ps -a
        sudo ls /etc/kubernetes/manifests/
        kubectl get nodes
        kubectl get pods -A
        curl -k https://127.0.0.1:6443/healthz

    Remember: control plane components run as static pods managed by kubelet.
    Changes to manifests in /etc/kubernetes/manifests/ cause automatic pod recreation.

FILES
    /etc/kubernetes/manifests/etcd.yaml
    /etc/kubernetes/manifests/kube-apiserver.yaml
    /etc/kubernetes/manifests/kube-controller-manager.yaml
    /etc/kubernetes/manifests/kube-scheduler.yaml
    /var/lib/kubelet/config.yaml
    /etc/containerd/config.toml
    /etc/cni/net.d/10-calico.conflist

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
  echo "  Cluster Break Scenario #${scenario}"
  echo "  (single-kubeadm)"
  echo "============================================="
  echo ""
  echo "Something has been broken in your cluster."
  echo "SSH into the VM and use kubectl, systemctl,"
  echo "journalctl, crictl, and your knowledge of the"
  echo "cluster to find and fix the problem."
  echo ""
  echo "  ssh -p 2222 kube@127.0.0.1"
  echo ""
  echo "Diagnostic starting points:"
  echo "  systemctl status kubelet containerd"
  echo "  journalctl -u kubelet -n 50"
  echo "  sudo crictl ps -a"
  echo "  sudo ls /etc/kubernetes/manifests/"
  echo "  kubectl get nodes"
  echo "  kubectl get pods -A"
  echo "  curl -k https://127.0.0.1:6443/healthz"
  echo ""
  echo "Remember: control plane components are static pods."
  echo "kubelet recreates them automatically when their"
  echo "manifest in /etc/kubernetes/manifests/ changes."
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
# Each one introduces a different category of failure that maps to a
# CKA-relevant troubleshooting skill.
# -------------------------------------------------------------------

# Difficulty: Beginner | Concept: etcd data directory path in static pod manifest | Symptom: etcd pod crashes; API server loses cluster state
scenario_1() {
  backup_if_needed /etc/kubernetes/manifests/etcd.yaml
  run_on_vm "sed -i 's|--data-dir=/var/lib/etcd|--data-dir=/var/lib/etcd-bad|' /etc/kubernetes/manifests/etcd.yaml" 2>/dev/null || true
}

# Difficulty: Beginner | Concept: etcd endpoint URL in kube-apiserver manifest | Symptom: API server pod restarts; logs show connection refused
scenario_2() {
  backup_if_needed /etc/kubernetes/manifests/kube-apiserver.yaml
  run_on_vm "sed -i 's|--etcd-servers=https://127.0.0.1:2379|--etcd-servers=https://127.0.0.1:9999|' /etc/kubernetes/manifests/kube-apiserver.yaml" 2>/dev/null || true
}

# Difficulty: Beginner | Concept: TLS certificate path in static pod manifest | Symptom: API server pod fails to start; logs show "no such file"
scenario_3() {
  backup_if_needed /etc/kubernetes/manifests/kube-apiserver.yaml
  run_on_vm "sed -i 's|--tls-cert-file=/etc/kubernetes/pki/apiserver.crt|--tls-cert-file=/etc/kubernetes/pki/missing.crt|' /etc/kubernetes/manifests/kube-apiserver.yaml" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: controller-manager kubeconfig path | Symptom: pod stays Running; deployments stop reconciling; failed pods not replaced
scenario_4() {
  backup_if_needed /etc/kubernetes/manifests/kube-controller-manager.yaml
  run_on_vm "sed -i 's|--kubeconfig=/etc/kubernetes/controller-manager.conf|--kubeconfig=/etc/kubernetes/wrong.conf|' /etc/kubernetes/manifests/kube-controller-manager.yaml" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: scheduler kubeconfig path | Symptom: scheduler pod fails; new pods stay Pending indefinitely
scenario_5() {
  backup_if_needed /etc/kubernetes/manifests/kube-scheduler.yaml
  run_on_vm "sed -i 's|--kubeconfig=/etc/kubernetes/scheduler.conf|--kubeconfig=/etc/kubernetes/missing-scheduler.conf|' /etc/kubernetes/manifests/kube-scheduler.yaml" 2>/dev/null || true
}

# Difficulty: Beginner | Concept: kubelet as static pod manager | Symptom: entire control plane disappears; static pods are orphaned
scenario_6() {
  run_on_vm "systemctl stop kubelet && systemctl disable kubelet" 2>/dev/null || true
}

# Difficulty: Advanced | Concept: etcd TLS certificate chain | Symptom: etcd pod restarts but cannot serve TLS; API server x509 errors
scenario_7() {
  backup_if_needed /etc/kubernetes/pki/etcd/ca.crt
  run_on_vm "mv /etc/kubernetes/pki/etcd/ca.crt /etc/kubernetes/pki/etcd/ca.crt.hidden" 2>/dev/null || true
}

# Difficulty: Advanced | Concept: service CIDR consistency | Symptom: API server runs; new services get wrong ClusterIPs; CoreDNS breaks
scenario_8() {
  backup_if_needed /etc/kubernetes/manifests/kube-apiserver.yaml
  run_on_vm "sed -i 's|--service-cluster-ip-range=10.96.0.0/16|--service-cluster-ip-range=10.99.0.0/16|' /etc/kubernetes/manifests/kube-apiserver.yaml" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: cgroup driver consistency | Symptom: node NotReady; new pods cannot start; kubelet logs cgroup errors
scenario_9() {
  backup_if_needed /etc/containerd/config.toml
  run_on_vm "sed -i 's|SystemdCgroup = true|SystemdCgroup = false|' /etc/containerd/config.toml && systemctl restart containerd" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: API server authorization mode | Symptom: API server starts; every kubectl request returns 403 Forbidden
scenario_10() {
  backup_if_needed /etc/kubernetes/manifests/kube-apiserver.yaml
  run_on_vm "sed -i 's|--authorization-mode=Node,RBAC|--authorization-mode=AlwaysDeny|' /etc/kubernetes/manifests/kube-apiserver.yaml" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: CRI socket path in kubelet config | Symptom: node NotReady; kubelet logs "failed to connect to container runtime"
scenario_11() {
  backup_if_needed /var/lib/kubelet/config.yaml
  run_on_vm "sed -i 's|containerRuntimeEndpoint: unix:///run/containerd/containerd.sock|containerRuntimeEndpoint: unix:///run/containerd/wrong.sock|' /var/lib/kubelet/config.yaml && systemctl restart kubelet" 2>/dev/null || true
}

# Difficulty: Beginner | Concept: container runtime service state | Symptom: node drops to NotReady; all running containers stop
scenario_12() {
  run_on_vm "systemctl stop containerd && systemctl disable containerd" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: CNI config file presence | Symptom: node NotReady; pods in ContainerCreating; kubelet logs "no CNI"
scenario_13() {
  run_on_vm "if [ -f /etc/cni/net.d/10-calico.conflist ]; then mv /etc/cni/net.d/10-calico.conflist /etc/cni/net.d/10-calico.conflist.hidden; fi" 2>/dev/null || true
}

# Difficulty: Advanced | Concept: CNI operator lifecycle | Symptom: cluster looks healthy initially; calico-node pods are not recreated if deleted
scenario_14() {
  run_on_vm "kubectl --kubeconfig=/etc/kubernetes/admin.conf scale deployment tigera-operator -n tigera-operator --replicas=0" 2>/dev/null || true
  # Then delete a calico-node pod so we can see the operator is missing
  run_on_vm "kubectl --kubeconfig=/etc/kubernetes/admin.conf delete pod -n calico-system -l k8s-app=calico-node --ignore-not-found" 2>/dev/null || true
}

# Difficulty: Advanced | Concept: admission controller list | Symptom: API server runs; GET works; all CREATE and UPDATE operations fail
scenario_15() {
  backup_if_needed /etc/kubernetes/manifests/kube-apiserver.yaml
  run_on_vm "sed -i 's|--enable-admission-plugins=NodeRestriction|--enable-admission-plugins=NodeRestriction,AlwaysDeny|' /etc/kubernetes/manifests/kube-apiserver.yaml" 2>/dev/null || true
}

# -------------------------------------------------------------------
# Reset function
# -------------------------------------------------------------------
reset_all() {
  echo "=== Restoring all components ==="

  $SSH_CMD "sudo bash" << 'REMOTE'
files=(
  /etc/kubernetes/manifests/etcd.yaml
  /etc/kubernetes/manifests/kube-apiserver.yaml
  /etc/kubernetes/manifests/kube-controller-manager.yaml
  /etc/kubernetes/manifests/kube-scheduler.yaml
  /etc/containerd/config.toml
  /var/lib/kubelet/config.yaml
  /etc/kubernetes/pki/etcd/ca.crt
)

for file in "${files[@]}"; do
  if [ -f "${file}.break-backup" ]; then
    cp "${file}.break-backup" "$file"
    echo "  Restored: $file"
  fi
  if [ -f "${file}.hidden" ]; then
    mv "${file}.hidden" "$file"
    echo "  Unhidden: $file"
  fi
done

# Restore Calico CNI config if hidden
if [ -f /etc/cni/net.d/10-calico.conflist.hidden ]; then
  mv /etc/cni/net.d/10-calico.conflist.hidden /etc/cni/net.d/10-calico.conflist
  echo "  Unhidden: /etc/cni/net.d/10-calico.conflist"
fi

# Re-enable services
systemctl daemon-reload
systemctl enable containerd kubelet 2>/dev/null || true
systemctl restart containerd
sleep 2
systemctl restart kubelet

# Scale tigera-operator back up if it was scaled down
kubectl --kubeconfig=/etc/kubernetes/admin.conf scale deployment tigera-operator -n tigera-operator --replicas=1 2>/dev/null || true

echo ""
echo "=== Reset complete. Waiting 15 seconds for static pods to come back... ==="
sleep 15

echo ""
echo "=== Service status ==="
for svc in containerd kubelet; do
  status=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
  printf "  %-30s %s\n" "$svc" "$status"
done

echo ""
echo "=== Static pod status ==="
sudo crictl ps 2>/dev/null | grep -E "apiserver|etcd|controller|scheduler" | awk '{print "  " $NF " " $5}' || echo "  crictl not responding yet"

echo ""
echo "=== Node status ==="
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes 2>/dev/null || echo "  apiserver not responding yet, give it another minute"
REMOTE
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
