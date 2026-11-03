// Guards: Integration issue IQ-00064 (an enrichment plan step is never marked done while its lane is idle-paused with its work unprocessed)
// The behaviour runs on isolated fixtures by tests/fixtures/plan-step-lane-hold/run.sh (scratch PostgreSQL; the live v2.15.423 definitions
// loaded from their live text and checked against the live md5s; the defect reproduced on them; the migration applied, checked with the switch
// off, applied again; every case asserted with the switch on). This spec holds the contract of the change.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261103200000_cf247_plan_step_lane_hold.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/plan-step-lane-hold'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const before = fs.readFileSync(`${FX}/fixtures-before.sql`, 'utf8')
const off = fs.readFileSync(`${FX}/fixtures-off.sql`, 'utf8')
const edit = (sig) => { const a = m.indexOf(`select pg_temp.edit_once('${sig}'`); expect(a, sig).toBeGreaterThan(-1); return m.slice(a, m.indexOf('], array[', a)) }
const after = (block) => block.split('$n$').filter((_, i) => i % 2 === 1).join('\n')

const MD5 = {
  'security.flag_jobs_v1()': ['22fa89f4c0c3c238b3d281bd481309b2', '668251ec6027c1e9e6dd7d7a9b340bb9'],
  'security.admin_job_watch_v1(uuid)': ['ad21305f89ee441bde462cc35e5a8a98', '5025e03969c4ac41f06980936aa14741'],
  'security.admin_jobs_tick_v1(integer)': ['e760363a6af21d850f7e6e1c86bca0cb', 'fc698f9912cffd90a7b8ae32e33dd09e'],
  'security.enrich_plan_tick_v1(uuid)': ['613782d4a04d3e6ce123c8837339d5e0', 'bdd7e639295c5c1acb35a7da39273f79'],
}

test('four live definitions are edited only from their live md5 and checked after; the fixture loads the same', () => {
  for (const [sig, [b, a]] of Object.entries(MD5)) {
    expect(edit(sig)).toContain(`'${b}', '${a}'`)
    expect(m).toContain(`${b} -> ${a}`)
    expect(run).toContain(b); expect(run).toContain(a)
  }
  expect(m).toContain("if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;")
  expect(m).toContain("raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;")
  // the slice still hands course_page_find to the watcher
  expect(m).toContain("('security.admin_job_slice_v1(uuid,integer)', '88f82c974b0ecde708a0550413791d86')")
  expect(run).toContain('grep -c \'already applied\' | grep -qx 4')
})

test('the switch ships off and the hold is bounded by a setting', () => {
  expect(m).toMatch(/\('pipeline', 'tasks\.lane_hold_on', [\s\S]*?'number', '0'::jsonb, '0', '1', 'on \(1\) or off \(0\)'/)
  expect(m).toMatch(/'tasks\.lane_hold_max_hours'[\s\S]*?'number', '24'::jsonb, '1', '168', 'hours'/)
  expect(m).toContain("raise exception 'IQ-00064 post-check: tasks.lane_hold_on must ship off'")
  for (const sig of Object.keys(MD5).filter((s) => !s.startsWith('security.admin_jobs_tick'))) expect(after(edit(sig))).toContain("security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1")
  expect(off).toContain("\\ir fixtures-before.sql")
})

test('cause 1: the idle guard does not pause a lane a task is waiting for, and wakes it', () => {
  const f = after(edit('security.flag_jobs_v1()'))
  expect(f).toContain("and not (security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1 and security.lane_task_waiting_v1(j.mode)) then")
  expect(f).toContain("or (security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1 and security.lane_task_waiting_v1(j.mode)))")
  expect(m).toContain("where j.kind = 'course_page_find' and j.state in ('queued', 'running'))")
  expect(fixtures).toContain("'B1 the idle guard does not pause the lane while a running task has courses queued for it (30 empty calls)'")
  expect(fixtures).toContain("'B2 with no task work waiting, 30 empty calls still pause the lane (the guard is kept)'")
})

test('cause 2: a task with unsearched courses is held with its reason, never done; bounded, it ends failed with the reason', () => {
  const w = after(edit('security.admin_job_watch_v1(uuid)'))
  expect(w).toContain("if not v_fin and v_j.kind = 'course_page_find' and v_done < v_total and security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1 then")
  expect(w).toContain('v_stall := null;')
  expect(w).toContain("v_extra := v_extra || jsonb_build_object('end_state', 'failed', 'unprocessed', v_total - v_done);")
  expect(after(edit('security.admin_jobs_tick_v1(integer)'))).toContain("state = case when result->>'end_state' = 'failed' then 'failed' else 'done' end")
  for (const k of ['C1 held by the Firecrawl day share (a budget hold is a hold)', 'C4 the task continues when the lane wakes', 'D1 the IQ-00064 case: held by the idle guard gate, not done',
    'E1 held past 24 hours: the task ends failed, not done', 'E2 the plan step fails with the task', 'C2 one event when the hold starts']) expect(fixtures).toContain(k)
  expect(before).toContain("'before: the task ended done with 2 of 4 courses unsearched'")
})

test('the plan step completes only when its task scope is processed, or the task failed or was cancelled with a reason', () => {
  const p = after(edit('security.enrich_plan_tick_v1(uuid)'))
  expect(p).toContain("and (j.result->>'done')::numeric < (j.result->>'total')::numeric then 'failed'")
  expect(p).toContain("and exists (select 1 from pipeline.admin_jobs j where j.id = (s->'ref'->>'id')::uuid and j.kind = 'course_page_find' and j.state in ('queued', 'running'))) then")
  expect(p).toContain("when 'failed' then case when s->'ref'->>'kind' = 'job'")
  for (const k of ['G1 done with 2 of 4 courses unsearched is not a done step', 'G3 a cancelled task: the step is cancelled with its reason', 'F1 a step past plans.step_max_hours is not timed out',
    'F2 another task kind times out as before']) expect(fixtures).toContain(k)
})
