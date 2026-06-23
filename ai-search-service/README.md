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
- **Fully containerized** — `docker-compose up` runs the whole stack (app + Ollama) with zero manual setup
- **Kubernetes-ready** — Deployment/Service/PVC manifests for both the app and the model server

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
```

## Tech Stack

| Layer | Tools |
|---|---|
| Backend | Python, FastAPI, SQLite |
| AI / NL search | Ollama (`qwen2.5:7b`), tool-calling |
| Frontend | Vanilla HTML/CSS/JS (no build step) |
| Containers | Docker, Docker Compose |
| Orchestration | Kubernetes (Deployment, Service, PVC, probes) — validated on Minikube |
| CI/CD | Lint (ruff) → Test (pytest) → Build (Docker) → Scan (Trivy) → Load → Deploy → Smoke test |
| Testing | pytest, FastAPI TestClient |
| Security | Trivy image scanning, PBKDF2 password hashing |

## Quick Start (Docker Compose — easiest)

```bash
cd ai-search-service
docker compose up -d
```

This builds the app, starts Ollama, pulls the model, and seeds the database
automatically on first run. Visit **http://localhost:8000**.

## Quick Start (Kubernetes / Minikube)

```bash
minikube start --memory=7000 --cpus=4
./pipeline.sh build        # build the image
./pipeline.sh load         # load it into Minikube
./pipeline.sh deploy       # apply k8s/ manifests
./pipeline.sh smoke        # verify /health and /search
```

Or run the whole CI/CD pipeline in one shot:

```bash
./pipeline.sh all
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
├── main.py                  # FastAPI app — search, auth, admin endpoints
├── db.py                    # DB schema + seed data + image fetching
├── frontend/index.html      # SPA — search, cart, wishlist, checkout
├── tests/test_main.py       # pytest suite (13 tests)
├── k8s/                     # Kubernetes manifests (app + ollama)
├── pipeline.sh              # Local CI/CD orchestrator, stage-by-stage
├── Dockerfile / docker-compose.yml
└── requirements.txt / requirements-dev.txt
```

## CI/CD Pipeline

`pipeline.sh` runs each stage standalone or all together:

```bash
./pipeline.sh lint     # ruff
./pipeline.sh test     # pytest (13 tests, Ollama mocked)
./pipeline.sh build    # docker build
./pipeline.sh scan     # trivy (fails on fixable HIGH/CRITICAL CVEs)
./pipeline.sh load     # minikube image load
./pipeline.sh deploy   # kubectl apply + rollout wait
./pipeline.sh smoke    # /health + /search through port-forward
```

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
