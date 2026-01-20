#!/bin/bash

set -euo pipefail

##############################
# COLORS & FORMATTING
##############################
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
PURPLE="\033[0;35m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

info()    { echo -e "${BLUE}${BOLD}[INFO]${RESET} $1"; }
success() { echo -e "${GREEN}${BOLD}[SUCCESS]${RESET} $1"; }
warn()    { echo -e "${YELLOW}${BOLD}[WARN]${RESET} $1"; }
error()   { echo -e "${RED}${BOLD}[ERROR]${RESET} $1"; }
section() {
  echo -e "\n${PURPLE}${BOLD}================================================"
  echo -e "$1"
  echo -e "================================================${RESET}\n"
}

##############################
# CONFIG
##############################
K8S_VERSION="1.33"
MASTER_IP="192.168.56.10"
POD_CIDR="192.168.0.0/16"
CNI="calico"
JOIN_CMD_FILE="$HOME/kubeadm-join.sh"
LOG_FILE="/var/log/kubeadm-master-init.log"

##############################
# LOGGING
##############################
sudo touch "$LOG_FILE"
sudo chown "$(id -u):$(id -g)" "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

section "KUBEADM MASTER INITIALIZATION STARTED"

info "Node        : $(hostname)"
info "K8S Version : v${K8S_VERSION}"
info "Master IP  : ${MASTER_IP}"
info "Timestamp  : $(date)"

##############################
# SAFETY CHECKS
##############################
section "PRE-FLIGHT SAFETY CHECKS"

if [ -f /etc/kubernetes/admin.conf ]; then
  error "Kubernetes is already initialized on this node"
  warn "If this is intentional, run: kubeadm reset -f"
  exit 0
fi

success "Node is safe to initialize"

##############################
# KUBEADM INIT
##############################
section "STEP 1/6 - INITIALIZE CONTROL PLANE"

info "Running kubeadm init..."

sudo kubeadm init \
  --apiserver-advertise-address="${MASTER_IP}" \
  --pod-network-cidr="${POD_CIDR}"

success "Control plane initialized successfully"

##############################
# KUBECTL CONFIG
##############################
section "STEP 2/6 - CONFIGURE kubectl"

info "Setting up kubeconfig for current user..."

mkdir -p "$HOME/.kube"
sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

success "kubectl configured"

##############################
# INSTALL CNI
##############################
section "STEP 3/6 - INSTALL CNI PLUGIN"

info "Selected CNI: ${CNI}"

if [ "$CNI" = "calico" ]; then
  info "Applying Calico manifests..."
  kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
  success "Calico CNI installed"
else
  error "Unsupported CNI: $CNI"
  exit 1
fi

##############################
# WAIT FOR CONTROL PLANE
##############################
section "STEP 4/6 - WAIT FOR CONTROL PLANE"

info "Waiting for master node to become Ready..."

kubectl wait --for=condition=Ready node "$(hostname)" --timeout=300s

success "Control plane node is Ready"

##############################
# GENERATE JOIN COMMAND
##############################
section "STEP 5/6 - GENERATE WORKER JOIN COMMAND"

info "Creating kubeadm join token..."

JOIN_CMD=$(sudo kubeadm token create --print-join-command)

echo "#!/bin/bash" | tee "$JOIN_CMD_FILE" >/dev/null
echo "sudo $JOIN_CMD" | tee -a "$JOIN_CMD_FILE" >/dev/null
chmod +x "$JOIN_CMD_FILE"

success "Join command generated"
info "Saved at: $JOIN_CMD_FILE"

##############################
# DONE
##############################
section "MASTER INITIALIZATION COMPLETED"

success "Kubernetes control plane setup is complete"

echo -e "${CYAN}${BOLD}NEXT STEPS:${RESET}"
echo -e "  ${GREEN}➜ Run this on ALL worker nodes:${RESET}"
echo -e "    ${BOLD}$JOIN_CMD_FILE${RESET}"
echo
