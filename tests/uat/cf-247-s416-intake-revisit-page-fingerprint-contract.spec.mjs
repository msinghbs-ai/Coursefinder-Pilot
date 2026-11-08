// Guards: F-INT (valid course intake dates; Platform Admin data population first delivery mandate, 9 Nov 2026): a row held for evidence is looked at again on a revisit time from stored inputs only (D3), the inputs fingerprint holds the course page wording (D2), the 5 Nov mandate section 9 stands for every other deterministic failure, course-specific proof is unchanged, G2 (a switch and the existing revisit_days setting, no number in code), G3 (no consumer API object touched), "nothing is dropped by an applied migration".
// Source contract over migration 20261109020000 and the isolated-PostgreSQL fixture tests/fixtures/intake-self-driving (run by .github/workflows/intake-run-validate-test.yml; its result is reported with the branch).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261109020000_cf247_intake_revisit_page_fingerprint.sql'
const FX = 'tests/fixtures/intake-self-driving'
const sql = fs.readFileSync(MIG, 'utf8')
const body = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const read = (f) => fs.readFileSync(`${FX}/${f}`, 'utf8')

test('D3: the four held actions get a revisit time from stored inputs, through one helper and one switch; every other deterministic failure keeps none', () => {
  expect(sql).toMatch(/^-- Replaces: .*intake_revisit_at_v1.*intake_failure_class_trg_v1.*intake_progress_repeats_v1.*intake_dates_plan_v3/m)
  expect(sql).toMatch(/^-- Retires: /m)
  // the one place that names the four actions and reads the switch
  expect(body).toContain("select p_next_action in ('evidence_ambiguous', 'reader_correction_needed', 'calendar_needs_correction', 'human_decision_required')")
  expect(body).toContain("and security.pipeline_num_v1('intake_dates.revisit_stored_inputs', 1) = 1")
  // the revisit time and the trigger edits are guarded by the production definitions and each applies exactly once
  expect(body).toContain("'30790a1cdb910a25012d2cc8fa938dbc'")
  expect(body).toContain("'1ce780aa6cbde2c9a1d9307c3cd68a53'")
  expect(body).toContain("'4f3d0930df6777edb2a915533e379efb'")
  expect(body).toContain("'27f5b2a6573aca6c508cd75ab4b3f151'")
  expect(body).toContain('or security.intake_revisit_stored_inputs_v1(p_next_action)')
  expect(body).toContain('new.next_revisit_at := case when security.intake_revisit_stored_inputs_v1(new.next_action) then security.intake_revisit_at_v1(new.next_action) end;')
  // the old rule is not rewritten for the other classes: the deterministic branch still ends in null for them (the case yields null) and no list of other actions is added
  expect(body).not.toMatch(/awaiting_official_calendar.*intake_revisit_stored_inputs_v1/)
  // the days are the existing setting; the new switch is a setting with a label, a range, a unit and a used_by line
  expect(body).toContain("security.pipeline_num_v1('intake_dates.revisit_days', 14)")
  expect(body).toMatch(/'intake_dates\.revisit_stored_inputs', '[^']+',\s*'[^']+'[\s\S]*?'number', to_jsonb\(1\), 0, 1, 'on\/off', 1013, 'Intake dates',\s*'[^']*intake_revisit_stored_inputs_v1[^']*'/)
  expect(body).toContain('on conflict (toolset_key, key) do nothing')
})

test('D3: a revisit reads stored inputs only and cannot re-admit a rejected, withdrawn or locked value (nothing in the plan is edited for it)', () => {
  // the migration edits the plan in two places only, both the fingerprint; no gate, rule, calendar reading, rejection memory or withdrawn-value guard is touched
  const planEdit = sql.slice(sql.indexOf("select pg_temp.edit('security.intake_dates_plan_v3(uuid[],integer)'"), sql.indexOf('-- 6 rows already waiting'))
  expect(planEdit).toContain('array[1, 1]')
  expect(planEdit).not.toMatch(/intake_date_rejections|withdrawn|manual_locks|intake_course_applicability_v1|page_refused_v1|course_page_check_v1/)
  // no function this migration writes reaches out or queues acquisition work
  expect(body).not.toMatch(/net\.http|http_post|firecrawl|openrouter|crawl\(|svc_pilot_submit|insert into pipeline\.(coverage|enrich|field_enrich|evidence)/i)
  const fx = read('cases-after.sql')
  expect(fx).toContain('PASS no spend (static)')
  expect(fx).toContain('c0 is distinct from c1')                                                                   // the acquisition and spend tables are identical before and after the revisits
  expect(fx).toContain('PASS no re-admission (rejected)')
  expect(fx).toContain('PASS no re-admission (withdrawn, locked)')
  expect(fx).toContain("from pipeline.intake_date_rejections")
  expect(fx).toContain('security.intake_date_withdraw_v1')
  expect(fx).toContain('PASS self-driving: after a person lifts the lock')
})

test('D3: a scheduled look is not a repeat to raise; an unchanged repeat before the time still is', () => {
  expect(body).toContain("when ev.p_revisit is not null and ev.run_at >= ev.p_revisit then 'excluded_scheduled_revisit'")
  expect(body).toContain("'excluded_scheduled_revisit', (select count(distinct k.intake_id) from k where k.status = 'excluded_scheduled_revisit'),")
  expect(body).toContain('array[1, 1, 1]')
  const fx = read('cases-after.sql')
  expect(fx).toContain("(v->>'excluded_scheduled_revisit')::int <> 4")
  expect(fx).toContain("(v->>'confirmed')::int <> 1")
  expect(read('live-repeats-function.sql')).toContain('create or replace function security.intake_progress_repeats_v1()')
  expect(fs.readFileSync('docs/intake-automation-progress.md', 'utf8')).toContain('`excluded_scheduled_revisit`')
})

test('D2: the fingerprint holds an order-insensitive hash of the stored page wording; settled rows keep their place (no storm); a page read after its decision is looked at once', () => {
  expect(body).toContain("string_agg(s, '|' order by s)")
  expect(body).toContain('security.intake_page_wording_v1(p_course, p_evidence, (select e.source_url from pipeline.evidence_artifacts e where e.id = p_evidence))')
  expect(body).toContain("v_settings || ';wording=' || security.intake_wording_fp_v1(r.course_id, r.evidence_id)")
  expect(body).toContain("v_settings || ';wording=' || security.intake_wording_fp_v1(i.course_id, i.evidence_id)")
  // the backfill rewrites only a row that matched the old fingerprint and whose page was not read after the decision
    const bf7 = sql.slice(sql.indexOf("v_settings text := 'lists='"))
  expect(bf7).toContain('where d.inputs_fp = security.intake_inputs_fp_v1(sets.s, i.evidence_id, c.course_url, v_settings)')
  expect(bf7).toContain('g.read_at > d.applied_at')
  expect(bf7).toContain("f.updated_at > d.applied_at")
  const fx = read('cases-after.sql')
  expect(fx).toContain('PASS no storm (fixture-wide)')
  expect(fx).toContain('PASS wording fingerprint (D2)')
  expect(fx).toContain('PASS re-read page (D2)')
})

test('the revisit backfill is bounded to the undated active rows, spread over the revisit days, and writes no date', () => {
  const bf = sql.slice(sql.indexOf('-- 6 rows already waiting'), sql.indexOf('-- 7 rows already settled'))
  expect(bf).toContain("i.status = 'active' and c.lifecycle_status = 'active'")
  expect(bf).toContain('d.next_revisit_at is null and security.intake_revisit_stored_inputs_v1(d.next_action)')
  expect(bf).toContain('hashtextextended(d.intake_id::text, 0)')
  expect(bf).toContain('-- fixed: seconds in a day')
  expect(bf).not.toMatch(/\bset\s+(start_date|intake_year|application_deadline)\b/i)
  expect(bf).not.toMatch(/catalogue\.course_intakes\s+set/i)
})

test('governance: nothing is dropped or deleted, no consumer API object is touched, comments and revokes are present, the fixture is in the workflow', () => {
  expect(body).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(body).not.toMatch(/create or replace function (api|public)\./i)
  expect(body).not.toMatch(/(website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1)/)
  expect(body).toContain('revoke all on function security.intake_revisit_stored_inputs_v1(text) from public, anon, authenticated;')
  expect(body).toContain('revoke all on function security.intake_wording_fp_v1(uuid, uuid) from public, anon, authenticated;')
  for (const f of ['intake_revisit_stored_inputs_v1(text)', 'intake_wording_fp_v1(uuid, uuid)', 'intake_revisit_at_v1(text)', 'intake_failure_class_trg_v1()']) expect(body).toContain(`comment on function security.${f}`)
  // no new table and no new job (G1): nothing to catalogue
  expect(body).not.toMatch(/create table|cron\.schedule/i)
  const wf = fs.readFileSync('.github/workflows/intake-run-validate-test.yml', 'utf8')
  expect(wf).toContain("'tests/fixtures/intake-self-driving/**'")
  expect(wf).toContain('SD_REUSE=1 bash tests/fixtures/intake-self-driving/run.sh | tee intake-self-driving-results.log')
  const run = read('run.sh')
  expect(run).toContain('PASS consumer API frozen')
  expect(run).toContain('PASS migration 20261109020000 applied twice without change')
  expect(run).toContain("'security.intake_dates_plan_v3(uuid[],integer) 27f5b2a6573aca6c508cd75ab4b3f151'")
  expect(run).toContain("'security.intake_progress_repeats_v1() 4f3d0930df6777edb2a915533e379efb'")
})
