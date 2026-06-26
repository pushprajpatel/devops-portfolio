#!/usr/bin/env bash
# local-up.sh — Clone the repo, run this script, done.
# Installs all dependencies automatically and brings up the full stack
# with local DNS — no port-forwarding required.
#
# Supported: macOS (Apple Silicon & Intel)
# Usage:     ./local-up.sh

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

step()  { echo -e "\n${YELLOW}${BOLD}==> $1${NC}"; }
ok()    { echo -e "${GREEN}    ✓ $1${NC}"; }
info()  { echo -e "    $1"; }
fail()  { echo -e "${RED}    ✗ $1${NC}"; exit 1; }

# ── 0. macOS check ────────────────────────────────────────────────────────────
[[ "$(uname)" == "Darwin" ]] || fail "This script supports macOS only."

# ── 1. Homebrew ───────────────────────────────────────────────────────────────
step "Checking Homebrew..."
if ! command -v brew >/dev/null 2>&1; then
  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to PATH for Apple Silicon
  [[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
  ok "Homebrew installed"
else
  ok "Homebrew already installed"
fi

# ── 2. kubectl ────────────────────────────────────────────────────────────────
step "Checking kubectl..."
if ! command -v kubectl >/dev/null 2>&1; then
  info "Installing kubectl..."
  brew install kubectl
  ok "kubectl installed"
else
  ok "kubectl $(kubectl version --client --short 2>/dev/null | awk '{print $3}') already installed"
fi

# ── 3. Minikube ───────────────────────────────────────────────────────────────
step "Checking Minikube..."
if ! command -v minikube >/dev/null 2>&1; then
  info "Installing Minikube..."
  brew install minikube
  ok "Minikube installed"
else
  ok "Minikube $(minikube version --short 2>/dev/null) already installed"
fi

# ── 4. Docker Desktop ─────────────────────────────────────────────────────────
step "Checking Docker..."
if ! command -v docker >/dev/null 2>&1; then
  info "Installing Docker Desktop via Homebrew..."
  brew install --cask docker
  ok "Docker Desktop installed"
fi

if ! docker info >/dev/null 2>&1; then
  info "Starting Docker Desktop..."
  open -a Docker
  echo -e "    ${YELLOW}Waiting for Docker to start (this may take up to 60 seconds)...${NC}"
  SECONDS_WAITED=0
  until docker info >/dev/null 2>&1; do
    sleep 3
    SECONDS_WAITED=$((SECONDS_WAITED + 3))
    if [[ $SECONDS_WAITED -ge 120 ]]; then
      fail "Docker did not start within 2 minutes. Please open Docker Desktop manually and re-run this script."
    fi
    echo -n "."
  done
  echo ""
  ok "Docker is running"
else
  ok "Docker is running"
fi

# ── 5. Start Minikube ─────────────────────────────────────────────────────────
step "Starting Minikube..."
if minikube status 2>/dev/null | grep -q "Running"; then
  ok "Minikube already running"
else
  minikube start --memory=7000 --cpus=4
  ok "Minikube started"
fi

# ── 6. Install ArgoCD ─────────────────────────────────────────────────────────
step "Checking ArgoCD..."
if kubectl get namespace argocd >/dev/null 2>&1; then
  ok "ArgoCD already installed"
else
  info "Installing ArgoCD (this takes a few minutes)..."
  kubectl create namespace argocd
  kubectl apply -n argocd --server-side \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  kubectl wait --for=condition=available deployment --all -n argocd --timeout=300s
  ok "ArgoCD installed"
fi

# ── 7. Ingress addon ──────────────────────────────────────────────────────────
step "Enabling Nginx Ingress addon..."
minikube addons enable ingress 2>&1 | grep -v "^$" || true
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
kubectl patch svc ingress-nginx-controller -n ingress-nginx \
  -p '{"spec":{"type":"LoadBalancer"}}' 2>/dev/null || true
ok "Ingress ready"

# ── 8. Enable metrics-server (for HPA) ───────────────────────────────────────
step "Enabling metrics-server..."
minikube addons enable metrics-server 2>&1 | grep -v "^$" || true
ok "metrics-server enabled"

# ── 9. Deploy the stack ───────────────────────────────────────────────────────
step "Deploying the full stack..."
kubectl apply -f ai-search-service/k8s/ 2>&1 | grep -v "unchanged" || true
ok "Stack deployed"

# ── 10. ArgoCD ingress ────────────────────────────────────────────────────────
step "Configuring ArgoCD ingress..."
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
spec:
  ingressClassName: nginx
  rules:
    - host: argocd.test
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 443
EOF
ok "ArgoCD ingress configured"

# ── 11. /etc/hosts ────────────────────────────────────────────────────────────
step "Updating /etc/hosts (requires sudo)..."
sudo sed -i '' '/styleai\.test\|grafana\.test\|prometheus\.test\|argocd\.test/d' /etc/hosts
echo "127.0.0.1  styleai.test grafana.test prometheus.test argocd.test" \
  | sudo tee -a /etc/hosts > /dev/null
ok "/etc/hosts updated"

# ── 12. ArgoCD password ───────────────────────────────────────────────────────
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 -d \
  || echo "(run: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)")

# ── 13. Summary ───────────────────────────────────────────────────────────────
echo -e "\n${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  Everything is up — open these in your browser:${NC}"
echo -e "${CYAN}  App         →  http://styleai.test${NC}"
echo -e "${CYAN}  Grafana     →  http://grafana.test         (admin / admin)${NC}"
echo -e "${CYAN}  Prometheus  →  http://prometheus.test${NC}"
echo -e "${CYAN}  ArgoCD      →  https://argocd.test${NC}"
echo -e "${CYAN}                  username : admin${NC}"
echo -e "${CYAN}                  password : ${ARGOCD_PASSWORD}${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "\n${YELLOW}  minikube tunnel is running — keep this terminal open.${NC}"
echo -e "${YELLOW}  Press Ctrl+C to stop.${NC}\n"

# ── 14. Start tunnel (blocking) ───────────────────────────────────────────────
minikube tunnel
