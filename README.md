# Azure FinOps Dashboard

> Production-grade multi-subscription Azure cost monitoring system — Python collector, PostgreSQL, Grafana, Next.js stakeholder UI, and automated Slack alerting via GitHub Actions.

[![FinOps Collector](https://github.com/AliHaidry/azure-finops-dashboard/actions/workflows/collector.yml/badge.svg)](https://github.com/AliHaidry/azure-finops-dashboard/actions/workflows/collector.yml)
[![Deploy Dashboard](https://github.com/AliHaidry/azure-finops-dashboard/actions/workflows/dashboard-deploy.yml/badge.svg)](https://github.com/AliHaidry/azure-finops-dashboard/actions/workflows/dashboard-deploy.yml)
[![FinOps Cost Alerts](https://github.com/AliHaidry/azure-finops-dashboard/actions/workflows/finops-alerts.yml/badge.svg)](https://github.com/AliHaidry/azure-finops-dashboard/actions/workflows/finops-alerts.yml)

**Built by:** [Syed Muhammad Ali Haidry](https://alihaidry-devops.website) · Senior DevOps Engineer  
**Blog post:** [Building a Multi-Subscription Azure FinOps Dashboard](https://alihaidry-devops.website/blog/azure-finops-dashboard)  
**Live dashboard:** ~~finops-dashboard-app.azurewebsites.net~~ *(torn down — redeploy with `terraform apply`)*

---

## Architecture

```
Azure Cost Management API (4 subscriptions)
        ↓
Python Collector — GitHub Actions daily at 06:00 UTC
        ↓
PostgreSQL Flexible Server (finops-pg-dev)
        ↓
        ├── Prometheus + Grafana     ← ops team (4 dashboards)
        └── Next.js Dashboard       ← stakeholders (Azure App Service)
                ↓
GitHub Actions Alert Checks — every 6 hours
                ↓
Slack #finops-alerts
```

## Tech Stack

| Layer | Technology |
|---|---|
| Infrastructure | Terraform + Azure Storage remote state |
| Auth | OIDC federation — zero stored secrets |
| Collection | Python 3.12 + azure-mgmt-costmanagement |
| Storage | PostgreSQL 16 Flexible Server |
| Ops dashboards | Prometheus + Grafana (Docker) |
| Stakeholder UI | Next.js 16 on Azure App Service B1 |
| Alerting | GitHub Actions + Slack Incoming Webhook |
| Secrets | Azure Key Vault |

---

## Repository Structure

```
azure-finops-dashboard/
├── terraform/                    # All infrastructure as code
│   ├── terraform-main.tf         # Root module — providers, resource group
│   ├── app-service.tf            # App Service Plan + Web App (app subscription)
│   ├── database.tf               # PostgreSQL Flexible Server
│   ├── keyvault.tf               # Key Vault + secrets
│   ├── registry.tf               # Container Registry
│   ├── terraform.tfvars          # Your values (gitignored)
│   ├── terraform.tfvars.example  # Template — copy and fill in
│   └── modules/
│       ├── database/             # PostgreSQL module
│       ├── keyvault/             # Key Vault module
│       ├── registry/             # ACR module
│       ├── webapp/               # App Service module
│       └── oidc/                 # GitHub OIDC federation module
├── collector/                    # Python cost collector
│   ├── collector.py              # Main collection script
│   ├── requirements.txt          # Python dependencies
│   └── .env.example              # Environment template
├── dashboard/                    # Next.js stakeholder UI
│   ├── app/
│   │   ├── page.tsx              # Main dashboard page
│   │   └── api/costs/route.ts    # PostgreSQL API route
│   ├── package.json
│   └── next.config.js
├── prometheus/
│   ├── prometheus.yml            # Prometheus scrape config
│   └── alerts.yml                # Alert rules (budget, spike, health)
├── alertmanager/
│   └── alertmanager.yml          # Alertmanager config (Slack routing)
├── grafana/
│   ├── dashboards/               # 4 Grafana dashboard JSON files
│   └── provisioning/
│       └── datasources/
│           └── prometheus.yml    # Auto-provisioned Prometheus datasource
├── scripts/
│   └── alert_check.py            # GitHub Actions alert checker
├── .github/
│   └── workflows/
│       ├── collector.yml         # Daily cost collection
│       ├── dashboard-deploy.yml  # Next.js deploy to App Service
│       └── finops-alerts.yml     # 6-hourly Slack alerts
└── docker-compose.yml            # Prometheus + Grafana + Alertmanager
```

---

## Prerequisites

- Azure account with at least one active subscription
- Azure CLI installed and logged in (`az login`)
- Terraform >= 1.5 installed
- Python 3.12+
- Node.js 20 LTS
- Docker Desktop (for Grafana/Prometheus locally)
- GitHub account (for Actions CI/CD)
- Slack workspace with Incoming Webhooks enabled

---

## Quick Start — Full Deployment

### Step 1 — Bootstrap Terraform Remote State

Create the storage account for Terraform state in your infra subscription:

```bash
# Create resource group for tfstate
az group create \
  --name finops-tfstate-rg \
  --location eastus2 \
  --subscription <your-infra-subscription-id>

# Create storage account
az storage account create \
  --name finopstfstateali \
  --resource-group finops-tfstate-rg \
  --location eastus2 \
  --sku Standard_LRS \
  --subscription <your-infra-subscription-id>

# Create state container
az storage container create \
  --name tfstate \
  --account-name finopstfstateali
```

### Step 2 — Configure Terraform Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
# terraform/terraform.tfvars
subscription_ids = [
  "your-dev-subscription-id",
  "your-infra-subscription-id",
  "your-poc-subscription-id",
  "your-app-subscription-id",
]

poc_subscription_id  = "your-poc-subscription-id"
app_subscription_id  = "your-app-subscription-id"

github_org  = "YourGitHubUsername"
github_repo = "azure-finops-dashboard"

location    = "eastus2"
environment = "dev"
```

### Step 3 — Deploy Infrastructure

```bash
cd terraform

# Initialise with remote state
terraform init

# Preview what will be created
terraform plan -var-file=terraform.tfvars

# Deploy — takes ~5-10 minutes
terraform apply -var-file=terraform.tfvars
```

**Resources created:**
- PostgreSQL Flexible Server (`finops-pg-dev`)
- Azure Key Vault (`finopskvalidev`) with pg connection string
- Container Registry (`finopsacralidev`)
- App Service Plan + Web App (`finops-dashboard-app`)
- OIDC App Registration (`finops-github-actions`) with federated credentials

### Step 4 — Grant Cost Management Reader on All Subscriptions

The SP needs Cost Management Reader at subscription scope to query costs:

```bash
# Get the SP object ID from terraform output
SP_OBJECT_ID=$(terraform output -raw github_actions_sp_object_id)

# Assign to each subscription via Portal (more reliable cross-subscription):
# portal.azure.com → Subscriptions → [each sub]
# → Access control (IAM) → Add role assignment
# → Cost Management Reader → finops-github-actions
```

Or via CLI for each subscription:
```bash
az role assignment create \
  --assignee-object-id <SP_OBJECT_ID> \
  --assignee-principal-type ServicePrincipal \
  --role "Cost Management Reader" \
  --scope "/subscriptions/<subscription-id>"
```

### Step 5 — Configure GitHub Secrets

Go to your GitHub repo → Settings → Secrets and variables → Actions → New repository secret:

| Secret Name | Value | How to get it |
|---|---|---|
| `AZURE_CLIENT_ID` | App registration client ID | `terraform output github_actions_client_id` |
| `AZURE_TENANT_ID` | Azure AD tenant ID | `terraform output tenant_id` |
| `AZURE_SUBSCRIPTION_ID` | Subscription where PostgreSQL lives | Your poc subscription ID |
| `AZURE_APP_SUBSCRIPTION_ID` | Subscription where App Service lives | Your app subscription ID |
| `DATABASE_URL` | PostgreSQL connection string | `terraform output pg_connection_string` |
| `NEXTAUTH_SECRET` | Random secret | `openssl rand -base64 32` |
| `ACR_LOGIN_SERVER` | ACR URL | `terraform output acr_login_server` |
| `SLACK_WEBHOOK_URL` | Slack incoming webhook | Create at api.slack.com/apps |
| `SUBSCRIPTION_IDS` | JSON array of all sub IDs | `'["sub-a","sub-b","sub-c","sub-d"]'` |

> **Important:** Also create a GitHub Environment named `app` (repo → Settings → Environments → New environment → `app`). The deploy workflow uses `environment: app` for OIDC scoping.

### Step 6 — Run Initial Data Collection

```bash
# Trigger manually first time
# GitHub → Actions → FinOps Collector → Run workflow
```

Or run locally:
```bash
cd collector
python -m venv venv
source venv/Scripts/activate  # Windows
# source venv/bin/activate    # Mac/Linux

pip install -r requirements.txt

export DATABASE_URL="postgresql://finops_admin:<password>@finops-pg-dev.postgres.database.azure.com:5432/finops_db?sslmode=require"

# Backfill last 30 days
python collector.py --backfill 30
```

### Step 7 — Start Grafana Dashboards Locally

```bash
# From repo root
docker-compose up -d

# Verify containers running
docker-compose ps
```

Open:
- **Grafana:** http://localhost:3000 (admin / finops123)
- **Prometheus:** http://localhost:9090
- **Alertmanager:** http://localhost:9093

Import the dashboard JSON files from `grafana/dashboards/` into Grafana.

### Step 8 — Deploy Next.js Dashboard

The dashboard deploys automatically on push to `main` when files in `dashboard/` change. To trigger manually:

```bash
# GitHub → Actions → Deploy Dashboard to Azure App Service → Run workflow
```

Or deploy locally for development:
```bash
cd dashboard
npm install
npm run dev
# Open http://localhost:3000
```

### Step 9 — Enable Slack Alerting

```bash
# GitHub → Actions → FinOps Cost Alerts → Run workflow
# Check your Slack #finops-alerts channel for test alerts
```

The alert workflow runs automatically every 6 hours. Alerts fire when:
- Budget utilisation > 80% (warning)
- Budget utilisation > 100% (critical)
- Yesterday's spend > 2x 7-day average (warning)
- No data collected in > 24 hours (critical)

---

## Local Development

### Collector

```bash
cd collector
python -m venv venv
source venv/Scripts/activate

pip install -r requirements.txt

# Copy and fill in environment file
cp .env.example .env

# Run with backfill
python collector.py --backfill 7

# Run single day
python collector.py

# Check metrics endpoint
curl http://localhost:8000/metrics
```

### Next.js Dashboard

```bash
cd dashboard
npm install

# Copy environment file
cp .env.example .env.local
# Set DATABASE_URL in .env.local

npm run dev
# Open http://localhost:3000
```

### Alert Check (test locally)

```bash
export DATABASE_URL="your-connection-string"
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
export BUDGET_WARNING_THRESHOLD="0.80"
export BUDGET_CRITICAL_THRESHOLD="1.00"
export SPIKE_MULTIPLIER="2.0"

python scripts/alert_check.py
```

---

## GitHub Actions Workflows

| Workflow | File | Trigger | Duration |
|---|---|---|---|
| FinOps Collector | `collector.yml` | Daily 06:00 UTC + manual | ~4 min |
| Deploy Dashboard | `dashboard-deploy.yml` | Push to `dashboard/**` + manual | ~6 min |
| FinOps Cost Alerts | `finops-alerts.yml` | Every 6h + manual | ~2 min |

---

## PostgreSQL Schema

Key table: `cost_records`

| Column | Type | Description |
|---|---|---|
| `id` | SERIAL | Auto-increment PK |
| `usage_date` | DATE | Date cost was incurred *(column is `usage_date`, not `date`)* |
| `subscription_id` | VARCHAR | Azure subscription GUID |
| `subscription_name` | VARCHAR | Subscription display name |
| `resource_group` | VARCHAR | Resource group name |
| `service_name` | VARCHAR | Azure service (PostgreSQL, ACR, etc.) |
| `cost_usd` | NUMERIC(12,6) | Cost in USD *(returns `decimal.Decimal` in Python — cast to `float()`)* |
| `team` | VARCHAR | `team` resource tag |
| `environment` | VARCHAR | `environment` resource tag |
| `owner` | VARCHAR | `owner` resource tag |
| `collected_at` | TIMESTAMPTZ | When this record was inserted |

---

## Troubleshooting

### OIDC authentication fails — subject claim mismatch
```
AADSTS700213: No matching federated identity record found
```
**Fix:** Check that the GitHub Actions job declares `environment: app` and that the federated credential on the app registration matches:
```bash
az ad app federated-credential list \
  --id <your-client-id> \
  --query "[].{Subject:subject}" -o table
```
Add missing credential:
```bash
az ad app federated-credential create \
  --id <your-client-id> \
  --parameters '{
    "name": "github-actions-deploy-app",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:YourOrg/azure-finops-dashboard:environment:app",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

### Database URL hostname error (`ENOTFOUND base`)
The `DATABASE_URL` contains special characters that break URL parsing.  
Percent-encode the password: `#` → `%23`, `&` → `%26`, `%` → `%25`, `[` → `%5B`

### `column "date" does not exist`
The actual column name is `usage_date`. Query the schema:
```bash
python -c "
import psycopg2, os
conn = psycopg2.connect(os.environ['DATABASE_URL'])
cur = conn.cursor()
cur.execute(\"SELECT column_name FROM information_schema.columns WHERE table_name='cost_records'\")
for row in cur.fetchall(): print(row[0])
"
```

### `TypeError: unsupported operand type(s) for /: 'decimal.Decimal' and 'float'`
Cast PostgreSQL NUMERIC values: `utilisation = float(mtd_cost) / budget`

### App Service quota = 0 in region
Personal tenants often have zero App Service quota. Options:
- Open a Microsoft support ticket for quota increase
- Switch to a Pay-as-you-go subscription (quota available by default)
- Try a different region

### Key Vault takes 10+ minutes to destroy
This is normal — Azure Key Vault uses soft-delete with a 7-day retention period. The terraform destroy will wait. After destroy, purge to free the name:
```bash
az keyvault purge --name finopskvalidev --location eastus2
```

---

## Teardown — Complete Shutdown

To stop all costs and remove all Azure resources:

### 1. Stop App Service
```bash
az webapp stop \
  --name finops-dashboard-app \
  --resource-group finops-app-rg \
  --subscription <app-subscription-id>
```

### 2. Disable GitHub Actions Workflows
GitHub → repository → Actions → each workflow → ⋯ → Disable workflow

### 3. Terraform Destroy
```bash
cd terraform
terraform destroy -var-file=terraform.tfvars
# Type 'yes' when prompted — takes ~15 minutes
```

### 4. Manual Cleanup via Portal
Items that may need manual deletion (if CLI fails with AuthorizationFailed):
- Role assignments on dev/infra subscriptions → Portal IAM → delete `finops-github-actions`
- `finops-tfstate-rg` resource group → Portal → Resource groups → Delete

### 5. Verify Clean
```bash
az group list --subscription <poc-sub> --query '[].name' -o table
az group list --subscription <app-sub> --query '[].name' -o table
az ad app list --display-name 'finops-github-actions' --query '[].displayName' -o table
# All should return empty / no finops resources
```

---

## Cost to Run

| Resource | Monthly Cost |
|---|---|
| PostgreSQL B1ms (idle when not collecting) | ~$3-8 |
| Container Registry Basic | ~$5 |
| App Service B1 | ~$13 |
| Key Vault + Storage | ~$0.02 |
| GitHub Actions | $0 (free tier) |
| **Total** | **~$21-26/month** |

---

## Project Phases

| Phase | Description | Status |
|---|---|---|
| Phase 1 | Terraform infrastructure (PostgreSQL, Key Vault, ACR, App Service, OIDC) | ✅ Complete |
| Phase 2 | Python collector + GitHub Actions daily workflow | ✅ Complete |
| Phase 3 | Grafana dashboards (overview, budget, teams, anomaly) | ✅ Complete |
| Phase 4 | Next.js stakeholder dashboard | ✅ Complete |
| Phase 5A | Azure App Service deployment via GitHub Actions OIDC | ✅ Complete |
| Phase 5B | Slack alerting via GitHub Actions (budget, spike, health) | ✅ Complete |
| Phase 6 | Blog post, portfolio card, Word documentation | ✅ Complete |

---

## Author

**Syed Muhammad Ali Haidry** — Senior DevOps Engineer  
🌐 [alihaidry-devops.website](https://alihaidry-devops.website)  
💼 [LinkedIn](https://linkedin.com/in/alihaidry)  
🐦 [@AliHaidry5](https://twitter.com/AliHaidry5)  
📁 [GitHub](https://github.com/AliHaidry)

---

*Azure FinOps Dashboard — Built May 2026*
