import { NextResponse } from 'next/server'
import pool from '@/lib/db'

export async function GET() {
  try {
    const client = await pool.connect()

    const result = await client.query(`
      SELECT 
        usage_date,
        subscription_name,
        team,
        service_name,
        resource_group,
        ROUND(cost_usd::numeric, 6) as cost_usd,
        currency_original
      FROM cost_records
      WHERE usage_date >= date_trunc('month', CURRENT_DATE)
      ORDER BY usage_date DESC, cost_usd DESC
    `)

    client.release()

    // Build CSV
    const headers = ['Date', 'Subscription', 'Team', 'Service', 'Resource Group', 'Cost (USD)', 'Currency']
    const rows = result.rows.map(row => [
      row.usage_date,
      row.subscription_name,
      row.team,
      row.service_name,
      row.resource_group,
      row.cost_usd,
      row.currency_original,
    ])

    const csv = [headers, ...rows]
      .map(row => row.map(cell => `"${cell}"`).join(','))
      .join('\n')

    const month = new Date().toISOString().slice(0, 7)

    return new NextResponse(csv, {
      headers: {
        'Content-Type': 'text/csv',
        'Content-Disposition': `attachment; filename="finops-report-${month}.csv"`,
      },
    })
  } catch (error) {
    console.error('Export error:', error)
    return NextResponse.json({ error: 'Export failed' }, { status: 500 })
  }
}
