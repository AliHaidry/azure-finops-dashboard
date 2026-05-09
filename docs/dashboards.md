# Grafana Dashboards

Four Grafana dashboards covering different aspects of Azure cost visibility.

---

## Dashboard overview

| Dashboard | Audience | Key panels |
|---|---|---|
| FinOps Overview | Engineering leads | All-subscription spend, top services, daily trend |
| Cost by Team | Team leads | MTD spend per team, budget utilisation |
| Budget Burn Rate | Finance / management | Burn rate gauge, projected month-end |
| Anomaly Detection | Platform / DevOps | Spend deviation, spike alerts |

---

## 1 — FinOps Overview

**File:** `grafana/dashboards/finops-overview.json`

The top-level view across all subscriptions.

### Panels

**Total MTD spend (stat panel)**
```promql
sum(azure_cost_daily_usd{})
```
Shows total month-to-date spend across all subscriptions. Color threshold: green < $500, yellow < $1000, red > $1000.

**Spend by subscription (pie chart)**
```promql
sum by (subscription) (azure_cost_daily_usd{})
```
Breakdown of spend per subscription for the current month.

**Daily spend trend (time series)**
```promql
sum by (subscription) (azure_cost_daily_usd{})
```
30-day daily spend trend, one line per subscription. Shows spending pattern and weekday/weekend variation.

**Top 10 services by cost (bar chart)**
```promql
topk(10, sum by (service) (azure_cost_by_service_usd{}))
```
Which Azure services are costing the most this month.

**Collection health (stat panel)**
```promql
time() - azure_collector_last_run_timestamp
```
Seconds since last successful collection. Alert if > 86400 (24 hours).

---

## 2 — Cost by Team

**File:** `grafana/dashboards/finops-by-team.json`

Breaks down spend by the `team` resource tag.

### Panels

**Team spend table (table panel)**
```promql
sum by (team) (azure_cost_by_team_usd{})
```
Sortable table: team name, MTD spend, budget limit, utilisation %.

**Budget utilisation bars (bar gauge)**
```promql
azure_budget_utilisation_percent{}
```
One bar per team. Thresholds: green < 70%, yellow < 90%, red > 90%.

**Team spend over time (time series)**
```promql
sum by (team) (azure_cost_by_team_usd{})
```
One line per team, showing cumulative MTD spend growth.

**Untagged resource cost (stat panel)**
```promql
sum(azure_cost_by_team_usd{team="untagged"})
```
Cost from resources with no `team` tag. Should trend toward zero as tagging improves.

---

## 3 — Budget Burn Rate

**File:** `grafana/dashboards/finops-budget-burn.json`

Projects whether current spend will exceed budget by month-end.

### Panels

**Budget burn rate gauge (gauge panel)**
```promql
# Days elapsed this month / days in month
# × projected month-end vs budget
azure_budget_utilisation_percent{team="platform"}
```
Shows actual utilisation vs the "ideal" burn rate for this point in the month. If it's day 15 (50% through month) and utilisation is 80%, you're burning too fast.

**Projected month-end spend (stat panel)**
```promql
# Linear projection: MTD spend / days elapsed × days in month
sum(azure_cost_by_team_usd{team="platform"}) / scalar(day_of_month(timestamp(sum(azure_cost_by_team_usd{})))) * 30
```
Best estimate of month-end total based on current daily run rate.

**Burn rate by team (table)**
```promql
sum by (team) (azure_cost_by_team_usd{})
```
Table with columns: team, MTD spend, budget, utilisation %, projected month-end, status (on track / over budget).

---

## 4 — Anomaly Detection

**File:** `grafana/dashboards/finops-anomaly.json`

Identifies unusual spend spikes before they become budget problems.

### Panels

**Anomaly score (time series)**
```promql
azure_cost_anomaly_score{}
```
Deviation of today's spend from the 7-day rolling average. Score > 2 = warning, score > 3 = critical.

**Daily spend vs rolling average (time series)**
```promql
# Actual daily spend
azure_cost_daily_usd{}

# 7-day rolling average (computed by collector)
avg_over_time(azure_cost_daily_usd{}[7d])
```
Two lines per subscription — actual vs average. Spikes are visually obvious.

**Recent anomalies (table)**
Shows dates where anomaly score exceeded threshold, with the subscription, actual cost, expected cost, and deviation percentage.

---

## Importing dashboards

### Via Grafana UI

1. Go to **Dashboards** → **Import**
2. Click **Upload JSON file**
3. Select the file from `grafana/dashboards/`
4. Select **Prometheus** as the data source
5. Click **Import**

### Via Grafana API

```bash
GRAFANA_URL=http://localhost:3000
GRAFANA_USER=admin
GRAFANA_PASS=admin

for dashboard in grafana/dashboards/*.json; do
  curl -X POST \
    -H "Content-Type: application/json" \
    -u "$GRAFANA_USER:$GRAFANA_PASS" \
    -d "{\"dashboard\": $(cat $dashboard), \"overwrite\": true}" \
    "$GRAFANA_URL/api/dashboards/import"
  echo "Imported: $dashboard"
done
```

---

## Customising thresholds

All threshold values are set in the dashboard JSON under `fieldConfig.defaults.thresholds`. To change them:

1. Open the dashboard in Grafana
2. Click the panel title → **Edit**
3. Go to **Field** tab → **Thresholds**
4. Update the values
5. Click **Save dashboard**

Then export the updated JSON (`Dashboard settings` → `JSON Model` → copy) and commit to `grafana/dashboards/` to keep it version-controlled.

---

## Variable templates

All dashboards support these template variables for filtering:

| Variable | Values | Description |
|---|---|---|
| `$subscription` | All · Production · Dev/Staging · Sandbox | Filter by subscription |
| `$team` | All · platform · backend · data · untagged | Filter by team tag |
| `$environment` | All · production · staging · dev | Filter by environment tag |
| `$timerange` | Last 7d · Last 30d · This month | Time window |
