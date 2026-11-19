#!/usr/bin/env node
// CF-247 S753 (session S2-BOOST-AER, Platform Admin 19 Nov 2026 15:59 AEDT): triage of the AER items waiting in Layer 4 and a bounded drain of the
// rule-compliant ones, run by GitHub Actions through the Supabase Management API so no person answers a prompt. Zero AI and Firecrawl spend: only
// database functions run, the AER v1 rules' own ones.
//   triage: every pending AER item (course first reads and entry-matrix reads) is put through its rule's read-only check (security.aer_machine_check_v1,
//           security.aer_matrix_machine_check_v1), in batches; counts by rule, plus person claims and their age.
//   drain:  triage, then each item whose check passes is handed to the same admission function the cron job aer-machine-admission calls
//           (security.aer_machine_admit_v1 / aer_matrix_machine_admit_v1, mode 'run'), at most MAX items a tick, rows locked with FOR UPDATE SKIP LOCKED;
//           the audit sample, every hold and the daily cap apply exactly as on the cron; then triage again and report before and after.
// Nothing here changes a rule, a threshold, a switch (aer.v2_shadow_on stays as it is), a manual lock or a held item. Layer 4 items carry no worker
// lease: a person's claim older than an hour is already ignored by the rules, so no claim is cleared.
import { need, lit, summary } from './boost-live-lib.mjs'
need()
const MODE = process.argv[2] === 'drain' ? 'drain' : 'triage'
const MAX = Math.max(1, Math.min(250, Math.floor(Number(process.argv[3]) || 100)))  // the Platform Admin's tick bound (at most 250)
const TOKEN = process.env.SUPABASE_ACCESS_TOKEN, REF = process.env.REF
const sql = async (query) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, { method: 'POST', headers: { authorization: `Bearer ${TOKEN}`, 'content-type': 'application/json' }, body: JSON.stringify({ query }) })
  const t = await r.text(); if (!r.ok) throw Error(`database query failed (HTTP ${r.status}): ${t.slice(0, 600)}`); return JSON.parse(t)
}
const SCOPE = `i.status = 'pending' and ((i.field_code = 'course_entry_first_read' and i.entity_type = 'course') or (i.field_code in ('entry_matrix_first_run', 'entry_matrix_change') and i.entity_type = 'provider'))`
const BATCH = 400  // items checked in one statement (inside the API's statement time)
async function triage(label) {
  const [{ n }] = await sql(`select count(*)::int n from pipeline.layer4_review_items i where ${SCOPE}`)
  const groups = {}, pass = []
  let claimed = 0, claimedRecent = 0, assigned = 0
  for (let off = 0; off < n + BATCH; off += BATCH) {
    const rows = await sql(`with p as (select i.id, i.field_code, i.claimed_at, i.assigned_to from pipeline.layer4_review_items i where ${SCOPE} order by i.id offset ${off} limit ${BATCH}),
      c as (select p.*, case when p.field_code = 'course_entry_first_read' then security.aer_machine_check_v1(p.id) else security.aer_matrix_machine_check_v1(p.id) end r from p)
      select id::text, field_code, coalesce(r->>'ok', 'false') ok, coalesce(r->>'rule', '') rule, claimed_at is not null claimed, coalesce(claimed_at > now() - interval '1 hour', false) recent, assigned_to is not null assigned from c`)
    if (!rows.length) break
    for (const x of rows) {
      const k = `${x.field_code}|${x.ok === 'true' ? 'passes the rule' : x.rule || '?'}`
      groups[k] = (groups[k] || 0) + 1
      if (x.ok === 'true') pass.push({ id: x.id, field: x.field_code })
      if (x.claimed) claimed++; if (x.recent) claimedRecent++; if (x.assigned) assigned++
    }
  }
  const [cer] = await sql(`select count(*) filter (where status = 'active')::int active, count(*)::int total from catalogue.course_entry_requirements`)
  const [lk] = await sql(`select count(*)::int locks from pipeline.manual_locks`)
  const out = { label, at: new Date().toISOString(), pending: n, groups, pass: pass.length, claimed, claimed_last_hour: claimedRecent, assigned, cer_active: cer.active, cer_total: cer.total, manual_locks: lk.locks }
  console.log('AERL4:' + JSON.stringify(out))
  return { out, pass }
}
// the cron job aer-machine-admission runs at :24 and :54; a tick is not started within two minutes of either
const clearOfCron = async () => { for (;;) { const m = new Date().getUTCMinutes(); if (!(m >= 22 && m <= 26) && !(m >= 52 && m <= 56)) return; await new Promise((r) => setTimeout(r, 30000)) } }
const before = await triage('before')
let after = before, ticks = [], failure = null
if (MODE === 'drain') {
  try {
    const ids = before.pass
    for (let i = 0; i < ids.length; i += MAX) {
      await clearOfCron()
      const part = ids.slice(i, i + MAX), t0 = Date.now()
      const [{ res }] = await sql(`with c as (select i.id, i.field_code from pipeline.layer4_review_items i where i.id = any (array[${part.map((x) => lit(x.id)).join(', ')}]::uuid[]) and i.status = 'pending' for update of i skip locked)
        select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'outcome', coalesce(v->>'outcome', v->>'rule', 'unknown'), 'rows', v->'rows')), '[]'::jsonb) res
          from c, lateral (select case when c.field_code = 'course_entry_first_read' then security.aer_machine_admit_v1(c.id, 'run') else security.aer_matrix_machine_admit_v1(c.id, 'run') end v) a`)
      const tally = {}; for (const x of res) tally[x.outcome] = (tally[x.outcome] || 0) + 1
      ticks.push({ tick: ticks.length + 1, items: part.length, locked_or_gone: part.length - res.length, ms: Date.now() - t0, outcomes: tally })
      console.log(`tick ${ticks.length}: ${part.length} items, ${Date.now() - t0} ms, ${JSON.stringify(tally)}`)
    }
  } catch (e) { failure = String(e.message || e) }
  after = await triage('after')
}
const record = { mode: MODE, max_per_tick: MAX, before: before.out, after: after.out, ticks, failure,
  admitted_rows: after.out.cer_active - before.out.cer_active, pending_change: after.out.pending - before.out.pending }
await sql(`insert into pipeline.admin_control_events(area, action, target, detail) values ('aer', ${lit(MODE === 'drain' ? 'l4_drain' : 'l4_triage')}, 'pipeline.layer4_review_items', ${lit(JSON.stringify(record))}::jsonb)`)
  .catch((e) => { failure = (failure ? failure + '; ' : '') + 'record failed: ' + e.message })
console.log('AERL4-RECORD:' + JSON.stringify(record))
const table = (o) => Object.entries(o.groups).sort((a, b) => b[1] - a[1]).map(([k, v]) => `| ${k.split('|')[0]} | ${k.split('|')[1]} | ${v} |`).join('\n')
await summary(`### S753 AER Layer 4 ${MODE}\n\nBefore: ${before.out.pending} pending, ${before.out.pass} pass the rule; claimed ${before.out.claimed} (last hour ${before.out.claimed_last_hour}), assigned ${before.out.assigned}; active entry requirement rows ${before.out.cer_active}; manual locks ${before.out.manual_locks}.\n\n| Field | Rule | Items |\n|---|---|---|\n${table(before.out)}\n\n` +
  (MODE === 'drain' ? `Ticks: ${JSON.stringify(ticks)}\n\nAfter: ${after.out.pending} pending, ${after.out.pass} pass the rule; active entry requirement rows ${after.out.cer_active} (+${record.admitted_rows}).\n\n| Field | Rule | Items |\n|---|---|---|\n${table(after.out)}\n` : ''))
if (failure) { await summary(`Stopped: ${failure}`); process.exit(1) }
