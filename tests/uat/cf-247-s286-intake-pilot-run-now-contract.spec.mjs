// Guards: Platform Admin decision 4 Nov 2026 20:05 (Course Intake Pilot Authority §1 fixed automatically selected 20-course cohort with its evidence,
// §2 reuse intake-dates-apply and its functions, §3 governed Run Now: catalogue, allowlist, rank, reason, pause, switch, cap, one run at a time, record,
// counts, no arbitrary SQL, bounded selector through the job's own path), 20:53 (cohort only from the top Australian universities by active courses)
// and 20:02 (immediate validation §2-§3: the read-back the 10-minute gate uses).
// The behaviour runs on isolated fixtures by tests/fixtures/intake-pilot-run-now/run.sh (scratch PostgreSQL 16; the intake-dates fixture database with
// the live plan and job md5-checked; the migration applied twice). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261104610000_cf247_intake_pilot_run_now.sql', 'utf8')
const scope = fs.readFileSync('supabase/migrations/20261104630000_cf247_intake_pilot_top_au_universities.sql', 'utf8')
const FX = 'tests/fixtures/intake-pilot-run-now'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8') + fs.readFileSync(`${FX}/fixtures2.sql`, 'utf8')

test('§2: the job keeps its command and body; the live definition is md5-guarded before and after', () => {
  expect(m).toContain("md5(pg_get_functiondef('security.intake_dates_apply_v1(integer)'::regprocedure)) <> 'd15c04c680dc0128ca5da33556426c43'")
  expect(m).toContain("<> '90e2250d2bcfda720b00ad93cada20db'")
  expect(m).toContain("<> 'd47fbe685ae62287264a1909c988e9d6'")
  expect(m).toContain('return security.intake_dates_apply_v1(p_limit, null::uuid[]);')
  expect(m).toContain('security.intake_dates_plan_v2(p_course_ids, p_limit)')
  expect(m).toContain("'select security.intake_dates_apply_v1(security.pipeline_num_v1(''batch.intake_dates_apply'', 200)::int)'")
  expect(m).not.toMatch(/cron\.(schedule|alter_job|unschedule)\s*\(/)
  expect(run).toContain('"d15c04c680dc0128ca5da33556426c43 8e3e11c3b78e4e52ea0709e48a666ff6"')
  expect(m).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(m).not.toMatch(/create\s+or\s+replace\s+function\s+(api\.|public\.website_|public\.zoho_)/i)
})

test('§1: the cohort is picked by the job\'s own plan, capped, spread, with evidence and denominator recorded', () => {
  expect(m).toContain('security.intake_dates_plan_v2(null, v_scan)')
  expect(m).toContain("security.pipeline_num_v1('run_now.pilot_cap', 20)")
  expect(m).toContain("security.pipeline_num_v1('run_now.cohort_scan_rows', 1500)")
  expect(m).toContain("row_number() over (partition by provider_id order by cardinality(fills) desc, md5(course_id::text)) rp")
  for (const k of ["'courses_eligible'", "'rows_eligible'", "'skipped_by_reason'", "'page_quote'", "'calendar_url'", "'start_quote'", "'planned'"]) expect(m).toContain(k)
  for (const s of ['PASS cohort: picked by the plan, capped, spread, evidence recorded, nothing written']) expect(fixtures).toContain(s.replace('PASS ', ''))
})

test('§3: Run Now is governed and extends the task mechanism; no SQL text is taken', () => {
  expect(m).toContain("insert into pipeline.admin_job_kinds(kind, label, what, can_pause, added_in)\nvalues ('job_run_now'")
  for (const w of ["'job is not on the Run now list'", "'job is not catalogued'", "'job is paused'", "'job switch is off (Intake dates: on)'", "'a cohort_id is required'",
    "'a run of this job is in progress'", "' courses, over the cap of '", "'requester rank '"]) expect(m).toContain(w)
  expect(m).toContain("pg_try_advisory_xact_lock(hashtext('cf247 intake dates apply'))")
  expect(m).toContain("security.toolset_setting('pipeline', 'run_now.jobs')")
  expect(m).toContain("'list', '[\"intake-dates-apply\"]'::jsonb")
  expect(m).not.toMatch(/execute\s+(p_args|v_|format)/i)
  expect(m).toContain("grant execute on function public.admin_job_run_now_v1(text, text, jsonb) to authenticated;")
  for (const f of ['security.job_run_now_v1(text, text, jsonb, uuid)', 'security.run_now_cohort_create_v1(text, uuid, text, text)', 'security.run_now_cohort_verify_v1(uuid)',
    'security.intake_dates_apply_v1(integer, uuid[])']) expect(m).toContain(`revoke all on function ${f} from public, anon, authenticated;`)
  for (const s of ['refusals: list, rank, reason, pause, switch, cap, cohort, signed-in entry; each recorded, nothing changed', 'idempotency key: the earlier run'])
    expect(fixtures).toContain(s)
  expect(run).toContain('PASS one run at a time: refused while the job\'s lock is held, the holding run returned')
})

test('§4-§5 and 20:02 §2: the run fills through the job\'s own path; the verification reads the website and Zoho back', () => {
  for (const k of ["'processed'", "'admitted'", "'skipped'", "'failed'", "'vendor_calls'", "'published'", "'zoho_checked'", "'not_as_planned'", "'eligible_values'"]) expect(m).toContain(k)
  expect(m).toContain("api.website_v2_course_item(m.course_id) -> 'intakes'")
  expect(m).toContain('public.zoho_edge_course_lookup_v1(m.course_id::text)')
  for (const s of ["run: four courses filled through the job''s own function and publication path; record, idempotency, read-back and totals",
    'scheduled job unchanged in behaviour; nothing is filled twice', "the job''s own publication refresh, for cohort courses only"]) expect(fixtures).toContain(s)
})

test('20:53: the cohort is picked only from the top Australian universities by active courses, recorded, never widened', () => {
  expect(scope).toContain("not in ('0fd43a771a427530995c20f88eb1af1c', '410db5ca480e038e32d12c16f66eefa9')")
  expect(scope).toContain("<> '410db5ca480e038e32d12c16f66eefa9'")
  expect(run).toContain('"0fd43a771a427530995c20f88eb1af1c"')
  expect(scope).toContain("security.pipeline_num_v1('run_now.cohort_top_au_universities', 10)")
  expect(scope).toContain("'run_now.cohort_top_au_universities', 'Run now: Australian universities a cohort is picked from'")
  expect(scope).toContain("join ref.provider_types t on t.id = p.provider_type_id and t.code = 'university'")
  expect(scope).toContain("join ref.countries co on co.id = p.country_id and co.iso_alpha2 = 'AU'")
  expect(scope).toContain('security.intake_dates_plan_v2(v_scope, v_scan)')
  expect(scope).not.toContain('security.intake_dates_plan_v2(null')
  expect(scope).not.toMatch(/canonical_name\s+(i?like|~)/i)
  expect(scope).toContain("row_number() over (partition by provider_id order by cardinality(fills) desc, md5(course_id::text)) rp")
  for (const k of ["'universities'", "'active_courses'", "'eligible_courses'", "'eligible_values'", "'scope_courses'"]) expect(scope).toContain(k)
  expect(scope).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(fixtures).toContain('scope: top Australian universities by active courses only; recorded with counts; a short scope gives a smaller cohort')
})

test('hotfix 20261104640000: the Run Now task outcome uses production outcome codes (admin_jobs_outcome_fkey)', () => {
  const h = fs.readFileSync('supabase/migrations/20261104640000_cf247_run_now_outcome_code.sql', 'utf8')
  expect(h).toContain("'cabacd4094ed138a57f6b102183eeacc'")
  for (const c of ['succeeded_with_result', 'succeeded_no_movement', 'failed_retryable', 'blocked_policy']) expect(h).toContain(`'${c}'`)
  expect(h).toMatch(/^-- Replaces: security\.job_run_now_v1/m)
  expect(h).toMatch(/^-- Retires: nothing/m)
})
