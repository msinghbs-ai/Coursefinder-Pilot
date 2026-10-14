// CF-247 v2.15.278 (S40): waste rules for data enrichment. Platform Admin, 15 Oct 2026 09:18: "If we are wasting resources on multiple tries
// then tighten rules around it, recording, flagging and moving on, rather getting stuck an wasting resources." Decisions: "Auto-pause idle jobs",
// "Yield-based retry cap", "No repeat reads unchanged", "Run admit jobs on new input"; approach "Top 50 by adapter, flag the tail".
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261015010000_cf247_enrichment_waste_rules.sql', 'utf8')
const settingsUi = fs.readFileSync('src/SettingsRegister.jsx', 'utf8')
const toolsets = fs.readFileSync('src/Toolsets.jsx', 'utf8')

test('settings: every waste rule is a setting on Pipeline settings › Waste rules', () => {
  for (const k of ['waste.idle_pause_hours', 'waste.admit_full_check_hours', 'waste.retry_min_yield_pct', 'waste.retry_window_days', 'waste.retry_min_sample',
    'waste.retry_max_attempts', 'waste.flipflop_max_changes', 'waste.flipflop_window_days', 'waste.page_reuse_hours', 'enrich.focus_top_n']) {
    expect(mig).toMatch(new RegExp(`\\('pipeline', '${k.replace('.', '\\.')}', '[^']+', '[^']+', 'number', to_jsonb\\(\\d+\\), \\d+, \\d+, '[^']+', \\d+, '[^']+', 'Waste rules', '[^']+'\\)`))
  }
  expect(mig).toContain("if v_n <> 10 then raise exception 'waste rules post-check: % settings, expected 10', v_n; end if;")
  expect(settingsUi).toContain("'Waste rules':'Stops work that keeps failing or finds nothing")
})

test('records: what is stopped is recorded with why; nothing dropped or deleted', () => {
  expect(mig).toContain('create table if not exists pipeline.enrichment_flags (')
  for (const code of ["'idle_paused'", "'flip_flop'", "'outside_focus'", "'page_not_found'"]) expect(mig).toContain(code)
  // the only drop is the admission function's own temporary working table (unchanged, created again each run)
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b(?! table if exists _adm;)/im)
  for (const t of ['enrichment_flags', 'job_input_marks', 'job_idle_watch', 'enrich_focus_providers']) expect(mig).toContain(`alter table pipeline.${t} enable row level security;`)
})

test('idle jobs pause and resume themselves; only jobs the guard paused are switched on again', () => {
  expect(mig).toContain('perform cron.alter_job(v_jobid, active := false);')
  expect(mig).toContain("elsif not v_active and w.paused_at is not null and coalesce(v_inp, 0) > 0 then")
  expect(mig).toContain("('course-link-reverse',")
  expect(mig).toContain("select cron.schedule('waste-guard', '17 * * * *', 'select security.waste_guard_v1()');")
  expect(mig).toContain("('waste-guard', 'Platform upkeep', 91,")
})

test('admit jobs run on new input, with a full check every few hours', () => {
  for (const j of ['coverage-admit', 'coverage-admit-intakes']) expect(mig).toContain(`command := 'select security.coverage_admission_gated_v1(''${j}'', security.pipeline_num_v1(`)
  expect(mig).toContain("command := 'select security.adapter_overwrite_gated_v1(security.pipeline_num_v1(''batch.adapter_overwrite'', 200)::int)'")
  expect(mig).toContain("return jsonb_build_object('skipped', 'no new input');")
  expect(mig).toContain("security.pipeline_num_v1('waste.admit_full_check_hours', 6)")
})

test('retries stop when further tries rarely succeed; the course is flagged and left', () => {
  expect(mig).toContain("if v_n >= v_sample and 100.0 * v_ok / v_n < v_min then return k - 1; end if;")
  expect(mig).toContain("v_cap int := security.retry_cap_v1('ai_match');")
  expect(mig).not.toMatch(/q\.course_id = co\.id\) < 3/)
})

test('flip-flops: the course page wins over a parent value; repeat changes freeze; a superseded proposal is not raised again', () => {
  expect(mig).toContain("v_mode := case when 'delivery' = any (v_af) and not security.own_page_value_v1(r.child_course_id, 'delivery') then r.parent_mode end;")
  expect(mig).toContain("if 'intakes' = any (v_af) and not security.own_page_value_v1(r.child_course_id, 'intakes') then")
  expect(mig).toContain('insert into pipeline.uni_adapter_delivery_exclusions(course_id, provider_id, active, reason)')
  expect(mig).toContain("i.status='superseded'")
  expect(mig).toContain("insert into pipeline.job_input_marks(job_key) values ('flipflop-guard') on conflict do nothing;  -- changes before now are not counted")
})

test('stored pages are reused; course-page search only at the focus providers; no deadlock between Firecrawl jobs', () => {
  expect(mig).toContain("v_reuse int := security.pipeline_num_v1('waste.page_reuse_hours', 24)::int;")
  expect(mig).toContain('and security.enrich_focus_v1(s.provider_id)')
  expect(mig).toContain('and security.enrich_focus_v1(d.provider_id)')
  expect(mig).toContain('and security.enrich_focus_v1(co.provider_id)')
  expect(mig).toContain("or coalesce(security.coverage_country(p_provider_id), '') <> 'AU'")
  expect(mig).toContain("if not pg_try_advisory_xact_lock(hashtext('cf247:firecrawl_targets_refresh')) then return 0; end if;")
})

test('replaced functions are md5-guarded; notices for paused jobs and frozen values', () => {
  expect(mig).toContain("raise exception 'live % differs from the definition this change replaces', v_sig;")
  expect(mig).toContain("raise exception 'waste rules post-check: % not as intended', v_sig;")
  expect(mig).toContain("'pipeline:0:waste_paused:' || w.jobname")
  expect(toolsets).toContain("case'pipeline:waste_paused':")
  expect(toolsets).toContain("case'pipeline:waste_frozen':")
})
