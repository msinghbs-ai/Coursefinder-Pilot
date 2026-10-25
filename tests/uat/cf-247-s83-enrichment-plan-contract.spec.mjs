// Guards: CF-247 S83: plan steps, estimates from use, runs and jobs
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// CF-247 v2.15.306 (Platform Admin, 21 Oct 2026 12:03): end to end enrichment per university; automation within the toolset shares,
// manual Run now from its own on-demand allowance after seeing the estimate. Choices: "Own on-demand allowance", "All, most missing
// first", "Universities row + plan tab".
const m = fs.readFileSync('supabase/migrations/20261021170000_cf247_enrichment_plan.sql', 'utf8')
const ui = fs.readFileSync('src/EnrichPlan.jsx', 'utf8')
const nav = fs.readFileSync('src/nav-map.js', 'utf8')
const row = fs.readFileSync('src/AdaptersWorkspace.jsx', 'utf8')

test('plan steps, estimates from use, runs and jobs', () => {
  for (const s of ["'step', 'site'", "'step', 'pages'", "'step', 'adapter'", "'step', 'admit'", "'step', 'fields'", "'step', 'scholarships'"]) expect(m).toContain(s)
  expect(m).toContain('create or replace function security.enrich_unit_costs_v1()')
  expect(m).toContain('create table if not exists pipeline.enrich_plan_runs')
  expect(m).toContain("select cron.schedule('enrich-plan-run', '*/5 * * * *', $$select security.enrich_plan_tick_v1()$$);")
  expect(m).toContain("select cron.schedule('enrich-plan-auto', '41 * * * *', $$select security.enrich_plan_auto_v1()$$);")
  for (const k of ['plans.auto_open_max', 'plans.auto_per_run', 'plans.redo_days', 'plans.step_wait_hours', 'plans.step_max_hours']) expect(m).toContain(`security.pipeline_num_v1('${k}'`)
  expect(m).toMatch(/-- Replaces: /)
  expect(m).toMatch(/-- Retires: /)
})

test('manual runs spend from their own allowance; automation keeps its shares', () => {
  expect(m).toContain("if security.fc_on_demand_today_v1() + p_units > security.fc_setting_num_v1('ondemand_credits_per_day', 2000) then v_why := 'on_demand_allowance'; end if;")
  expect(m).toContain('and x.on_demand_run is null;')
  expect(m).toContain("raise exception 'the estimate (% credits) is more than the on-demand allowance left today")
  expect(m).toContain("if v_rank < 4 then raise exception 'Pipeline Operator role or above required'")
  expect(m).toContain("if v_rank < 6 then raise exception 'Platform Admin role required'")
  // a directory site is never paid for, on demand or not: the directory check stays first
  expect(m.indexOf("elsif v_od is not null then")).toBeGreaterThan(0)
})

test('screen: plan tab, row link, estimate before Run now', () => {
  expect(nav).toContain("{ key: 'plan', label: 'Enrichment plan', min: 3 }")
  expect(row).toContain("hrefFor('layer2','plan',{provider:pid})")
  expect(ui).toContain("supabase.rpc('admin_enrich_plan'")
  expect(ui).toContain('data-plan-panel')
  expect(ui).toContain("call('run',{provider:pid,steps:pick,reason:reason.trim()})")
  expect(ui).toContain('More than the on-demand allowance left today')
})

// v2.15.307 (Platform Admin 21 Oct 2026 17:30, "Pick b, and proceed with task 2 and 3"): plan tasks say they belong to a plan; plans that
// finish with a stopped or skipped step say what a person has to do; automatic search refresh requests are spaced out.
test('plan tasks are labelled, plans that need a person are listed, automatic refreshes spaced', () => {
  const n = fs.readFileSync('supabase/migrations/20261021190000_cf247_plan_needs_person.sql', 'utf8')
  const tasks = fs.readFileSync('src/AdminTasks.jsx', 'utf8')
  expect(n).toContain("args || jsonb_build_object('plan_run', r.id, 'plan_mode', r.mode)")
  expect(n).toContain('alter table pipeline.enrich_plan_runs add column if not exists needs_person text;')
  expect(n).toContain('comment on column pipeline.enrich_plan_runs.needs_person')
  expect(n).toContain('needs_person = security.enrich_plan_needs_person_v1(r.id),')
  expect(n).toContain("security.pipeline_num_v1('search.refresh_min_gap_minutes', 30)")
  expect(n).toContain("q.requested_by !~ '^(enrich fields task|enrichment plan) '")
  expect(n).toMatch(/^-- Replaces: /m)
  expect(n).toMatch(/^-- Retires: /m)
  expect(ui).toContain('data-plan-needs-person')
  expect(ui).toContain("ov.needs_person||[]")
  expect(tasks).toContain("'Enrichment plan (automatic)'")
})

// v2.15.308 (Platform Admin 21 Oct 2026 18:36, "Two tracks + more credits")
test('two tracks per plan, priority countries, larger shares logged', () => {
  const k = fs.readFileSync('supabase/migrations/20261021230000_cf247_plan_two_tracks.sql', 'utf8')
  expect(k).toContain("foreach v_track in array array['ai', 'fc'] loop")
  expect(k).toContain("case when x->>'step' = 'fields' then 'ai' else 'fc' end = v_track")
  expect(k).toContain("('pipeline', 'plans.priority_countries'")
  expect(k).toContain("s.key = 'plans.priority_countries')) desc,")
  expect(k).toContain("insert into pipeline.admin_control_events(area, action, target, detail, actor)")
  expect(k).toMatch(/^-- Replaces: /m)
  expect(k).toMatch(/^-- Retires: /m)
  expect(ui).toContain('Fill missing fields starts straight away on its own track')
})
