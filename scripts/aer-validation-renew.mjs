#!/usr/bin/env node
// CF-247 S674 (session S1-AER; Platform Admin standing rule 18 Nov 2026 20:53 AEDT: "automatic 7-day validation renewal on unchanged thresholds (0.8 confidence,
// 8-character quote, 0 regressions) ... without pausing for manual sign-off"). Run by GitHub Actions (aer-validation-renew.yml) through the Management API, no prompt.
//   status: read only. The last passing validation of rules aer-machine-v1 (course reads) and aer-matrix-machine-v1 (provider tables), their age, the thresholds,
//           the validators' live md5, and what the machines admitted since a time (default the last 24 hours) and what still waits as would-admit.
//   renew:  status, then for each rule whose last pass is at least aer.validation_renew_after_days old: runs its validation again ONLY when the thresholds are the
//           ones the standing rule names, the validator is the definition checked on 18 Nov 2026 (md5), the mode is 2 and admission is not suspended. A validation
//           that does not pass is reported and the run fails, and admission falls back to shadow when the old pass lapses (nothing is forced on).
// Nothing else changes: no setting, mode, threshold or row other than the validation record and one control event per renewal.
import { need, read, lit, summary } from './boost-live-lib.mjs'
need()
const MODE = String(process.argv[2] || 'status'), SINCE = String(process.argv[3] || '')
const TOKEN = process.env.SUPABASE_ACCESS_TOKEN, REF = process.env.REF
const write = async (query) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, { method: 'POST', headers: { authorization: `Bearer ${TOKEN}`, 'content-type': 'application/json' }, body: JSON.stringify({ query }) })
  const t = await r.text(); if (!r.ok) throw Error(`database write failed (HTTP ${r.status}): ${t.slice(0, 600)}`); return JSON.parse(t)
}
// fixed: what the standing rule of 18 Nov 2026 20:53 names as unchanged, and the validators it was given for (a changed validator needs a new decision)
const RULES = [
  { name: 'aer-machine-v1 (course reads)', table: 'pipeline.aer_machine_validations', fn: 'security.aer_machine_validate_v1()', md5: '945077fe5dc291cc0893976f8fe65aef',
    mode: 'aer.machine_mode', suspended: 'aer.machine_suspended', thresholds: { 'aer.machine_min_confidence': 0.8, 'aer.machine_min_quote_chars': 8 } },
  { name: 'aer-matrix-machine-v1 (provider tables)', table: 'pipeline.aer_matrix_machine_validations', fn: 'security.aer_matrix_machine_validate_v1()', md5: '162cfa24e35bfcc9100c1bea81c61b6a',
    mode: 'aer.matrix_machine_mode', suspended: null, thresholds: { 'aer.matrix_machine_min_confidence': 0.9, 'aer.machine_min_quote_chars': 8 } }]
const num = (k) => `security.pipeline_num_v1(${lit(k)}, -1)`
const since = SINCE ? `${lit(SINCE)}::timestamptz` : `now() - interval '24 hours'`
const [st] = await read(`select now() as at, ${num('aer.validation_renew_after_days')} as renew_after_days,
  (select jsonb_object_agg(r.k, security.pipeline_num_v1(r.k, -1)) from unnest(array['aer.machine_mode', 'aer.machine_suspended', 'aer.machine_min_confidence', 'aer.machine_min_quote_chars',
     'aer.matrix_machine_mode', 'aer.matrix_machine_min_confidence']) r(k)) as settings,
  ${RULES.map((r, i) => `(select jsonb_build_object('at', max(validated_at), 'age_days', round((extract(epoch from now() - max(validated_at)) / 86400)::numeric, 2)) from ${r.table} where passed) as v${i},
  md5(pg_catalog.pg_get_functiondef(${lit(r.fn)}::regprocedure)) as m${i}`).join(',\n  ')},
  (select count(*) from pipeline.aer_machine_admissions where mode = 'admit' and outcome = 'admitted' and created_at > ${since}) as course_admitted,
  (select coalesce(sum(rows_admitted), 0) from pipeline.aer_machine_admissions where mode = 'admit' and outcome = 'admitted' and created_at > ${since}) as course_rows,
  (select count(*) from pipeline.aer_machine_admissions m join pipeline.layer4_review_items i on i.id = m.review_item_id and i.status = 'pending' where m.mode = 'shadow' and m.outcome = 'would_admit') as course_would_admit_waiting,
  (select count(*) from pipeline.aer_matrix_machine_admissions where mode = 'admit' and outcome = 'admitted' and created_at > ${since}) as matrix_admitted,
  (select count(*) from pipeline.layer4_review_items where field_code = 'course_entry_first_read' and status = 'pending') as course_reads_waiting,
  (select count(*) from security.consumer_api_functions_v1()) || '/' || (select count(*) from security.consumer_api_relations_v1()) as g3`)
await summary(`### AER validation ${MODE} (${st.at})\n\n| Rule | Last pass | Age (days) | Validator md5 as checked |\n|---|---|---|---|\n${RULES.map((r, i) => `| ${r.name} | ${st[`v${i}`]?.at ?? 'none'} | ${st[`v${i}`]?.age_days ?? '-'} | ${st[`m${i}`] === r.md5 ? 'yes' : 'NO (' + st[`m${i}`] + ')'} |`).join('\n')}\n\nSettings: ${JSON.stringify(st.settings)}; renew after ${st.renew_after_days} days. G3 ${st.g3}.\n\nSince ${SINCE || 'the last 24 hours'}: course reads admitted ${st.course_admitted} (${st.course_rows} rows), provider tables admitted ${st.matrix_admitted}; course reads still recorded would-admit and waiting ${st.course_would_admit_waiting}; course reads waiting in Layer 4 ${st.course_reads_waiting}.`)
if (MODE !== 'renew') process.exit(0)
let failed = false
for (const [i, r] of RULES.entries()) {
  const age = Number(st[`v${i}`]?.age_days ?? 99), after = Number(st.renew_after_days)
  if (!(after >= 1)) { await summary(`${r.name}: not renewed: aer.validation_renew_after_days is not set`); failed = true; continue }
  if (age < after) { await summary(`${r.name}: not due (${age} of ${after} days)`); continue }
  const off = Object.entries(r.thresholds).filter(([k, v]) => Number(st.settings[k]) !== v).map(([k, v]) => `${k} is ${st.settings[k]}, the rule names ${v}`)
  if (st[`m${i}`] !== r.md5) off.push(`${r.fn} is not the definition the rule was given for (md5 ${st[`m${i}`]})`)
  if (Number(st.settings[r.mode]) !== 2) off.push(`${r.mode} is ${st.settings[r.mode]}, not 2`)
  if (r.suspended && Number(st.settings[r.suspended]) >= 1) off.push(`${r.suspended} is on`)
  if (off.length) { await summary(`${r.name}: NOT renewed, the standing rule does not cover it: ${off.join('; ')}. A person decides.`); failed = true; continue }
  const [{ v }] = await write(`with v as (select ${r.fn} as v)
    insert into pipeline.admin_control_events(area, action, target, detail)
    select 'aer', ${lit(i === 0 ? 'machine_validate' : 'matrix_machine_validate')}, ${lit(r.mode)}, (v.v - 'history_disagreements' - 'history') || jsonb_build_object('authority',
      'Platform Admin standing rule 18 Nov 2026 20:53 AEDT (S1-AER s674): automatic 7-day renewal on unchanged thresholds', 'by', 'workflow aer-validation-renew') from v returning detail as v`)
  const pass = String(v.passed) === 'true' && Number(v.regressions_on_recheck) === 0
  await summary(`${r.name}: renewed, passed ${v.passed}, regressions ${v.regressions_on_recheck}, would-admit re-checked ${v.shadow_would_admit}`)
  if (!pass) failed = true
}
if (failed) process.exit(1)
