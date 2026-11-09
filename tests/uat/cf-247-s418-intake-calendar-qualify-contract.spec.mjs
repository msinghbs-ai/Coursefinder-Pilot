// Guards: F-INT.01/SRC-01 (Platform Admin data population first delivery mandate, 9 Nov 2026): the calendar qualification route (migration 20261109060000) approves an official main teaching calendar by rule only when every safe condition holds, is OFF by default, is a machine decision with evidence and a withdrawal path, never uses central.auto_approve_calendar_dates or changes central.calendar_excluded_words, and is proved on the isolated-PostgreSQL fixture tests/fixtures/intake-calendar-qualify (run by .github/workflows/intake-run-validate-test.yml)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261109060000_cf247_intake_calendar_qualify.sql'
const FX = 'tests/fixtures/intake-calendar-qualify'
const sql = fs.readFileSync(MIG, 'utf8')
const body = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const read = (f) => fs.readFileSync(`${FX}/${f}`, 'utf8')
const fn = (name) => { const a = body.indexOf(`create or replace function ${name}`); return body.slice(a, body.indexOf('$function$;', body.indexOf('as $function$', a) + 13)) }

test('G2 and default off: the switch is a setting that is 0, every setting has a label, range, unit and used_by, and no number is written into the route', () => {
  expect(body).toMatch(/'central\.calendar_qualify_main_teaching'[\s\S]{0,1500}'number', to_jsonb\(0\), 0, 1, 'on\/off'/)
  for (const k of ['batch.calendar_qualify', 'batch.calendar_qualify_refresh', 'batch.calendar_qualify_withdraw', 'central.calendar_qualify_blocked_words', 'central.calendar_qualify_required_words',
    'central.calendar_qualify_blocked_period_words', 'central.calendar_qualify_min_starts', 'central.calendar_qualify_max_series', 'central.calendar_qualify_max_families', 'central.calendar_qualify_max_evidence_age_days'])
    expect(body).toContain(`'${k}'`)
  expect(body).toContain('on conflict (toolset_key, key) do nothing')
  const run = fn('security.calendar_qualify_v1()') + fn('security.calendar_qualify_check_v1(p_proposal_id uuid)') + fn('security.calendar_qualify_withdraw_v1(p_proposal uuid')
  expect(run).not.toMatch(/interval\s+'\d/i)
  expect(run).not.toMatch(/\blimit\s+\d{3,}/i)   // as s32: a limit of 100 or more is a setting; the one-row and twelve-quote limits are structural
  expect(fn('security.calendar_qualify_v1()')).toContain("security.pipeline_num_v1('central.calendar_qualify_main_teaching', 0) <> 1 then return jsonb_build_object('off', true)")
  expect(fn('security.calendar_qualify_v1()')).toContain("security.pipeline_num_v1('batch.calendar_qualify', 25)")
})

test('the two settings the brief keeps apart are never written: central.auto_approve_calendar_dates is not used and central.calendar_excluded_words is only read through calendar_scope_v1', () => {
  expect(body).not.toContain('auto_approve_calendar_dates')
  expect(body).not.toMatch(/update\s+pipeline\.platform_toolset_settings[^;]*calendar_excluded_words/i)
  expect(body).not.toMatch(/insert\s+into\s+pipeline\.platform_toolset_settings[^;]*'central\.calendar_excluded_words'/i)
  expect(fn('security.calendar_qualify_check_v1(p_proposal_id uuid)')).toContain('security.calendar_scope_v1(')
})

test('the verdict is read-only and gives one exact reason, in the order cheap checks first, the dated reader last', () => {
  const chk = fn('security.calendar_qualify_check_v1(p_proposal_id uuid)')
  expect(chk).toMatch(/language sql\s+stable/)
  expect(chk).not.toMatch(/\b(insert|update|delete)\s+(into\s+)?(pipeline|catalogue|public)\./i)
  const reasons = ['not_a_proposed_calendar', 'qualifier_settings_missing', 'platform_admin_rejected_address', 'provider_locked_by_hand', 'host_not_provider_website', 'excluded_by_calendar_scope', 'blocked_word',
    'not_a_calendar_page', 'non_main_period', 'no_evidence', 'no_dated_starts', 'year_not_proved', 'edition_not_current', 'starts_beyond_window', 'too_few_starts', 'evidence_stale',
    'rejected_or_withdrawn_value', 'scope_check_series', 'scope_check_families', 'contradicts_hand_set_calendar', 'contradicts_approved_calendar', 'adds_no_new_value', 'qualifies']
  let at = -1
  for (const r of reasons) { const i = chk.indexOf(`'${r}'`); expect(i, r).toBeGreaterThan(-1) }
  for (const r of ['platform_admin_rejected_address', 'host_not_provider_website', 'blocked_word', 'no_dated_starts', 'rejected_or_withdrawn_value', 'adds_no_new_value', 'qualifies']) { const i = chk.indexOf(`'${r}'`); expect(i, r).toBeGreaterThan(at); at = i }
  expect(chk).toContain('calendar_dated_periods_v2')
  expect(chk).toContain('calendar_proposal_dates_v1')
  expect(chk).toContain('intake_date_rejections')
  expect(chk).toContain("outcome = 'withdrawn'")
})

test('approval is a machine decision with evidence and before/after audit; the route is bounded and chooses its work by index lookups', () => {
  const run = fn('security.calendar_qualify_v1()')
  expect(run).toContain("decided_by = null")
  expect(run).toContain("'system:' || v_rule")
  expect(run).toContain("Machine decision (rule %s, not a person)")
  expect(run).toContain("'approve_machine'")
  for (const f of ['content_hash', 'captured_at', 'edition_year', 'quotes', 'before_state', 'after_state']) expect(run).toContain(f)
  expect(run).toContain('pg_try_advisory_xact_lock')
  expect(run).toMatch(/order by[^;]*limit v_batch/)
  expect(run).toContain('calendar_refresh_requests')
  expect(run).toContain('central.calendar_refresh_credit_budget')
  expect(run).not.toMatch(/net\.http|http_post|openrouter|firecrawl\.|crawl\(/i)   // the read itself is the external worker's; this function only asks, through calendar_refresh_requests
  expect(body).toContain('course_intake_date_events_withdrawn_idx')
})

test('withdrawal: the Platform Admin function needs rank 6, the reading becomes rejected by the named person, the values it admitted go through the governed withdrawal', () => {
  const w = fn('security.calendar_qualify_withdraw_v1(p_proposal uuid')
  expect(w).toContain("status = 'rejected', decided_by = p_actor")
  expect(w).toContain('security.intake_date_withdraw_v1(')
  expect(w).toContain("'withdraw_machine_approval'")
  expect(w).toContain("security.pipeline_num_v1('batch.calendar_qualify_withdraw', 50)")
  expect(fn('public.admin_calendar_qualify_withdraw_v1(')).toContain('security.current_role_rank() < 6')
  expect(body).toContain('grant execute on function public.admin_calendar_qualify_withdraw_v1(uuid, text, boolean) to authenticated')
  expect(body).toContain('revoke all on function security.calendar_qualify_v1() from public, anon, authenticated')
})

test('housekeeping, G1 and G3: Replaces and Retires lines, comment on each new table, no new job (folded into policy-auto-approve), nothing dropped, the consumer API untouched, one md5-guarded edit', () => {
  expect(sql).toMatch(/^-- Replaces: .*policy_auto_approve_v1/m)
  expect(sql).toMatch(/^-- Retires: nothing/m)
  for (const t of ['pipeline.calendar_qualify_decisions', 'pipeline.calendar_qualify_runs']) expect(body).toContain(`comment on table ${t} is`)
  expect(body).not.toMatch(/cron\.schedule/i)
  expect(body).toContain("update pipeline.automation_catalogue set description = description || ' It also runs the calendar qualification route")
  expect(body).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(body).not.toMatch(/(website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\.)\w*\s*\(/)
  expect(sql).toContain('189d5c4349f604653f20c8fc854d1cd1')
  expect(sql).toContain('live security.policy_auto_approve_v1 differs from the definition this change edits')
  expect(sql).toContain('perform security.calendar_qualify_v1();')
  expect(body).toMatch(/-- fixed: /)
})

test('fixtures: every mandatory negative and positive case, production-shaped tables, the guarded refusal, the performance budget, and the CI run', () => {
  const cases = read('cases-after.sql') + read('helpers.sql')
  for (const t of ["'adelaide_online_how_to_apply'", "'wsu_international_college'", "'uts_six_sessions'", "'newcastle_enrolment_repeats_calendar'", "'macquarie_english_pathway'", "'deakin_rejected_value'",
    "'uq_withdrawn_value'", "'unsw_withdrawn_value'", "'federation'", "'canberra'", "'torrens'", 'Semester 1 = 1 March and Semester 2 = 26 July', 'machine decision', 'withdrawal: the reading is rejected by the named person'])
    expect(cases, t).toContain(t)
  expect(read('parity-tables.sql')).toContain('PASS parity: written tables carry the production unique keys, CHECKs, foreign keys, NOT NULL sets and triggers (asserted)')
  const run = read('run.sh')
  for (const t of ['189d5c4349f604653f20c8fc854d1cd1', 'PASS refusal:', 'applied twice without change', 'PASS consumer API frozen', 'perf.sql', 'live-policy-auto-approve.sql']) expect(run, t).toContain(t)
  const perf = read('perf.sql')
  for (const t of ['under 5,000 ms', 'under 2,000 ms', 'under 100 ms', 'does not grow with the volume']) expect(perf, t).toContain(t)
  const wf = fs.readFileSync('.github/workflows/intake-run-validate-test.yml', 'utf8')
  expect(wf).toContain("'tests/fixtures/intake-calendar-qualify/**'")
  expect(wf).toContain('bash tests/fixtures/intake-calendar-qualify/run.sh')
})
