'use client'

import { useEffect, useState } from 'react'
import { BarChart, Bar, PieChart, Pie, Cell, LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts'
import { DollarSign, TrendingUp, AlertTriangle, Download, RefreshCw, Database } from 'lucide-react'

interface CostData {
  total_mtd: number
  projected_month_end: number
  team_spend: { team: string; total_cost: number; record_count: number }[]
  service_spend: { service_name: string; total_cost: number }[]
  daily_spend: { date: string; total_cost: number }[]
  budgets: { team: string; budget: number; spent: number; utilisation_pct: number }[]
  generated_at: string
}

const COLORS = ['#22c55e', '#3b82f6', '#f59e0b', '#ef4444', '#8b5cf6', '#06b6d4']

export default function Dashboard() {
  const [data, setData] = useState<CostData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [lastRefresh, setLastRefresh] = useState<Date>(new Date())

  const fetchData = async () => {
    setLoading(true)
    setError(null)
    try {
      const res = await fetch('/api/costs')
      if (!res.ok) throw new Error('Failed to fetch cost data')
      const json = await res.json()
      setData(json)
      setLastRefresh(new Date())
    } catch (err) {
      setError('Unable to load cost data. Check database connection.')
      console.error(err)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchData()
  }, [])

  const handleExport = () => {
    window.open('/api/export', '_blank')
  }

  if (loading) return (
    <div className="min-h-screen bg-gray-950 flex items-center justify-center">
      <div className="text-center">
        <Database className="w-12 h-12 text-blue-500 animate-pulse mx-auto mb-4" />
        <p className="text-gray-400 text-lg">Loading Azure cost data...</p>
      </div>
    </div>
  )

  if (error) return (
    <div className="min-h-screen bg-gray-950 flex items-center justify-center">
      <div className="text-center">
        <AlertTriangle className="w-12 h-12 text-red-500 mx-auto mb-4" />
        <p className="text-red-400 text-lg">{error}</p>
        <button onClick={fetchData} className="mt-4 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700">
          Retry
        </button>
      </div>
    </div>
  )

  return (
    <div className="min-h-screen bg-gray-950 text-white">

      {/* Header */}
      <div className="border-b border-gray-800 px-6 py-4">
        <div className="max-w-7xl mx-auto flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold text-white">Azure FinOps Dashboard</h1>
            <p className="text-gray-400 text-sm mt-0.5">
              Multi-subscription cost visibility · Last updated {lastRefresh.toLocaleTimeString()}
            </p>
          </div>
          <div className="flex gap-3">
            <button
              onClick={fetchData}
              className="flex items-center gap-2 px-4 py-2 bg-gray-800 hover:bg-gray-700 rounded-lg text-sm transition"
            >
              <RefreshCw className="w-4 h-4" />
              Refresh
            </button>
            <button
              onClick={handleExport}
              className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded-lg text-sm transition"
            >
              <Download className="w-4 h-4" />
              Export CSV
            </button>
          </div>
        </div>
      </div>

      <div className="max-w-7xl mx-auto px-6 py-8 space-y-8">

        {/* KPI Cards */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">

          {/* Total MTD Spend */}
          <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
            <div className="flex items-center justify-between mb-2">
              <p className="text-gray-400 text-sm">Total MTD Spend</p>
              <DollarSign className="w-5 h-5 text-green-500" />
            </div>
            <p className="text-4xl font-bold text-white">
              ${Number(data?.total_mtd || 0).toFixed(3)}
            </p>
            <p className="text-gray-500 text-xs mt-1">Month to date · all subscriptions</p>
          </div>

          {/* Projected Month End */}
          <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
            <div className="flex items-center justify-between mb-2">
              <p className="text-gray-400 text-sm">Projected Month-End</p>
              <TrendingUp className="w-5 h-5 text-blue-500" />
            </div>
            <p className="text-4xl font-bold text-white">
              ${Number(data?.projected_month_end || 0).toFixed(3)}
            </p>
            <p className="text-gray-500 text-xs mt-1">Linear projection based on daily run rate</p>
          </div>

          {/* Top Service */}
          <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
            <div className="flex items-center justify-between mb-2">
              <p className="text-gray-400 text-sm">Highest Cost Service</p>
              <AlertTriangle className="w-5 h-5 text-amber-500" />
            </div>
            <p className="text-2xl font-bold text-white truncate">
              {data?.service_spend[0]?.service_name || '—'}
            </p>
            <p className="text-amber-400 text-lg font-semibold mt-1">
              ${Number(data?.service_spend[0]?.total_cost || 0).toFixed(3)}
            </p>
          </div>
        </div>

        {/* Budget Progress */}
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
          <h2 className="text-lg font-semibold mb-6">Budget Utilisation</h2>
          <div className="space-y-4">
            {data?.budgets.map((budget) => {
              const pct = Math.min(Number(budget.utilisation_pct), 100)
              const color = pct >= 100 ? 'bg-red-500' : pct >= 80 ? 'bg-amber-500' : 'bg-green-500'
              const status = pct >= 100 ? 'Exceeded' : pct >= 80 ? 'Warning' : 'On track'
              const statusColor = pct >= 100 ? 'text-red-400' : pct >= 80 ? 'text-amber-400' : 'text-green-400'
              return (
                <div key={budget.team}>
                  <div className="flex items-center justify-between mb-1">
                    <span className="text-sm font-medium text-gray-300">{budget.team}</span>
                    <div className="flex items-center gap-4 text-sm">
                      <span className="text-gray-400">
                        ${Number(budget.spent).toFixed(3)} / ${Number(budget.budget).toFixed(2)}
                      </span>
                      <span className={`font-semibold ${statusColor}`}>{status}</span>
                      <span className="text-white font-bold w-16 text-right">{budget.utilisation_pct}%</span>
                    </div>
                  </div>
                  <div className="w-full bg-gray-800 rounded-full h-3">
                    <div
                      className={`${color} h-3 rounded-full transition-all duration-500`}
                      style={{ width: `${pct}%` }}
                    />
                  </div>
                </div>
              )
            })}
          </div>
        </div>

        {/* Charts row */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">

          {/* Cost by Service Pie */}
          <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
            <h2 className="text-lg font-semibold mb-6">Cost by Service</h2>
            <ResponsiveContainer width="100%" height={280}>
              <PieChart>
                <Pie
                  data={data?.service_spend.map(s => ({
                    ...s,
                    total_cost: Number(s.total_cost)
                  }))}
                  dataKey="total_cost"
                  nameKey="service_name"
                  cx="50%"
                  cy="50%"
                  innerRadius={60}
                  outerRadius={100}
                  paddingAngle={3}
                  labelLine={false}
                  label={({ cx, cy, midAngle, innerRadius, outerRadius, percent }) => {
                    if (!percent || percent < 0.05) return null
                    const RADIAN = Math.PI / 180
                    const radius = innerRadius + (outerRadius - innerRadius) * 0.5
                    const x = cx + radius * Math.cos(-midAngle * RADIAN)
                    const y = cy + radius * Math.sin(-midAngle * RADIAN)
                    return (
                      <text x={x} y={y} fill="white" textAnchor="middle" dominantBaseline="central" fontSize={13} fontWeight="bold">
                        {`${(percent * 100).toFixed(0)}%`}
                      </text>
                    )
                  }}
                >
                  {data?.service_spend.map((_, i) => (
                    <Cell key={i} fill={COLORS[i % COLORS.length]} />
                  ))}
                </Pie>
                <Tooltip
                  formatter={(value) => [`$${Number(value).toFixed(4)}`, 'Cost']}
                  contentStyle={{ backgroundColor: '#1f2937', border: '1px solid #374151', borderRadius: '8px' }}
                />
                <Legend />
              </PieChart>
            </ResponsiveContainer>
          </div>

          {/* Cost by Team Bar */}
          <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
            <h2 className="text-lg font-semibold mb-6">Cost by Team</h2>
            <ResponsiveContainer width="100%" height={280}>
              <BarChart data={data?.team_spend} margin={{ top: 5, right: 20, bottom: 5, left: 10 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
                <XAxis dataKey="team" tick={{ fill: '#9ca3af', fontSize: 12 }} />
                <YAxis tick={{ fill: '#9ca3af', fontSize: 12 }} tickFormatter={(v) => `$${v}`} />
                <Tooltip
                  formatter={(value) => [`$${Number(value).toFixed(4)}`, 'MTD Spend']}
                  contentStyle={{ backgroundColor: '#1f2937', border: '1px solid #374151', borderRadius: '8px' }}
                />
                <Bar dataKey="total_cost" fill="#22c55e" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>

        {/* Daily Spend Trend */}
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
          <h2 className="text-lg font-semibold mb-6">Daily Spend Trend — Last 30 Days</h2>
          <ResponsiveContainer width="100%" height={240}>
            <LineChart data={data?.daily_spend} margin={{ top: 5, right: 20, bottom: 5, left: 10 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
              <XAxis dataKey="date" tick={{ fill: '#9ca3af', fontSize: 11 }} />
              <YAxis tick={{ fill: '#9ca3af', fontSize: 12 }} tickFormatter={(v) => `$${v}`} />
              <Tooltip
                formatter={(value) => [`$${Number(value).toFixed(4)}`, 'Daily Spend']}
                contentStyle={{ backgroundColor: '#1f2937', border: '1px solid #374151', borderRadius: '8px' }}
              />
              <Line type="monotone" dataKey="total_cost" stroke="#3b82f6" strokeWidth={2} dot={{ fill: '#3b82f6', r: 4 }} />
            </LineChart>
          </ResponsiveContainer>
        </div>

        {/* Service breakdown table */}
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
          <h2 className="text-lg font-semibold mb-6">Service Breakdown</h2>
          <table className="w-full text-sm">
            <thead>
              <tr className="text-gray-400 border-b border-gray-800">
                <th className="text-left pb-3 font-medium">Service</th>
                <th className="text-right pb-3 font-medium">MTD Cost</th>
                <th className="text-right pb-3 font-medium">% of Total</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-800">
              {data?.service_spend.map((service) => {
                const pct = data.total_mtd > 0
                  ? (Number(service.total_cost) / Number(data.total_mtd) * 100).toFixed(1)
                  : '0.0'
                return (
                  <tr key={service.service_name} className="hover:bg-gray-800/50 transition">
                    <td className="py-3 text-gray-300">{service.service_name}</td>
                    <td className="py-3 text-right text-white font-medium">
                      ${Number(service.total_cost).toFixed(4)}
                    </td>
                    <td className="py-3 text-right text-gray-400">{pct}%</td>
                  </tr>
                )
              })}
            </tbody>
            <tfoot>
              <tr className="border-t border-gray-700">
                <td className="pt-3 font-semibold text-white">Total</td>
                <td className="pt-3 text-right font-bold text-white">
                  ${Number(data?.total_mtd || 0).toFixed(4)}
                </td>
                <td className="pt-3 text-right text-gray-400">100%</td>
              </tr>
            </tfoot>
          </table>
        </div>

        {/* Footer */}
        <div className="text-center text-gray-600 text-xs pb-8">
          Azure FinOps Dashboard · Built by Ali Haidry ·{' '}
          <a href="https://alihaidry-devops.website" className="hover:text-gray-400 transition">
            alihaidry-devops.website
          </a>
        </div>
      </div>
    </div>
  )
}
