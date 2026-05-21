# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

---

## [Unreleased] — Phase 5 + 6

### Planned
- Full Azure deployment (App Service, Container Instances)
- Alertmanager with Slack + email integration
- Nginx reverse proxy with SSL
- Blog post on alihaidry-devops.website
- Portfolio card on projects page
- Complete Word document

---

## [0.4.0] — Phase 4 Complete

### Added
- Next.js 16 stakeholder dashboard (`dashboard/`)
- KPI cards: Total MTD spend, projected month-end, highest cost service
- Budget utilisation progress bars with On track / Warning / Exceeded status
- Cost by Service donut chart (recharts)
- Cost by Team bar chart with interactive tooltips
- Daily Spend Trend line chart — last 30 days
- Service Breakdown table with % of total
- CSV export endpoint (`/api/export`)
- REST API (`/api/costs`) returning all cost + budget data
- PostgreSQL connection pooling via `pg` library
- 30-day linear cost forecast

---

## [0.3.0] — Phase 3 Complete

### Added
- Docker Compose stack: Prometheus + Grafana
- Prometheus scrape config for collector `/metrics` endpoint
- 4 Grafana dashboards:
  - FinOps Overview (total MTD, pie chart, daily trend, cost by team)
  - Budget Burn Rate (gauges, MTD progress, spend by subscription)
  - Cost by Team (table, bar chart, daily trend, highest cost service)
  - Anomaly Detection (spend vs 7-day avg, collector health)
- Prometheus alert rules: AzureBudgetWarning, AzureBudgetCritical, AzureCostAnomaly, AzureCostSpike, CollectorDown
- Budget seeding via Python psycopg2 script
- Grafana datasource auto-provisioning
- Dashboard JSON exports to `grafana/dashboards/`

### Fixed
- Budget utilisation metric query — removed subscription_name filter from JOIN
- Prometheus scrape interval reduced to 15s for local development

---

## [0.2.0] — Phase 2 Complete

### Added
- Python cost collector (`collector/collector.py`)
- Azure Cost Management API integration (3 subscriptions)
- Tag enrichment: team, environment, owner, project
- PostgreSQL schema: cost_records, budgets, forecasts tables
- Upsert with deduplication on (usage_date, resource_id, subscription_id)
- Prometheus metrics endpoint (:8000/metrics)
- 8 Prometheus metrics: azure_cost_daily_usd, azure_cost_by_team_usd, azure_cost_by_service_usd, azure_budget_utilisation_percent, azure_cost_anomaly_score, azure_collector_last_run_timestamp, azure_collector_records_collected_total, azure_collector_errors_total
- GitHub Actions workflow (`collector.yml`) — daily 06:00 UTC
- Auto-start/stop PostgreSQL in GitHub Actions workflow
- OIDC keyless authentication in CI
- Local firewall rule for development access

### Fixed
- psycopg2-binary Windows installation — use `--only-binary=:all:`
- DATABASE_URL special character URL encoding
- ON CONFLICT duplicate row error — deduplication before upsert
- Collector keep-alive loop for Prometheus scraping

---

## [0.1.0] — Phase 1 Complete

### Added
- Terraform remote backend (Azure Storage: finopstfstateali)
- Resource group: finops-rg-dev (eastus2)
- PostgreSQL Flexible Server: finops-pg-dev (B_Standard_B1ms, PG16)
- Key Vault: finopskvalidev
- Container Registry: finopsacralidev (Basic)
- App Registration + OIDC federation for GitHub Actions
- Cost Collector service principal
- Cost Management Reader role on all 3 subscriptions
- GitHub secrets configured (7 secrets)
- Complete documentation: architecture, setup-guide, collector, dashboards, alerts, api-reference, terraform, runbook

### Notes
- App Service skipped — quota limit on free tier (resolved: Pay-as-you-go)
- Key Vault renamed finopskvalidev (global name conflict)
- ACR renamed finopsacralidev (global name conflict)
