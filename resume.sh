#!/usr/bin/env bash
# resume.sh — bring the local stack back after a break, and verify every piece.
#
# Safe to run any time (idempotent): it only starts what is not already running.
#   Docker Desktop → Minikube → workloads → ArgoCD / Prometheus / Grafana / Alertmanager
#   / Ollama (+ model) → health checks → minikube tunnel.
#
# Usage:  ./resume.sh              start everything, verify, then run `minikube tunnel`
#         ./resume.sh --no-tunnel  start + verify only (no sudo prompt, returns immediately)
#
# First-time setup on a fresh machine? Run ./local-up.sh instead.

set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
step() { echo -e "\n${YELLOW}${BOLD}==> $1${NC}"; }
ok()   { echo -e "${GREEN}    ✓ $1${NC}"; }
warn() { echo -e "${YELLOW}    ! $1${NC}"; }
bad()  { echo -e "${RED}    ✗ $1${NC}"; }

TUNNEL=1
[[ "${1:-}" == "--no-tunnel" ]] && TUNNEL=0

FAILED=()
fail() { FAILED+=("$1"); bad "$1"; }

# ── 1. Docker ─────────────────────────────────────────────────────────────────
step "Docker Desktop"
if docker info >/dev/null 2>&1; then
  ok "already running"
else
  echo "    starting Docker Desktop..."
  open -a Docker
  for _ in $(seq 1 60); do docker info >/dev/null 2>&1 && break; sleep 3; done
  docker info >/dev/null 2>&1 && ok "Docker is up" || { fail "Docker did not start within 3 min"; exit 1; }
fi

# ── 2. Minikube ───────────────────────────────────────────────────────────────
step "Minikube"
if minikube status --format='{{.Host}}/{{.APIServer}}' 2>/dev/null | grep -q '^Running/Running$'; then
  ok "already running"
else
  echo "    starting minikube..."
  minikube start 2>&1 | grep -E "Done!|Error|error" || true
  minikube status --format='{{.Host}}/{{.APIServer}}' 2>/dev/null | grep -q '^Running/Running$' \
    && ok "minikube is up" || { fail "minikube failed to start"; exit 1; }
fi
kubectl wait --for=condition=Ready node --all --timeout=120s >/dev/null 2>&1 && ok "node Ready" || fail "node not Ready"

# ── 3. Workloads ──────────────────────────────────────────────────────────────
# Pods left over from the last shutdown show Error/Completed for a minute while
# the kubelet restarts them — so wait for rollout instead of judging immediately.
step "Waiting for workloads (up to 3 min each)"
wait_for() {  # <namespace> <kind/name> <label>
  if kubectl -n "$1" rollout status "$2" --timeout=180s >/dev/null 2>&1; then
    ok "$3"
  else
    fail "$3 not ready"
    # Surface the reason the way an SRE would: last termination state of its pods.
    kubectl -n "$1" get pods --no-headers 2>/dev/null | awk -v n="${2#*/}" '$1 ~ n {split($2, r, "/"); if (r[1] != r[2]) print $1}' | while read -r p; do
      reason=$(kubectl -n "$1" get pod "$p" -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null)
      echo "      $p → ${reason:-still starting}"
    done
  fi
}
wait_for default  deploy/app          "StyleAI app"
wait_for default  deploy/ollama       "Ollama"
wait_for default  deploy/prometheus   "Prometheus"
wait_for default  deploy/alertmanager "Alertmanager"
wait_for default  deploy/grafana      "Grafana"
wait_for default  deploy/otel-collector "OTel Collector"
wait_for default  deploy/jaeger       "Jaeger"
wait_for argocd   statefulset/argocd-application-controller "ArgoCD application-controller"
wait_for argocd   deploy/argocd-repo-server "ArgoCD repo-server"
wait_for argocd   deploy/argocd-server      "ArgoCD server"
wait_for ingress-nginx deploy/ingress-nginx-controller "Ingress controller"

# ── 4. Ollama model ───────────────────────────────────────────────────────────
step "Ollama model"
MODEL="qwen2.5:7b"
if kubectl exec deploy/ollama -- ollama list 2>/dev/null | grep -q "$MODEL"; then
  ok "$MODEL present"
else
  warn "$MODEL missing — pulling (several GB, first time only)..."
  kubectl exec deploy/ollama -- ollama pull "$MODEL" && ok "$MODEL pulled" || fail "could not pull $MODEL"
fi

# ── 5. Health endpoints (via API-server proxy — works without the tunnel) ─────
step "Health checks"
probe() {  # <label> <service:port> <path> — retries up to ~60s (Grafana takes ~20s to open its port)
  for _ in $(seq 1 20); do
    if kubectl get --raw "/api/v1/namespaces/default/services/$2/proxy$3" >/dev/null 2>&1; then
      ok "$1"
      return
    fi
    sleep 3
  done
  fail "$1 not responding"
}
probe "App          /health"       app:8000          /health
probe "Prometheus   /-/ready"      prometheus:9090   /-/ready
probe "Alertmanager /-/ready"      alertmanager:9093 /-/ready
probe "Grafana      /api/health"   grafana:3000      /api/health
probe "Jaeger UI    /"             jaeger:16686      /

# Prometheus must actually be scraping the app, not merely be up.
if kubectl get --raw '/api/v1/namespaces/default/services/prometheus:9090/proxy/api/v1/query?query=up%7Bjob%3D%22ai-search-app%22%7D' 2>/dev/null | grep -q '"1"\]'; then
  ok "Prometheus is scraping the app (up=1)"
else
  warn "Prometheus has no up=1 sample for the app yet (may need ~30s after a fresh start)"
fi

# ── 6. ArgoCD sync ────────────────────────────────────────────────────────────
step "ArgoCD"
APP_STATE=$(kubectl -n argocd get application ai-search-service -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)
[[ "$APP_STATE" == "Synced/Healthy" ]] && ok "ai-search-service: $APP_STATE" || warn "ai-search-service: ${APP_STATE:-not found}"

# ── 7. Local DNS ──────────────────────────────────────────────────────────────
step "Local DNS (/etc/hosts)"
for h in styleai.test grafana.test prometheus.test argocd.test; do
  grep -q "$h" /etc/hosts && ok "$h" || fail "$h missing in /etc/hosts — run ./local-up.sh once to add it"
done

# ── 7b. Jaeger UI has no ingress/DNS entry — expose it on localhost ───────────
if ! lsof -nP -iTCP:16686 -sTCP:LISTEN >/dev/null 2>&1; then
  nohup kubectl port-forward svc/jaeger 16686:16686 >/dev/null 2>&1 &
  ok "port-forwarding Jaeger UI → http://localhost:16686"
else
  ok "Jaeger UI already on http://localhost:16686"
fi

# ── 8. Summary ────────────────────────────────────────────────────────────────
echo
if ((${#FAILED[@]})); then
  echo -e "${RED}${BOLD}Problems found:${NC}"
  printf '  - %s\n' "${FAILED[@]}"
  echo -e "Inspect with: ${CYAN}kubectl get pods -A${NC}  /  ${CYAN}kubectl describe pod <name>${NC}"
else
  echo -e "${GREEN}${BOLD}Everything is up and healthy.${NC}"
fi
echo -e "
  App         →  ${CYAN}http://styleai.test${NC}
  Grafana     →  ${CYAN}http://grafana.test${NC}   (admin / admin)
  Prometheus  →  ${CYAN}http://prometheus.test${NC}
  Jaeger      →  ${CYAN}http://localhost:16686${NC}   (traces: pick service "styleai-search")
  ArgoCD      →  ${CYAN}https://argocd.test${NC}   (admin / kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
"

# ── 9. Tunnel ─────────────────────────────────────────────────────────────────
if pgrep -f "minikube tunnel" >/dev/null 2>&1; then
  ok "minikube tunnel already running"
elif ((TUNNEL)); then
  echo -e "${YELLOW}Starting minikube tunnel (asks for your sudo password). Keep this terminal open; Ctrl-C stops it.${NC}"
  exec minikube tunnel
else
  warn "tunnel not running — the *.test URLs will not open. Run: minikube tunnel"
fi

((${#FAILED[@]})) && exit 1 || exit 0
