#!/usr/bin/env bash
#
# break-cluster.sh
#
# Introduces a single fault into the Kubernetes cluster for troubleshooting practice.
# Run this from the QEMU host. The script SSHes into the VM to apply the break.
#
# Usage:
#   ./break-cluster.sh          # Pick a random scenario
#   ./break-cluster.sh 3        # Run scenario 3 specifically
#   ./break-cluster.sh --list   # Show how many scenarios are available (no spoilers)
#   ./break-cluster.sh --reset  # Attempt to restore all components to working state
#
# Configuration:
#   Set BREAK_SSH_CMD to override the default SSH command.
#   Example: export BREAK_SSH_CMD="ssh node01"
#
# After running, SSH into the VM and use kubectl, systemctl, journalctl, and your
# knowledge of the cluster to diagnose and fix the problem.

set -euo pipefail

TOTAL_SCENARIOS=15

# -------------------------------------------------------------------
# SSH configuration
# Adjust these if your SSH config differs.
# If you have a Host entry in ~/.ssh/config, set BREAK_SSH_CMD="ssh node01".
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
    break-cluster.sh - Introduce faults into single-node systemd Kubernetes cluster

SYNOPSIS
    ./break-cluster.sh [OPTION | SCENARIO]

DESCRIPTION
    Introduces a single controlled fault into your single-node, from-scratch,
    systemd-managed Kubernetes cluster for troubleshooting practice. Run this
    from the QEMU host. The script SSHes into the VM to apply the break.

    This variant targets systemd service unit files for etcd, kube-apiserver,
    kube-controller-manager, kube-scheduler, kubelet, and kube-proxy.

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
            export BREAK_SSH_CMD="ssh node01"
            export BREAK_SSH_CMD="ssh -p 2222 kube@127.0.0.1"

EXAMPLES
    Run a random scenario:
        ./break-cluster.sh

    Run scenario 7 specifically:
        ./break-cluster.sh 7

    List available scenarios:
        ./break-cluster.sh --list

    Reset cluster to working state:
        ./break-cluster.sh --reset

    SSH into the VM after running a scenario:
        ssh -p 2222 kube@127.0.0.1

DIAGNOSTIC COMMANDS
    After a scenario runs, SSH into the VM and diagnose the problem:

        systemctl status <service>
        journalctl -u <service> -n 50
        kubectl get nodes
        kubectl get pods -A
        curl -k https://127.0.0.1:6443/healthz

    Key services: etcd, kube-apiserver, kube-controller-manager, kube-scheduler,
                  containerd, kubelet, kube-proxy

FILES
    /etc/systemd/system/etcd.service
    /etc/systemd/system/kube-apiserver.service
    /etc/systemd/system/kube-controller-manager.service
    /etc/systemd/system/kube-scheduler.service
    /var/lib/kubelet/kubelet-config.yaml
    /etc/cni/net.d/10-bridge.conf

EXIT STATUS
    0   Success
    1   Invalid scenario number or other error

SEE ALSO
    kubectl(1), systemctl(1), journalctl(1)
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
  echo "============================================="
  echo ""
  echo "Something has been broken in your cluster."
  echo "SSH into the VM and use kubectl, systemctl,"
  echo "journalctl, and your knowledge of the cluster"
  echo "to find and fix the problem."
  echo ""
  echo "  ssh -p 2222 kube@127.0.0.1"
  echo ""
  echo "Diagnostic starting points:"
  echo "  systemctl status <service>"
  echo "  journalctl -u <service>"
  echo "  kubectl get nodes"
  echo "  kubectl get pods -A"
  echo "  curl -k https://127.0.0.1:6443/healthz"
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
# Each scenario has a header comment: Difficulty | Concept | Symptom
# Difficulty: Beginner = single service, obvious logs
#             Intermediate = requires cross-component reasoning
#             Advanced = subtle misconfiguration, non-obvious symptom
# -------------------------------------------------------------------

# Difficulty: Beginner | Concept: etcd data directory path | Symptom: etcd fails to start; API server loses connection to etcd
scenario_1() {
  backup_if_needed /etc/systemd/system/etcd.service
  run_on_vm "sed -i 's|--data-dir=/var/lib/etcd|--data-dir=/var/lib/etcd-bad|' /etc/systemd/system/etcd.service && systemctl daemon-reload && systemctl restart etcd" 2>/dev/null || true
}

# Difficulty: Beginner | Concept: etcd endpoint URL in kube-apiserver | Symptom: API server starts then crashes; cannot reach etcd on wrong port
scenario_2() {
  backup_if_needed /etc/systemd/system/kube-apiserver.service
  run_on_vm "sed -i 's|--etcd-servers=https://127.0.0.1:2379|--etcd-servers=https://127.0.0.1:9999|' /etc/systemd/system/kube-apiserver.service && systemctl daemon-reload && systemctl restart kube-apiserver" 2>/dev/null || true
}

# Difficulty: Beginner | Concept: TLS certificate file path | Symptom: API server crashes immediately; logs show "no such file or directory"
scenario_3() {
  backup_if_needed /etc/systemd/system/kube-apiserver.service
  run_on_vm "sed -i 's|--tls-cert-file=/var/lib/kubernetes/kubernetes.pem|--tls-cert-file=/var/lib/kubernetes/missing.pem|' /etc/systemd/system/kube-apiserver.service && systemctl daemon-reload && systemctl restart kube-apiserver" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: controller-manager kubeconfig path | Symptom: API server runs; kubectl works; but deployments stop reconciling and failed pods are not replaced
scenario_4() {
  backup_if_needed /etc/systemd/system/kube-controller-manager.service
  run_on_vm "sed -i 's|--kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig|--kubeconfig=/var/lib/kubernetes/wrong.kubeconfig|' /etc/systemd/system/kube-controller-manager.service && systemctl daemon-reload && systemctl restart kube-controller-manager" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: scheduler config file path | Symptom: existing pods keep running; new pods stay Pending indefinitely
scenario_5() {
  backup_if_needed /etc/systemd/system/kube-scheduler.service
  run_on_vm "sed -i 's|--config=/etc/kubernetes/config/kube-scheduler.yaml|--config=/etc/kubernetes/config/missing-scheduler.yaml|' /etc/systemd/system/kube-scheduler.service && systemctl daemon-reload && systemctl restart kube-scheduler" 2>/dev/null || true
}

# Difficulty: Beginner | Concept: systemd service enabled/disabled state | Symptom: kubectl completely unresponsive; kube-apiserver.service is disabled
scenario_6() {
  run_on_vm "systemctl stop kube-apiserver && systemctl disable kube-apiserver" 2>/dev/null || true
}

# Difficulty: Advanced | Concept: etcd TLS certificate chain | Symptom: etcd restarts fine but fails TLS handshake; API server logs show x509 errors
scenario_7() {
  backup_if_needed /etc/etcd/ca.pem
  run_on_vm "mv /etc/etcd/ca.pem /etc/etcd/ca.pem.hidden && systemctl restart etcd" 2>/dev/null || true
}

# Difficulty: Advanced | Concept: service CIDR consistency across components | Symptom: API server runs; kubectl works; but CoreDNS gets a wrong ClusterIP and new services break
scenario_8() {
  backup_if_needed /etc/systemd/system/kube-apiserver.service
  run_on_vm "sed -i 's|--service-cluster-ip-range=10.96.0.0/16|--service-cluster-ip-range=10.99.0.0/16|' /etc/systemd/system/kube-apiserver.service && systemctl daemon-reload && systemctl restart kube-apiserver" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: etcd client URL scheme (http vs https) | Symptom: etcd starts; API server fails with TLS handshake error connecting to etcd
scenario_9() {
  backup_if_needed /etc/systemd/system/etcd.service
  run_on_vm "sed -i 's|--listen-client-urls https://|--listen-client-urls http://|g' /etc/systemd/system/etcd.service && systemctl daemon-reload && systemctl restart etcd" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: API server authorization mode | Symptom: API server starts; kubectl connects; every request returns 403 Forbidden
scenario_10() {
  backup_if_needed /etc/systemd/system/kube-apiserver.service
  run_on_vm "sed -i 's|--authorization-mode=Node,RBAC|--authorization-mode=AlwaysDeny|' /etc/systemd/system/kube-apiserver.service && systemctl daemon-reload && systemctl restart kube-apiserver" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: kubelet CRI socket path | Symptom: node shows NotReady; kubelet logs show "failed to connect to container runtime"
scenario_11() {
  backup_if_needed /var/lib/kubelet/kubelet-config.yaml
  run_on_vm "sed -i 's|containerRuntimeEndpoint: \"unix:///var/run/containerd/containerd.sock\"|containerRuntimeEndpoint: \"unix:///var/run/containerd/wrong.sock\"|' /var/lib/kubelet/kubelet-config.yaml && systemctl restart kubelet" 2>/dev/null || true
}

# Difficulty: Beginner | Concept: container runtime dependency chain | Symptom: node NotReady; all running containers stop; containerd.service is disabled
scenario_12() {
  run_on_vm "systemctl stop containerd && systemctl disable containerd" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: CNI configuration file presence | Symptom: node NotReady; kubelet logs show "network plugin not ready"; existing pods stop getting IPs
scenario_13() {
  backup_if_needed /etc/cni/net.d/10-bridge.conf
  run_on_vm "mv /etc/cni/net.d/10-bridge.conf /etc/cni/net.d/10-bridge.conf.hidden && systemctl restart kubelet" 2>/dev/null || true
}

# Difficulty: Intermediate | Concept: kubelet kubeconfig server URL | Symptom: node NotReady; kubelet logs show "connection refused" to wrong port; API server is healthy
scenario_14() {
  backup_if_needed /var/lib/kubelet/kubeconfig
  run_on_vm "sed -i 's|server: https://127.0.0.1:6443|server: https://127.0.0.1:7777|' /var/lib/kubelet/kubeconfig && systemctl restart kubelet" 2>/dev/null || true
}

# Difficulty: Advanced | Concept: admission controller list | Symptom: API server runs; GET requests work; all CREATE and UPDATE operations fail with admission error
scenario_15() {
  backup_if_needed /etc/systemd/system/kube-apiserver.service
  run_on_vm "sed -i 's|--enable-admission-plugins=|--enable-admission-plugins=AlwaysDeny,|' /etc/systemd/system/kube-apiserver.service && systemctl daemon-reload && systemctl restart kube-apiserver" 2>/dev/null || true
}

# -------------------------------------------------------------------
# Reset function
# -------------------------------------------------------------------
reset_all() {
  echo "=== Restoring all components ==="

  $SSH_CMD "sudo bash" << 'REMOTE'
files=(
  /etc/systemd/system/etcd.service
  /etc/systemd/system/kube-apiserver.service
  /etc/systemd/system/kube-controller-manager.service
  /etc/systemd/system/kube-scheduler.service
  /var/lib/kubelet/kubelet-config.yaml
  /var/lib/kubelet/kubeconfig
  /etc/cni/net.d/10-bridge.conf
  /etc/etcd/ca.pem
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

systemctl daemon-reload
systemctl enable etcd kube-apiserver kube-controller-manager kube-scheduler containerd kubelet kube-proxy 2>/dev/null || true
systemctl restart etcd
sleep 2
systemctl restart kube-apiserver
sleep 2
systemctl restart kube-controller-manager
systemctl restart kube-scheduler
systemctl restart containerd
sleep 2
systemctl restart kubelet
systemctl restart kube-proxy

echo ""
echo "=== Reset complete. Waiting 10 seconds for components to stabilize... ==="
sleep 10

echo ""
echo "=== Component status ==="
for svc in etcd kube-apiserver kube-controller-manager kube-scheduler containerd kubelet kube-proxy; do
  status=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
  printf "  %-30s %s\n" "$svc" "$status"
done

echo ""
echo "=== Node status ==="
KUBECONFIG=/home/kube/.kube/config kubectl get nodes 2>/dev/null || echo "  kubectl not responding yet, give it another minute"
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
