# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).  
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Planned
- Thanos integration for long-term Prometheus storage
- Azure Policy enforcement for required resource tags
- Multi-currency support (GBP, EUR)
- Slack slash command for on-demand cost queries
- Cost anomaly ML model (replace simple deviation score)

---

## [1.0.0] - TBD

### Added
- Multi-subscription Azure cost collection via Cost Management API
- Python collector with tag enrichment and currency normalisation
- PostgreSQL schema: `cost_records`, `budgets`, `forecasts` tables
- Prometheus metrics endpoint (`/metrics`) with 8 cost metrics
- Grafana dashboards: Overview, By Team, Budget Burn Rate, Anomaly Detection
- Next.js stakeholder dashboard with cost by team, budget progress, 30-day forecasts
- CSV export endpoint for finance reporting
- Alertmanager routing: warning → Slack, critical → Slack + email
- Terraform infrastructure: PostgreSQL, App Service, Key Vault, ACR, OIDC
- GitHub Actions CI/CD pipeline with OIDC keyless authentication
- Complete documentation: architecture, setup guide, collector, dashboards, alerts, API reference, Terraform, runbook
