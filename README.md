# azure-finops-dashboard

![Azure](https://img.shields.io/badge/Azure-0078D4?style=flat&logo=microsoftazure&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=flat&logo=python&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=flat&logo=terraform&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-F46800?style=flat&logo=grafana&logoColor=white)
![Next.js](https://img.shields.io/badge/Next.js-000000?style=flat&logo=nextdotjs&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=flat&logo=postgresql&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=flat&logo=prometheus&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat&logo=docker&logoColor=white)
![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)

A production-grade, multi-subscription Azure FinOps dashboard — combining a Python cost collector, PostgreSQL historical storage, Prometheus real-time metrics, Grafana ops dashboards, and a Next.js stakeholder web UI with budget alerting.

> Built by [Syed Muhammad Ali Haidry](https://alihaidry-devops.website) — Senior DevOps Engineer

---

## What this project does

- Pulls daily cost data from **3 Azure subscriptions** via the Cost Management API
- Enriches spend with **resource tags** (team, environment, owner, project)
- Stores history in **PostgreSQL** for trend analysis and 30-day forecasting
- Exposes real-time cost metrics to **Prometheus**
- Visualises spend in **4 Grafana dashboards** (overview, budget, teams, anomaly)
- Serves a **Next.js stakeholder dashboard** with budget progress bars and CSV export
- Runs **fully automated** via GitHub Actions — daily OIDC keyless collection

---

## Architecture

```
Azure Subscriptions (dev · infra · poc)
         │  Cost Management API
         ▼
   Python Collector — GitHub Actions 06:00 UTC
   OIDC auth · tag enrichment · deduplication
         │
    ┌────┴────────────┐
    │   PostgreSQL     │   Historical records · budgets
    └────┬────────────┘
         │
    ┌────┴──────────────────────┐
    │       Prometheus           │   azure_cost_daily_usd
    │       :8000/metrics        │   azure_budget_utilisation_%
    └────┬──────────────────────┘
         │
    ┌────┴──────────┐    ┌──────────────────────┐
    │    Grafana     │    │  Next.js Dashboard    │
    │  4 dashboards  │    │  Budget · Forecast    │
    └────┬──────────┘    │  CSV export           │
         │               └──────────────────────┘
    ┌────┴──────────┐
    │  Alertmanager  │   Slack · Email alerts
    └───────────────┘
```

→ Full architecture: [docs/architecture.md](docs/architecture.md)

---

## Tech stack

| Layer | Tool | Purpose |
|---|---|---|
| IaC | Terraform | All Azure resources |
| Data source | Azure Cost Management API | Multi-subscription cost data |
| Collector | Python 3.12 | Fetch · enrich · normalise |
| Store | PostgreSQL 16 | Cost history · budgets · forecasts |
| Metrics | Prometheus | Real-time cost gauges |
| Alerting | Alertmanager | Budget breach → Slack / email |
| Ops UI | Grafana | 4 dashboards |
| Stakeholder UI | Next.js 16 | Budget progress · forecast · CSV |
| CI/CD | GitHub Actions + OIDC | Daily collection · keyless auth |
| Secrets | Azure Key Vault | No hardcoded credentials |
| Containers | Docker Compose | Local Prometheus + Grafana |

---

## Project structure

```
azure-finops-dashboard/
├── .github/workflows/collector.yml   ← Daily 06:00 UTC
├── collector/
│   ├── collector.py                  ← Cost collector
│   ├── requirements.txt
│   └── .env.example
├── dashboard/                        ← Next.js UI
│   ├── app/
│   │   ├── page.tsx
│   │   └── api/costs · export
│   └── lib/db.ts
├── docs/                             ← Full documentation
├── grafana/
│   ├── dashboards/                   ← JSON exports
│   └── provisioning/datasources/
├── prometheus/
│   ├── prometheus.yml
│   └── alerts/finops-alerts.yml
├── terraform/                        ← IaC
│   ├── main.tf · variables.tf · outputs.tf
│   ├── bootstrap-backend.sh
│   └── modules/database · keyvault · registry · webapp · oidc
├── docker-compose.yml
├── CHANGELOG.md
└── README.md
```

---

## Quick start

### Prerequisites
- Azure CLI · Terraform ≥ 1.6 · Python 3.12+ · Node.js 20+ · Docker Desktop

### 1 — Infrastructure
```bash
./terraform/bootstrap-backend.sh
cd terraform && cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

### 2 — Collector
```bash
cd collector
python -m venv venv && source venv/Scripts/activate
pip install -r requirements.txt --only-binary=:all:
cp .env.example .env  # Add DATABASE_URL from terraform output
python collector.py --backfill 7
```

### 3 — Grafana + Prometheus
```bash
docker-compose up -d
# Grafana: http://localhost:3000 (admin / finops123)
```

### 4 — Stakeholder dashboard
```bash
cd dashboard && npm install
cp .env.local.example .env.local  # Add DATABASE_URL
npm run dev
# Open: http://localhost:3001
```

→ Full guide: [docs/setup-guide.md](docs/setup-guide.md)

---

## GitHub Actions pipeline

```
Schedule 06:00 UTC → OIDC auth → Start PostgreSQL
→ Collect 3 subscriptions → Write DB → Stop PostgreSQL
```

**Required secrets:** `AZURE_CLIENT_ID` · `AZURE_TENANT_ID` · `AZURE_SUBSCRIPTION_ID` · `SUBSCRIPTION_IDS` · `DATABASE_URL` · `ACR_LOGIN_SERVER` · `ACR_NAME`

---

## Grafana dashboards

| Dashboard | Key panels |
|---|---|
| **FinOps Overview** | Total MTD, cost by service pie, daily trend, cost by team |
| **Budget Burn Rate** | Utilisation gauges (19.2%, 0.02%), MTD progress, by subscription |
| **Cost by Team** | Team table, bar chart, daily trend, highest cost service |
| **Anomaly Detection** | Spend vs 7-day average, collector health, records count |

---

## Live data

```
Total MTD Spend:       $0.958
Projected Month-End:   $1.414

Top services:
  Container Registry    $0.505  52.8%
  PostgreSQL            $0.452  47.2%

Budget status:
  finops-rg-dev    19.2% of $5.00  On track
  finops-tfstate-rg  0.0% of $1.00  On track
```

---

## Roadmap

- [x] Phase 1 — Terraform infrastructure
- [x] Phase 2 — Python collector + GitHub Actions
- [x] Phase 3 — Grafana dashboards
- [x] Phase 4 — Next.js stakeholder dashboard
- [ ] Phase 5 — Full Azure deployment + Alerting
- [ ] Phase 6 — Blog post + portfolio card + Word doc

---

## Documentation

[Architecture](docs/architecture.md) · [Setup Guide](docs/setup-guide.md) · [Collector](docs/collector.md) · [Dashboards](docs/dashboards.md) · [Alerts](docs/alerts.md) · [API Reference](docs/api-reference.md) · [Terraform](docs/terraform.md) · [Runbook](docs/runbook.md)

---

## Author

**Syed Muhammad Ali Haidry** · Senior DevOps Engineer  
[alihaidry-devops.website](https://alihaidry-devops.website) · [GitHub](https://github.com/AliHaidry) · [LinkedIn](https://www.linkedin.com/in/ali-haidry-meng-7b5ba9136/)
