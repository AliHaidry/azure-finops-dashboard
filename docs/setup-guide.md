# Setup Guide

Complete phase-by-phase setup from a fresh clone to a fully running FinOps dashboard.

**Total time:** ~4-5 hours  
**Prerequisites:** Azure subscription (Pay-as-you-go), GitHub account, tools below

---

## Prerequisites check

```bash
az --version          # Azure CLI
terraform --version   # >= 1.6
python --version      # >= 3.12
node --version        # >= 20
docker --version      # Docker Desktop
git --version
```

---

## Phase 1 — Infrastructure (Terraform)

### Step 1 — Bootstrap remote state backend

```bash
chmod +x terraform/bootstrap-backend.sh
./terraform/bootstrap-backend.sh
# Creates: finops-tfstate-rg + finopstfstateali storage account
```

### Step 2 — Configure variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
code terraform.tfvars  # Fill in your values
```

```hcl
subscription_ids = [
  "24838f8a-cebe-4693-81d3-26d6b74b47cd",  # dev
  "dd844520-0912-4407-b70b-53e40e499dfb",  # infra
  "f99345eb-69a8-455e-82d7-25706b78ccaf",  # poc
]
location    = "eastus2"
environment = "dev"
github_org  = "AliHaidry"
github_repo = "azure-finops-dashboard"
```

### Step 3 — Deploy

```bash
terraform init
terraform plan
terraform apply
# ~10-15 minutes
```

### Step 4 — Save outputs

```bash
terraform output github_secrets_summary
# Configure the 7 GitHub secrets shown
terraform output pg_connection_string
# Save this for collector .env
```

**Phase 1 creates:**
- Resource group `finops-rg-dev`
- PostgreSQL `finops-pg-dev.postgres.database.azure.com`
- Key Vault `finopskvalidev`
- Container Registry `finopsacralidev`
- OIDC app registration + federated credentials
- Cost Management Reader on all 3 subscriptions

---

## Phase 2 — Python Collector

### Step 1 — Install dependencies

```bash
cd collector
python -m venv venv
source venv/Scripts/activate    # Windows Git Bash
pip install -r requirements.txt --only-binary=:all:
```

### Step 2 — Configure environment

```bash
cp .env.example .env
code .env
```

```bash
SUBSCRIPTION_IDS=24838f8a...,dd844520...,f99345eb...
DATABASE_URL=postgresql://finops_admin:PASSWORD@finops-pg-dev.postgres.database.azure.com:5432/finops_db?sslmode=require
CURRENCY=USD
PROMETHEUS_PORT=8000
LOG_LEVEL=INFO
```

> Note: URL-encode special characters in password using `python -c "from urllib.parse import quote; print(quote('YOUR_PASS', safe=''))"`

### Step 3 — Add local firewall rule

```bash
az postgres flexible-server firewall-rule create \
  --resource-group finops-rg-dev \
  --name finops-pg-dev \
  --rule-name AllowMyLocalIP \
  --start-ip-address $(curl -4 -s icanhazip.com) \
  --end-ip-address $(curl -4 -s icanhazip.com)
```

### Step 4 — Run collector

```bash
python collector.py --backfill 7
# Verify: "Collection complete — N total records written"
# Keep running: "Metrics server running — press Ctrl+C to stop"
```

### Step 5 — Configure GitHub secrets

Go to repo → Settings → Secrets → Actions → add:

| Secret | Value |
|---|---|
| `AZURE_CLIENT_ID` | from `terraform output github_actions_client_id` |
| `AZURE_TENANT_ID` | from `terraform output tenant_id` |
| `AZURE_SUBSCRIPTION_ID` | your primary subscription ID |
| `SUBSCRIPTION_IDS` | all 3 IDs comma-separated |
| `DATABASE_URL` | PostgreSQL connection string |
| `ACR_LOGIN_SERVER` | from `terraform output acr_login_server` |
| `ACR_NAME` | from `terraform output acr_name` |

---

## Phase 3 — Grafana + Prometheus

### Step 1 — Start Docker stack

```bash
# Ensure Docker Desktop is running
docker-compose up -d
# Grafana:    http://localhost:3000 (admin / finops123)
# Prometheus: http://localhost:9090
```

### Step 2 — Verify metrics

```bash
# Check collector is exposing metrics
curl http://localhost:8000/metrics | grep azure_cost
```

### Step 3 — Seed budgets

```bash
cd collector
python -c "
import psycopg2, os
from dotenv import load_dotenv
load_dotenv()
conn = psycopg2.connect(os.getenv('DATABASE_URL'))
cur = conn.cursor()
cur.execute('''
INSERT INTO budgets (team, subscription_id, monthly_limit_usd)
VALUES
  ('finops-rg-dev', 'f99345eb-69a8-455e-82d7-25706b78ccaf', 5.00),
  ('finops-tfstate-rg', 'f99345eb-69a8-455e-82d7-25706b78ccaf', 1.00)
ON CONFLICT DO NOTHING;
''')
conn.commit()
conn.close()
print('Budgets seeded!')
"
```

### Step 4 — Import Grafana dashboards

1. Grafana → Dashboards → Import
2. Upload JSON files from `grafana/dashboards/`
3. Select Prometheus as data source

---

## Phase 4 — Next.js Dashboard

### Step 1 — Install and configure

```bash
cd dashboard
npm install
cp .env.local.example .env.local
code .env.local
# Add: DATABASE_URL=your-connection-string
```

### Step 2 — Run

```bash
npm run dev
# Open: http://localhost:3001
```

### Step 3 — Verify

- Total MTD Spend card shows data
- Budget progress bars visible
- Cost by Service donut chart rendering
- Daily Spend Trend line chart showing dates
- Service Breakdown table populated
- CSV Export button downloads file

---

## Daily operations

### Start everything for development

```bash
# Terminal 1 — start PostgreSQL
az postgres flexible-server start --resource-group finops-rg-dev --name finops-pg-dev

# Terminal 2 — run collector (keep open for Prometheus)
cd collector && source venv/Scripts/activate
python collector.py --backfill 1

# Terminal 3 — start Docker
docker-compose up -d

# Terminal 4 — start dashboard
cd dashboard && npm run dev
```

### Stop everything

```bash
# Stop Docker
docker-compose down

# Stop PostgreSQL (saves ~$0.43/day)
az postgres flexible-server stop --resource-group finops-rg-dev --name finops-pg-dev
```

---

## Verification checklist

```
Phase 1 — Infrastructure
  [ ] terraform apply completes with 0 errors
  [ ] PostgreSQL accessible from local machine
  [ ] GitHub secrets all configured (7 secrets)

Phase 2 — Collector
  [ ] python collector.py --backfill 7 writes records
  [ ] GitHub Actions FinOps Collector workflow succeeds
  [ ] localhost:8000/metrics shows azure_cost_* metrics

Phase 3 — Grafana
  [ ] All 4 dashboards loading with live data
  [ ] Budget Utilisation gauge showing %
  [ ] Prometheus targets showing finops_collector UP

Phase 4 — Dashboard
  [ ] localhost:3001 loads without errors
  [ ] All KPI cards showing values
  [ ] Charts rendering correctly
  [ ] CSV export working
```
