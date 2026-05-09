# Python Collector

The collector is the core data engine of the FinOps dashboard. It runs on a daily schedule, fetches cost data from all configured Azure subscriptions, enriches records with resource tags, and feeds both the PostgreSQL historical store and the Prometheus metrics endpoint.

---

## How it works

```
collector.py
     │
     ├── 1. Authenticate to Azure (OIDC / Service Principal)
     │
     ├── 2. For each subscription:
     │       ├── Call Azure Cost Management API
     │       ├── Parse cost records (resource, service, cost, date)
     │       ├── Enrich with resource tags (team, env, owner, project)
     │       └── Normalise currency to USD
     │
     ├── 3. Write records to PostgreSQL (upsert by resource + date)
     │
     ├── 4. Compute aggregations (by team, by subscription, by day)
     │
     └── 5. Update Prometheus gauge metrics
```

---

## Azure Cost Management API

### Endpoint

```
POST /providers/Microsoft.CostManagement/query?api-version=2023-11-01
```

Scoped per subscription:
```
/subscriptions/{subscription-id}/providers/Microsoft.CostManagement/query
```

### Request body

```json
{
  "type": "ActualCost",
  "timeframe": "Custom",
  "timePeriod": {
    "from": "2025-01-01",
    "to": "2025-01-31"
  },
  "dataset": {
    "granularity": "Daily",
    "aggregation": {
      "totalCost": {
        "name": "Cost",
        "function": "Sum"
      }
    },
    "grouping": [
      { "type": "Dimension", "name": "ResourceId" },
      { "type": "Dimension", "name": "ResourceGroupName" },
      { "type": "Dimension", "name": "ServiceName" },
      { "type": "Dimension", "name": "ResourceType" }
    ]
  }
}
```

### Response structure

```json
{
  "properties": {
    "rows": [
      ["2025-01-15", 12.45, "USD", "/subscriptions/.../resourceGroups/rg-prod/providers/...", "rg-prod", "Virtual Machines", "microsoft.compute/virtualmachines"],
      ...
    ],
    "columns": [
      {"name": "UsageDate", "type": "Number"},
      {"name": "Cost", "type": "Number"},
      {"name": "Currency", "type": "String"},
      {"name": "ResourceId", "type": "String"},
      {"name": "ResourceGroupName", "type": "String"},
      {"name": "ServiceName", "type": "String"},
      {"name": "ResourceType", "type": "String"}
    ]
  }
}
```

---

## Tag enrichment

Resource tags are the foundation of FinOps cost allocation. The collector fetches tags for each resource and uses them to split costs by team, environment, and owner.

### Required tags (configure on your Azure resources)

| Tag key | Example value | Purpose |
|---|---|---|
| `team` | `platform`, `backend`, `data` | Cost by engineering team |
| `environment` | `production`, `staging`, `dev` | Cost by environment |
| `owner` | `ali.haidry@company.com` | Cost by individual owner |
| `project` | `finops-dashboard`, `api-gateway` | Cost by project |

### How the collector fetches tags

```python
from azure.mgmt.resource import ResourceManagementClient

def get_resource_tags(credential, subscription_id, resource_id):
    client = ResourceManagementClient(credential, subscription_id)
    resource = client.resources.get_by_id(resource_id, api_version="2021-04-01")
    return resource.tags or {}
```

### Tag fallback

If a resource has no `team` tag, the collector falls back to `resource_group` name, then `untagged`. This ensures every record has a team value — critical for accurate budget tracking.

```python
def resolve_team(tags, resource_group):
    return tags.get("team") or resource_group or "untagged"
```

---

## PostgreSQL schema

### `cost_records` table

```sql
CREATE TABLE cost_records (
    id                  BIGSERIAL PRIMARY KEY,
    usage_date          DATE NOT NULL,
    subscription_id     TEXT NOT NULL,
    subscription_name   TEXT NOT NULL,
    resource_id         TEXT NOT NULL,
    resource_group      TEXT NOT NULL,
    resource_type       TEXT,
    service_name        TEXT,
    cost_usd            NUMERIC(12, 4) NOT NULL,
    currency_original   TEXT NOT NULL DEFAULT 'USD',
    team                TEXT NOT NULL DEFAULT 'untagged',
    environment         TEXT,
    owner               TEXT,
    project             TEXT,
    tags                JSONB,
    collected_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (usage_date, resource_id, subscription_id)
);

CREATE INDEX idx_cost_records_date        ON cost_records (usage_date);
CREATE INDEX idx_cost_records_team        ON cost_records (team);
CREATE INDEX idx_cost_records_subscription ON cost_records (subscription_id);
```

### `budgets` table

```sql
CREATE TABLE budgets (
    id                  SERIAL PRIMARY KEY,
    team                TEXT NOT NULL,
    subscription_id     TEXT,
    monthly_limit_usd   NUMERIC(10, 2) NOT NULL,
    currency            TEXT NOT NULL DEFAULT 'USD',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (team, subscription_id)
);
```

### `forecasts` table

```sql
CREATE TABLE forecasts (
    id                  SERIAL PRIMARY KEY,
    forecast_date       DATE NOT NULL,
    team                TEXT NOT NULL,
    subscription_id     TEXT,
    projected_cost_usd  NUMERIC(12, 4) NOT NULL,
    lower_bound_usd     NUMERIC(12, 4),
    upper_bound_usd     NUMERIC(12, 4),
    computed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (forecast_date, team, subscription_id)
);
```

---

## Prometheus metrics

The collector exposes an HTTP `/metrics` endpoint (default port `8000`) compatible with Prometheus scraping.

### Metrics reference

| Metric | Type | Labels | Description |
|---|---|---|---|
| `azure_cost_daily_usd` | Gauge | `subscription`, `date` | Total daily spend per subscription |
| `azure_cost_by_team_usd` | Gauge | `team`, `subscription` | MTD spend per team |
| `azure_cost_by_service_usd` | Gauge | `service`, `subscription` | MTD spend per Azure service |
| `azure_budget_utilisation_percent` | Gauge | `team`, `subscription` | % of monthly budget consumed |
| `azure_cost_anomaly_score` | Gauge | `subscription` | Deviation from 7-day rolling avg |
| `azure_collector_last_run_timestamp` | Gauge | — | Unix timestamp of last successful run |
| `azure_collector_records_collected_total` | Counter | `subscription` | Total records collected since start |
| `azure_collector_errors_total` | Counter | `subscription`, `error_type` | Collection errors |

### Example Prometheus scrape config

```yaml
# /etc/prometheus/prometheus.yml
scrape_configs:
  - job_name: 'finops_collector'
    static_configs:
      - targets: ['localhost:8000']
    scrape_interval: 1h        # cost data updates daily — no need to scrape every 15s
```

---

## Environment variables reference

| Variable | Required | Default | Description |
|---|---|---|---|
| `AZURE_TENANT_ID` | ✅ | — | Azure AD tenant ID |
| `AZURE_CLIENT_ID` | ✅ | — | Service principal client ID |
| `AZURE_CLIENT_SECRET` | ⚠️ | — | Only if not using OIDC |
| `SUBSCRIPTION_IDS` | ✅ | — | Comma-separated subscription IDs |
| `DATABASE_URL` | ✅ | — | PostgreSQL connection string |
| `COLLECTION_START_DATE` | ✅ | — | Backfill start date (YYYY-MM-DD) |
| `CURRENCY` | — | `USD` | Target currency for normalisation |
| `COST_API_GRANULARITY` | — | `Daily` | `Daily` or `Monthly` |
| `PROMETHEUS_PORT` | — | `8000` | Port for `/metrics` endpoint |
| `LOG_LEVEL` | — | `INFO` | `DEBUG`, `INFO`, `WARNING`, `ERROR` |
| `DRY_RUN` | — | `false` | Fetch data but skip DB writes |

---

## CLI flags

```bash
python collector.py [OPTIONS]

Options:
  --backfill DAYS     Fetch last N days of data (default: 1)
  --subscription ID   Run for a single subscription only
  --dry-run           Fetch and log without writing to DB
  --no-prometheus     Skip Prometheus metrics update
  --log-level LEVEL   Override LOG_LEVEL env variable
```

### Common invocations

```bash
# Normal daily run (run by cron/scheduler)
python collector.py

# Backfill last 90 days (initial setup)
python collector.py --backfill 90

# Test a single subscription
python collector.py --subscription sub-a-id --dry-run

# Debug mode
python collector.py --log-level DEBUG --backfill 7
```

---

## Error handling

| Error | Behaviour |
|---|---|
| API rate limit (429) | Exponential backoff — retry up to 3 times |
| Subscription not found | Log warning, skip subscription, continue |
| Missing resource tags | Fall back to resource_group name |
| DB write failure | Retry once, then log error and continue |
| Network timeout | Retry with 30s timeout per request |

All errors increment `azure_collector_errors_total{error_type="..."}` for Prometheus tracking.
