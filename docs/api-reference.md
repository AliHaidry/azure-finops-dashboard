# API Reference

The Next.js dashboard exposes a REST API for the stakeholder UI. All endpoints require an `X-API-Key` header.

**Base URL:** `https://your-app-service.azurewebsites.net/api`  
**Authentication:** `X-API-Key: your-api-key`  
**Content-Type:** `application/json`

---

## Endpoints

### GET /api/costs

Returns aggregated cost data for a time range.

**Query parameters**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `from` | string (YYYY-MM-DD) | Start of current month | Start date |
| `to` | string (YYYY-MM-DD) | Today | End date |
| `subscription` | string | all | Filter by subscription ID |
| `team` | string | all | Filter by team tag |
| `environment` | string | all | Filter by environment tag |
| `groupBy` | string | `team` | Group results by: `team`, `subscription`, `service`, `day` |

**Example request**

```bash
curl -H "X-API-Key: your-key" \
  "https://your-dashboard.azurewebsites.net/api/costs?groupBy=team&from=2025-01-01"
```

**Example response**

```json
{
  "from": "2025-01-01",
  "to": "2025-01-31",
  "currency": "USD",
  "total_cost": 1247.83,
  "groups": [
    {
      "key": "platform",
      "cost_usd": 524.10,
      "percentage": 42.0,
      "resource_count": 18
    },
    {
      "key": "backend",
      "cost_usd": 398.22,
      "percentage": 31.9,
      "resource_count": 12
    },
    {
      "key": "data",
      "cost_usd": 201.44,
      "percentage": 16.1,
      "resource_count": 7
    },
    {
      "key": "untagged",
      "cost_usd": 124.07,
      "percentage": 9.9,
      "resource_count": 43
    }
  ]
}
```

---

### GET /api/costs/daily

Returns daily cost breakdown for trend charts.

**Query parameters**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `days` | integer | 30 | Number of days to return |
| `subscription` | string | all | Filter by subscription |
| `team` | string | all | Filter by team tag |

**Example response**

```json
{
  "days": 30,
  "currency": "USD",
  "series": [
    {
      "date": "2025-01-01",
      "cost_usd": 38.44,
      "breakdown": {
        "platform": 16.20,
        "backend": 12.80,
        "data": 7.11,
        "untagged": 2.33
      }
    },
    {
      "date": "2025-01-02",
      "cost_usd": 41.22
    }
  ]
}
```

---

### GET /api/budgets

Returns all configured budgets with current utilisation.

**Example response**

```json
{
  "budgets": [
    {
      "team": "platform",
      "subscription_id": "sub-a-id",
      "subscription_name": "Production",
      "monthly_limit_usd": 500.00,
      "mtd_spend_usd": 312.45,
      "utilisation_percent": 62.5,
      "days_remaining": 16,
      "projected_month_end_usd": 468.67,
      "status": "on_track"
    },
    {
      "team": "backend",
      "monthly_limit_usd": 300.00,
      "mtd_spend_usd": 289.10,
      "utilisation_percent": 96.4,
      "status": "at_risk"
    }
  ]
}
```

**Status values**

| Status | Condition |
|---|---|
| `on_track` | Utilisation ≤ 70% |
| `watch` | Utilisation 70–80% |
| `warning` | Utilisation 80–100% |
| `exceeded` | Utilisation > 100% |
| `at_risk` | Projected month-end > budget |

---

### PUT /api/budgets

Create or update a budget.

**Request body**

```json
{
  "team": "platform",
  "subscription_id": "sub-a-id",
  "monthly_limit_usd": 600.00
}
```

**Response**

```json
{
  "success": true,
  "budget": {
    "team": "platform",
    "subscription_id": "sub-a-id",
    "monthly_limit_usd": 600.00,
    "updated_at": "2025-01-15T10:30:00Z"
  }
}
```

---

### GET /api/forecasts

Returns 30-day cost forecasts.

**Query parameters**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `team` | string | all | Filter by team |
| `subscription` | string | all | Filter by subscription |

**Example response**

```json
{
  "generated_at": "2025-01-15T06:00:00Z",
  "forecasts": [
    {
      "team": "platform",
      "current_mtd_usd": 312.45,
      "projected_month_end_usd": 468.67,
      "lower_bound_usd": 420.00,
      "upper_bound_usd": 520.00,
      "monthly_budget_usd": 500.00,
      "projected_overrun": false
    }
  ]
}
```

---

### GET /api/export/csv

Exports cost data as a CSV file.

**Query parameters:** Same as `GET /api/costs`

**Response:** `Content-Type: text/csv` file download

```csv
date,subscription,team,environment,service,resource_group,cost_usd
2025-01-01,Production,platform,production,Virtual Machines,rg-prod,12.45
2025-01-01,Production,backend,production,Azure SQL,rg-backend,8.22
```

---

### GET /api/health

Health check endpoint — no authentication required.

**Response**

```json
{
  "status": "healthy",
  "database": "connected",
  "last_collection": "2025-01-15T06:00:00Z",
  "version": "1.0.0"
}
```

---

## Error responses

All errors follow this structure:

```json
{
  "error": "BUDGET_NOT_FOUND",
  "message": "No budget found for team 'platform' in subscription 'sub-a-id'",
  "status": 404
}
```

| HTTP status | Error code | Meaning |
|---|---|---|
| 400 | `INVALID_PARAMS` | Missing or invalid query parameters |
| 401 | `UNAUTHORIZED` | Missing or invalid API key |
| 404 | `NOT_FOUND` | Resource not found |
| 429 | `RATE_LIMITED` | Too many requests |
| 500 | `INTERNAL_ERROR` | Server error |
| 503 | `DB_UNAVAILABLE` | PostgreSQL connection failed |
