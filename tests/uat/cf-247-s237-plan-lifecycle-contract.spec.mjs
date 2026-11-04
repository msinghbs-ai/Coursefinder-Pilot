// Guards: Platform Admin P0 mandate 3 Nov 2026 10:44 §3 Agent A (enrichment-plan lifecycle: safe re-planning, no orphaned work)
// Automatic plans re-plan a university early on new verified evidence and on failed steps whose cause has cleared (settings, ship off),
// beside v2.15.419's grown gaps, under one per-hour cap and a per-university minimum interval; an input fingerprint stops duplicate plans of
// unchanged inputs and a university with nothing to do is not re-evaluated until its inputs change; done steps whose inputs did not change
// are not redone; causes time does not clear are not retried by time (measured: 1,036 of 1,043 unfinished last steps); fair order (ships
// off). Run now takes over an open automatic plan (carrying its running tasks), never an open Run now; a cancelled run starts nothing and
// its tasks are cancelled as the person who started each; an orphan check feeds the integration queue. Layer 2 rows on Refresh schedules
// show a note instead of an inoperative Run on demand button. Behaviour runs on isolated fixtures by tests/fixtures/enrich-plan-lifecycle/run.sh
// (scratch PostgreSQL; eight live definitions checked against their live md5, v2.15.419 applied, this migration applied twice, the cases).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261103150000_cf247_plan_lifecycle.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/enrich-plan-lifecycle'
const read = (p) => fs.readFileSync(p, 'utf8')
const run = read(`${FX}/run.sh`)
const fixtures = read(`${FX}/fixtures.sql`)

test('each edited definition changes only from the md5 it was written against and is checked after; the fixtures prove the live text first', () => {
  expect(m).toContain("select pg_temp.replace_once('security.enrich_plan_auto_v1()', '2d8944d7624b90cbbefb9925d602c92b', '14d4769267f827736a0d4e2f013c4dad'")
  for (const [sig, before, after] of [
    ['security.enrich_plan_start_step_v1(uuid,text)', '4e240fab607122eff455ea3c57b5447f', '50b4ea8f613389062efc2116ece62db7'],
    ['security.enrich_plan_tick_v1(uuid)', '0ba546e23715c8d3244e840c49e61e9b', '613782d4a04d3e6ce123c8837339d5e0'],
    ['public.admin_enrich_plan(text,jsonb)', '0c9d3ec1b7d043e2d9f3ac83f9d99e1d', 'dab650c5adefd9b0b9c006b0c5db4d5d'],
    ['security.enrich_plan_cancel_steps_v1(uuid,text)', '60ec6f01a645eae5e246daa3e721deac', '209ac4e0a45fa307e3efb81f1e541598'],
  ]) { expect(m).toContain(`select pg_temp.edit_once('${sig}', '${before}', '${after}'`); expect(run).toContain(after) }
  // the v2.15.419 results this change is written against, and the live definitions under them
  for (const s of ['2d8944d7624b90cbbefb9925d602c92b', '0c9d3ec1b7d043e2d9f3ac83f9d99e1d', '60ec6f01a645eae5e246daa3e721deac', '0ba546e23715c8d3244e840c49e61e9b', '4e240fab607122eff455ea3c57b5447f']) expect(run).toContain(s)
  expect(fs.existsSync(`${FX}/live/security.enrich_plan_tick_v1.sql`)).toBe(true)
  expect(m).toContain("('security.enrich_plan_v1(uuid)', '818ef130484e567c35a7a2cf5a99d7c8')")
  expect(run).toContain("grep -c 'already applied' | grep -qx 5")
})

test('re-planning: evidence and retryable steps beside grown gaps, one hourly cap, a minimum interval, a fingerprint, no starvation; new triggers ship off', () => {
  for (const [k, v] of [['plans.replan_on_evidence', "'0'"], ['plans.replan_on_retry', "'0'"], ['plans.fair_order', "'0'"], ['plans.run_now_supersedes_auto', "'1'"]]) {
    expect(m).toMatch(new RegExp(`\\('pipeline', '${k.replace('.', '\\.')}', [^\\n]*\\n[^\\n]*\\n\\s*'number', ${v}::jsonb`))
  }
  expect(m).toContain("or (v_on_ev and ((i.v->>'evidence_new')::int > 0 or (i.v->>'central_new')::boolean))")
  expect(m).toContain("or (v_on_rt and jsonb_array_length(i.v->'retry_steps') > 0))")
  expect(m).toContain("where v_re_max > 0 and l.id is not null and l.created_at > now() - make_interval(days => v_redo)")
  expect(m).toContain("continue when v_is_re and v_re_used + v_re >= v_re_max;")
  expect(m).toContain("and not exists (select 1 from pipeline.enrich_plan_noop n where n.provider_id = x.provider_id and n.fingerprint = i.fp)")
  expect(m).toContain("comment on table pipeline.enrich_plan_noop is")
  expect(m).toContain("w.key = 'plans.retry_waits_for_change'")
  expect(m).toContain("< security.pipeline_num_v1('plans.step_retry_max', 3)")
  for (const c of ['ok F1-F3 fair order', 'ok A1 as shipped', 'ok A2-A3 evidence', 'ok A4 retry', 'ok A5 input fingerprint', 'ok A6 evidence and retry re-plans share', 'ok A7 the Run now hold', 'ok A8 a cause']) expect(fixtures).toContain(c)
})

test('Run now and automatic plans: one plan per university; Run now takes over an automatic plan and carries its running tasks; the screen offers it', () => {
  expect(m).toContain("when s->>'status' = 'running' then s || jsonb_build_object('status', 'handed_over', 'note', 'task carried into the Run now plan', 'finished_at', now())")
  expect(m).toContain("where not exists (select 1 from jsonb_array_elements(v_carry) k where k->>'step' = x->>'step'));  -- already running: carried, not started again")
  expect(m).toContain("raise exception 'a plan is already running for this university%'")
  for (const c of ['ok B1-B4 Run now on an open automatic plan', 'ok B5 an open Run now plan is never taken over']) expect(fixtures).toContain(c)
  const ep = read('src/EnrichPlan.jsx')
  expect(ep).toContain("const takeover=!!open&&open.mode==='auto'")
  expect(ep).toContain("{takeover?'Run now (takes over the automatic plan)':'Run now'}")
  expect(ep).toContain("handed_over:['Carried into Run now','info']")
})

test('cancellation: a cancelled run starts no step, its tasks are cancelled as their starters, and orphaned plan work raises an integration issue', () => {
  expect(m).toContain("if r.id is null or r.state not in ('queued', 'running') then raise exception 'the plan run is %; no further step starts'")
  expect(m).toContain("elsif (select x.state from pipeline.enrich_plan_runs x where x.id = r.id) not in ('queued', 'running') then")
  expect(m).toContain("(select j.requested_by from pipeline.admin_jobs j where j.id = (s->'ref'->>'id')::uuid) end, r.requested_by)")
  expect(m).toContain("'fingerprint', 'enrich_plan_orphans'")
  expect(m).toContain("command := v_cmd || ', security.enrich_plan_orphans_issue_v1()'")
  expect(run).toContain('security.integration_yield_checks_v1(), security.enrich_plan_orphans_issue_v1()')
  for (const c of ['ok C1-C2 cancel', 'ok C3 an open run', 'ok D1-D3 orphans', 'ok E1 the Enrichment plan overview']) expect(fixtures).toContain(c)
})

// 'Refresh schedules: Layer 2 rows show a note ...' retired 4 Nov 2026 with the section (SS-020 follow-up, Decision 269 amendment; s274)
