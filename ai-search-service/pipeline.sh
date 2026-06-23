#!/bin/bash
# Local CI/CD pipeline for ai-search-service, validated against Minikube.
# Run all stages:        ./pipeline.sh
# Run a single stage:    ./pipeline.sh test
set -e

cd "$(dirname "$0")"

IMAGE_NAME="ai-search-service:ci"
VENV_PY="venv/bin/python3"
VENV_PIP="venv/bin/pip"

stage_lint() {
  echo "==> [1/7] Lint (ruff)"
  "$VENV_PY" -m ruff check .
}

stage_test() {
  echo "==> [2/7] Test (pytest)"
  "$VENV_PY" -m pytest tests/ -v
}

stage_build() {
  echo "==> [3/7] Build (docker build)"
  docker build -t "$IMAGE_NAME" .
}

stage_scan() {
  echo "==> [4/7] Scan (trivy)"
  # --ignore-unfixed: only fail the pipeline on vulnerabilities that actually
  # have an available fix. Base-image OS CVEs with no upstream fix yet
  # (status: fix_deferred/affected) would otherwise block every build
  # regardless of anything we control in this repo.
  trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --quiet "$IMAGE_NAME"
}

stage_load_image() {
  echo "==> [5/7] Load image into Minikube"
  minikube image load "$IMAGE_NAME"
}

stage_deploy() {
  echo "==> [6/7] Deploy to Minikube"
  kubectl apply -f k8s/ollama-deployment.yaml
  kubectl apply -f k8s/app-deployment.yaml
  kubectl rollout status deployment/ollama --timeout=120s
  kubectl rollout status deployment/app --timeout=120s
}

stage_smoke_test() {
  echo "==> [7/7] Smoke test"
  # kubectl port-forward (not `minikube service --url`) — the docker driver's
  # service tunnel blocks in the foreground, which doesn't fit a script that
  # needs to curl and move on.
  kubectl port-forward svc/app 18000:8000 > /tmp/port-forward.log 2>&1 &
  local pf_pid=$!
  trap 'kill $pf_pid 2>/dev/null || true' EXIT
  sleep 3
  local url="http://localhost:18000"
  echo "App exposed at $url (via port-forward)"

  echo "Checking /health..."
  health_code=$(curl -s -o /dev/null -w "%{http_code}" "$url/health")
  if [ "$health_code" != "200" ]; then
    echo "FAILED: /health returned $health_code"
    exit 1
  fi

  echo "Checking /search..."
  search_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$url/search" \
    -H "Content-Type: application/json" -d '{"query":"black tshirt"}')
  if [ "$search_code" != "200" ]; then
    echo "FAILED: /search returned $search_code"
    exit 1
  fi

  echo "Smoke test passed."
}

run_all() {
  stage_lint
  stage_test
  stage_build
  stage_scan
  stage_load_image
  stage_deploy
  stage_smoke_test
  echo "✅ Pipeline completed successfully."
}

case "${1:-all}" in
  lint) stage_lint ;;
  test) stage_test ;;
  build) stage_build ;;
  scan) stage_scan ;;
  load) stage_load_image ;;
  deploy) stage_deploy ;;
  smoke) stage_smoke_test ;;
  all) run_all ;;
  *)
    echo "Usage: $0 [lint|test|build|scan|load|deploy|smoke|all]"
    exit 1
    ;;
esac
