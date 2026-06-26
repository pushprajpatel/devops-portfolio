# DevOps Portfolio

[![CI](https://github.com/pushprajpatel/devops-portfolio/actions/workflows/ci.yml/badge.svg)](https://github.com/pushprajpatel/devops-portfolio/actions/workflows/ci.yml)

A collection of projects demonstrating end-to-end DevOps practices —
containerization, orchestration, CI/CD, and infrastructure-as-code.

## Projects

### [StyleAI — AI-Powered E-commerce Search](./ai-search-service)

A full-stack e-commerce app with a locally-hosted LLM for natural-language
product search, fully containerized and deployed to Kubernetes. Covers:

- Docker + Docker Compose multi-service setup (app + local LLM)
- Kubernetes manifests (Deployment, Service, PVC, health probes)
- A complete CI/CD pipeline (lint → test → build → security scan → deploy →
  smoke test), validated end-to-end on Minikube
- GitOps continuous delivery via ArgoCD (auto-sync from `k8s/`)
- Observability with Prometheus metrics (`/metrics`) + Grafana dashboards
- Automated testing (pytest) and linting (ruff)
- Container image vulnerability scanning (Trivy)

See [`ai-search-service/README.md`](./ai-search-service/README.md) for full
setup instructions, architecture, and a feature walkthrough.

### [Terraform — AWS Deployment](./terraform)

Provisions the same app onto AWS: an Application Load Balancer in front of
an Auto Scaling Group of EC2 instances, each bootstrapping itself via
`user_data` (Docker install → clone repo → `docker compose up`).

See [`terraform/README.md`](./terraform/README.md) for step-by-step deploy
instructions. ⚠️ Creates real, billable AWS resources — nothing runs
automatically, and remember to `terraform destroy` when done.

---

More projects coming soon.
