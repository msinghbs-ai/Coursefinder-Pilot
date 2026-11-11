// Guards: Platform Admin final intake recovery mandate 5 Nov 2026 12:44 (R1 re-read on a reader change, R2 at most 40 Firecrawl credits in total for the top 10, §6 publication check, §8 relevant calendars only and no global increases, §9 durable failure classes, §10 Process results, §11 production-parity DB tests in CI).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261105040000_cf247_intake_recovery_final.sql', 'utf8')

test('R2: the refresh credit budget is 40 in total, bounded per run, and the existing provider-facts reads do the fetching', () => {
  expect(m).toMatch(/'central\.calendar_refresh_credit_budget'[\s\S]{0,400}'number', to_jsonb\(40\), 0, 40, 'credits'/)
  expect(m).toMatch(/'batch\.calendar_refresh'[\s\S]{0,300}'number', to_jsonb\(1\), 0, 5, 'documents'/)
  expect(m).toContain('exit when v_spent + v_res > v_budget;')
  expect(m).toContain("v_res := greatest(v_each, coalesce((select max(c.credits_used) from pipeline.firecrawl_calls c where c.url = r.url), 0));")
  expect(m).toContain("and not exists (select 1 from pipeline.calendar_refresh_requests q where q.status = 'requested')")   // one open request at a time
  expect(m).toContain("pg_try_advisory_xact_lock(hashtext('cf247.calendar_refresh'))")                                   // one run at a time
  expect(m).toContain('greatest(q.credit_estimate, coalesce(q.credits_used, 0))')
  expect(m).toContain("update pipeline.provider_fact_sources set status = 'found', attempts = 0, updated_at = now() where id = r.id;")
  expect(m).toContain('and not exists (select 1 from pipeline.calendar_refresh_requests q where q.url = f.url)')   // deduplicated
  expect(m).toContain("and f.decided_by is null and f.decision is null")                                         // never a person's binding
  expect(m).toContain("security.calendar_scope_v1('{}'::jsonb, f.url, null) = 'main_teaching'")                 // never college, pathway or offshore
  // no global concurrency or spend increase: no existing batch, concurrency or spend setting is changed
  expect(m).not.toMatch(/update pipeline\.platform_toolset_settings/)
})

test('R1 and §8: a reader change re-reads only needed calendars, most missing rows first; the worker passes its reader', () => {
  expect(m).toContain("where s.reader_version is distinct from p_reader and s.state in ('dated_by_parser', 'read_by_ai', 'no_dates', 'failed', 'sent_to_ai')")
  expect(m).toContain("'not needed: no intake row of this university in the intake scope misses a date'")
  expect(m).toContain('order by (v_rel->>s.provider_id::text)::int desc nulls last')
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  const rr = w.slice(w.indexOf('if (mode === "calendar_reread") {'), w.indexOf('// v0.47.0 (CF-247 Track C'))
  // v0.67.0 (11 Nov 2026): the run size is setting batch.calendar_reread (maximum 100); 100 guards a malformed call only
  expect(rr).toContain('rpc("svc_calendar_reread_next_v2", { p_limit: Math.min(Number(body.limit || 20), 100) /* fixed: guards a malformed call only; the run size is setting batch.calendar_reread (maximum 100) */, p_reader: CALENDAR_READER })')
  expect(rr).toContain('rpc("svc_calendar_refresh_v1", { p_reader: CALENDAR_READER })')
  expect(rr).toContain('paid_reads: 0')
})

test('§9 and §6: every mandated class is named; deterministic failures lose their timer; publication is checked by the existing jobs', () => {
  for (const c of ['no_valid_calendar_source', 'stale_calendar_edition', 'wrong_institution_or_campus', 'course_identity_unresolved', 'calendar_interpretation_failed',
    'academic_year_unproven', 'no_matching_commencement_period', 'multiple_periods_match', 'course_level_exception', 'missing_application_deadline_evidence',
    'admission_held', 'consumer_publication_failed', 'waiting_for_next_academic_year']) expect(m).toContain(`'${c}'`)
  expect(m).toContain('if c.deterministic then new.next_revisit_at := null;')
  expect(m).toContain("'course_identity_unresolved', 'waiting_for_next_academic_year', 'consumer_publication_failed', 'admission_held', 'course_level_exception');")   // timer kept: a removed lock is seen
  expect(m).toContain("select cron.schedule('intake-dates-apply', '26 * * * *', $c$select security.intake_dates_apply_v1(security.pipeline_num_v1('batch.intake_dates_apply', 200)::int); select security.intake_publication_check_v1()$c$);")
  expect(m).toContain("select security.intake_publication_check_v1(); select security.process_results_record_v1(); select security.process_results_recovery_record_v1()")
  expect(m).not.toMatch(/select cron\.schedule\('calendar-refresh'/)   // no new scheduler
})

test('guarded edits by live md5, nothing dropped, and the parity fixture runs in CI', () => {
  for (const [sig, md5] of [['public.admin_process_results_v1(text,jsonb)', '1eadf70533349cdbe605b9e9aee164cb'], ['security.intake_ui_selection_v1(text,integer)', '36ecb3ad4d8fbd7a398e570159dfe4c8'],
    ['security.run_now_cohort_create_v1(text,uuid,text,text)', 'a8b976cbb37c1f92121ed51ce49fa019']]) expect(m).toContain(`'${sig}', '${md5}'`)
  expect(m).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  const wf = fs.readFileSync('.github/workflows/intake-run-validate-test.yml', 'utf8')
  expect(wf).toContain('bash tests/fixtures/intake-recovery-final/run.sh'); expect(wf).toContain('bash tests/fixtures/intake-recovery-final/browser.sh')
  const cases = fs.readFileSync('tests/fixtures/intake-recovery-final/cases.sql', 'utf8')
  for (const k of ['UNSW year-in-heading', 'year from the wrong section rejected', 'college rejected', 'offshore rejected', 'exact course start date', 'unique month', 'multiple periods',
    'missing year', 'old edition not used', 'explicit course date overrides the calendar', 'validated data admitted', 'held data protected', 'publication matches the catalogue',
    'duplicate recovery prevented']) expect(cases).toContain(k)
})
