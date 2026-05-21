import { NextResponse } from 'next/server'
import pool from '@/lib/db'

export async function GET() {
  try {
    const client = await pool.connect()

    // MTD spend by team
    const teamSpend = await client.query(`
      SELECT 
        team,
        ROUND(SUM(cost_usd)::numeric, 4) as total_cost,
        COUNT(*) as record_count
      FROM cost_records
      WHERE usage_date >= date_trunc('month', CURRENT_DATE)
      GROUP BY team
      ORDER BY total_cost DESC
    `)

    // MTD spend by service
    const serviceSpend = await client.query(`
      SELECT 
        service_name,
        ROUND(SUM(cost_usd)::numeric, 4) as total_cost
      FROM cost_records
      WHERE usage_date >= date_trunc('month', CURRENT_DATE)
      GROUP BY service_name
      ORDER BY total_cost DESC
    `)

    // Daily spend last 30 days
    const dailySpend = await client.query(`
      SELECT 
        usage_date::text as date,
        ROUND(SUM(cost_usd)::numeric, 4) as total_cost
      FROM cost_records
      WHERE usage_date >= CURRENT_DATE - INTERVAL '30 days'
      GROUP BY usage_date
      ORDER BY usage_date ASC
    `)

    // Budget utilisation
    const budgets = await client.query(`
      SELECT 
        b.team,
        b.monthly_limit_usd as budget,
        ROUND(COALESCE(SUM(c.cost_usd), 0)::numeric, 4) as spent,
        ROUND((COALESCE(SUM(c.cost_usd), 0) / b.monthly_limit_usd * 100)::numeric, 1) as utilisation_pct
      FROM budgets b
      LEFT JOIN cost_records c
        ON c.team = b.team
        AND c.subscription_id = b.subscription_id
        AND c.usage_date >= date_trunc('month', CURRENT_DATE)
      GROUP BY b.team, b.monthly_limit_usd
      ORDER BY utilisation_pct DESC
    `)

    // Total MTD spend
    const total = await client.query(`
      SELECT ROUND(SUM(cost_usd)::numeric, 4) as total
      FROM cost_records
      WHERE usage_date >= date_trunc('month', CURRENT_DATE)
    `)

    // 30-day forecast (linear projection)
    const forecast = await client.query(`
      SELECT 
        ROUND(
          (SUM(cost_usd) / EXTRACT(DAY FROM CURRENT_DATE) * 
          EXTRACT(DAY FROM (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')))::numeric
        , 4) as projected_month_end
      FROM cost_records
      WHERE usage_date >= date_trunc('month', CURRENT_DATE)
    `)

    client.release()

    return NextResponse.json({
      total_mtd: total.rows[0]?.total || 0,
      projected_month_end: forecast.rows[0]?.projected_month_end || 0,
      team_spend: teamSpend.rows,
      service_spend: serviceSpend.rows,
      daily_spend: dailySpend.rows,
      budgets: budgets.rows,
      generated_at: new Date().toISOString(),
    })
  } catch (error) {
    console.error('DB error:', error)
    return NextResponse.json({ error: 'Database error' }, { status: 500 })
  }
}
