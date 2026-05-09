# Architecture

## Overview

`azure-finops-dashboard` follows a **4-layer pipeline** architecture:

1. **Sources** — Azure subscriptions expose cost data via the Cost Management API
2. **Collect** — A Python control plane fetches, enriches, and normalises the data
3. **Store** — PostgreSQL holds historical records; Prometheus holds real-time metrics
4. **Visualise** — Grafana (ops) and Next.js (stakeholders) render the data; Alertmanager fires alerts

The design principle is **separation of concerns**: the collector doesn't know about dashboards, dashboards don't know about subscriptions, and alerts don't depend on the UI being up.

---

## Component diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     Azure Subscriptions                          │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Subscription │  │ Subscription │  │ Subscription │          │
│  │      A       │  │      B       │  │      C       │          │
│  │  Production  │  │  Dev/Staging │  │   Sandbox    │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         └─────────────────┼─────────────────┘                   │
│                           │ Cost Management API                  │
└───────────────────────────┼─────────────────────────────────────┘
                            │
                   ┌────────▼────────┐
                   │  Python         │
                   │  Collector      │  ← Scheduled daily (cron / Azure Function)
                   │                 │    Enriches with resource tags
                   └────────┬────────┘    Normalises across subscriptions
                            │
               ┌────────────┴────────────┐
               │                         │
      ┌────────▼────────┐     ┌──────────▼──────────┐
      │   PostgreSQL    │     │     Prometheus        │
      │                 │     │                       │
      │ Cost history    │     │ Real-time cost        │
      │ Budget records  │     │ metrics endpoint      │
      │ Forecasts       │     │ /metrics              │
      └────────┬────────┘     └──────────┬────────────┘
               │                         │
      ┌────────▼────────┐     ┌──────────▼────────────┐
      │   Next.js        │     │      Grafana           │
      │   Dashboard      │     │      Dashboards        │
      │                 │     │                        │
      │ Cost by team    │     │ Spend over time        │
      │ Budget progress │     │ Anomaly detection      │
      │ 30-day forecast │     │ Burn rate gauge        │
      └─────────────────┘     └──────────┬────────────┘
                                         │
                              ┌──────────▼────────────┐
                              │    Alertmanager        │
                              │                        │
                              │ >80% budget → warning  │
                              │ >100% budget → critical│
                              └──────────┬────────────┘
                                         │
                              ┌──────────▼────────────┐
                              │  Slack · Email         │
                              └───────────────────────┘
```

---

## Data flow — end to end

### Step 1 — Collection (daily, scheduled)

1. Python collector authenticates to Azure using a **Service Principal with OIDC** — no stored passwords
2. For each configured subscription, calls `Azure Cost Management API` (`/providers/Microsoft.CostManagement/query`)
3. Returns: resource name, resource group, service name, cost (USD), usage quantity, date
4. Enriches each record with **resource tags**: `team`, `environment`, `owner`, `project`
5. Normalises currency across subscriptions (all stored as USD)
6. Writes records to PostgreSQL `cost_records` table
7. Updates Prometheus gauge metrics via `/metrics` endpoint

### Step 2 — Storage

**PostgreSQL** stores:
- `cost_records` — daily cost per resource, enriched with tags
- `budgets` — configured monthly budgets per subscription/team
- `forecasts` — 30-day linear projections computed nightly

**Prometheus** tracks:
- `azure_cost_daily_usd` — daily spend per subscription
- `azure_cost_by_team_usd` — spend per resource tag `team`
- `azure_budget_utilisation_percent` — % of monthly budget consumed
- `azure_cost_anomaly_score` — deviation from 7-day rolling average

### Step 3 — Visualisation

**Grafana** (ops team):
- Queries Prometheus for real-time metrics and trends
- Anomaly detection panel alerts when daily spend > 2× 7-day average
- Budget burn-rate gauge shows projected month-end spend

**Next.js dashboard** (stakeholders):
- Queries PostgreSQL via internal REST API
- Cost breakdown by team tag, environment, subscription
- Budget progress bars per team
- 30-day forecast with confidence range
- CSV export for finance team

### Step 4 — Alerting

Alertmanager receives alerts fired by Prometheus recording rules:
- `AzureBudgetWarning` — utilisation > 80% → Slack `#finops-alerts` (warning)
- `AzureBudgetCritical` — utilisation > 100% → Slack + email (critical)
- `AzureCostAnomaly` — daily spend > 2× rolling average → Slack (warning)
- `AzureCostSpike` — daily spend > 3× rolling average → Slack + email (critical)

---

## Design decisions

### Why multiple subscriptions?

Enterprise Azure environments almost always span multiple subscriptions — one per environment (prod/dev/sandbox) or one per business unit. A single-subscription FinOps tool doesn't reflect real-world complexity. This project simulates the enterprise pattern from day one.

### Why both PostgreSQL and Prometheus?

They serve different purposes:
- **PostgreSQL** is for *history* — you need months of cost data for trend analysis, forecasting, and budget tracking. Prometheus has a configurable retention (typically 15-30 days) and is not designed for analytical queries.
- **Prometheus** is for *real-time ops* — alerting, anomaly detection, and Grafana time-series panels work best with Prometheus's query language (PromQL).

### Why Next.js for the stakeholder UI?

Grafana is powerful but requires an account and is designed for engineers. Finance managers and team leads need a simpler view: "how much did my team spend this month vs budget?" — with no PromQL, no panels, no data sources. Next.js gives full control over the UX for that audience.

### Why OIDC over Service Principal secrets?

Following the same pattern as `paktech-hello` — no long-lived credentials stored anywhere. GitHub Actions and Azure authenticate via federated identity tokens. Key Vault stores any remaining secrets the collector needs.

---

## Security considerations

| Concern | Mitigation |
|---|---|
| Azure credentials | OIDC federation — no stored secrets |
| Database credentials | Azure Key Vault — injected at runtime |
| API authentication | Next.js API routes protected by API key header |
| Prometheus endpoint | Bound to localhost — not exposed externally |
| Grafana access | Behind Nginx reverse proxy with SSL |
| PostgreSQL access | Private Azure network — not publicly reachable |

---

## Infrastructure — what Terraform provisions

| Resource | Purpose |
|---|---|
| Azure Resource Group | Logical container for all FinOps resources |
| Azure PostgreSQL Flexible Server | Cost history database |
| Azure App Service | Hosts the Next.js dashboard |
| Azure Key Vault | Stores all secrets |
| Azure Container Registry | Stores collector Docker image |
| App Registration + OIDC | Keyless auth for GitHub Actions |
| Role assignments | Least-privilege access per component |

→ Full Terraform reference: [terraform.md](terraform.md)
