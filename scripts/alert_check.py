"""
FinOps Alert Check
Queries PostgreSQL for cost anomalies and sends Slack alerts.
Runs every 6 hours via GitHub Actions.
"""

import os
import json
import requests
import psycopg2
from datetime import datetime, timedelta

DATABASE_URL = os.environ["DATABASE_URL"]
SLACK_WEBHOOK_URL = os.environ["SLACK_WEBHOOK_URL"]
BUDGET_WARNING = float(os.environ.get("BUDGET_WARNING_THRESHOLD", "0.80"))
BUDGET_CRITICAL = float(os.environ.get("BUDGET_CRITICAL_THRESHOLD", "1.00"))
SPIKE_MULTIPLIER = float(os.environ.get("SPIKE_MULTIPLIER", "2.0"))

BUDGETS = {
    "finops-rg-dev": 5.00,
    "finops-tfstate-rg": 1.00,
}

def get_connection():
    return psycopg2.connect(DATABASE_URL)

def send_slack(message: str, level: str = "warning"):
    emoji = "🔴" if level == "critical" else "⚠️"
    color = "#FF0000" if level == "critical" else "#FFA500"
    payload = {
        "attachments": [{
            "color": color,
            "title": f"{emoji} FinOps Alert — {level.upper()}",
            "text": message,
            "footer": "Azure FinOps Dashboard",
            "ts": int(datetime.utcnow().timestamp())
        }]
    }
    r = requests.post(SLACK_WEBHOOK_URL, json=payload)
    print(f"Slack response: {r.status_code} — {message}")

def check_budget():
    print("Checking budget utilisation...")
    conn = get_connection()
    cur = conn.cursor()

    # MTD spend per resource group
    cur.execute("""
        SELECT resource_group, SUM(cost_usd) as mtd_cost
        FROM cost_records
        WHERE usage_date >= date_trunc('month', CURRENT_DATE)
        GROUP BY resource_group
    """)
    rows = cur.fetchall()
    cur.close()
    conn.close()

    for resource_group, mtd_cost in rows:
        budget = BUDGETS.get(resource_group)
        if not budget:
            continue
        utilisation = float(mtd_cost) / budget
        print(f"{resource_group}: ${mtd_cost:.3f} / ${budget:.2f} = {utilisation:.1%}")

        if utilisation >= BUDGET_CRITICAL:
            send_slack(
                f"*{resource_group}* has *exceeded* its monthly budget!\n"
                f"Spent: *${mtd_cost:.2f}* / Budget: *${budget:.2f}* "
                f"({utilisation:.1%})",
                level="critical"
            )
        elif utilisation >= BUDGET_WARNING:
            send_slack(
                f"*{resource_group}* is approaching its monthly budget.\n"
                f"Spent: *${mtd_cost:.2f}* / Budget: *${budget:.2f}* "
                f"({utilisation:.1%})",
                level="warning"
            )

def check_cost_spike():
    print("Checking for cost spikes...")
    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT
            COALESCE(SUM(CASE WHEN usage_date = CURRENT_DATE - 1 THEN cost_usd END), 0) as yesterday,
            COALESCE(AVG(daily_total), 0) as avg_7d
        FROM (
            SELECT usage_date, SUM(cost_usd) as daily_total
            FROM cost_records
            WHERE usage_date >= CURRENT_DATE - 8 AND usage_date < CURRENT_DATE - 1
            GROUP BY usage_date
        ) daily
        CROSS JOIN (
            SELECT SUM(cost_usd) as yesterday_total
            FROM cost_records WHERE usage_date = CURRENT_DATE - 1
        ) yd
    """)
    row = cur.fetchone()
    cur.close()
    conn.close()

    if not row:
        return

    yesterday, avg_7d = float(row[0]), float(row[1])
    if avg_7d > 0 and yesterday > avg_7d * SPIKE_MULTIPLIER:
        send_slack(
            f"Cost spike detected!\n"
            f"Yesterday's spend: *${yesterday:.2f}*\n"
            f"7-day average: *${avg_7d:.2f}*\n"
            f"That's *{yesterday/avg_7d:.1f}x* the normal daily rate.",
            level="warning"
        )
    else:
        print(f"No spike: yesterday=${yesterday:.2f}, 7d avg=${avg_7d:.2f}")

def check_collector_health():
    print("Checking collector health...")
    conn = get_connection()
    cur = conn.cursor()

    cur.execute("SELECT MAX(usage_date) FROM cost_records")
    row = cur.fetchone()
    cur.close()
    conn.close()

    if not row or not row[0]:
        send_slack("No cost records found in database!", level="critical")
        return

    last_date = row[0]
    days_since = (datetime.utcnow().date() - last_date).days
    print(f"Last collection: {last_date} ({days_since} days ago)")

    if days_since > 1:
        send_slack(
            f"FinOps collector may be down!\n"
            f"Last data collected: *{last_date}* ({days_since} days ago)\n"
            f"Check GitHub Actions → FinOps Collector workflow.",
            level="critical"
        )

if __name__ == "__main__":
    print(f"FinOps alert check starting at {datetime.utcnow().isoformat()}")
    check_budget()
    check_cost_spike()
    check_collector_health()
    print("Alert check complete.")
