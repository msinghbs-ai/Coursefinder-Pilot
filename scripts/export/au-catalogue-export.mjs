#!/usr/bin/env node
// AU catalogue export (Platform Admin 2 Nov 2026 11:10 §1, §3, §4; snapshot method and production impact 11:18).
// Exports every Australian course held in the catalogue and its child datasets as CSV, read-only, then builds the reconciliation,
// field-state and data dictionary sheets and a manifest. The workbook (.xlsx) is built afterwards by au-catalogue-workbook.py.
//
// Used by .github/workflows/au-catalogue-export.yml. Connection: the standard libpq variables (PGHOST, PGPORT, PGUSER, PGDATABASE,
// PGPASSWORD, PGSSLMODE), read by psql. Nothing is written to the database: every statement is a select (the queries are in
// au-catalogue-queries.mjs and the spec s219 checks them), inside transactions opened READ ONLY.
//
// Snapshot method (11:18 direction):
//   1. Measure: outside any data transaction, during the measure minutes (:x6-:x8 by default), each dataset's row count is read with a
//      small count and one calibration page is timed. The estimate (pages, queries, seconds) goes in the manifest before any data is read.
//   2. single (default when the estimate is within SINGLE_BUDGET_S): ONE transaction, BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY,
//      started at the beginning of the longest quiet gap and run continuously through every dataset (never idle, no waits inside). If it
//      runs past SINGLE_ABORT_S it is rolled back and the export falls back to per_dataset.
//   3. per_dataset: one short REPEATABLE READ READ ONLY transaction per dataset or page group, each started in a quiet minute and
//      committed before TXN_BUDGET_S or before the next busy minute. Waits happen only between transactions. Each transaction's now()
//      and txid_current_snapshot() go in the manifest, and the cross-dataset checks report drift (child rows whose course is missing,
//      courses changed after the first snapshot) instead of hiding it.
// Busy minutes: the start minutes of the admission jobs read from cron.job (BUSY_JOBS), plus EXTRA_BUSY, plus the daily peak (PEAK, in
// TZ). A query is started only when it can finish (statement_timeout) before the next busy minute.
// Logs carry counts, timings and md5s only: no row data, no connection string, no password.
import { spawn } from 'node:child_process'
import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import { datasets, boundarySql, pageSql, countSql, checkSqls, CATALOGUE_SQL } from './au-catalogue-queries.mjs'
import { parseCsv } from './csv.mjs'
import { buildDerived } from './au-catalogue-derived.mjs'

const env = process.env
const num = (k, d) => { const v = env[k]; if (v === undefined || v === '') return d; const n = Number(v); if (!Number.isFinite(n)) throw new Error(`${k} must be a number`); return n }
export const CONFIG = {
  out: env.OUT_DIR || 'au-export',
  country: env.COUNTRY || 'AU',
  batch: num('BATCH', 2000),
  statementTimeoutS: num('STATEMENT_TIMEOUT_S', 30),
  mode: env.MODE || 'auto',
  singleBudgetS: num('SINGLE_BUDGET_S', 180),
  singleAbortS: num('SINGLE_ABORT_S', 300),
  txnBudgetS: num('TXN_BUDGET_S', 45),
  busyJobs: (env.BUSY_JOBS || 'coverage-admit,coverage-admit-intakes,adapter-overwrite,exit-awards-apply').split(',').map((s) => s.trim()).filter(Boolean),
  extraBusy: env.EXTRA_BUSY ?? '0-5,35-42,47-48',
  measureMinutes: env.MEASURE_MINUTES ?? '6-8',
  peak: env.PEAK ?? '06:50-07:15',
  tz: env.TZ_PACING || 'Australia/Melbourne',
  maxRuntimeMin: num('MAX_RUNTIME_MIN', 75),
  failureRetries: num('FAILURE_RETRIES', 2),
  gitSha: env.GIT_SHA || '',
  pacing: env.PACING !== 'off', // off only for the local fixture run (scratch PostgreSQL, no cron)
  forceFallback: env.FORCE_SINGLE_ABORT === '1', // fixture run: proves the fall-back path
}
if (!['auto', 'single', 'per_dataset'].includes(CONFIG.mode)) throw new Error(`MODE must be auto, single or per_dataset`)
if (!(CONFIG.batch >= 100 && CONFIG.batch <= 5000)) throw new Error('BATCH must be 100-5000')
if (!(CONFIG.statementTimeoutS >= 5 && CONFIG.statementTimeoutS <= 60)) throw new Error('STATEMENT_TIMEOUT_S must be 5-60')

const started = Date.now()
const log = (...a) => console.log(`[${((Date.now() - started) / 1000).toFixed(1)}s]`, ...a)
const md5 = (s) => crypto.createHash('md5').update(s).digest('hex')
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
// an error message without quoted values (a value could be data)
export const redact = (s) => String(s).split('\n')[0].replace(/"[^"]*"|'[^']*'/g, '…').slice(0, 300)

// ---------------------------------------------------------------------------------------------------------------------- pacing
export function cronMinutes(expr) {
  const f = String(expr).trim().split(/\s+/)[0]
  const out = new Set()
  for (const part of f.split(',')) {
    const [range, stepS] = part.split('/')
    const step = stepS ? Number(stepS) : 1
    let lo, hi
    if (range === '*') { lo = 0; hi = 59 } else if (range.includes('-')) { [lo, hi] = range.split('-').map(Number) } else { lo = Number(range); hi = stepS ? 59 : lo }
    if (![lo, hi, step].every(Number.isInteger)) throw new Error(`cannot read cron minute field ${f}`)
    for (let m = lo; m <= hi; m += step) out.add(m)
  }
  return out
}
export function rangeMinutes(spec) {
  const out = new Set()
  for (const part of String(spec || '').split(',').map((s) => s.trim()).filter(Boolean)) {
    const [a, b] = part.split('-').map(Number)
    for (let m = a; m <= (Number.isInteger(b) ? b : a); m++) out.add(m)
  }
  return out
}
// minutes of each 10 (e.g. "6-8") -> every hour minute
export function tensMinutes(spec) {
  const d = rangeMinutes(spec), out = new Set()
  for (let t = 0; t < 60; t += 10) for (const m of d) out.add(t + m)
  return out
}
export function quietGaps(busy) {
  // cyclic runs of quiet minutes: [{start, length}]
  const gaps = []
  if (busy.size >= 60) return gaps
  const first = [...Array(60).keys()].find((m) => busy.has(m) && !busy.has((m + 1) % 60))
  if (first === undefined) return [{ start: 0, length: 60 }]
  let m = (first + 1) % 60, cur = null
  for (let i = 0; i < 60; i++, m = (m + 1) % 60) {
    if (!busy.has(m)) { if (!cur) gaps.push((cur = { start: m, length: 0 })); cur.length++ } else cur = null
  }
  return gaps
}
function localParts(date, tz) {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-AU', { timeZone: tz, hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' })
    .formatToParts(date).map((x) => [x.type, x.value]))
  return { h: Number(p.hour), m: Number(p.minute), s: Number(p.second) }
}
function inPeak(date, tz, peak) {
  if (!peak) return false
  const [a, b] = peak.split('-').map((x) => x.split(':').map(Number))
  const { h, m } = localParts(date, tz), t = h * 60 + m
  return t >= a[0] * 60 + a[1] && t <= b[0] * 60 + b[1]
}
// is the whole interval [now, now + seconds] outside busy minutes and the peak?
export function intervalQuiet(date, seconds, busy, tz, peak) {
  for (let t = 0; t <= seconds; t += 15) {
    const d = new Date(date.getTime() + t * 1000)
    if (busy.has(localParts(d, tz).m) || inPeak(d, tz, peak)) return false
  }
  const end = new Date(date.getTime() + seconds * 1000)
  return !busy.has(localParts(end, tz).m) && !inPeak(end, tz, peak)
}
function secondsLeftQuiet(date, busy, tz, peak, cap = 3600) {
  let t = 0
  while (t < cap && intervalQuiet(date, t + 15, busy, tz, peak)) t += 15
  return t
}

// ---------------------------------------------------------------------------------------------------------------------- psql
export class Psql {
  constructor() {
    this.p = spawn('psql', ['-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=terse', '-P', 'pager=off'],
      { stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, PGAPPNAME: process.env.PGAPPNAME || 'au-catalogue-export', PGCONNECT_TIMEOUT: '20' } })
    this.buf = ''; this.lines = []; this.n = 0; this.waiter = null; this.err = ''; this.queries = 0
    this.p.stdout.setEncoding('utf8')
    this.p.stdout.on('data', (d) => { this.buf += d; let i; while ((i = this.buf.indexOf('\n')) >= 0) { this.lines.push(this.buf.slice(0, i)); this.buf = this.buf.slice(i + 1) } this.poke() })
    this.p.stderr.setEncoding('utf8')
    this.p.stderr.on('data', (d) => { this.err += d })
    this.closed = new Promise((r) => this.p.on('close', (code) => { this.code = code; this.dead = true; this.poke(); r(code) }))
    this.p.stdin.on('error', () => {})
  }
  poke() { if (this.waiter) this.waiter() }
  async exec(text) {
    if (this.dead) throw new Error(`psql stopped: ${redact(this.err)}`)
    const tag = `@@AUX${++this.n}@@`
    this.queries++
    this.p.stdin.write(`${text}\n\\echo ${tag}\n`)
    const out = []
    for (;;) {
      while (this.lines.length) { const l = this.lines.shift(); if (l === tag) return out; out.push(l) }
      if (this.dead) throw new Error(`psql stopped (exit ${this.code}): ${redact(this.err.trim().split('\n').pop() || '')}`)
      await new Promise((r) => { this.waiter = r })
      this.waiter = null
    }
  }
  async json(sql) { const out = (await this.exec(`${sql};`)).filter((l) => l.trim() !== ''); return out.length ? JSON.parse(out[out.length - 1]) : null }
  async copy(sql, file) {
    if (/'/.test(file)) throw new Error('file path must not contain a quote')
    await this.exec(`copy (${sql}) to stdout with (format csv, header true) \\g '${file}'`)
  }
  async close() { try { this.p.stdin.end('\\q\n') } catch {} await this.closed }
}

// ---------------------------------------------------------------------------------------------------------------------- export
const TXN_BEGIN = 'begin isolation level repeatable read read only'
async function beginSnapshot(pg, stmtTimeoutS) {
  await pg.exec(`${TXN_BEGIN};`)
  await pg.exec(`set local statement_timeout = '${Number(stmtTimeoutS)}s'; set local lock_timeout = '5s'; set local idle_in_transaction_session_timeout = '60s'; set local timezone = 'UTC'; set local datestyle = 'ISO, YMD';`)
  const snap = await pg.json(checkSqls(CONFIG.country).snapshot)
  if (snap.read_only !== 'on' || snap.isolation !== 'repeatable read') throw new Error(`transaction is not REPEATABLE READ READ ONLY (${snap.isolation}, read_only ${snap.read_only})`)
  return snap
}

async function main() {
  const C = CONFIG
  const out = path.resolve(C.out), csvDir = path.join(out, 'csv'), partDir = path.join(out, 'parts')
  fs.rmSync(out, { recursive: true, force: true }); fs.mkdirSync(csvDir, { recursive: true }); fs.mkdirSync(partDir, { recursive: true })
  const manifest = {
    export: 'au-catalogue-export', authority: 'Platform Admin 2 Nov 2026 11:10 (§1, §3, §4) and 11:18 (snapshot method, production impact)',
    country: C.country, source_commit: C.gitSha || null, started_at: new Date().toISOString(),
    config: { batch: C.batch, statement_timeout_s: C.statementTimeoutS, mode_requested: C.mode, single_budget_s: C.singleBudgetS, single_abort_s: C.singleAbortS,
      txn_budget_s: C.txnBudgetS, busy_jobs: C.busyJobs, extra_busy_minutes: C.extraBusy, measure_minutes_of_each_10: C.measureMinutes, daily_peak: C.peak, pacing_time_zone: C.tz, pacing: C.pacing },
    schedule: null, measure: null, production_impact: null, snapshots: [], datasets: [], checks: [], omitted: [], limitations: [], drift: null,
  }
  const pg = new Psql()
  const deadline = started + C.maxRuntimeMin * 60_000
  let busy = new Set(), measureOk = new Set([...Array(60).keys()])
  const wait = async (seconds, why, minutes = null) => {
    if (!C.pacing) return
    let waited = 0
    for (;;) {
      const now = new Date()
      const okMinute = !minutes || minutes.has(localParts(now, C.tz).m)
      if (okMinute && intervalQuiet(now, seconds, busy, C.tz, C.peak)) break
      if (Date.now() > deadline) throw new Error(`stopped: no quiet window for ${why} before MAX_RUNTIME_MIN`)
      await sleep(5000); waited += 5
    }
    if (waited) log(`waited ${waited}s for a quiet window (${why})`)
  }
  try {
    // --- 1 schedules and back-off (catalogue reads; outside any data transaction)
    await wait(10, 'schedule read', C.pacing ? tensMinutes(C.measureMinutes) : null)
    let cron = []
    cron = (await pg.json(CATALOGUE_SQL.cron(C.busyJobs))) || []
    for (const j of cron) for (const m of cronMinutes(j.schedule)) busy.add(m)
    for (const m of rangeMinutes(C.extraBusy)) busy.add(m)
    const missing = C.busyJobs.filter((j) => !cron.some((x) => x.job === j))
    manifest.schedule = { jobs: cron, jobs_not_found: missing, busy_minutes: [...busy].sort((a, b) => a - b), quiet_gaps: quietGaps(busy) }
    log(`admission schedule read: ${cron.length} jobs, ${busy.size} busy minutes per hour, longest quiet gap ${Math.max(0, ...quietGaps(busy).map((g) => g.length))} min`)
    if (C.pacing && missing.length) log(`note: jobs not in cron.job: ${missing.join(', ')}`)
    for (let attempt = 0; C.pacing; attempt++) {
      const f = await pg.json(CATALOGUE_SQL.recentFailures)
      if (!f.n) break
      if (attempt >= C.failureRetries) throw new Error(`stopped: ${f.n} job failures or time-outs in the last 15 minutes (load policy rule 5)`)
      log(`${f.n} recent job failures or time-outs: backing off 15 minutes (load policy rule 5)`); await sleep(15 * 60_000)
    }
    const docColumns = await pg.json(CATALOGUE_SQL.docColumns)
    const dictionary = { columns: await pg.json(CATALOGUE_SQL.columns), tables: await pg.json(CATALOGUE_SQL.tables) }
    const D = datasets(C.country, docColumns)

    // --- 2 measure: counts and one calibration page (each its own short read-only transaction, in the measure minutes)
    const measure = { counts: {}, count_ms: {}, calibration: null }
    const mm = C.pacing ? tensMinutes(C.measureMinutes) : null
    for (const d of D) {
      await wait(C.statementTimeoutS, `count ${d.name}`, mm)
      const t0 = Date.now()
      await pg.exec(`${TXN_BEGIN}; set local statement_timeout = '${C.statementTimeoutS}s';`)
      measure.counts[d.name] = (await pg.json(countSql(d))).n
      await pg.exec('commit;')
      measure.count_ms[d.name] = Date.now() - t0
    }
    {
      const cal = D.find((d) => d.name === 'course_fees')
      await wait(C.statementTimeoutS * 2, 'calibration page', mm)
      const t0 = Date.now()
      await pg.exec(`${TXN_BEGIN}; set local statement_timeout = '${C.statementTimeoutS}s';`)
      const b = await pg.json(boundarySql(cal, null, C.batch))
      const t1 = Date.now()
      const f = path.join(partDir, 'calibration.csv')
      if (b.n) await pg.copy(pageSql(cal, null, b.last), f)
      await pg.exec('commit;')
      const t2 = Date.now()
      const bytes = b.n ? fs.statSync(f).size : 0
      fs.rmSync(f, { force: true })
      measure.calibration = { dataset: cal.name, rows: b.n, boundary_ms: t1 - t0, page_ms: t2 - t1, bytes }
    }
    const perRowMs = measure.calibration.rows ? measure.calibration.page_ms / measure.calibration.rows : 0.5
    const boundaryMs = Math.max(20, measure.calibration.boundary_ms)
    const estimate = D.map((d) => {
      const n = measure.counts[d.name], pages = d.key ? Math.max(1, Math.ceil(n / C.batch)) : 1
      return { dataset: d.name, rows: n, pages, queries: pages * (d.key ? 2 : 1) + 1, seconds: (pages * boundaryMs + n * perRowMs + measure.count_ms[d.name]) / 1000 }
    })
    const total = estimate.reduce((a, e) => ({ rows: a.rows + e.rows, pages: a.pages + e.pages, queries: a.queries + e.queries, seconds: a.seconds + e.seconds }), { rows: 0, pages: 0, queries: 0, seconds: 0 })
    manifest.measure = measure
    let mode = C.mode === 'auto' ? (total.seconds <= C.singleBudgetS ? 'single' : 'per_dataset') : C.mode
    manifest.production_impact = {
      statement_timeout_s: C.statementTimeoutS, lock_timeout_s: 5, batch_rows: C.batch, pagination: 'keyset on each dataset\'s unique key (index order), limit = batch',
      estimate: { ...total, seconds: Math.round(total.seconds), per_dataset: estimate.map((e) => ({ ...e, seconds: Math.round(e.seconds * 10) / 10 })) },
      mode_chosen: mode, reason: C.mode !== 'auto' ? 'requested' : `estimate ${Math.round(total.seconds)} s ${total.seconds <= C.singleBudgetS ? '<=' : '>'} single budget ${C.singleBudgetS} s`,
      locks: 'none taken: REPEATABLE READ READ ONLY selects (MVCC); the cost is the held xmin for the length of each snapshot',
    }
    log(`measured: ${total.rows} rows, ${total.pages} pages, about ${total.queries} queries, estimated ${Math.round(total.seconds)} s; mode ${mode}`)
    fs.writeFileSync(path.join(out, 'manifest.json'), JSON.stringify(manifest, null, 2))

    // --- 3 export
    const state = Object.fromEntries(D.map((d) => [d.name, { last: null, done: false, parts: 0, rows: 0, snapshots: [], count_in_snapshot: null }]))
    const pageOnce = async (d) => {
      const st = state[d.name]
      if (!d.key) {
        const f = path.join(partDir, `${d.name}.0001.csv`)
        await pg.copy(pageSql(d), f); st.parts = 1; st.done = true; return
      }
      const b = await pg.json(boundarySql(d, st.last, C.batch))
      if (!b.n) {
        // an empty dataset still gets its header (no rows)
        if (!st.parts) await pg.copy(`select ${d.select} from ${d.from} where false`, path.join(partDir, `${d.name}.${String(++st.parts).padStart(4, '0')}.csv`))
        st.done = true; return
      }
      const f = path.join(partDir, `${d.name}.${String(++st.parts).padStart(4, '0')}.csv`)
      await pg.copy(pageSql(d, st.last, b.last), f)
      st.last = b.last; st.rows += b.n
      if (b.n < C.batch) st.done = true
    }
    const resetOutputs = () => { fs.rmSync(partDir, { recursive: true, force: true }); fs.mkdirSync(partDir); for (const d of D) Object.assign(state[d.name], { last: null, done: false, parts: 0, rows: 0, snapshots: [], count_in_snapshot: null }); manifest.snapshots = [] }
    const checks = checkSqls(C.country)
    let finalChecks = null

    if (mode === 'single') {
      const gaps = quietGaps(busy).sort((a, b) => b.length - a.length)
      if (C.pacing && gaps.length) {
        const g = gaps[0]
        // the start of the longest quiet gap
        while (localParts(new Date(), C.tz).m !== g.start || inPeak(new Date(), C.tz, C.peak)) {
          if (Date.now() > deadline) throw new Error('stopped: the longest quiet gap did not come before MAX_RUNTIME_MIN'); await sleep(2000)
        }
        log(`single snapshot starts at the beginning of the longest quiet gap (minute ${g.start}, ${g.length} min)`)
      }
      const t0 = Date.now()
      const snap = await beginSnapshot(pg, C.statementTimeoutS)
      manifest.snapshots.push({ id: 1, scope: 'all datasets', ...snap })
      let aborted = false
      try {
        for (const d of D) {
          state[d.name].count_in_snapshot = (await pg.json(countSql(d))).n
          state[d.name].snapshots.push(1)
          while (!state[d.name].done) {
            if (C.forceFallback || (Date.now() - t0) / 1000 > C.singleAbortS) { aborted = true; break }
            await pageOnce(d)
          }
          if (aborted) break
          log(`${d.name}: ${state[d.name].rows || '(reference)'} rows in ${state[d.name].parts} pages`)
        }
        if (!aborted) finalChecks = { courses: await pg.json(checks.courses), documents: await pg.json(checks.documents), documentsByCode: await pg.json(checks.documentsByCode), regionFallback: await pg.json(checks.regionFallback), snapshot: 1 }
      } finally {
        await pg.exec(aborted ? 'rollback;' : 'commit;').catch(() => {})
      }
      manifest.snapshots[0].seconds = Math.round((Date.now() - t0) / 100) / 10
      if (aborted) {
        log(`single snapshot passed ${C.singleAbortS} s: rolled back, falling back to per_dataset`)
        manifest.production_impact.fallback = `single snapshot rolled back after ${manifest.snapshots[0].seconds} s (limit ${C.singleAbortS} s); per_dataset used`
        resetOutputs(); mode = 'per_dataset'
      }
    }
    if (mode === 'per_dataset') {
      let sid = 0
      for (const d of D) {
        while (!state[d.name].done) {
          await wait(Math.min(C.txnBudgetS, 60), `dataset ${d.name}`)
          const t0 = Date.now()
          const room = C.pacing ? secondsLeftQuiet(new Date(), busy, C.tz, C.peak) : C.txnBudgetS
          const budget = Math.min(C.txnBudgetS, Math.max(5, room - C.statementTimeoutS))
          const snap = await beginSnapshot(pg, C.statementTimeoutS)
          manifest.snapshots.push({ id: ++sid, scope: d.name, ...snap })
          state[d.name].snapshots.push(sid)
          try {
            if (state[d.name].count_in_snapshot === null) state[d.name].count_in_snapshot = (await pg.json(countSql(d))).n
            do { await pageOnce(d) } while (!state[d.name].done && (Date.now() - t0) / 1000 < budget)
          } finally { await pg.exec('commit;').catch(() => {}) }
          manifest.snapshots[manifest.snapshots.length - 1].seconds = Math.round((Date.now() - t0) / 100) / 10
        }
        log(`${d.name}: ${state[d.name].rows || '(reference)'} rows in ${state[d.name].parts} pages, ${state[d.name].snapshots.length} snapshot(s)`)
      }
      await wait(C.statementTimeoutS, 'final checks')
      const snap = await beginSnapshot(pg, C.statementTimeoutS)
      manifest.snapshots.push({ id: ++sid, scope: 'final checks', ...snap })
      try {
        const first = manifest.snapshots[0].now
        finalChecks = { courses: await pg.json(checks.courses), documents: await pg.json(checks.documents), documentsByCode: await pg.json(checks.documentsByCode),
          regionFallback: await pg.json(checks.regionFallback), changedSince: await pg.json(CATALOGUE_SQL.changedSince(C.country, first)), snapshot: sid }
      } finally { await pg.exec('commit;').catch(() => {}) }
    }
    manifest.production_impact.mode_used = mode
    manifest.production_impact.queries_run = pg.queries
    manifest.production_impact.export_seconds = Math.round((Date.now() - started) / 1000)
    await pg.close()

    // --- 4 files, counts, distinct ids, md5s
    const data = {}
    for (const d of D) {
      const parts = fs.readdirSync(partDir).filter((f) => f.startsWith(`${d.name}.`) && f.endsWith('.csv')).sort()
      const file = path.join(csvDir, `${d.name}.csv`)
      let header = null, body = ''
      for (const p of parts) {
        const txt = fs.readFileSync(path.join(partDir, p), 'utf8')
        const nl = txt.indexOf('\n')
        const h = nl < 0 ? txt : txt.slice(0, nl)
        if (header === null) header = h
        else if (h !== header) throw new Error(`${d.name}: page header differs`)
        body += nl < 0 ? '' : txt.slice(nl + 1)
      }
      const content = (header ?? '') + '\n' + body
      fs.writeFileSync(file, content)
      const rows = parseCsv(content)
      data[d.name] = rows
      const idCols = d.idColumn ? d.idColumn.split('|') : null
      const distinct = idCols ? new Set(rows.map((r) => idCols.map((c) => r[c]).join('|'))).size : null
      const st = state[d.name]
      manifest.datasets.push({
        name: d.name, sheet: d.sheet, file: `csv/${d.name}.csv`, rows: rows.length, distinct_ids: distinct, id_column: d.idColumn || null,
        count_measured: measure.counts[d.name], count_in_snapshot: st.count_in_snapshot, pages: st.parts, snapshots: st.snapshots,
        md5: md5(content), bytes: Buffer.byteLength(content),
        query_md5: { page: md5(pageSql(d, d.key ? d.key.map(() => '$last') : null, d.key ? d.key.map(() => '$upto') : null)), boundary: d.key ? md5(boundarySql(d, d.key.map(() => '$last'), C.batch)) : null, count: md5(countSql(d)) },
        query_template: pageSql(d, d.key ? d.key.map(() => '$last') : null, d.key ? d.key.map(() => '$upto') : null),
        consumer_rule: d.visibleRule || null, reference: Boolean(d.reference),
      })
      log(`${d.name}: ${rows.length} rows${distinct !== null ? `, ${distinct} distinct ids` : ''}, md5 ${md5(content)}`)
    }
    fs.rmSync(partDir, { recursive: true, force: true })

    // --- 5 checks
    const ds = Object.fromEntries(manifest.datasets.map((x) => [x.name, x]))
    const check = (name, ok, detail) => { manifest.checks.push({ check: name, pass: Boolean(ok), detail }); log(`${ok ? 'PASS' : 'FAIL'} ${name}: ${JSON.stringify(detail)}`) }
    for (const x of manifest.datasets) {
      check(`${x.name}: rows equal the count in its snapshot`, x.rows === x.count_in_snapshot, { rows: x.rows, count_in_snapshot: x.count_in_snapshot })
      if (x.distinct_ids !== null) check(`${x.name}: ids are unique`, x.distinct_ids === x.rows, { rows: x.rows, distinct_ids: x.distinct_ids })
    }
    const courseIds = new Set(data.courses.map((r) => r.id))
    check('AU courses equal count(*) in the snapshot', data.courses.length === finalChecks.courses.n, { exported: data.courses.length, snapshot_count: finalChecks.courses.n, snapshot: finalChecks.snapshot })
    const flagged = data.courses.filter((r) => r.x_in_website_api_v2 === 't').length
    check('in_website_api_v2 subset equals the search.course_documents rows of AU courses', flagged === finalChecks.documents.n && data.search_course_documents.length === finalChecks.documents.n,
      { flagged, projection_rows_exported: data.search_course_documents.length, course_documents_au_courses: finalChecks.documents.n })
    check('in_website_api_v2 subset equals search.course_documents with country_code AU', flagged === finalChecks.documentsByCode.n, { flagged, course_documents_country_code: finalChecks.documentsByCode.n })
    const orphans = {}
    for (const d of D) {
      const col = d.courseColumn; if (!col || d.name === 'courses') continue
      const bad = data[d.name].filter((r) => !courseIds.has(r[col]))
      orphans[d.name] = bad.length
      check(`${d.name}: every ${col} is in courses`, bad.length === 0, { rows: data[d.name].length, missing_course: bad.length })
    }
    const schIds = new Set(data.scholarship_master.map((r) => r.id))
    for (const d of D.filter((x) => x.scholarshipColumn)) {
      const bad = data[d.name].filter((r) => !schIds.has(r[d.scholarshipColumn])).length
      check(`${d.name}: every scholarship_id is in scholarship_master`, bad === 0, { rows: data[d.name].length, missing_scholarship: bad })
    }
    const missSch = data.course_scholarships.filter((r) => !schIds.has(r.scholarship_id)).length
    check('course_scholarships: every scholarship_id is in scholarship_master', missSch === 0, { missing_scholarship: missSch })
    const provIds = new Set(data.providers.map((r) => r.id))
    for (const d of D.filter((x) => x.providerColumn)) {
      const bad = data[d.name].filter((r) => !provIds.has(r[d.providerColumn])).length
      check(`${d.name}: every provider_id is in providers`, bad === 0, { rows: data[d.name].length, missing_provider: bad })
    }
    const badProv = data.courses.filter((r) => !provIds.has(r.provider_id)).length
    check('courses: every provider_id is in providers', badProv === 0, { missing_provider: badProv })
    manifest.drift = mode === 'single' ? { method: 'single snapshot: no drift between datasets is possible', courses_changed_after_first_snapshot: 0 }
      : { method: 'per_dataset snapshots', first_snapshot_at: manifest.snapshots[0]?.now, courses_changed_after_first_snapshot: finalChecks.changedSince.n,
          course_ids_changed: finalChecks.changedSince.ids, child_rows_whose_course_is_missing: orphans }

    // --- 6 derived sheets (from the exported files only: no further database reads)
    const derived = buildDerived(data, { country: C.country, snapshotDate: String(manifest.snapshots[0].now).slice(0, 10), regionFallback: finalChecks.regionFallback?.countries || [], dictionary, manifestDatasets: manifest.datasets })
    for (const [name, { header, rows, sheet, idColumns, note }] of Object.entries(derived)) {
      const content = toCsv(header, rows)
      fs.writeFileSync(path.join(csvDir, `${name}.csv`), content)
      const distinct = idColumns ? new Set(rows.map((r) => idColumns.map((c) => r[header.indexOf(c)]).join('|'))).size : null
      manifest.datasets.push({ name, sheet, file: `csv/${name}.csv`, rows: rows.length, distinct_ids: distinct, id_column: idColumns ? idColumns.join('|') : null, derived: true, note, md5: md5(content), bytes: Buffer.byteLength(content) })
      log(`${name}: ${rows.length} rows (derived), md5 ${md5(content)}`)
      if (idColumns) check(`${name}: one row per ${idColumns.join(' and ')}`, distinct === rows.length, { rows: rows.length, distinct })
    }
    if (data.provider_rankings.length === 0) manifest.limitations.push('provider_rankings: no ranking row is held for any AU provider in this snapshot (the dataset is exported, with its columns, and is empty).')
    manifest.limitations.push(
      'layer4_course_field_resolutions is not exported: it holds no confirmed not-applicable decision usable as a field state; "not_applicable" is therefore never assigned (null is never read as not applicable).',
      'field_state_reconciliation "processing" means rows stored but not admitted (status proposed) with no pending Layer 4 item; course page reads in flight are not inferred.',
      'website_api_v2_field_reconciliation official_url: with several active candidate links and none primary, the projection choice calls security.course_page_check_v1 (E16-2), which this export does not re-run; such rows are marked chosen_among_candidates.',
    )
    manifest.finished_at = new Date().toISOString()
    manifest.all_checks_pass = manifest.checks.every((c) => c.pass)
    fs.writeFileSync(path.join(out, 'manifest.json'), JSON.stringify(manifest, null, 2))
    log(`manifest written: ${manifest.checks.filter((c) => c.pass).length}/${manifest.checks.length} checks pass`)
    if (!manifest.all_checks_pass) process.exitCode = 2
  } catch (e) {
    await pg.exec('rollback;').catch(() => {})
    await pg.close().catch(() => {})
    console.error(`::error::${redact(e.message)}`); if (process.env.EXPORT_DEBUG) console.error(e.stack)
    manifest.error = redact(e.message)
    fs.writeFileSync(path.join(out, 'manifest.json'), JSON.stringify(manifest, null, 2))
    process.exitCode = 1
  }
}

export function toCsv(header, rows) {
  const q = (v) => (v === null || v === undefined ? '' : /[",\n\r]/.test(String(v)) || String(v) === '' ? `"${String(v).replace(/"/g, '""')}"` : String(v))
  return [header.map(q).join(','), ...rows.map((r) => r.map(q).join(','))].join('\n') + '\n'
}

if (import.meta.url === `file://${process.argv[1]}`) main()
