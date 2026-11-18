// CF-247 RM1I climate (S2-Build, Platform Admin 18 Nov 2026 10:31; Study Square ruling 13 Nov: climate as long-term averages, summer and winter
// averages and annual rainfall; admin docs/Roadmap/2026-01/RM1-AUSTRALIA-PAGE-TRACEABILITY.md rows 34-41). Reads one Bureau of Meteorology
// "Climate statistics for Australian locations" page (product IDCJCM0037, cw_<station>_All.shtml) with the shared HTML table reader and returns
// the three monthly statistics the destination figures are built from: mean maximum temperature, mean minimum temperature and mean rainfall.
// Each statistic carries its twelve monthly values (null where the page holds none), the annual value and the years of record the page states.
// The seasonal figures are worked out on the server from these months (security.destination_climate_load_v1), so the season months stay data.
import { extractHtmlTables } from './cf247-html-table.js'

export const BOM_STATISTICS = {
  mean_max_temp_c: /^mean maximum temperature\s*\(\s*°?\s*c\s*\)/i,
  mean_min_temp_c: /^mean minimum temperature\s*\(\s*°?\s*c\s*\)/i,
  mean_rainfall_mm: /^mean rainfall\s*\(\s*mm\s*\)/i,
}

const num = (s) => {
  const t = String(s ?? '').replace(/[^\d.\-]/g, '')
  if (!t || t === '-' || t === '.') return null
  const n = Number(t)
  return Number.isFinite(n) ? n : null
}

// one statistic row: the label cell, twelve months, the annual value, then the count of years and the first and last year of record
export function parseStatisticRow(cells) {
  const c = cells.map((x) => String(x ?? '').trim())
  const months = c.slice(1, 13).map(num)
  if (months.length !== 12 || months.filter((v) => v != null).length < 12) return null
  const annual = num(c[13])
  const years = (c.slice(14).join(' ').match(/\b(18|19|20)\d{2}\b/g) || []).map(Number)
  return { months, annual, first_year: years.length ? Math.min(...years) : null, last_year: years.length ? Math.max(...years) : null }
}

export function parseBomClimate(html) {
  const text = String(html ?? '')
  const station = (text.match(/(?:Site number|Station number)\s*:?\s*(?:<[^>]*>\s*)*(\d{4,6})/i) || [])[1] || null
  const prepared = (text.match(/Product IDCJCM0037\s+Prepared at\s+([^<\n]+)/i) || [])[1]?.trim() || null
  const out = {}
  for (const t of extractHtmlTables(text)) {
    for (const row of t.rows) {
      const label = String(row[0] ?? '').trim()
      for (const [key, re] of Object.entries(BOM_STATISTICS)) {
        if (out[key] || !re.test(label)) continue
        const r = parseStatisticRow(row)
        if (r) out[key] = r
      }
    }
  }
  const missing = Object.keys(BOM_STATISTICS).filter((k) => !out[k])
  return { station, prepared, statistics: out, missing }
}
