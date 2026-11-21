#!/usr/bin/env node
// CF-247 s927: the daily data gap register (Platform Admin 21 Nov 2026 12:19: "maintain gap registers which gets updated everyday at google
// drive Monitoring folder ... with detailed institute being worked on and daily updates - removing them if data field is admitted, per
// country basis"; answers 12:2x: course × field rows, all open gaps, not shared yet).
// Reads the same rows as scripts/telemetry/course-field-readiness.mjs (scripts/telemetry/course-field-readiness.sql, with its raw column)
// and yesterday's register state, and writes:
//   Data_Gap_Register_<CC>[_Part<n>]_<date>.csv  one row per open gap (course × field), by country, each file under MAX_PART_BYTES.
//                                               A gap leaves the register on the day its field is admitted.
//   Data_Gap_Closed_<date>.csv                  the gaps that left since the last register, and why (admitted, or the course left)
//   Data_Gap_Institutions_<CC>_<date>.csv       one row per institution and field with open gaps: counts by gap, what is being worked on
//                                               now, what was admitted since the last register; a row leaves when the field is complete
//   Data_Gap_Register_Sheet.json                the tabs of the Google Sheet StudySearch_Data_Gap_Register: Summary (country × field × gap,
//                                               today, the last register and the change), Institutions_Top (the institutions with the most
//                                               open gaps per country) and Closed_Today (what was admitted since the last register)
//   Data_Gap_State.json.gz                      the state the next run compares with (first day each gap was seen, and the summary counts)
// Usage: node scripts/telemetry/data-gap-register.mjs <out-dir> <date YYYY-MM-DD> <prev-state.json.gz | -> <part.json>...
// Read only: it reads files and writes files; nothing reaches the database from here.
import fs from 'node:fs'
import path from 'node:path'
import zlib from 'node:zlib'
import { FIELDS, MAX_PART_BYTES, stateOf, csvCell } from './course-field-readiness.mjs'

// The coverage attribute behind each canonical field (the raw column of the export)
export const RAW_ATTR = { official_url: 'official_url', description: 'description', tuition_fee: 'provider_tuition', fee_basis: 'provider_tuition',
  intake_dates: 'intakes', application_deadlines: 'deadline', duration: 'duration', campus_locality: 'campus', aer_academic: 'academic_entry',
  english_requirements: 'english' }

// The gaps, in the order the register shows them, with what happens next (the Summary tab's legend)
export const GAPS = [
  ['Being checked', 'Read from the official page; the platform\'s checks are running', 'Admitted automatically when the checks pass'],
  ['Waiting for a person', 'Read and held for a person\'s approval', 'Admitted as soon as it is approved'],
  ['Page not found yet', 'The institution\'s website is known; the page for this course and field is not found yet', 'Being searched for; read when found'],
  ['No website on record', 'No website is held for the institution', 'The website is being sourced first'],
  ['Site blocked', 'The site refuses automated reading (robots rules or a directory site)', 'Needs another official source or a manual read'],
  ['No reader yet', 'No reader is switched on for this field yet', 'Waits for the reader to be released'],
  ['No scholarship found yet', 'No scholarship linked to this course has been found', 'Scholarship pages are being read'],
  ['Not published by the provider', 'Read against the official source and not published there', 'Nothing to collect: show "Check with the provider"'],
]
export const GAP_NAMES = GAPS.map((g) => g[0])

export function gapOf(field, state, raw) {
  const r = raw ? raw[RAW_ATTR[field]] : undefined
  if (state === 'TRYING') return r === 'in_review' ? 'Waiting for a person' : 'Being checked'
  if (state === 'NOT_POSSIBLE') return 'Not published by the provider'
  if (state === 'POSSIBLE_NEEDS_SOURCE') {
    if (field === 'scholarships') return 'No scholarship found yet'
    if (r === 'no_website') return 'No website on record'
    if (r === 'blocked') return 'Site blocked'
    if (r === 'no_reader') return 'No reader yet'
    return 'Page not found yet'
  }
  return null // ADMITTED, or EMPTY_NOT_STARTED (the country's scope is not on yet: counted on Summary, no rows)
}

// fixed: how many institutions per country the Institutions_Top tab shows (a display size, not a pipeline limit)
export const TOP_PER_COUNTRY = 100

const HEADER = ['country_code', 'institution', 'course_id', 'course_title', 'field', 'gap', 'first_seen', 'days_open', 'provider_id']
const daysBetween = (a, b) => Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / 86_400_000)

export function register(rows, date, prev = null, maxPartBytes = MAX_PART_BYTES) {
  rows = [...rows].sort((a, b) => String(a.country_code).localeCompare(String(b.country_code)) || String(a.provider_name).localeCompare(String(b.provider_name))
    || String(a.course_title).localeCompare(String(b.course_title)) || String(a.course_id).localeCompare(String(b.course_id)))
  const prevSeen = (prev && prev.first_seen) || {}
  const firstSeen = {}
  const gapRows = [] // [cc, line]
  const counts = {} // `${cc}|${field}|${gap}` -> n
  const notStarted = {} // `${cc}|${field}` -> n
  const inst = new Map() // `${provider_id}|${field}` -> institution × field row
  const present = new Map() // course_id -> row
  const coursesOf = new Map() // provider_id -> active courses
  const add = (o, k, n = 1) => { o[k] = (o[k] || 0) + n }
  for (const r of rows) {
    const cells = typeof r.cells === 'string' ? JSON.parse(r.cells) : r.cells
    const raw = typeof r.raw === 'string' ? JSON.parse(r.raw) : (r.raw || {})
    present.set(r.course_id, { r, cells }); coursesOf.set(r.provider_id, (coursesOf.get(r.provider_id) || 0) + 1)
    for (const f of FIELDS) {
      const s = stateOf(cells[f])
      if (s === 'EMPTY_NOT_STARTED') { add(notStarted, `${r.country_code}|${f}`); continue }
      // fee_basis is only its own gap when the fee itself is held
      if (f === 'fee_basis' && stateOf(cells.tuition_fee) !== 'ADMITTED') continue
      const g = gapOf(f, s, raw)
      if (!g) continue
      const key = `${r.course_id}|${f}`
      const seen = prevSeen[key] || date
      firstSeen[key] = seen
      add(counts, `${r.country_code}|${f}|${g}`)
      const ik = `${r.provider_id}|${f}`
      const it = inst.get(ik) || { cc: r.country_code, institution: r.provider_name, provider_id: r.provider_id, field: f, open: 0, oldest: seen,
        gaps: Object.fromEntries(GAP_NAMES.map((n) => [n, 0])), closed: 0 }
      it.open++; it.gaps[g]++; if (seen < it.oldest) it.oldest = seen
      inst.set(ik, it)
      gapRows.push([r.country_code, [r.country_code, r.provider_name, r.course_id, r.course_title, f, g, seen, daysBetween(seen, date), r.provider_id].map(csvCell).join(',')])
    }
  }
  // Closed since the last register: a gap seen last time and not open today
  const closedLines = [['country_code', 'institution', 'course_id', 'course_title', 'field', 'closed_because', 'first_seen', 'closed_on', 'provider_id'].join(',')]
  const closedInst = new Map()
  let closedCount = 0
  for (const [key, seen] of Object.entries(prevSeen).sort()) {
    if (firstSeen[key]) continue
    const [courseId, f] = key.split('|')
    const p = present.get(courseId)
    let why
    if (!p) why = 'Course no longer active'
    else {
      const s = stateOf(p.cells[f])
      if (s === 'ADMITTED') why = 'Admitted'
      else if (s === 'EMPTY_NOT_STARTED') why = 'Country scope not started'
      else if (f === 'fee_basis') why = 'Fee itself not held'
      else continue
    }
    closedCount++
    const r = p ? p.r : { country_code: '', provider_name: '', course_title: '', provider_id: '' }
    closedLines.push([r.country_code, r.provider_name, courseId, r.course_title, f, why, seen, date, r.provider_id].map(csvCell).join(','))
    if (p && why === 'Admitted') {
      const ik = `${r.provider_id}|${f}`
      const c = closedInst.get(ik) || { cc: r.country_code, institution: r.provider_name, provider_id: r.provider_id, field: f, n: 0 }
      c.n++; closedInst.set(ik, c)
      const it = inst.get(ik); if (it) it.closed++
    }
  }
  const files = parted(gapRows, date, maxPartBytes)
  const summary = summaryTab(counts, notStarted, (prev && prev.counts) || null, date, prev && prev.date, closedCount)
  // Institution × field, by country (one CSV per country; small enough for one upload)
  const instHeader = ['country_code', 'institution', 'field', 'open_gaps', 'worked_on_now', ...GAP_NAMES.map((n) => n.toLowerCase().replace(/[^a-z]+/g, '_')),
    'admitted_since_last_register', 'oldest_gap_since', 'provider_id']
  const byCc = {}
  for (const it of inst.values()) (byCc[it.cc] = byCc[it.cc] || []).push(it)
  const instFiles = Object.keys(byCc).sort().map((cc) => {
    const list = byCc[cc].sort((a, b) => String(a.institution).localeCompare(String(b.institution)) || FIELDS.indexOf(a.field) - FIELDS.indexOf(b.field))
    const content = [instHeader.join(','), ...list.map((it) => [cc, it.institution, it.field, it.open,
      it.gaps['Being checked'] + it.gaps['Waiting for a person'] > 0 ? 'Yes' : 'No', ...GAP_NAMES.map((n) => it.gaps[n]), it.closed, it.oldest, it.provider_id]
      .map(csvCell).join(','))].join('\n') + '\n'
    return { name: `Data_Gap_Institutions_${cc}_${date}.csv`, country: cc, rows: list.length, bytes: Buffer.byteLength(content), content }
  })
  // Institutions_Top: per country, the institutions with the most open gaps (the full list is in the institution CSVs)
  const perInst = new Map()
  for (const it of inst.values()) {
    const k = it.provider_id
    const t = perInst.get(k) || { cc: it.cc, institution: it.institution, provider_id: k, open: 0, gaps: Object.fromEntries(GAP_NAMES.map((n) => [n, 0])), closed: 0, fields: [] }
    t.open += it.open; t.closed += it.closed; for (const n of GAP_NAMES) t.gaps[n] += it.gaps[n]
    t.fields.push([it.field, it.open]); perInst.set(k, t)
  }
  for (const c of closedInst.values()) if (!perInst.has(c.provider_id)) perInst.set(c.provider_id, { cc: c.cc, institution: c.institution, provider_id: c.provider_id, open: 0, gaps: Object.fromEntries(GAP_NAMES.map((n) => [n, 0])), closed: c.n, fields: [] })
  const top = [
    [`Institutions with the most open gaps, per country (top ${TOP_PER_COUNTRY}), register of ${date} (AEDT). Every institution is in Data_Gap_Institutions_<country>_${date}.csv.`],
    ['Country', 'Institution', 'Active courses', 'Open gaps', 'Being checked', 'Waiting for a person', 'Page not found yet', 'No website on record', 'Not published by the provider', 'Admitted since last register', 'Fields with most gaps', 'provider_id'],
  ]
  const ccsTop = [...new Set([...perInst.values()].map((t) => t.cc))].sort()
  for (const cc of ccsTop) {
    const list = [...perInst.values()].filter((t) => t.cc === cc && t.open > 0).sort((a, b) => b.open - a.open || String(a.institution).localeCompare(String(b.institution))).slice(0, TOP_PER_COUNTRY)
    for (const t of list) top.push([cc, t.institution, coursesOf.get(t.provider_id) || 0, t.open, t.gaps['Being checked'], t.gaps['Waiting for a person'], t.gaps['Page not found yet'],
      t.gaps['No website on record'], t.gaps['Not published by the provider'], t.closed,
      t.fields.sort((a, b) => b[1] - a[1]).slice(0, 3).map(([f, n]) => `${f} (${n})`).join('; '), t.provider_id])
  }
  const closedByField = {}
  for (const c of closedInst.values()) add(closedByField, `${c.cc}|${c.field}`, c.n)
  const closedTab = [
    [`Fields admitted since the last register (${prev && prev.date ? prev.date : 'first register'} to ${date}). Every course is in Data_Gap_Closed_${date}.csv.`],
    ['Country', 'Field', 'Courses admitted'],
    ...Object.entries(closedByField).sort((a, b) => a[0].localeCompare(b[0]) || 0).map(([k, n]) => { const [cc, f] = k.split('|'); return [cc, f, n] })
      .sort((a, b) => a[0].localeCompare(b[0]) || FIELDS.indexOf(a[1]) - FIELDS.indexOf(b[1])),
  ]
  const tabs = { Summary: summary, Institutions_Top: top, Closed_Today: closedTab }
  const state = { date, first_seen: firstSeen, counts }
  const list = (fs_) => fs_.map(({ name, country, rows: n, bytes }) => ({ name, country, rows: n, bytes }))
  return { files, instFiles, closedCsv: closedLines.join('\n') + '\n', closedCount, tabs, state,
    totals: { open: gapRows.length, closed: closedCount, institutions_fields: inst.size, files: list(files), institution_files: list(instFiles) } }
}

export function parted(gapRows, date, maxPartBytes) {
  const header = HEADER.join(',') + '\n'
  const byCc = new Map()
  for (const [cc, l] of gapRows) { if (!byCc.has(cc)) byCc.set(cc, []); byCc.get(cc).push(l + '\n') }
  const out = []
  for (const [cc, ls] of [...byCc.entries()].sort((a, b) => a[0].localeCompare(b[0]))) {
    const parts = []; let cur = []; let size = Buffer.byteLength(header)
    for (const l of ls) {
      const b = Buffer.byteLength(l)
      if (Buffer.byteLength(header) + b > maxPartBytes) throw new Error(`one ${cc} gap row is over the part size`)
      if (size + b > maxPartBytes && cur.length) { parts.push(cur); cur = []; size = Buffer.byteLength(header) }
      cur.push(l); size += b
    }
    if (cur.length) parts.push(cur)
    parts.forEach((p, i) => {
      const content = header + p.join('')
      const name = parts.length === 1 ? `Data_Gap_Register_${cc}_${date}.csv` : `Data_Gap_Register_${cc}_Part${i + 1}_${date}.csv`
      out.push({ name, country: cc, rows: p.length, bytes: Buffer.byteLength(content), content })
    })
  }
  return out
}

export function summaryTab(counts, notStarted, prevCounts, date, prevDate, closedCount) {
  const ccs = [...new Set(Object.keys(counts).concat(Object.keys(notStarted)).map((k) => k.split('|')[0]))].sort()
  const open = Object.values(counts).reduce((a, b) => a + b, 0)
  const rows = [
    [`StudySearch data gap register, ${date} (AEDT). Open gaps: ${open.toLocaleString('en-AU')}. Gaps closed since the last register (${prevDate || 'first register'}): ${closedCount.toLocaleString('en-AU')}.`],
    ['Course-level rows: the files Data_Gap_Register_<country>_<date>.csv in this folder (one row per course and field still missing).'],
    [],
    ['Country', 'Field', 'Gap', 'Courses today', 'Courses at the last register', 'Change'],
  ]
  for (const cc of ccs) for (const f of FIELDS) for (const g of GAP_NAMES) {
    const k = `${cc}|${f}|${g}`
    const n = counts[k] || 0; const p = prevCounts ? prevCounts[k] || 0 : ''
    if (n || p) rows.push([cc, f, g, n, p, prevCounts ? `=D${rows.length + 1}-E${rows.length + 1}` : ''])
  }
  const ns = Object.entries(notStarted).sort()
  if (ns.length) {
    rows.push([], ['Not started for the country yet (no rows in the register)'], ['Country', 'Field', 'Courses'])
    for (const [k, n] of ns) { const [cc, f] = k.split('|'); rows.push([cc, f, n]) }
  }
  rows.push([], ['What each gap means'], ['Gap', 'Meaning', 'What happens next'], ...GAPS)
  return rows
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [outDir, date, prevPath, ...parts] = process.argv.slice(2)
  if (!outDir || !/^\d{4}-\d{2}-\d{2}$/.test(date || '') || !prevPath || !parts.length) {
    console.error('usage: data-gap-register.mjs <out-dir> <YYYY-MM-DD> <prev-state.json.gz | -> <part.json>...'); process.exit(2)
  }
  let prev = null
  if (prevPath !== '-' && fs.existsSync(prevPath) && fs.statSync(prevPath).size > 0) {
    prev = JSON.parse(zlib.gunzipSync(fs.readFileSync(prevPath)).toString('utf8'))
    if (prev.date === date) prev = null // a re-run on the same day compares with nothing rather than with itself
  }
  const rows = parts.flatMap((p) => JSON.parse(fs.readFileSync(p, 'utf8')))
  const { files, instFiles, closedCsv, tabs, state, totals } = register(rows, date, prev)
  fs.mkdirSync(outDir, { recursive: true })
  for (const f of [...files, ...instFiles]) fs.writeFileSync(path.join(outDir, f.name), f.content)
  fs.writeFileSync(path.join(outDir, `Data_Gap_Closed_${date}.csv`), closedCsv)
  fs.writeFileSync(path.join(outDir, 'Data_Gap_Register_Sheet.json'), JSON.stringify({ date, tabs, totals }, null, 1))
  fs.writeFileSync(path.join(outDir, 'Data_Gap_State.json.gz'), zlib.gzipSync(JSON.stringify(state)))
  console.log(JSON.stringify({ date, previous: prev ? prev.date : null, ...totals }))
}
