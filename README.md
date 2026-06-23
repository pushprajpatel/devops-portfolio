# DevOps Portfolio

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
- Automated testing (pytest) and linting (ruff)
- Container image vulnerability scanning (Trivy)

See [`ai-search-service/README.md`](./ai-search-service/README.md) for full
setup instructions, architecture, and a feature walkthrough.

---

More projects coming soon.
