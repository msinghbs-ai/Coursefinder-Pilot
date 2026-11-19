// Guards: Platform Admin 19 Nov 2026 23:12 and 23:21 AEDT (chat S1-Build, s791, IQ-00313 F-INT OPS-01 and VERIFY-01): each intake cohort keeps durable stage counts (fetched, parsed, extracted at selection; verified, admitted, held after each run, with its run id), shown on verify; admission stays with the existing intake job and its no-overwrite, manual-lock and same-month guards.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261120002000_cf247_s790_s791_intake_run_validate.sql', 'utf8')
const body = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('OPS-01: stage counts are kept in an internal table, written at selection and after each run with its run id', () => {
  expect(body).toContain('create table if not exists pipeline.intake_cohort_stages (')
  expect(body).toContain("stage text not null check (stage in ('fetched', 'parsed', 'extracted', 'verified', 'admitted', 'held'))")
  expect(body).toContain('comment on table pipeline.intake_cohort_stages is')
  expect(body).toContain('revoke all on pipeline.intake_cohort_stages from public, anon, authenticated;')
  expect(body).toContain("from (values (1, 'fetched'), (2, 'parsed'), (3, 'extracted')) s(o, stage)")
  expect(body).toContain("from (values (1, 'verified'), (2, 'admitted'), (3, 'held')) s(o, stage)")
  expect(body).toContain('from pipeline.course_intake_date_events ev')
  expect(body).toContain("perform security.intake_cohort_stages_record_v1(c, null);")
  expect(body).toContain("perform security.intake_cohort_stages_record_v1(r.cohort_id, nullif(v_result->>'run_id','')::uuid);")
  expect(body).toContain("exception when others then raise warning 'intake stage counts not recorded")
  expect(body).toContain("'8a6d250362cba7319b3e18086073844e'")
  expect(body).toContain("'d3f2c2445a955f9c6e71fe0a00ab0608'")
})

test('VERIFY-01: verify returns the stage history; admission is the existing job only, never a direct write', () => {
  expect(body).toContain("'stage_history',coalesce((select jsonb_agg(")
  expect(body).toContain("'fa7d47a39f1401e54e751fbfe4de29c9'")
  expect(body).toContain("public.admin_job_run_now_v1('intake-dates-apply'")
  expect(body).not.toMatch(/(insert into|update|delete from)\s+(catalogue\.course_intakes|pipeline\.course_intake_dates\b|pipeline\.manual_locks)/i)
  expect(body).not.toMatch(/intake_dates_apply_v1\s*\(/)
})

test('VERIFY-01: the verify screen shows the stage history with run ids', async ({ page }) => {
  await page.goto('/')
  await page.evaluate(async () => {
    const React = await import('/node_modules/.vite/deps/react.js')
    const { default: ReactDOM } = await import('/node_modules/.vite/deps/react-dom_client.js')
    const { default: Intake } = await import('/src/IntakeRunValidate.jsx')
    const id = '11111111-1111-4111-8111-111111111111'
    const caps = { contract: 'intake-run-validate-v1', can_run: true, control_rank: 6, min_size: 1, max_size: 20, default_size: 20, page_courses: 200, scopes: [], recent: [{ cohort_id: id, created_at: '2026-11-20T00:00:00Z', reason: 'r' }] }
    const report = { cohort_id: id, as_at: '2026-11-20T00:05:00Z', totals: {}, runs: [], courses: [], saved_request: { scope: 'courses:bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', size: 1, reason: 'r', request_key: 'k' },
      stage_history: [{ run_id: null, stage: 'fetched', courses: 2, intakes: 3, recorded_at: '2026-11-20T00:00:00Z' }, { run_id: null, stage: 'parsed', courses: 2, intakes: 3, recorded_at: '2026-11-20T00:00:00Z' },
        { run_id: null, stage: 'extracted', courses: 2, intakes: 3, recorded_at: '2026-11-20T00:00:00Z' }, { run_id: '22222222-2222-4222-8222-222222222222', stage: 'verified', courses: 2, intakes: 3, recorded_at: '2026-11-20T00:04:00Z' },
        { run_id: '22222222-2222-4222-8222-222222222222', stage: 'admitted', courses: 2, intakes: 3, recorded_at: '2026-11-20T00:04:00Z' }, { run_id: '22222222-2222-4222-8222-222222222222', stage: 'held', courses: 0, intakes: 0, recorded_at: '2026-11-20T00:04:00Z' }] }
    const client = { async read(view) { return view === 'capabilities' ? caps : report }, async prepare() { return {} }, async run() { return {} } }
    document.body.innerHTML = '<div id="root"></div>'
    ReactDOM.createRoot(document.getElementById('root')).render(React.default.createElement(Intake, { client, rank: 6 }))
  })
  const h = page.getByTestId('intake-stage-history')
  await expect(h).toBeVisible()
  await expect(h.locator('tbody tr')).toHaveCount(6)
  await expect(h.locator('tr[data-stage="admitted"]')).toContainText('22222222-2222-4222-8222-222222222222')
  await expect(h.locator('tr[data-stage="fetched"]')).toContainText('At selection')
  await expect(page.getByText('Scope: courses:bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')).toBeVisible()
})

const B = fs.readFileSync('supabase/migrations/20261120010000_cf247_s791b_run_now_dispatcher_jobs.sql', 'utf8')
const bBody = B.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('VERIFY-01 (s791b): Run Now and the screen read the live dispatcher target before the cron row; every other Run Now check is unchanged', () => {
  expect(bBody).toContain('create or replace function security.job_schedule_refusal_v1(p_job text)')
  for (const t of ['pipeline.field_execution_registry r where r.kind = \'worker_lane\' and r.mode = \'live\' and r.legacy_job = p_job', 'pipeline.rollup_targets t where t.mode = \'live\' and t.legacy_job = p_job', 'pipeline.admission_rules a where a.mode = \'live\' and a.legacy_job = p_job']) expect(bBody).toContain(t)
  expect(bBody).toContain("'3c769a37828264b0292e13ca02ef6537'")
  expect(bBody).toContain("'d98dd923bb41fde5ef5314bca7d2050c'")
  expect(bBody).toContain('when security.job_schedule_refusal_v1(p_job) is not null then security.job_schedule_refusal_v1(p_job)')
  expect(bBody).not.toMatch(/run_now\.jobs|intake_dates\.apply_enabled|pg_try_advisory_xact_lock|update cron\.job|cron\.(alter_job|schedule|unschedule)/)
  expect(bBody).toContain("raise exception 'cf-s791b-undo';")
  expect(bBody).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
})
