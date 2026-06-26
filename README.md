# DevOps Portfolio

[![CI](https://github.com/pushprajpatel/devops-portfolio/actions/workflows/ci.yml/badge.svg)](https://github.com/pushprajpatel/devops-portfolio/actions/workflows/ci.yml)

A collection of projects demonstrating end-to-end DevOps engineering — containerisation, Kubernetes orchestration, GitOps, observability, alerting, autoscaling, CI/CD automation, and cloud infrastructure provisioning.

---

## Projects

### [StyleAI — AI-Powered E-commerce Search](./ai-search-service)

![StyleAI App](./screenshots/app.png)

A production-grade e-commerce application powered by a locally-hosted LLM that parses natural-language product queries into structured database filters — with a complete DevOps stack running end-to-end on Kubernetes.

**What's covered:**

| Area | Implementation |
|---|---|
| Containers | Docker, Docker Compose (app + Ollama + Prometheus + Grafana) |
| Orchestration | Kubernetes — Deployment, Service, PVC, health probes, Ingress |
| Autoscaling | HorizontalPodAutoscaler — 1–5 replicas based on CPU & memory |
| GitOps | ArgoCD — auto-syncs `k8s/` to the cluster on every push to `main` |
| CI/CD | GitHub Actions — lint → test → build → Trivy scan → push to GHCR |
| Observability | Prometheus metrics, Grafana dashboards (request rate, latency, errors) |
| Alerting | Prometheus alert rules (app down, high error rate, high latency) + Alertmanager |
| Security | Trivy image scanning, PBKDF2 password hashing, no secrets in source |
| IaC | Terraform — AWS ALB + Auto Scaling Group of EC2 instances |

**One-command setup** — installs all dependencies and brings up the full stack:
```bash
git clone https://github.com/pushprajpatel/devops-portfolio.git
cd devops-portfolio
./local-up.sh
```

| Service | URL |
|---|---|
| App | http://styleai.test |
| Grafana | http://grafana.test |
| Prometheus | http://prometheus.test |
| ArgoCD | https://argocd.test |

See [`ai-search-service/README.md`](./ai-search-service/README.md) for full setup instructions, architecture diagrams, and feature details.

---

### [Terraform — AWS Deployment](./terraform)

Provisions the same application onto AWS: an Application Load Balancer in front of an Auto Scaling Group of EC2 instances, each bootstrapping itself via `user_data` (Docker install → clone repo → `docker compose up`).

See [`terraform/README.md`](./terraform/README.md) for step-by-step instructions.

> ⚠️ Creates real, billable AWS resources. Nothing runs automatically — remember to `terraform destroy` when finished.

---

More projects coming soon.
