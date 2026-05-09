# azure-finops-dashboard

![Azure](https://img.shields.io/badge/Azure-0078D4?style=flat&logo=microsoftazure&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=flat&logo=python&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=flat&logo=terraform&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-F46800?style=flat&logo=grafana&logoColor=white)
![Next.js](https://img.shields.io/badge/Next.js-000000?style=flat&logo=nextdotjs&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=flat&logo=postgresql&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=flat&logo=prometheus&logoColor=white)
![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)

A production-grade, multi-subscription Azure FinOps dashboard — combining a Python cost collector, PostgreSQL historical storage, Prometheus real-time metrics, Grafana ops dashboards, and a Next.js stakeholder web UI with budget alerting via Alertmanager.

> Built by [Syed Muhammad Ali Haidry](https://alihaidry-devops.website) — Senior DevOps Engineer · [alihaidry.dev](https://alihaidry-devops.website)

---

## What this project does

- Pulls daily cost and usage data from **multiple Azure subscriptions** via the Azure Cost Management API
- Enriches spend data with **resource tags** (team, environment, owner, project)
- Stores historical cost records in **PostgreSQL** for trend analysis and forecasting
- Exposes real-time cost metrics to **Prometheus** for alerting and time-series queries
- Visualises ops-level spend in **Grafana** (anomaly detection, burn rate, daily breakdown)
- Serves a clean **Next.js stakeholder dashboard** showing cost by team, budget progress, and 30-day forecasts
- Fires **Slack and email alerts** when budgets hit 80% (warning) or 100% (critical)

---

## Architecture

```
Azure Subscriptions (A · B · C)
         │  Cost Management API
         ▼
   Python Collector  ──────────────────────────┐
   (scheduled daily)                           │
         │                                     │
    ┌────┴────┐                         ┌──────▼──────┐
    │PostgreSQL│                         │ Prometheus  │
    │ history  │                         │  metrics    │
    └────┬────┘                         └──────┬──────┘
         │                                     │
    ┌────▼────────────┐              ┌──────────▼──────┐
    │ Next.js          │              │   Grafana        │
    │ Stakeholder UI   │              │   Ops dashboard  │
    └─────────────────┘              └──────────┬──────┘
                                                │
                                     ┌──────────▼──────┐
                                     │  Alertmanager    │
                                     │  Slack · Email   │
                                     └─────────────────┘
```

→ Full architecture diagram: [docs/architecture.md](docs/architecture.md)

---

## Tech stack

| Layer | Tool | Purpose |
|---|---|---|
| IaC | Terraform | Provisions all Azure resources |
| Data source | Azure Cost Management API | Multi-subscription cost + usage data |
| Collector | Python 3.12 | Scheduled fetch, tag enrichment, normalisation |
| Historical store | PostgreSQL | Cost history, budgets, forecasts |
| Real-time metrics | Prometheus | Cost as metrics, scrape endpoint |
| Alerting | Alertmanager | Budget breach → Slack / email |
| Ops dashboard | Grafana | Spend over time, anomaly detection |
| Stakeholder UI | Next.js 14 | Cost by team/tag, budget progress, forecasts |
| CI/CD | GitHub Actions + OIDC | Build, test, deploy pipeline |
| Secrets | Azure Key Vault | All credentials — no hardcoded secrets |

---

## Quick start

### Prerequisites

- Azure CLI (`az --version`)
- Terraform ≥ 1.6 (`terraform --version`)
- Python 3.12+ (`python --version`)
- Node.js 20+ (`node --version`)
- Docker (`docker --version`)
- PostgreSQL client (`psql --version`)

### 1 — Clone the repo

```bash
git clone https://github.com/AliHaidry/azure-finops-dashboard.git
cd azure-finops-dashboard
```

### 2 — Provision infrastructure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Fill in your subscription IDs and config
terraform init
terraform apply
```

### 3 — Configure and run the collector

```bash
cd collector
cp .env.example .env
# Fill in your Azure credentials and DB connection string
pip install -r requirements.txt
python collector.py
```

### 4 — Start the Next.js dashboard

```bash
cd dashboard
cp .env.local.example .env.local
npm install
npm run dev
# Open http://localhost:3000
```

### 5 — Import Grafana dashboards

```bash
# Import JSON files from grafana/dashboards/
# See docs/dashboards.md for step-by-step instructions
```

→ Full setup guide: [docs/setup-guide.md](docs/setup-guide.md)

---

## Documentation

| Document | Description |
|---|---|
| [Architecture](docs/architecture.md) | Full architecture, design decisions, data flow |
| [Setup Guide](docs/setup-guide.md) | Phase-by-phase setup from scratch |
| [Collector](docs/collector.md) | Python collector deep-dive |
| [Dashboards](docs/dashboards.md) | Grafana dashboard guide |
| [Alerts](docs/alerts.md) | Alertmanager rules and routing |
| [API Reference](docs/api-reference.md) | Next.js API endpoints |
| [Terraform](docs/terraform.md) | IaC reference |
| [Runbook](docs/runbook.md) | Day-2 operations and troubleshooting |

---

## Blog post

→ [How I built a multi-subscription Azure FinOps dashboard](https://alihaidry-devops.website/blog/azure-finops-dashboard) *(coming soon)*

---

## License

MIT — see [LICENSE](LICENSE)

---

## Author

**Syed Muhammad Ali Haidry** · Senior DevOps Engineer  
[alihaidry-devops.website](https://alihaidry-devops.website) · [GitHub](https://github.com/AliHaidry) · [LinkedIn](https://www.linkedin.com/in/ali-haidry-meng-7b5ba9136/)
