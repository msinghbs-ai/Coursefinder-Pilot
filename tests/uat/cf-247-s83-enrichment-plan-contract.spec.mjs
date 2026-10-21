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
