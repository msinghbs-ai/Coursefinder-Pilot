#!/usr/bin/env node
// CF-247 s842 (session S1-ELR, Platform Admin 20 Nov 2026 15:10 AEDT): the English requirement sweep from GitHub Actions, through the Management API with no prompt.
// $0: no model, no Firecrawl. Mode status (read only) prints security.elr_det_status_v1(). Mode run calls one sweep run (security.elr_det_sweep_tick_v1, the job
// elr-det-sweep's own command) every 60 s for the given number of minutes, so a governed Run Now drains a bounded workload at once and its gains are read back.
// Arguments: 1 = mode (status | run), 2 = minutes (run only, 1 to 50).
import { need, summary } from './boost-live-lib.mjs'
need()
const mode = process.argv[2] || 'status', minutes = Math.min(50, Math.max(1, Number(process.argv[3] || 10)))  // fixed: a run stays inside the workflow's 60-minute limit
// s843: the status function is revoked from public, so the read-only role cannot call it; it is read through the owner's connection (it is STABLE and writes nothing)
const status = async () => (await query('select security.elr_det_status_v1() as s'))[0].s
const tick = async () => (await query('select security.elr_det_sweep_tick_v1() as r'))[0].r
async function query(sql) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${process.env.REF}/database/query`, { method: 'POST',
    headers: { authorization: `Bearer ${process.env.SUPABASE_ACCESS_TOKEN}`, 'content-type': 'application/json' }, body: JSON.stringify({ query: sql }) })
  const t = await r.text(); if (!r.ok) throw Error(`database query failed (HTTP ${r.status}): ${t.slice(0, 400)}`); return JSON.parse(t)
}
const line = (s) => `promoted ${s.courses_promoted} courses (${s.rows_promoted} rows); Layer 4 ${s.layer4_pending}; pages ${JSON.stringify(s.pages)}; calls ${JSON.stringify(s.calls)}`
const before = await status()
let md = `### English requirement sweep (${mode})\n\nBefore: ${line(before)}\n\nBy country: ${JSON.stringify(before.by_country)}\n`
if (mode === 'run') {
  const until = Date.now() + minutes * 60000
  while (Date.now() < until) {
    const r = await tick(); md += `\n- run: ${JSON.stringify(r)}`
    await new Promise((res) => setTimeout(res, 60000))
  }
  const r = await tick(); md += `\n- last run (reads back the last answers): ${JSON.stringify(r)}\n`
  const after = await status()
  md += `\nAfter: ${line(after)}\n\nBy country: ${JSON.stringify(after.by_country)}\n\nHeld reasons: ${JSON.stringify(after.held_reasons)}\n`
}
await summary(md)
