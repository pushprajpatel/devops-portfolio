# StyleAI — AI-Powered E-commerce Search

A full-stack e-commerce demo where a **local LLM** (no external API, zero
token cost) parses natural-language search queries — including Hinglish —
into structured product filters via tool-calling, then queries a product
catalog in real time.

> "black mein M size dikhado jo 400 se 500 ke beech mai ho" → `{color: black, size: M, min_price: 400, max_price: 500}`

Built as an end-to-end DevOps showcase: containerized, tested, linted,
security-scanned, and deployed to Kubernetes — with the full CI/CD pipeline
validated locally against Minikube before being wired into GitHub Actions.

## Features

- **AI-powered NL search** — [Ollama](https://ollama.ai) (`qwen2.5:7b`) running locally, tool-calling to extract structured filters from free-text queries
- **Full e-commerce UI** — animated storefront, product detail modal, cart, wishlist, sort/filter, fake checkout flow (QR-code simulation)
- **Auth** — customer signup/login + admin role (PBKDF2-hashed passwords, session tokens)
- **100-product catalog** — real product photography, category/brand/color/price metadata, SQLite-backed
- **Fully containerized** — `docker-compose up` runs the whole stack (app + Ollama + Prometheus + Grafana) with zero manual setup
- **Kubernetes-ready** — Deployment/Service/PVC manifests for the app, model server, and monitoring stack
- **GitOps via ArgoCD** — `k8s/argocd-app.yaml` auto-syncs the cluster whenever `k8s/` changes on `main`
- **Observability** — Prometheus scrapes `/metrics` every 15s; Grafana visualises request rates, latencies, and error counts

## Architecture

```
┌─────────────┐   NL query    ┌──────────────────┐   tool-call    ┌──────────────────┐
│   Browser   │ ────────────▶ │  FastAPI server   │ ─────────────▶ │  Ollama (local)   │
│ (frontend)  │ ◀──────────── │     (main.py)      │ ◀───────────── │   qwen2.5:7b       │
└─────────────┘   JSON resp   └──────────────────┘  structured     └──────────────────┘
                                       │              filters
                                       ▼
                              ┌──────────────────┐
                              │  SQLite (100      │
                              │  products + auth) │
                              └──────────────────┘

                              Observability layer
┌────────────────┐  scrape /metrics  ┌──────────────────┐   query   ┌──────────────┐
│  FastAPI app   │ ─────────────────▶│   Prometheus      │ ─────────▶│   Grafana    │
│  (:8000)       │    every 15s      │   (:9090)         │           │   (:3000)    │
└────────────────┘                   └──────────────────┘           └──────────────┘

                              GitOps layer
┌──────────────┐  watches k8s/  ┌──────────────────┐  kubectl apply  ┌─────────────┐
│  GitHub repo │ ──────────────▶│     ArgoCD        │ ───────────────▶│  Kubernetes │
│  (main)      │  auto-sync     │                   │                 │  cluster    │
└──────────────┘                └──────────────────┘                 └─────────────┘
```

## Tech Stack

| Layer | Tools |
|---|---|
| Backend | Python, FastAPI, SQLite |
| AI / NL search | Ollama (`qwen2.5:7b`), tool-calling |
| Frontend | Vanilla HTML/CSS/JS (no build step) |
| Containers | Docker, Docker Compose |
| Orchestration | Kubernetes (Deployment, Service, PVC, probes) — validated on Minikube |
| GitOps / CD | ArgoCD (auto-sync from `k8s/` on push to `main`) |
| Observability | Prometheus (`/metrics` via `prometheus-fastapi-instrumentator`), Grafana |
| CI/CD | Lint (ruff) → Test (pytest) → Build (Docker) → Scan (Trivy) → Load → Deploy → Smoke test |
| Testing | pytest, FastAPI TestClient |
| Security | Trivy image scanning, PBKDF2 password hashing |

## Quick Start (Docker Compose — easiest)

```bash
cd ai-search-service
docker compose up -d
```

This builds the app, starts Ollama, pulls the model, seeds the database,
and launches Prometheus + Grafana automatically on first run.

| Service | URL |
|---|---|
| App | http://localhost:8000 |
| Metrics | http://localhost:8000/metrics |
| Prometheus | http://localhost:9090 |
| Grafana | http://localhost:3000 (admin / admin) |

## Quick Start (Kubernetes / Minikube — full stack)

One script sets up everything and keeps it running with no port-forwarding:

```bash
# From the project root
./local-up.sh
```

This will:
1. Start Minikube (if not already running)
2. Enable the Nginx Ingress addon
3. Apply all `k8s/` manifests (app, Ollama, Prometheus, Grafana, Ingress)
4. Register the ArgoCD ingress
5. Update `/etc/hosts` and start `minikube tunnel`

All services are then available via local DNS — keep the terminal open:

| Service | URL |
|---|---|
| App | http://styleai.test |
| Prometheus | http://prometheus.test |
| Grafana | http://grafana.test (admin / admin) |
| ArgoCD | https://argocd.test (admin / see below) |

**ArgoCD password:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

> **macOS note:** `.test` domains are used instead of `.local` because macOS
> routes `.local` via mDNS (Bonjour) and ignores `/etc/hosts` for them.

**First-time image build** (if pods show `ImagePullBackOff`):
```bash
cd ai-search-service
docker build -t ai-search-service:ci .
docker save ai-search-service:ci -o /tmp/ai-search.tar
minikube cp /tmp/ai-search.tar /tmp/ai-search.tar
minikube ssh "docker load -i /tmp/ai-search.tar"
kubectl rollout restart deployment/app
```

Or run the full local CI/CD pipeline stage by stage:

```bash
cd ai-search-service
./pipeline.sh build && ./pipeline.sh load && ./pipeline.sh deploy && ./pipeline.sh smoke
```

## Run Locally (no Docker)

```bash
cd ai-search-service
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

ollama pull qwen2.5:7b && ollama serve &   # requires Ollama installed
python3 db.py                               # seeds products.db
uvicorn main:app --reload --port 8000
```

## Project Structure

```
ai-search-service/
├── main.py                  # FastAPI app — search, auth, admin, /metrics
├── db.py                    # DB schema + seed data + image fetching
├── frontend/index.html      # SPA — search, cart, wishlist, checkout
├── prometheus.yml           # Prometheus scrape config (targets app:8000)
├── tests/test_main.py       # pytest suite (13 tests)
├── k8s/
│   ├── app-deployment.yaml  # App Deployment + Service + PVC
│   ├── ollama-deployment.yaml
│   ├── monitoring.yaml      # Prometheus + Grafana Deployments + Services
│   └── argocd-app.yaml      # ArgoCD Application (GitOps auto-sync)
├── pipeline.sh              # Local CI/CD orchestrator, stage-by-stage
├── Dockerfile / docker-compose.yml
└── requirements.txt / requirements-dev.txt
```

## CI/CD Pipeline

**GitHub Actions** (`.github/workflows/ci.yml`) runs Lint → Test → Build →
Scan automatically on every push/PR to `main`. The Deploy and Smoke-test
stages aren't in GitHub Actions yet — GitHub's cloud runners can't reach a
local Minikube cluster, so those stages currently run via `pipeline.sh`
against Minikube locally (see below). Wiring them into CI would need either
a self-hosted runner or a real cloud cluster as the deploy target.

`pipeline.sh` runs every stage (including the local-only ones) standalone or
all together:

```bash
./pipeline.sh lint     # ruff
./pipeline.sh test     # pytest (13 tests, Ollama mocked)
./pipeline.sh build    # docker build
./pipeline.sh scan     # trivy (fails on fixable HIGH/CRITICAL CVEs)
./pipeline.sh load     # minikube image load
./pipeline.sh deploy   # kubectl apply + rollout wait
./pipeline.sh smoke    # /health + /search through port-forward
```

## Monitoring (Prometheus + Grafana)

The app exposes a `/metrics` endpoint (via `prometheus-fastapi-instrumentator`)
with HTTP request counts, latencies, and in-progress requests per route.

**Docker Compose** — metrics stack starts automatically with `docker compose up`.

**Kubernetes** — apply the monitoring manifests:

```bash
kubectl apply -f k8s/monitoring.yaml
```

Then set up Grafana:

1. Open Grafana at `http://$(minikube ip):<NodePort>` (or `http://localhost:3000` for Compose)
2. Log in with `admin` / `admin`
3. Add a Prometheus data source: URL = `http://prometheus:9090`
4. Import dashboard ID **17175** (FastAPI Observability) from grafana.com

## GitOps / ArgoCD

`k8s/argocd-app.yaml` defines an ArgoCD Application that watches `ai-search-service/k8s/`
on `main` and auto-syncs the cluster on every push — no manual `kubectl apply` needed.

**Install ArgoCD on Minikube:**

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

**Register this app:**

```bash
kubectl apply -f k8s/argocd-app.yaml
```

**Access the ArgoCD UI:**

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# open https://localhost:8080
# username: admin
# password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

After this, pushing any change to `k8s/` on `main` will trigger ArgoCD to
automatically reconcile the cluster state.

## Demo Login

| Role | Username | Password |
|---|---|---|
| Admin | `admin` (default) | `admin` (default) |
| Customer | *sign up via the UI* | — |

Admin credentials are seeded from `ADMIN_USERNAME` / `ADMIN_PASSWORD` env
vars (see `.env.example`) — the values above are just the local-dev default.
Override them before deploying anywhere beyond your own machine.

## Known Limitations (by design, for a demo)

- Auth sessions are in-memory (reset on restart) — not production auth
- Catalog limited to 4 colors / 3 categories — constrained by available free product photography
- No real payment processing — checkout is a UI simulation

## License

MIT — built as a personal DevOps portfolio project.
