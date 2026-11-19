#!/usr/bin/env node
// CF-247 s770: per-course field readiness (Platform Admin 19 Nov 2026 11:41). Turns the rows of scripts/telemetry/course-field-readiness.sql
// (one Management API answer per part, JSON arrays) into:
//   Course_Field_Readiness_Matrix_<date>.csv      one row per active course, the 14 canonical API v3 fields and the per-course counts
//   Stakeholder_Course_Readiness_Summary.json     the three tabs of the Google Sheet Stakeholder_Course_Readiness_Summary (rows of cells)
// Usage: node scripts/telemetry/course-field-readiness.mjs <out-dir> <date YYYY-MM-DD> <part.json>...
// Read only: it reads files and writes files; nothing reaches the database from here.
import fs from 'node:fs'
import path from 'node:path'

export const FIELDS = ['official_url', 'description', 'study_load', 'tuition_fee', 'fee_basis', 'intake_dates', 'application_deadlines', 'duration',
  'campus_locality', 'aer_academic', 'english_requirements', 'scholarships', 'destination_city_stats', 'career_outcomes']
export const STATES = ['TRYING', 'POSSIBLE_NEEDS_SOURCE', 'NOT_POSSIBLE', 'EMPTY_NOT_STARTED']

// What each state means to a stakeholder and how the website shows it (API v3 courses carry empty_reason_code for an empty field)
export const DISPLAY_RULES = [
  ['state', 'meaning', 'api_v3_empty_reason_code', 'frontend_display_rule'],
  ['ADMITTED (the value)', 'Read from the official source and admitted (Layer 1, a page read or a Layer 4 decision)', '(none; the field has a value)', 'Show the value'],
  ['TRYING', 'A page is found and a read, re-read, Layer 3 or Layer 4 step is queued or running', 'pending_extraction', 'Hide the field, or show "Being checked"; never show a guess'],
  ['POSSIBLE_NEEDS_SOURCE', 'No course or provider page found yet, the site only, a blocked site or no reader for the field', 'source_unavailable', 'Hide the field; show "Check with the provider" with the provider\'s website link'],
  ['NOT_POSSIBLE', 'Read against the official source and not published there (for example a month-only intake, or not stated on the page)', 'not_published_by_provider (online_only_no_campus for campus fields)', 'Show "Not published by the provider" (or "Online only" for campus fields); do not ask again'],
  ['EMPTY_NOT_STARTED', 'The country\'s scope is not switched on yet (Canada entry requirements; destination data where the country has no approved edition)', 'not_listed_on_register', 'Hide the field and its section for that country; no message'],
]

export const stateOf = (cell) => (STATES.includes(cell) ? cell : 'ADMITTED')

export const csvCell = (v) => {
  const s = v == null ? '' : String(v)
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
}

export function build(rows, date) {
  const header = ['course_id', 'country_code', 'provider_id', 'provider_name', 'course_title', ...FIELDS,
    'fields_admitted', 'fields_trying', 'fields_possible_needs_source', 'fields_not_possible', 'fields_empty_not_started']
  const lines = [header.join(',')]
  const byField = Object.fromEntries(FIELDS.map((f) => [f, { ADMITTED: 0, TRYING: 0, POSSIBLE_NEEDS_SOURCE: 0, NOT_POSSIBLE: 0, EMPTY_NOT_STARTED: 0 }]))
  const byProvider = new Map()
  const byCountry = {}
  for (const r of rows) {
    const cells = typeof r.cells === 'string' ? JSON.parse(r.cells) : r.cells
    const n = { ADMITTED: 0, TRYING: 0, POSSIBLE_NEEDS_SOURCE: 0, NOT_POSSIBLE: 0, EMPTY_NOT_STARTED: 0 }
    const p = byProvider.get(r.provider_id) || { provider_id: r.provider_id, provider_name: r.provider_name, country_code: r.country_code, courses: 0,
      needs_source: 0, trying: 0, gaps: Object.fromEntries(FIELDS.map((f) => [f, 0])) }
    for (const f of FIELDS) {
      const s = stateOf(cells[f])
      n[s]++; byField[f][s]++
      if (s === 'POSSIBLE_NEEDS_SOURCE') { p.needs_source++; p.gaps[f]++ }
      if (s === 'TRYING') p.trying++
    }
    p.courses++; byProvider.set(r.provider_id, p)
    byCountry[r.country_code] = (byCountry[r.country_code] || 0) + 1
    lines.push([r.course_id, r.country_code, r.provider_id, r.provider_name, r.course_title, ...FIELDS.map((f) => cells[f]),
      n.ADMITTED, n.TRYING, n.POSSIBLE_NEEDS_SOURCE, n.NOT_POSSIBLE, n.EMPTY_NOT_STARTED].map(csvCell).join(','))
  }
  const total = rows.length
  const pct = (x) => (total ? Math.round((1000 * x) / total) / 10 : 0)
  const executive = [
    [`Course field readiness, ${date} (AEDT), ${total.toLocaleString('en-AU')} active courses: ${Object.entries(byCountry).sort().map(([k, v]) => `${k} ${v.toLocaleString('en-AU')}`).join(', ')}`],
    ['field', 'admitted', 'admitted_pct', 'trying', 'trying_pct', 'possible_needs_source', 'possible_needs_source_pct', 'not_possible', 'not_possible_pct', 'empty_not_started', 'empty_not_started_pct'],
    ...FIELDS.map((f) => {
      const b = byField[f]
      return [f, b.ADMITTED, pct(b.ADMITTED), b.TRYING, pct(b.TRYING), b.POSSIBLE_NEEDS_SOURCE, pct(b.POSSIBLE_NEEDS_SOURCE), b.NOT_POSSIBLE, pct(b.NOT_POSSIBLE),
        b.EMPTY_NOT_STARTED, pct(b.EMPTY_NOT_STARTED)]
    }),
  ]
  const providers = [...byProvider.values()].filter((p) => p.needs_source > 0)
    .sort((a, b) => b.needs_source - a.needs_source || b.courses - a.courses || String(a.provider_name).localeCompare(String(b.provider_name)))
  const byProviderTab = [
    ['rank', 'provider_name', 'country_code', 'active_courses', 'cells_possible_needs_source', 'cells_trying', 'top_fields_needing_a_source', 'provider_id'],
    ...providers.slice(0, 100).map((p, i) => [i + 1, p.provider_name, p.country_code, p.courses, p.needs_source, p.trying,
      Object.entries(p.gaps).filter(([, v]) => v > 0).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([f, v]) => `${f} (${v})`).join('; '), p.provider_id]),
  ]
  return { csv: lines.join('\n') + '\n', summary: { date, total, by_country: byCountry, Executive_Summary: executive, By_Provider_Action_List: byProviderTab, Dev_Display_Rules: DISPLAY_RULES,
    sheet_tabs: sheetTabs(executive, byProviderTab, total, date) } }
}

// The Google Sheet Stakeholder_Course_Readiness_Summary (Drive › Monitoring): each tab's rows, written from A1 as they are. On Executive_Summary
// the counts are the export's data and every percentage and the row check are formulas over them (B2 is the number of active courses).
export function sheetTabs(executive, byProviderTab, total, date) {
  const [title, , ...fieldRows] = executive
  const exec = [
    [title[0]],
    ['Active courses', total, `Source: workflow course-field-readiness, branch course-readiness-snapshot, export of ${date} (AEDT)`],
    [],
    ['Field', 'Admitted', 'Admitted %', 'Trying', 'Trying %', 'Possible, needs a source', 'Possible, needs a source %', 'Not possible', 'Not possible %',
      'Empty, not started', 'Empty, not started %', 'Row check (equals B2)'],
    ...fieldRows.map((r, i) => {
      const n = i + 5
      const pct = (col) => `=IF($B$2=0,0,${col}${n}/$B$2)`
      return [r[0], r[1], pct('B'), r[3], pct('D'), r[5], pct('F'), r[7], pct('H'), r[9], pct('J'), `=B${n}+D${n}+F${n}+H${n}+J${n}`]
    }),
  ]
  return { Executive_Summary: exec, By_Provider_Action_List: byProviderTab, Dev_Display_Rules: DISPLAY_RULES }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [outDir, date, ...parts] = process.argv.slice(2)
  if (!outDir || !/^\d{4}-\d{2}-\d{2}$/.test(date || '') || !parts.length) {
    console.error('usage: course-field-readiness.mjs <out-dir> <YYYY-MM-DD> <part.json>...'); process.exit(2)
  }
  const rows = parts.flatMap((p) => JSON.parse(fs.readFileSync(p, 'utf8')))
  const ids = new Set(rows.map((r) => r.course_id))
  if (ids.size !== rows.length) { console.error(`duplicate course rows: ${rows.length} rows, ${ids.size} courses`); process.exit(1) }
  const { csv, summary } = build(rows, date)
  fs.mkdirSync(outDir, { recursive: true })
  fs.writeFileSync(path.join(outDir, `Course_Field_Readiness_Matrix_${date}.csv`), csv)
  fs.writeFileSync(path.join(outDir, 'Stakeholder_Course_Readiness_Summary.json'), JSON.stringify(summary, null, 1))
  console.log(JSON.stringify({ date, courses: rows.length, by_country: summary.by_country }))
}
