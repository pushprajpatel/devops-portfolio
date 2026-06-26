#!/usr/bin/env bash
# local-up.sh — One-shot local dev environment setup.
# Run once after every machine restart.
# Access everything via DNS — no port-forwarding needed.

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

step() { echo -e "\n${YELLOW}==> $1${NC}"; }
ok()   { echo -e "${GREEN}    ✓ $1${NC}"; }

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

# ── 2. Ingress addon ──────────────────────────────────────────────────────────
step "Enabling Ingress addon..."
minikube addons enable ingress 2>&1 | grep -v "^$" || true
ok "Ingress addon enabled"

step "Waiting for Ingress controller to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
ok "Ingress controller ready"

# Patch to LoadBalancer so minikube tunnel assigns 127.0.0.1 (Docker driver requirement)
kubectl patch svc ingress-nginx-controller -n ingress-nginx \
  -p '{"spec":{"type":"LoadBalancer"}}' 2>/dev/null || true

# ── 3. Apply k8s manifests (app + monitoring + ingress) ──────────────────────
step "Applying app manifests..."
kubectl apply -f ai-search-service/k8s/ 2>&1 | grep -v "unchanged" || true
ok "Manifests applied"

# ── 4. ArgoCD ingress (separate namespace — not synced by ArgoCD itself) ─────
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

# ── 5. /etc/hosts (127.0.0.1 — minikube tunnel maps here) ────────────────────
step "Updating /etc/hosts (sudo required once)..."
sudo sed -i '' '/styleai\.test\|grafana\.test\|prometheus\.test\|argocd\.test/d' /etc/hosts
echo "127.0.0.1  styleai.test grafana.test prometheus.test argocd.test" \
  | sudo tee -a /etc/hosts > /dev/null
ok "/etc/hosts updated → 127.0.0.1"

# ── 6. Done ───────────────────────────────────────────────────────────────────
echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  All services live — no port-forwarding needed:${NC}"
echo -e "${CYAN}  App         →  http://styleai.test${NC}"
echo -e "${CYAN}  Grafana     →  http://grafana.test        (admin / admin)${NC}"
echo -e "${CYAN}  Prometheus  →  http://prometheus.test${NC}"
echo -e "${CYAN}  ArgoCD      →  https://argocd.test${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "\n${YELLOW}  Keeping tunnel alive — do not close this terminal.${NC}"
echo -e "${YELLOW}  Press Ctrl+C to stop.${NC}\n"

# ── 7. minikube tunnel (blocking — must stay running) ─────────────────────────
minikube tunnel
