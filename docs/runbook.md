# Runbook

Day-2 operations reference — common failure modes, their causes, and how to fix them.

---

## Common failure modes

### Collector down

**Symptom:** `CollectorDown` alert fires. Dashboard shows stale data. `azure_collector_last_run_timestamp` is more than 24 hours ago.

**Check:**
```bash
# Check cron job
crontab -l | grep collector

# Check last run log
tail -100 /var/log/finops-collector.log

# Check Azure Function (if using)
az functionapp list-functions --name finops-collector --resource-group finops-rg
az functionapp logs show --name finops-collector
```

**Fix:**
```bash
# Run manually to see the error
python collector.py --log-level DEBUG

# Common causes:
# 1. Azure credential expired → re-authenticate
az login
# 2. DB connection failed → check pg_connection_string
psql $DATABASE_URL -c "SELECT 1;"
# 3. Key Vault access denied → check managed identity role assignments
az keyvault show --name finops-kv-dev --query "properties.accessPolicies"
```

---

### Budget utilisation showing 0%

**Symptom:** Budget progress bars show 0% or N/A in the Next.js dashboard.

**Check:**
```bash
# Verify budgets exist in DB
psql $DATABASE_URL -c "SELECT * FROM budgets;"

# Verify cost records exist
psql $DATABASE_URL -c "SELECT COUNT(*) FROM cost_records WHERE usage_date >= date_trunc('month', CURRENT_DATE);"

# Check team tag matching
psql $DATABASE_URL -c "SELECT DISTINCT team FROM cost_records ORDER BY team;"
```

**Fix:**

If no budgets:
```sql
INSERT INTO budgets (team, subscription_id, monthly_limit_usd)
VALUES ('platform', 'your-sub-id', 500.00);
```

If team tags don't match budget team names — update the tag on your Azure resources or update the budget `team` value to match what the collector is extracting.

---

### Cost data missing for a subscription

**Symptom:** One subscription shows no data in the dashboard or Grafana.

**Check:**
```bash
# Verify subscription is in config
echo $SUBSCRIPTION_IDS

# Check if records exist for that subscription
psql $DATABASE_URL -c "
  SELECT subscription_name, COUNT(*), MAX(usage_date)
  FROM cost_records
  GROUP BY subscription_name;
"

# Test API access manually
python -c "
from azure.identity import DefaultAzureCredential
from azure.mgmt.costmanagement import CostManagementClient
cred = DefaultAzureCredential()
client = CostManagementClient(cred)
print('Auth OK')
"
```

**Fix:**
```bash
# Run manual backfill for that subscription
python collector.py --subscription sub-id --backfill 30 --log-level DEBUG
```

---

### Untagged resources showing high cost

**Symptom:** `untagged` team shows significant cost in dashboards. Budget for actual teams appears low.

**Check:**
```sql
-- Find the top untagged resources
SELECT resource_id, resource_group, service_name, SUM(cost_usd) as total_cost
FROM cost_records
WHERE team = 'untagged'
  AND usage_date >= date_trunc('month', CURRENT_DATE)
GROUP BY resource_id, resource_group, service_name
ORDER BY total_cost DESC
LIMIT 20;
```

**Fix:**

Tag the resources in Azure:
```bash
az resource tag \
  --ids /subscriptions/{sub-id}/resourceGroups/{rg}/providers/{provider}/{name} \
  --tags team=platform environment=production
```

Or use Azure Policy to enforce tagging on new resources.

---

### Grafana dashboard shows "No data"

**Symptom:** Grafana panels show "No data" or "N/A".

**Check:**
```bash
# Verify Prometheus is scraping the collector
curl http://localhost:9090/api/v1/targets | python3 -m json.tool | grep finops

# Verify metrics exist
curl http://localhost:8000/metrics | grep azure_cost

# Check Prometheus query manually
curl "http://localhost:9090/api/v1/query?query=azure_cost_daily_usd" | python3 -m json.tool
```

**Fix:**
```bash
# Restart collector (refreshes Prometheus metrics)
python collector.py

# Restart Prometheus (reloads config)
sudo systemctl restart prometheus

# Check scrape config
cat /etc/prometheus/prometheus.yml | grep finops
```

---

### Next.js dashboard returns 500

**Symptom:** Dashboard shows error page or API returns 500.

**Check:**
```bash
# Check App Service logs (Azure)
az webapp log tail --name finops-dashboard --resource-group finops-rg

# Check locally
npm run dev
# Look for error in terminal output
```

**Common causes:**
- `DATABASE_URL` missing or wrong → check App Service environment variables
- PostgreSQL connection refused → check PostgreSQL server firewall rules
- `API_KEY` not set → add to App Service configuration

---

### Alertmanager not firing alerts

**Symptom:** Budget exceeded but no Slack/email received.

**Check:**
```bash
# Verify Alertmanager is running
sudo systemctl status alertmanager

# Check active alerts in Prometheus
curl http://localhost:9090/api/v1/alerts | python3 -m json.tool

# Check Alertmanager received the alert
curl http://localhost:9093/api/v1/alerts | python3 -m json.tool

# Test Slack webhook manually
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Test from FinOps runbook"}' \
  YOUR_SLACK_WEBHOOK_URL
```

**Fix:**
```bash
# Reload Alertmanager config
sudo systemctl reload alertmanager

# Validate config syntax
/usr/local/bin/amtool check-config /etc/alertmanager/alertmanager.yml
```

---

## Operational tasks

### Manually trigger a collection

```bash
# Full collection (all subscriptions, last 1 day)
python collector.py

# Backfill specific subscription
python collector.py --subscription sub-a-id --backfill 7

# Dry run (no DB writes)
python collector.py --dry-run --log-level DEBUG
```

### Add a new team budget

```sql
INSERT INTO budgets (team, subscription_id, monthly_limit_usd, currency)
VALUES ('new-team', 'sub-a-id', 250.00, 'USD')
ON CONFLICT (team, subscription_id)
DO UPDATE SET monthly_limit_usd = EXCLUDED.monthly_limit_usd,
              updated_at = NOW();
```

### Export cost report for finance

```bash
curl -H "X-API-Key: your-key" \
  "https://your-dashboard.azurewebsites.net/api/export/csv?from=2025-01-01&to=2025-01-31" \
  -o finops-report-jan-2025.csv
```

### Reset and re-collect a date range

```sql
-- Remove records for a date range (e.g. if data was corrupted)
DELETE FROM cost_records
WHERE usage_date BETWEEN '2025-01-01' AND '2025-01-07'
  AND subscription_id = 'sub-a-id';
```

```bash
# Re-collect
python collector.py --subscription sub-a-id --backfill 7
```

### Rotate API key

1. Generate a new key: `openssl rand -hex 32`
2. Update in Key Vault:
```bash
az keyvault secret set \
  --vault-name finops-kv-dev \
  --name dashboard-api-key \
  --value "new-key-here"
```
3. Update App Service environment variable
4. Update any external consumers of the API

### Scale up PostgreSQL

```bash
# Update terraform.tfvars
# pg_sku_name = "GP_Standard_D2s_v3"   # general purpose tier

terraform plan
terraform apply
# PostgreSQL scales with minimal downtime
```

---

## Useful SQL queries

```sql
-- MTD spend by team
SELECT team, SUM(cost_usd) as mtd_cost
FROM cost_records
WHERE usage_date >= date_trunc('month', CURRENT_DATE)
GROUP BY team
ORDER BY mtd_cost DESC;

-- Daily spend last 7 days
SELECT usage_date, SUM(cost_usd) as daily_cost
FROM cost_records
WHERE usage_date >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY usage_date
ORDER BY usage_date;

-- Top 10 most expensive resources this month
SELECT resource_id, resource_group, service_name, team, SUM(cost_usd) as total_cost
FROM cost_records
WHERE usage_date >= date_trunc('month', CURRENT_DATE)
GROUP BY resource_id, resource_group, service_name, team
ORDER BY total_cost DESC
LIMIT 10;

-- Untagged resource cost as % of total
SELECT
  ROUND(SUM(CASE WHEN team = 'untagged' THEN cost_usd ELSE 0 END) / SUM(cost_usd) * 100, 1) as untagged_percent
FROM cost_records
WHERE usage_date >= date_trunc('month', CURRENT_DATE);

-- Budget utilisation check
SELECT
  b.team,
  b.monthly_limit_usd as budget,
  COALESCE(SUM(c.cost_usd), 0) as mtd_spend,
  ROUND(COALESCE(SUM(c.cost_usd), 0) / b.monthly_limit_usd * 100, 1) as utilisation_pct
FROM budgets b
LEFT JOIN cost_records c
  ON c.team = b.team
  AND c.usage_date >= date_trunc('month', CURRENT_DATE)
GROUP BY b.team, b.monthly_limit_usd
ORDER BY utilisation_pct DESC;
```

---

## Logs — where to look

| Log | Location | What it shows |
|---|---|---|
| Collector | `/var/log/finops-collector.log` | Daily collection runs, errors, record counts |
| Azure Function | Azure Portal → Function App → Monitor | Execution history, errors |
| Prometheus | `journalctl -u prometheus` | Scrape errors, rule evaluation |
| Alertmanager | `journalctl -u alertmanager` | Alert routing, notification delivery |
| Next.js | Azure App Service → Log stream | API errors, DB connection issues |
| PostgreSQL | Azure Portal → PostgreSQL → Logs | Query errors, connection issues |
