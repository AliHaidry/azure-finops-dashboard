"""
azure-finops-dashboard · collector.py
--------------------------------------
Fetches daily cost data from Azure Cost Management API across multiple
subscriptions, enriches records with resource tags, writes to PostgreSQL,
and exposes Prometheus metrics on :8000/metrics.

Usage:
    python collector.py                     # collect yesterday's data
    python collector.py --backfill 30       # collect last 30 days
    python collector.py --subscription ID   # single subscription only
    python collector.py --dry-run           # fetch but skip DB writes
"""

import argparse
import logging
import os
import sys
import time
from datetime import date, datetime, timedelta
from typing import Optional

from azure.identity import DefaultAzureCredential
from azure.mgmt.costmanagement import CostManagementClient
from azure.mgmt.costmanagement.models import (
    QueryDefinition,
    QueryDataset,
    QueryAggregation,
    QueryGrouping,
    QueryTimePeriod,
    GranularityType,
    ExportType,
    TimeframeType,
)
from azure.mgmt.resource import ResourceManagementClient
from prometheus_client import Gauge, Counter, start_http_server
import psycopg2
from psycopg2.extras import execute_values
from dotenv import load_dotenv

load_dotenv()

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("finops.collector")

# ── Config ────────────────────────────────────────────────────────────────────

SUBSCRIPTION_IDS = [
    s.strip()
    for s in os.getenv("SUBSCRIPTION_IDS", "").split(",")
    if s.strip()
]

DATABASE_URL     = os.getenv("DATABASE_URL", "")
PROMETHEUS_PORT  = int(os.getenv("PROMETHEUS_PORT", "8000"))
CURRENCY         = os.getenv("CURRENCY", "USD")
DRY_RUN          = os.getenv("DRY_RUN", "false").lower() == "true"

# ── Prometheus metrics ────────────────────────────────────────────────────────

cost_daily = Gauge(
    "azure_cost_daily_usd",
    "Daily Azure spend in USD",
    ["subscription_name", "date"],
)

cost_by_team = Gauge(
    "azure_cost_by_team_usd",
    "Month-to-date Azure spend by team tag",
    ["team", "subscription_name"],
)

cost_by_service = Gauge(
    "azure_cost_by_service_usd",
    "Month-to-date Azure spend by service",
    ["service", "subscription_name"],
)

budget_utilisation = Gauge(
    "azure_budget_utilisation_percent",
    "Percentage of monthly budget consumed",
    ["team", "subscription_name"],
)

collector_last_run = Gauge(
    "azure_collector_last_run_timestamp",
    "Unix timestamp of last successful collection run",
)

records_collected = Counter(
    "azure_collector_records_collected_total",
    "Total cost records collected",
    ["subscription_name"],
)

collection_errors = Counter(
    "azure_collector_errors_total",
    "Total collection errors",
    ["subscription_name", "error_type"],
)

# ── Database ──────────────────────────────────────────────────────────────────

def get_db_connection():
    """Return a psycopg2 connection using DATABASE_URL."""
    if not DATABASE_URL:
        raise ValueError("DATABASE_URL environment variable is not set")
    return psycopg2.connect(DATABASE_URL)


def init_schema(conn):
    """Create tables if they don't exist."""
    with conn.cursor() as cur:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS cost_records (
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

            CREATE INDEX IF NOT EXISTS idx_cost_records_date
                ON cost_records (usage_date);
            CREATE INDEX IF NOT EXISTS idx_cost_records_team
                ON cost_records (team);
            CREATE INDEX IF NOT EXISTS idx_cost_records_subscription
                ON cost_records (subscription_id);

            CREATE TABLE IF NOT EXISTS budgets (
                id                  SERIAL PRIMARY KEY,
                team                TEXT NOT NULL,
                subscription_id     TEXT,
                monthly_limit_usd   NUMERIC(10, 2) NOT NULL,
                currency            TEXT NOT NULL DEFAULT 'USD',
                created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                UNIQUE (team, subscription_id)
            );

            CREATE TABLE IF NOT EXISTS forecasts (
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
        """)
    conn.commit()
    log.info("Database schema initialised")


def upsert_records(conn, records: list[dict]):
    """Upsert cost records — skip duplicates on (usage_date, resource_id, subscription_id)."""
    if not records:
        return 0

    rows = [
        (
            r["usage_date"],
            r["subscription_id"],
            r["subscription_name"],
            r["resource_id"],
            r["resource_group"],
            r.get("resource_type"),
            r.get("service_name"),
            r["cost_usd"],
            r.get("currency_original", "USD"),
            r.get("team", "untagged"),
            r.get("environment"),
            r.get("owner"),
            r.get("project"),
            psycopg2.extras.Json(r.get("tags", {})),
        )
        for r in records
    ]

    sql = """
        INSERT INTO cost_records (
            usage_date, subscription_id, subscription_name,
            resource_id, resource_group, resource_type, service_name,
            cost_usd, currency_original,
            team, environment, owner, project, tags
        ) VALUES %s
        ON CONFLICT (usage_date, resource_id, subscription_id)
        DO UPDATE SET
            cost_usd        = EXCLUDED.cost_usd,
            service_name    = EXCLUDED.service_name,
            team            = EXCLUDED.team,
            environment     = EXCLUDED.environment,
            owner           = EXCLUDED.owner,
            project         = EXCLUDED.project,
            tags            = EXCLUDED.tags,
            collected_at    = NOW()
    """

    with conn.cursor() as cur:
        execute_values(cur, sql, rows)
    conn.commit()
    return len(rows)


# ── Tag enrichment ────────────────────────────────────────────────────────────

_tag_cache: dict[str, dict] = {}


def get_resource_tags(
    credential,
    subscription_id: str,
    resource_id: str,
) -> dict:
    """Fetch resource tags with in-memory caching."""
    if resource_id in _tag_cache:
        return _tag_cache[resource_id]

    try:
        client = ResourceManagementClient(credential, subscription_id)
        resource = client.resources.get_by_id(resource_id, api_version="2021-04-01")
        tags = resource.tags or {}
    except Exception as e:
        log.debug(f"Could not fetch tags for {resource_id}: {e}")
        tags = {}

    _tag_cache[resource_id] = tags
    return tags


def resolve_team(tags: dict, resource_group: str) -> str:
    """Resolve team from tags with fallback to resource group."""
    return (
        tags.get("team")
        or tags.get("Team")
        or tags.get("TEAM")
        or resource_group
        or "untagged"
    )


# ── Cost Management API ───────────────────────────────────────────────────────

def fetch_costs(
    credential,
    subscription_id: str,
    start_date: date,
    end_date: date,
) -> list[dict]:
    """
    Fetch daily cost records from Azure Cost Management API.
    Returns list of raw cost dicts.
    """
    client = CostManagementClient(credential)
    scope = f"/subscriptions/{subscription_id}"

    query = QueryDefinition(
        type=ExportType.ACTUAL_COST,
        timeframe=TimeframeType.CUSTOM,
        time_period=QueryTimePeriod(
            from_property=datetime.combine(start_date, datetime.min.time()),
            to=datetime.combine(end_date, datetime.min.time()),
        ),
        dataset=QueryDataset(
            granularity=GranularityType.DAILY,
            aggregation={
                "totalCost": QueryAggregation(name="Cost", function="Sum")
            },
            grouping=[
                QueryGrouping(type="Dimension", name="ResourceId"),
                QueryGrouping(type="Dimension", name="ResourceGroupName"),
                QueryGrouping(type="Dimension", name="ServiceName"),
                QueryGrouping(type="Dimension", name="ResourceType"),
            ],
        ),
    )

    retries = 3
    for attempt in range(retries):
        try:
            result = client.query.usage(scope=scope, parameters=query)
            break
        except Exception as e:
            if attempt < retries - 1:
                wait = 2 ** attempt * 5
                log.warning(f"API error (attempt {attempt + 1}/{retries}), retrying in {wait}s: {e}")
                time.sleep(wait)
            else:
                raise

    # Parse columns for positional mapping
    columns = [col.name for col in result.columns]
    col = {name: idx for idx, name in enumerate(columns)}

    rows = []
    for row in result.rows:
        try:
            # UsageDate comes back as an integer YYYYMMDD
            raw_date = str(row[col["UsageDate"]])
            usage_date = date(
                int(raw_date[:4]),
                int(raw_date[4:6]),
                int(raw_date[6:8]),
            )

            rows.append({
                "usage_date":    usage_date,
                "resource_id":   row[col["ResourceId"]] or "unknown",
                "resource_group": row[col["ResourceGroupName"]] or "unknown",
                "service_name":  row[col["ServiceName"]] or "unknown",
                "resource_type": row[col.get("ResourceType", -1)] if "ResourceType" in col else None,
                "cost_usd":      float(row[col["Cost"]]),
                "currency_original": CURRENCY,
            })
        except Exception as e:
            log.debug(f"Skipping malformed row: {row} — {e}")

    return rows


# ── Prometheus updates ────────────────────────────────────────────────────────

def update_prometheus_metrics(conn, subscription_name: str):
    """Recompute and update all Prometheus gauges from the DB."""
    with conn.cursor() as cur:
        # Daily spend — last 30 days
        cur.execute("""
            SELECT usage_date::text, SUM(cost_usd)
            FROM cost_records
            WHERE subscription_name = %s
              AND usage_date >= CURRENT_DATE - INTERVAL '30 days'
            GROUP BY usage_date
        """, (subscription_name,))
        for row in cur.fetchall():
            cost_daily.labels(
                subscription_name=subscription_name,
                date=row[0],
            ).set(float(row[1]))

        # MTD spend by team
        cur.execute("""
            SELECT team, SUM(cost_usd)
            FROM cost_records
            WHERE subscription_name = %s
              AND usage_date >= date_trunc('month', CURRENT_DATE)
            GROUP BY team
        """, (subscription_name,))
        for row in cur.fetchall():
            cost_by_team.labels(
                team=row[0],
                subscription_name=subscription_name,
            ).set(float(row[1]))

        # MTD spend by service
        cur.execute("""
            SELECT service_name, SUM(cost_usd)
            FROM cost_records
            WHERE subscription_name = %s
              AND usage_date >= date_trunc('month', CURRENT_DATE)
            GROUP BY service_name
            ORDER BY SUM(cost_usd) DESC
            LIMIT 20
        """, (subscription_name,))
        for row in cur.fetchall():
            cost_by_service.labels(
                service=row[0],
                subscription_name=subscription_name,
            ).set(float(row[1]))

        # Budget utilisation
        cur.execute("""
            SELECT b.team, b.monthly_limit_usd, COALESCE(SUM(c.cost_usd), 0)
            FROM budgets b
            LEFT JOIN cost_records c
                ON c.team = b.team
                AND c.subscription_id = b.subscription_id
                AND c.usage_date >= date_trunc('month', CURRENT_DATE)
            WHERE b.subscription_id IN (
                SELECT DISTINCT subscription_id FROM cost_records
                WHERE subscription_name = %s
            )
            GROUP BY b.team, b.monthly_limit_usd
        """, (subscription_name,))
        for row in cur.fetchall():
            team, limit, spent = row
            if limit and float(limit) > 0:
                pct = float(spent) / float(limit) * 100
                budget_utilisation.labels(
                    team=team,
                    subscription_name=subscription_name,
                ).set(pct)


# ── Main collection loop ──────────────────────────────────────────────────────

def collect_subscription(
    credential,
    subscription_id: str,
    subscription_name: str,
    start_date: date,
    end_date: date,
    conn,
    dry_run: bool = False,
):
    """Collect cost data for one subscription and write to DB."""
    log.info(f"→ Collecting [{subscription_name}] {start_date} → {end_date}")

    try:
        raw_records = fetch_costs(credential, subscription_id, start_date, end_date)
        log.info(f"  {len(raw_records)} records fetched from API")
    except Exception as e:
        log.error(f"  API fetch failed: {e}")
        collection_errors.labels(
            subscription_name=subscription_name,
            error_type="api_fetch",
        ).inc()
        return 0

    # Enrich with subscription info and tags
    enriched = []
    for record in raw_records:
        tags = get_resource_tags(credential, subscription_id, record["resource_id"])
        record.update({
            "subscription_id":   subscription_id,
            "subscription_name": subscription_name,
            "team":        resolve_team(tags, record["resource_group"]),
            "environment": tags.get("environment") or tags.get("Environment"),
            "owner":       tags.get("owner") or tags.get("Owner"),
            "project":     tags.get("project") or tags.get("Project"),
            "tags":        tags,
        })
        enriched.append(record)

    if dry_run:
        log.info(f"  [DRY RUN] Would write {len(enriched)} records — skipping DB write")
        return len(enriched)

    try:
        written = upsert_records(conn, enriched)
        records_collected.labels(subscription_name=subscription_name).inc(written)
        log.info(f"  ✓ {written} records written to PostgreSQL")
        return written
    except Exception as e:
        log.error(f"  DB write failed: {e}")
        collection_errors.labels(
            subscription_name=subscription_name,
            error_type="db_write",
        ).inc()
        conn.rollback()
        return 0


def run(
    subscription_filter: Optional[str] = None,
    backfill_days: int = 1,
    dry_run: bool = False,
):
    """Main entry point — authenticate, collect, store, update metrics."""

    if not SUBSCRIPTION_IDS:
        log.error("SUBSCRIPTION_IDS environment variable is not set or empty")
        sys.exit(1)

    log.info("─" * 60)
    log.info("FinOps Collector starting")
    log.info(f"  Subscriptions : {len(SUBSCRIPTION_IDS)}")
    log.info(f"  Backfill days : {backfill_days}")
    log.info(f"  Dry run       : {dry_run}")
    log.info("─" * 60)

    credential = DefaultAzureCredential()

    end_date   = date.today() - timedelta(days=1)   # yesterday (latest available)
    start_date = end_date - timedelta(days=backfill_days - 1)

    conn = None if dry_run else get_db_connection()

    if conn:
        init_schema(conn)

    subscriptions = SUBSCRIPTION_IDS
    if subscription_filter:
        subscriptions = [s for s in subscriptions if subscription_filter in s]
        log.info(f"Filtered to subscription: {subscription_filter}")

    # Get subscription display names
    sub_names = {}
    for sub_id in subscriptions:
        try:
            from azure.mgmt.subscription import SubscriptionClient
            sub_client = SubscriptionClient(credential)
            sub = sub_client.subscriptions.get(sub_id)
            sub_names[sub_id] = sub.display_name
        except Exception:
            sub_names[sub_id] = sub_id   # fallback to ID

    total_written = 0
    for sub_id in subscriptions:
        sub_name = sub_names.get(sub_id, sub_id)
        written = collect_subscription(
            credential=credential,
            subscription_id=sub_id,
            subscription_name=sub_name,
            start_date=start_date,
            end_date=end_date,
            conn=conn,
            dry_run=dry_run,
        )
        total_written += written

        if conn and not dry_run:
            update_prometheus_metrics(conn, sub_name)

    if conn:
        conn.close()

    collector_last_run.set(time.time())

    log.info("─" * 60)
    log.info(f"Collection complete — {total_written} total records written")
    log.info("─" * 60)


# ── CLI ───────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Azure FinOps cost collector")
    parser.add_argument(
        "--backfill",
        type=int,
        default=1,
        metavar="DAYS",
        help="Number of days to backfill (default: 1 = yesterday only)",
    )
    parser.add_argument(
        "--subscription",
        type=str,
        default=None,
        metavar="ID",
        help="Collect for a single subscription ID only",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        default=DRY_RUN,
        help="Fetch data but skip writing to database",
    )
    parser.add_argument(
        "--no-prometheus",
        action="store_true",
        help="Skip starting the Prometheus metrics server",
    )

    args = parser.parse_args()

    if not args.no_prometheus:
        start_http_server(PROMETHEUS_PORT)
        log.info(f"Prometheus metrics available at http://localhost:{PROMETHEUS_PORT}/metrics")

    run(
        subscription_filter=args.subscription,
        backfill_days=args.backfill,
        dry_run=args.dry_run,
    )
