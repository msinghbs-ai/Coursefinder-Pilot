// Guards: Integration issue IQ-00064 (an enrichment plan step is never marked done while its lane is idle-paused with its work unprocessed)
// Release A (consolidated mandate 3 Nov 2026 13:09 §3: P0 release blocker). The behaviour runs on isolated fixtures by
// tests/fixtures/plan-step-lane-hold/run.sh (scratch PostgreSQL; the live v2.15.423 definitions loaded from their live text and checked against
// the live md5s; the defect reproduced on them; the 18 measured steps seeded with their real ids and reconciled; the migration checked with the
// switch set off and applied again; every case asserted; a changed set refused). This spec holds the contract of the change and the screen.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261103200000_cf247_plan_step_lane_hold.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/plan-step-lane-hold'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const before = fs.readFileSync(`${FX}/fixtures-before.sql`, 'utf8')
const off = fs.readFileSync(`${FX}/fixtures-off.sql`, 'utf8')
const seed = fs.readFileSync(`${FX}/seed-reconcile.sql`, 'utf8')
const ui = fs.readFileSync('src/EnrichPlan.jsx', 'utf8')
const edit = (sig) => { const a = m.indexOf(`select pg_temp.edit_once('${sig}'`); expect(a, sig).toBeGreaterThan(-1); return m.slice(a, m.indexOf('\n], array[', a)) }
const after = (block) => block.split('$n$').filter((_, i) => i % 2 === 1).join('\n')

const MD5 = {
  'security.flag_jobs_v1()': ['22fa89f4c0c3c238b3d281bd481309b2', '668251ec6027c1e9e6dd7d7a9b340bb9'],
  'security.admin_job_watch_v1(uuid)': ['ad21305f89ee441bde462cc35e5a8a98', '34a1cfd57b367d0e60ccb4a85f56e228'],
  'security.admin_jobs_tick_v1(integer)': ['e760363a6af21d850f7e6e1c86bca0cb', 'fc698f9912cffd90a7b8ae32e33dd09e'],
  'security.enrich_plan_tick_v1(uuid)': ['613782d4a04d3e6ce123c8837339d5e0', 'cab734df6715e25014935bd22058343b'],
  'security.integration_yield_checks_v1()': ['2bcba102aa776a21c888bae711fd3374', '265d5fa8637185016018b3b81dad1b39'],
}
const IDS = ['316bf0b2-1e98-48bb-816f-62fedb32733e', '31c01095-fdce-4495-80c6-5187adc0b2d9', '3daf6428-a61a-48f5-8f70-a12e6bef3f70', '530cd23a-50ae-4e6c-b2e8-09e71e869af2',
  '5b5f5d3f-5972-48e8-b47f-c0f3c168b9b1', '63014f13-a64e-4731-8503-cd97f9d1754e', '66933787-b937-40ad-86c9-dc456f608034', '80e98946-30ab-43b3-b6e9-1f2f52e1dfa6',
  '86cf79ca-3e36-4702-aac8-f71a04a56795', '8bf3e9af-0c4d-46c0-b732-25b55d5abeea', '8c12b05c-b9b7-4f5b-9b74-c1ced82b7088', 'a8042193-44a9-4322-a221-e1ca8579990d',
  'b29022a2-545d-4e96-951f-865b864c3032', 'b95281a2-2f96-408c-9c19-849b577cd89f', 'eb1f211d-c7c9-4df8-8de6-d59cabd869f5', 'f201a700-da26-40f9-bd69-0022961ce347',
  'fa579433-070c-4433-9fd1-1b2b2cfdd236', 'fba22606-c3a5-42c8-bc18-2f22ff5c1410']

test('five live definitions are edited only from their live md5 and checked after; the fixture loads the same', () => {
  for (const [sig, [b, a]] of Object.entries(MD5)) {
    expect(edit(sig)).toContain(`'${b}', '${a}'`)
    expect(m).toContain(`${b} -> ${a}`)
    expect(run).toContain(b); expect(run).toContain(a)
  }
  expect(m).toContain("if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;")
  expect(m).toContain("raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;")
  expect(m).toContain("('security.admin_job_slice_v1(uuid,integer)', '88f82c974b0ecde708a0550413791d86')")
  expect(run).toContain("grep -c '^security\\..*: already applied$')\" = 5 ]")
})

test('the switch ships on (P0 mandate); the kinds, the bound and the look-back are settings', () => {
  expect(m).toMatch(/\('pipeline', 'tasks\.lane_hold_on', [\s\S]*?'number', '1'::jsonb, '0', '1', 'on \(1\) or off \(0\)'/)
  expect(m).toMatch(/'tasks\.lane_hold_max_hours'[\s\S]*?'number', '24'::jsonb, '1', '168', 'hours'/)
  expect(m).toContain(`'list', '["course_page_find", "scholarship_provider_scan", "provider_fill"]'::jsonb, null, null, 'task kinds'`)
  expect(m).toMatch(/'tasks\.unfinished_lookback_days'[\s\S]*?'number', '7'::jsonb, '1', '90', 'days'/)
  for (const sig of ['security.flag_jobs_v1()', 'security.admin_job_watch_v1(uuid)', 'security.enrich_plan_tick_v1(uuid)']) expect(after(edit(sig))).toContain("security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1")
  expect(off).toContain("set value = '0' where toolset_key = 'pipeline' and key = 'tasks.lane_hold_on'")
  expect(off).toContain('\\ir fixtures-before.sql')
  expect(run).toContain('tasks.lane_hold_on must ship on')
})

test('cause 1: the idle guard does not pause a lane a task is waiting for, and wakes it', () => {
  const f = after(edit('security.flag_jobs_v1()'))
  expect(f).toContain("and not (security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1 and security.lane_task_waiting_v1(j.mode)) then")
  expect(f).toContain("or (security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1 and security.lane_task_waiting_v1(j.mode)))")
  expect(fixtures).toContain("'B1 the idle guard does not pause the lane while a running task has courses queued for it (30 empty calls)'")
  expect(fixtures).toContain("'B2 with no task work waiting, 30 empty calls still pause the lane (the guard is kept)'")
  expect(before).toContain("'before: the idle guard paused the lane while a running task had 2 courses queued for it'")
})

test('cause 2, generalised: a task of tasks.hold_kinds with work left is held with reason and checkpoint, never done; bounded, it ends failed', () => {
  const w = after(edit('security.admin_job_watch_v1(uuid)'))
  expect(w).toContain("v_j.kind = any (security.pipeline_list_v1('tasks.hold_kinds', '[\"course_page_find\", \"scholarship_provider_scan\", \"provider_fill\"]'))")
  expect(w).toContain('v_stall := null;')
  expect(w).toContain("'checkpoint', jsonb_build_object('done', v_done, 'total', v_total, 'last_change_at', v_last_at, 'phase', v_phase)")
  expect(w).toContain("jsonb_build_object('end_state', 'failed', 'unprocessed', v_total - v_done)")
  expect(after(edit('security.admin_jobs_tick_v1(integer)'))).toContain("state = case when result->>'end_state' = 'failed' then 'failed' else 'done' end")
  for (const k of ['C1 held by the Firecrawl day share (a budget hold is a hold)', 'C4 the task continues when the lane wakes', 'D1 the IQ-00064 case: held by the idle guard gate, not done',
    'E1 held past 24 hours: the task ends failed, not done', 'I1 provider fill with 1 of 3 parts done', 'I2 a scholarship scan with a page unread', 'I3 the kinds are a setting']) expect(fixtures).toContain(k)
})

test('parent and child reconcile: a step is done only when its task scope is; the step shows hold, remaining and restart eligibility', () => {
  const p = after(edit('security.enrich_plan_tick_v1(uuid)'))
  expect(p).toContain("and (j.result->>'done')::numeric < (j.result->>'total')::numeric then 'failed'")
  expect(p).toContain("'ended done with ' || ((j.result->>'total')::numeric - (j.result->>'done')::numeric)")
  expect(p).toContain("jsonb_build_object('restart', security.plan_step_restart_v1(x.steps->i))")
  expect(p).toContain("jsonb_build_object('held', j.result->'held', 'remaining', j.result->'unprocessed', 'note', j.result->>'note')")
  expect(m).toContain("'waits_for_change', exists (select 1 from pipeline.platform_toolset_settings w")
  for (const k of ['G1 done with 2 of 4 courses unsearched is not a done step', 'F1 a step past plans.step_max_hours is not timed out', 'J1 the running step carries the hold',
    'J3 an ended step keeps its remaining items and when the governed re-plan may retry it', 'J4 a cause time does not clear']) expect(fixtures).toContain(k)
  // the Enrichment plan screen's step detail
  expect(ui).toContain('function StepHold({s}){')
  expect(ui).toContain('<StepHold s={s}/>')
  expect(ui).toContain("data-step-hold={h?'held':'ended'}")
})

test('monitoring: one fingerprinted issue while a plan step or task ended done with work unfinished, cleared when none remains', () => {
  const y = after(edit('security.integration_yield_checks_v1()'))
  expect(y).toContain("'fingerprint', 'plan_unfinished_done:plans'")
  expect(y).toContain("v_ok := v_ok || 'plan_unfinished_done'::text;")
  expect(y).toContain('from security.plan_unfinished_done_v1() u;')
  expect(m).toContain("coalesce((select max(e.created_at) from pipeline.admin_control_events e where e.action = 'iq64_plan_step_reconcile'), '-infinity') cut")
  for (const k of ['K1 one issue raised', 'K2 observed again, still one issue (fingerprinted)', 'K5 none remains: the issue is marked cleared']) expect(fixtures).toContain(k)
})

test('reconciliation: exactly the 18 measured steps, guarded by count and id md5, failed with the reason; once; refused on a changed set', () => {
  for (const id of IDS) { expect(m).toContain(`'${id}'`); expect(seed).toContain(`'${id}'`) }
  expect(m.match(/'effa0dc2788015cfbef9c66247d5bade'/g).length).toBeGreaterThanOrEqual(2)
  expect(m).toContain("'note', 'ended done with ' || v_s.n || ' items unprocessed (IQ-00064)'")
  expect(m).toContain("if exists (select 1 from pipeline.admin_control_events e where e.action = 'iq64_plan_step_reconcile') then")
  expect(m).toContain("insert into pipeline.admin_control_events(area, action, target, detail)")
  expect(m).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
  expect(run).toContain('ok reconciliation: 18 measured steps failed with the reason (314 items)')
  expect(run).toContain('ok refusal: 17 of the 18 measured steps still match')
})
