#!/usr/bin/env bash
# local-up.sh — One-shot local dev environment setup.
# Clone the repo, run this script once, and every service is accessible
# via local DNS with no port-forwarding required.
#
# Prerequisites: Docker Desktop, Minikube, kubectl
# macOS install: brew install minikube kubectl

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

step() { echo -e "\n${YELLOW}==> $1${NC}"; }
ok()   { echo -e "${GREEN}    ✓ $1${NC}"; }
fail() { echo -e "${RED}    ✗ $1${NC}"; exit 1; }

# ── 0. Prerequisites ──────────────────────────────────────────────────────────
step "Checking prerequisites..."
command -v docker   >/dev/null 2>&1 || fail "Docker not found. Install Docker Desktop: https://www.docker.com/products/docker-desktop"
command -v minikube >/dev/null 2>&1 || fail "Minikube not found. Install: brew install minikube"
command -v kubectl  >/dev/null 2>&1 || fail "kubectl not found. Install: brew install kubectl"
docker info >/dev/null 2>&1         || fail "Docker daemon is not running. Please start Docker Desktop."
ok "All prerequisites satisfied"

# ── 1. Minikube ──────────────────────────────────────────────────────────────
step "Checking Minikube..."
if minikube status 2>/dev/null | grep -q "Running"; then
  ok "Minikube already running"
else
  echo "    Starting Minikube (7 GB RAM, 4 CPUs)..."
  minikube start --memory=7000 --cpus=4
  ok "Minikube started"
fi

MINIKUBE_IP=$(minikube ip)

# ── 2. ArgoCD ────────────────────────────────────────────────────────────────
step "Checking ArgoCD..."
if kubectl get namespace argocd >/dev/null 2>&1; then
  ok "ArgoCD namespace already exists"
else
  echo "    Installing ArgoCD..."
  kubectl create namespace argocd
  kubectl apply -n argocd --server-side \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  echo "    Waiting for ArgoCD to be ready (this may take a few minutes)..."
  kubectl wait --for=condition=available deployment --all -n argocd --timeout=300s
  ok "ArgoCD installed"
fi

# ── 3. Ingress addon ──────────────────────────────────────────────────────────
step "Enabling Ingress addon..."
minikube addons enable ingress 2>&1 | grep -v "^$" || true
ok "Ingress addon enabled"

step "Waiting for Ingress controller to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
ok "Ingress controller ready"

# Patch to LoadBalancer so minikube tunnel assigns 127.0.0.1 (Docker driver requirement on macOS)
kubectl patch svc ingress-nginx-controller -n ingress-nginx \
  -p '{"spec":{"type":"LoadBalancer"}}' 2>/dev/null || true

# ── 4. Apply k8s manifests ───────────────────────────────────────────────────
step "Applying Kubernetes manifests..."
kubectl apply -f ai-search-service/k8s/ 2>&1 | grep -v "unchanged" || true
ok "Manifests applied"

# ── 5. ArgoCD ingress (separate namespace — not managed by ArgoCD itself) ────
step "Applying ArgoCD ingress..."
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
ok "ArgoCD ingress applied"

# ── 6. /etc/hosts ─────────────────────────────────────────────────────────────
step "Updating /etc/hosts (requires sudo)..."
sudo sed -i '' '/styleai\.test\|grafana\.test\|prometheus\.test\|argocd\.test/d' /etc/hosts
echo "127.0.0.1  styleai.test grafana.test prometheus.test argocd.test" \
  | sudo tee -a /etc/hosts > /dev/null
ok "/etc/hosts updated → 127.0.0.1"

# ── 7. ArgoCD admin password ──────────────────────────────────────────────────
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "not ready yet — run: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d")

# ── 8. Done ───────────────────────────────────────────────────────────────────
echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  All services are live — no port-forwarding needed:${NC}"
echo -e "${CYAN}  App         →  http://styleai.test${NC}"
echo -e "${CYAN}  Grafana     →  http://grafana.test         (admin / admin)${NC}"
echo -e "${CYAN}  Prometheus  →  http://prometheus.test${NC}"
echo -e "${CYAN}  ArgoCD      →  https://argocd.test${NC}"
echo -e "${CYAN}                  username: admin${NC}"
echo -e "${CYAN}                  password: ${ARGOCD_PASSWORD}${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "\n${YELLOW}  minikube tunnel is starting — keep this terminal open.${NC}"
echo -e "${YELLOW}  Press Ctrl+C to stop all services.${NC}\n"

# ── 9. minikube tunnel (blocking — must stay running) ─────────────────────────
minikube tunnel
