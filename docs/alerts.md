# Alerts

All alerting flows through Prometheus recording rules → Alertmanager → Slack / email.

---

## Alert rules

### Infrastructure alerts

| Alert | Expression | For | Severity | Meaning |
|---|---|---|---|---|
| `CollectorDown` | `time() - azure_collector_last_run_timestamp > 86400` | 1h | critical | Collector hasn't run in 24 hours |
| `CollectorErrors` | `rate(azure_collector_errors_total[1h]) > 0` | 30m | warning | Collection errors occurring |

### Budget alerts

| Alert | Expression | For | Severity | Meaning |
|---|---|---|---|---|
| `AzureBudgetWarning` | `azure_budget_utilisation_percent > 80` | 1h | warning | Team at 80% of monthly budget |
| `AzureBudgetCritical` | `azure_budget_utilisation_percent > 100` | 30m | critical | Team has exceeded monthly budget |
| `AzureBudgetProjectedOverrun` | `(projected_month_end / budget_limit) > 1.1` | 2h | warning | Projected to exceed budget by 10%+ |

### Anomaly alerts

| Alert | Expression | For | Severity | Meaning |
|---|---|---|---|---|
| `AzureCostAnomaly` | `azure_cost_anomaly_score > 2` | 1h | warning | Spend > 2× 7-day average |
| `AzureCostSpike` | `azure_cost_anomaly_score > 3` | 30m | critical | Spend > 3× 7-day average |

---

## Prometheus alert rules file

**File:** `prometheus/alerts/finops-alerts.yml`

```yaml
groups:
  - name: finops.collector
    rules:
      - alert: CollectorDown
        expr: time() - azure_collector_last_run_timestamp > 86400
        for: 1h
        labels:
          severity: critical
        annotations:
          summary: "FinOps collector has not run in 24 hours"
          description: "Last successful run was {{ $value | humanizeDuration }} ago. Check cron job or Azure Function."
          runbook: "https://github.com/AliHaidry/azure-finops-dashboard/blob/main/docs/runbook.md#collector-down"

      - alert: CollectorErrors
        expr: rate(azure_collector_errors_total[1h]) > 0
        for: 30m
        labels:
          severity: warning
        annotations:
          summary: "FinOps collector is encountering errors"
          description: "{{ $value | humanize }} errors/sec in the last hour for subscription {{ $labels.subscription }}."

  - name: finops.budget
    rules:
      - alert: AzureBudgetWarning
        expr: azure_budget_utilisation_percent > 80
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Team {{ $labels.team }} at {{ $value | humanizePercentage }} of monthly budget"
          description: "Team {{ $labels.team }} has consumed {{ $value | humanizePercentage }} of their monthly budget with {{ remaining_days }} days remaining."
          runbook: "https://github.com/AliHaidry/azure-finops-dashboard/blob/main/docs/runbook.md#budget-warning"

      - alert: AzureBudgetCritical
        expr: azure_budget_utilisation_percent > 100
        for: 30m
        labels:
          severity: critical
        annotations:
          summary: "Team {{ $labels.team }} has EXCEEDED monthly budget"
          description: "Team {{ $labels.team }} has consumed {{ $value | humanizePercentage }} of their budget. Immediate action required."
          runbook: "https://github.com/AliHaidry/azure-finops-dashboard/blob/main/docs/runbook.md#budget-exceeded"

  - name: finops.anomaly
    rules:
      - alert: AzureCostAnomaly
        expr: azure_cost_anomaly_score > 2
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Unusual spend detected in {{ $labels.subscription }}"
          description: "Daily spend is {{ $value | humanize }}× the 7-day average in subscription {{ $labels.subscription }}."

      - alert: AzureCostSpike
        expr: azure_cost_anomaly_score > 3
        for: 30m
        labels:
          severity: critical
        annotations:
          summary: "Cost spike in {{ $labels.subscription }} — immediate review required"
          description: "Daily spend is {{ $value | humanize }}× the 7-day average. Possible runaway resource or misconfiguration."
          runbook: "https://github.com/AliHaidry/azure-finops-dashboard/blob/main/docs/runbook.md#cost-spike"
```

---

## Alertmanager configuration

**File:** `alertmanager/alertmanager.yml`

```yaml
global:
  resolve_timeout: 5m
  slack_api_url: '<YOUR_SLACK_WEBHOOK_URL>'

route:
  group_by: ['alertname', 'severity', 'team']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'slack-warnings'

  routes:
    - match:
        severity: critical
      receiver: 'slack-critical-and-email'
      repeat_interval: 1h
      continue: false

    - match:
        severity: warning
      receiver: 'slack-warnings'
      continue: false

receivers:
  - name: 'slack-warnings'
    slack_configs:
      - channel: '#finops-alerts'
        title: '{{ .GroupLabels.alertname }}'
        text: |
          *Severity:* {{ .GroupLabels.severity | title }}
          {{ range .Alerts }}
          *Summary:* {{ .Annotations.summary }}
          *Description:* {{ .Annotations.description }}
          {{ if .Annotations.runbook }}*Runbook:* <{{ .Annotations.runbook }}|View runbook>{{ end }}
          {{ end }}
        color: '{{ if eq .GroupLabels.severity "critical" }}danger{{ else }}warning{{ end }}'

  - name: 'slack-critical-and-email'
    slack_configs:
      - channel: '#finops-alerts'
        title: '🚨 CRITICAL: {{ .GroupLabels.alertname }}'
        text: |
          {{ range .Alerts }}
          *Summary:* {{ .Annotations.summary }}
          *Description:* {{ .Annotations.description }}
          {{ if .Annotations.runbook }}*Runbook:* <{{ .Annotations.runbook }}|View runbook>{{ end }}
          {{ end }}
        color: 'danger'
    email_configs:
      - to: 'alihaidry11@gmail.com'
        from: 'alertmanager@alihaidry-devops.website'
        smarthost: 'localhost:25'
        subject: '[CRITICAL] {{ .GroupLabels.alertname }}'
        body: |
          {{ range .Alerts }}
          Summary: {{ .Annotations.summary }}
          Description: {{ .Annotations.description }}
          Runbook: {{ .Annotations.runbook }}
          {{ end }}

inhibit_rules:
  - source_match:
      severity: critical
    target_match:
      severity: warning
    equal: ['alertname', 'team']
```

---

## Setting up Slack

1. Go to **api.slack.com/apps** → Create New App
2. Add **Incoming Webhooks** → Activate → Add to workspace
3. Select channel `#finops-alerts` → Copy webhook URL
4. Add to Alertmanager config as `slack_api_url`
5. Restart Alertmanager: `sudo systemctl restart alertmanager`

---

## Tuning alert thresholds

Thresholds are intentionally conservative for a new deployment. Tune after 2-4 weeks of data:

| Alert | Default threshold | When to lower | When to raise |
|---|---|---|---|
| `AzureBudgetWarning` | 80% | Teams consistently hit 80% without issues | Budgets are frequently wrong |
| `AzureBudgetCritical` | 100% | You want earlier warning | Budget overruns are acceptable |
| `AzureCostAnomaly` | 2× average | Spend is very stable | Spend varies naturally day to day |
| `AzureCostSpike` | 3× average | You want to catch smaller spikes | Getting too many false positives |

Update thresholds in `prometheus/alerts/finops-alerts.yml` and reload:
```bash
sudo systemctl reload prometheus
```
