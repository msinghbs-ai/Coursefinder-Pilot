// CF-247 s1327 (S1-Build; Platform Admin 28 Nov 2026 06:54 scoped exception): runs one registered fee schedule through the existing
// fee-schedule-etl worker (dry_run or apply) with a one-time Pilot nonce, optionally limited to course codes checked one by one; prints the
// result. The worker reads the provider's official page itself and writes only through svc_fee_schedule_apply.
import { need, op, lit, summary } from './boost-live-lib.mjs'

need()
const [schedule, mode, codesIn] = process.argv.slice(2)
if (!/^[a-z0-9_]{3,40}$/.test(String(schedule || '')) || !['dry_run', 'apply'].includes(mode)) { console.error('::error::schedule and mode (dry_run or apply) are required'); process.exit(1) }
const codes = String(codesIn || '').split(/[\s,]+/).map((x) => x.trim().toUpperCase()).filter((x) => /^\d{6}[0-9A-Z]$/.test(x))
const callWorker = async (pid) => {
  const [{ n }] = await op(`select public.svc_pilot_issue_nonce('fee-schedule-etl') as n`)
  const r = await fetch(`https://${process.env.REF}.supabase.co/functions/v1/fee-schedule-etl`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-cf-run-nonce': String(n) },
    body: JSON.stringify({ mode, schedule, ...(pid ? { provider_id: pid } : {}), ...(codes.length ? { codes } : {}) }), signal: AbortSignal.timeout(140000) })  // fixed: API time-out of one schedule run
  const text = await r.text(); let res; try { res = JSON.parse(text) } catch { res = { error: text.slice(0, 400) } }
  return { r, res }
}
let { r, res } = await callWorker(null)
// s1334 (SS-Programme-Control 28 Nov 2026 07:44 and 09:03): the site refused the direct read. The provider is taken from its registered fee schedule source,
// one on-demand window is opened for one Firecrawl read (CLAUDE.md: opened, reported, closed), and the run is made once more
let od = null, cricos = null
const fcNeed = /FIRECRAWL_NEEDS_PROVIDER (\w{5})/.exec(String(res.error || ''))
if (fcNeed) {
  cricos = fcNeed[1]
  const rows = await op(`select provider_id as pid from pipeline.sources where source_type = 'provider_fee_schedule' and metadata->>'provider_cricos' = ${lit(cricos)} and provider_id is not null limit 1`)
  if (rows.length) {
    const [{ o }] = await op(`select security.on_demand_open_v1('claude_session', ${lit(`s1334 fee schedule ${schedule} (${mode}): one Firecrawl read; the site refused the direct read (SS-Programme-Control 28 Nov 2026 09:03)`)},
      array[${lit(rows[0].pid)}::uuid], jsonb_build_object('firecrawl_credits', 1, 'openrouter_usd', 0, 'detail', ${lit(`one page: ${schedule}`)}), null, array['firecrawl']) as o`)
    od = o; console.log('On-demand window: ' + JSON.stringify(od));
    ({ r, res } = await callWorker(rows[0].pid))
  }
}
const brief = { http: r.status, schedule, mode, provider_cricos: cricos, via: res.via, on_demand: od, codes: codes.length, sha256: res.sha256, parsedRows: res.parsedRows, rejectedRows: res.rejectedRows, parked: res.parked,
  actions: res.preview?.actions ?? res.preview, applied: res.applied ? { ...res.applied, skipped_detail: undefined } : undefined, skipped_detail: res.applied?.skipped_detail, error: res.error, worker: res.workerVersion }
if (od?.id) { try { const [{ c }] = await op(`select security.on_demand_close_v1(${lit(od.id)}::uuid) as c`); brief.on_demand_closed = c } catch (e) { brief.on_demand_closed = String(e).slice(0, 200) } }
await summary(['Fee schedule ' + mode + ': ' + schedule, '', '```json', JSON.stringify(brief, null, 2).slice(0, 8000), '```'].join('\n'))
console.log(JSON.stringify(brief, null, 2).slice(0, 8000))
if (!r.ok || res.ok !== true) process.exit(1)
