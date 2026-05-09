# Setup Guide

Complete phase-by-phase setup from a fresh clone to a fully running FinOps dashboard.

**Total time:** ~3-4 hours  
**Prerequisites:** Azure subscription, GitHub account, tools listed in README

---

## Phase 1 — Infrastructure provisioning (Terraform)

### Step 1 — Login to Azure

```bash
az login
az account show --query name -o tsv
# Verify the correct subscription is active
```

### Step 2 — Configure Terraform variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
# Azure
subscription_ids = [
  "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",  # Subscription A (Production)
  "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy",  # Subscription B (Dev/Staging)
  "zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz"  # Subscription C (Sandbox)
]
location    = "eastus2"
environment = "dev"

# GitHub OIDC
github_org  = "AliHaidry"
github_repo = "azure-finops-dashboard"

# PostgreSQL
pg_admin_username = "finops_admin"
pg_sku_name       = "B_Standard_B1ms"  # cheapest tier for dev

# App Service
app_service_sku = "B1"
```

### Step 3 — Initialise and apply

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
# Takes approximately 10-15 minutes
```

### Step 4 — Save outputs

```bash
terraform output -json > terraform-outputs.json

# Individual values you will need later
terraform output pg_connection_string   # → DATABASE_URL
terraform output key_vault_uri          # → KEY_VAULT_URI
terraform output acr_login_server       # → ACR_LOGIN_SERVER
terraform output app_service_url        # → your dashboard URL
```

### Phase 1 — Definition of done

- [ ] Resource group visible in Azure Portal
- [ ] PostgreSQL server accessible (`psql $(terraform output pg_connection_string)`)
- [ ] Key Vault created with correct access policies
- [ ] App Service deployed and returning 200

---

## Phase 2 — Python collector setup

### Step 1 — Configure environment

```bash
cd collector
cp .env.example .env
```

Edit `.env`:

```bash
# Azure
AZURE_TENANT_ID=your-tenant-id
AZURE_CLIENT_ID=your-client-id        # from Terraform output
SUBSCRIPTION_IDS=sub-a-id,sub-b-id,sub-c-id

# Database
DATABASE_URL=postgresql://finops_admin:password@hostname:5432/finops_db

# Collection settings
COLLECTION_START_DATE=2025-01-01      # how far back to backfill
CURRENCY=USD
COST_API_GRANULARITY=Daily

# Prometheus
PROMETHEUS_PORT=8000

# Logging
LOG_LEVEL=INFO
```

### Step 2 — Install dependencies

```bash
python -m venv venv
source venv/bin/activate              # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### Step 3 — Initialise the database

```bash
python db/init_schema.py
# Creates: cost_records, budgets, forecasts tables
```

### Step 4 — Run a manual collection

```bash
python collector.py --backfill 30     # fetch last 30 days
# Expected output:
# [INFO] Collecting from Subscription A (Production)...
# [INFO]   → 847 records fetched
# [INFO] Collecting from Subscription B (Dev/Staging)...
# [INFO]   → 312 records fetched
# [INFO] Collection complete. 1,159 records written to PostgreSQL.
# [INFO] Prometheus metrics updated at :8000/metrics
```

### Step 5 — Verify Prometheus metrics

```bash
curl http://localhost:8000/metrics | grep azure_cost
# Expected:
# azure_cost_daily_usd{subscription="Production"} 47.23
# azure_cost_by_team_usd{team="platform"} 31.10
# azure_budget_utilisation_percent{subscription="Production"} 62.5
```

### Step 6 — Set up scheduling

**Option A — cron (Linux/macOS):**
```bash
crontab -e
# Add: run daily at 06:00 UTC
0 6 * * * /path/to/venv/bin/python /path/to/collector/collector.py >> /var/log/finops-collector.log 2>&1
```

**Option B — Azure Function (recommended for production):**
```bash
# Deploy the collector as an Azure Function with TimerTrigger
cd collector/azure-function
func azure functionapp publish finops-collector
```

### Phase 2 — Definition of done

- [ ] `collector.py --backfill 30` completes without errors
- [ ] PostgreSQL `cost_records` table has rows (`SELECT COUNT(*) FROM cost_records;`)
- [ ] `curl localhost:8000/metrics` returns `azure_cost_*` metrics
- [ ] Scheduled collection running (cron or Azure Function)

---

## Phase 3 — Grafana dashboards

### Step 1 — Add Prometheus data source

1. Open Grafana → Settings → Data Sources → Add data source → Prometheus
2. URL: `http://localhost:9090` (or your Prometheus host)
3. Click **Save & Test** → green checkmark

### Step 2 — Import dashboards

1. Go to Dashboards → Import
2. Upload each JSON file from `grafana/dashboards/`:

| File | Dashboard name |
|---|---|
| `finops-overview.json` | FinOps Overview — all subscriptions |
| `finops-by-team.json` | Cost by team tag |
| `finops-budget-burn.json` | Budget burn rate |
| `finops-anomaly.json` | Anomaly detection |

### Step 3 — Configure alert rules

```bash
# Import alert rules
curl -X POST http://admin:admin@localhost:3000/api/ruler/grafana/api/v1/rules \
  -H "Content-Type: application/json" \
  -d @grafana/alerts/finops-alerts.json
```

### Phase 3 — Definition of done

- [ ] All 4 dashboards loading with live data
- [ ] Budget burn rate gauge showing correct percentage
- [ ] Anomaly detection panel showing last 30 days
- [ ] Alert rules visible in Grafana Alerting

---

## Phase 4 — Next.js stakeholder dashboard

### Step 1 — Configure environment

```bash
cd dashboard
cp .env.local.example .env.local
```

Edit `.env.local`:

```bash
DATABASE_URL=postgresql://finops_admin:password@hostname:5432/finops_db
NEXTAUTH_SECRET=your-random-secret-here
NEXTAUTH_URL=http://localhost:3000
API_KEY=your-dashboard-api-key
```

### Step 2 — Install and run locally

```bash
npm install
npm run dev
# Open http://localhost:3000
```

### Step 3 — Deploy to Azure App Service

```bash
# GitHub Actions handles this automatically on push to main
# Manual deploy:
npm run build
az webapp deploy \
  --resource-group finops-rg \
  --name finops-dashboard \
  --src-path .next
```

### Step 4 — Configure budgets

Set monthly budgets per team/subscription in the dashboard UI:
1. Open dashboard → Settings → Budgets
2. Add budget: Team `platform`, Amount `$500`, Subscription `Production`
3. Repeat for each team

Or seed via SQL:
```sql
INSERT INTO budgets (team, subscription_id, monthly_limit_usd, currency)
VALUES
  ('platform',  'sub-a-id', 500.00, 'USD'),
  ('backend',   'sub-a-id', 300.00, 'USD'),
  ('data',      'sub-b-id', 200.00, 'USD');
```

### Phase 4 — Definition of done

- [ ] Dashboard loads at localhost:3000 (dev) or App Service URL (prod)
- [ ] Cost by team cards showing correct data
- [ ] Budget progress bars rendering
- [ ] 30-day forecast chart visible
- [ ] CSV export working

---

## Phase 5 — Alerting

### Step 1 — Configure Alertmanager

```bash
# Edit alertmanager/alertmanager.yml
# Add your Slack webhook URL and email address
# See docs/alerts.md for full configuration reference
sudo systemctl restart alertmanager
```

### Step 2 — Add alert rules to Prometheus

```bash
sudo cp prometheus/alerts/finops-alerts.yml /etc/prometheus/alerts/
# Add to prometheus.yml:
# rule_files:
#   - /etc/prometheus/alerts/*.yml
sudo systemctl restart prometheus
```

### Step 3 — Test an alert

```bash
# Temporarily lower a budget threshold to trigger a test alert
# Or use Alertmanager's test endpoint:
curl -X POST http://localhost:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{"labels":{"alertname":"AzureBudgetWarning","team":"platform","severity":"warning"},"annotations":{"summary":"Test alert"}}]'
# Check Slack channel for the test notification
```

### Phase 5 — Definition of done

- [ ] Alertmanager accessible at port 9093
- [ ] Test alert received in Slack
- [ ] Email alert received for critical severity
- [ ] All alert rules visible in Prometheus → Alerts

---

## Full verification checklist

```
Infrastructure
  [ ] All Terraform resources created without errors
  [ ] PostgreSQL accessible from collector host
  [ ] Key Vault accessible with correct permissions

Collector
  [ ] Daily collection running on schedule
  [ ] All 3 subscriptions being collected
  [ ] Tag enrichment working (check cost_records.tags column)
  [ ] Prometheus /metrics endpoint returning azure_cost_* metrics

Grafana
  [ ] All 4 dashboards loading with live data
  [ ] Anomaly detection panel populated
  [ ] Budget burn rate showing correct %

Dashboard
  [ ] Next.js app accessible at production URL
  [ ] All team cost cards showing data
  [ ] Budget progress bars accurate
  [ ] CSV export generates correct file

Alerting
  [ ] Alertmanager running
  [ ] Slack integration working
  [ ] Email integration working
  [ ] Alert rules active in Prometheus
```
