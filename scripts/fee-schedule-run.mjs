// CF-247 s1327 (S1-Build; Platform Admin 28 Nov 2026 06:54 scoped exception): runs one registered fee schedule through the existing
// fee-schedule-etl worker (dry_run or apply) with a one-time Pilot nonce, optionally limited to course codes checked one by one; prints the
// result. The worker reads the provider's official page itself and writes only through svc_fee_schedule_apply.
import { need, op, summary } from './boost-live-lib.mjs'

need()
const [schedule, mode, codesIn] = process.argv.slice(2)
if (!/^[a-z0-9_]{3,40}$/.test(String(schedule || '')) || !['dry_run', 'apply'].includes(mode)) { console.error('::error::schedule and mode (dry_run or apply) are required'); process.exit(1) }
const codes = String(codesIn || '').split(/[\s,]+/).map((x) => x.trim().toUpperCase()).filter((x) => /^\d{6}[0-9A-Z]$/.test(x))
const [{ n }] = await op(`select public.svc_pilot_issue_nonce('fee-schedule-etl') as n`)
const r = await fetch(`https://${process.env.REF}.supabase.co/functions/v1/fee-schedule-etl`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-cf-run-nonce': String(n) },
  body: JSON.stringify({ mode, schedule, ...(codes.length ? { codes } : {}) }), signal: AbortSignal.timeout(140000) })  // fixed: API time-out of one schedule run
const text = await r.text(); let res; try { res = JSON.parse(text) } catch { res = { error: text.slice(0, 400) } }
const brief = { http: r.status, schedule, mode, codes: codes.length, sha256: res.sha256, parsedRows: res.parsedRows, rejectedRows: res.rejectedRows, parked: res.parked,
  actions: res.preview?.actions ?? res.preview, applied: res.applied ? { ...res.applied, skipped_detail: undefined } : undefined, skipped_detail: res.applied?.skipped_detail, error: res.error, worker: res.workerVersion }
await summary(['Fee schedule ' + mode + ': ' + schedule, '', '```json', JSON.stringify(brief, null, 2).slice(0, 8000), '```'].join('\n'))
console.log(JSON.stringify(brief, null, 2).slice(0, 8000))
if (!r.ok || res.ok !== true) process.exit(1)
