// Guards: CF-247 decision W34 cached snapshots (Platform Admin 30 Oct 2026 06:53): the four slow admin reads (course_coverage, pipeline_jobs_page, providers_page, courses_page) are fast without loosening any budget; course_coverage answers from a derived, single-flight snapshot that shows when it was built and whether it is stale; drill-downs stay live; permission checks unchanged
// CF-247 W34 (S178). Platform Admin 30 Oct 2026 06:53: "Cached snapshots for the four slow admin reads: APPROVED FOR DESIGN AND IMPLEMENTATION.
// Keep them read-only and derived; no consumer/API or admission behaviour change. Show snapshot generation time and staleness. Define bounded
// refresh/invalidation and prevent expensive concurrent rebuild stampedes. Preserve permission checks and exact live-detail drilldowns. Prove the
// four red deployed tests pass without loosening assertions, increasing timeouts to conceal the problem or skipping live-acting safety controls."
// G1, G2, G3 and housekeeping for this migration are guarded centrally (s42, s32, s57); this file guards the W34 design only.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const DIR = 'supabase/migrations'
const file = fs.readdirSync(DIR).find((f) => f.endsWith('_cf247_admin_read_snapshots.sql'))
const mig = fs.readFileSync(`${DIR}/${file}`, 'utf8')
const refresh = mig.slice(mig.indexOf('create or replace function security.course_coverage_snapshot_refresh_v1'), mig.indexOf('end $function$;', mig.indexOf('create or replace function security.course_coverage_snapshot_refresh_v1')))
const snapshotBranch = mig.slice(mig.indexOf("  elsif p_operation='course_coverage' and exists (select 1 from pipeline.course_coverage_snapshot"), mig.indexOf("  elsif p_operation='course_coverage' then\n    with a as ($n$"))
const replaced = [...mig.matchAll(/array\[\$o\$([\s\S]*?)\$o\$,/g)].map((m) => m[1])

test('course_coverage answers from a derived snapshot; the live re-total stays only as the fallback; drill-downs stay live', () => {
  expect(file, 'the W34 migration').toBeTruthy()
  expect(mig).toContain('Platform Admin 30 Oct 2026 06:53')
  expect(mig).toContain("select pg_temp.edit_n('security.admin_course_coverage_read(text,jsonb)', '0485f037236c3859e3c9f757b8a440eb'")
  // the snapshot branch comes first and never reads the 524,000-row source table; the live re-total follows unchanged as the fallback
  expect(snapshotBranch.length).toBeGreaterThan(1000)
  expect(snapshotBranch).toContain('from pipeline.course_coverage_totals x')
  expect(snapshotBranch).not.toContain('course_attribute_coverage')
  expect(snapshotBranch).toContain("'snapshot',(select jsonb_build_object('source','snapshot','generated_at',h.generated_at,'checked_at',h.checked_at,")
  expect(snapshotBranch).toContain("'stale',h.checked_at < now() - make_interval(mins => v_stale_min)")
  expect(snapshotBranch).toContain("security.pipeline_num_v1('snapshot.course_coverage_stale_minutes',30)")
  expect(mig).toContain("return v||jsonb_build_object('snapshot',jsonb_build_object('source','live','generated_at',now(),'checked_at',now(),'stale',false));")
  // only the course_coverage operation changes: the drill-downs (course_coverage_courses, course_coverage_providers) are not edited
  for (const o of replaced.filter((x) => x.includes('course_coverage'))) expect(o).not.toMatch(/course_coverage_(courses|providers)' then\n\s+(if|return)/)
})

test('the snapshot is rebuilt by one bounded, single-flight job; readers never rebuild', () => {
  expect(refresh).toContain("if not pg_try_advisory_xact_lock(hashtext('cf247:course_coverage_snapshot')) then")
  expect(refresh).toContain("return jsonb_build_object('skipped', 'busy');")
  expect(refresh).toContain("perform set_config('lock_timeout', '2000', true);  -- fixed:")
  expect(refresh).toContain("exception when lock_not_available then\n    return jsonb_build_object('skipped', 'source_build_running');")
  expect(refresh).toContain("update pipeline.course_coverage_snapshot set checked_at = now() where id = 1;\n      return jsonb_build_object('skipped', 'current'")
  expect(refresh).toContain("security.pipeline_num_v1('snapshot.course_coverage_min_interval_minutes', 10)")
  expect(refresh).toContain("return jsonb_build_object('skipped', 'min_interval'")
  // one transaction, no truncate: a reader sees the whole previous or the whole new snapshot
  expect(refresh).toContain('delete from pipeline.course_coverage_totals;')
  expect(refresh).not.toMatch(/^\s*truncate\s/im)
  expect(mig).toContain("select cron.schedule('course-coverage-snapshot', '2-59/5 * * * *', 'select security.course_coverage_snapshot_refresh_v1()');")
  expect(mig).toContain('revoke all on function security.course_coverage_snapshot_refresh_v1(boolean) from public, anon, authenticated;')
  // the read path never writes: the snapshot branch has no insert, update or delete
  expect(snapshotBranch).not.toMatch(/\b(insert into|update pipeline|delete from)\b/i)
})

test('providers_page, courses_page and pipeline_jobs_page choose the page first; same fields, order and total; live md5 guarded', () => {
  expect(mig).toContain("select pg_temp.edit_n('security.admin_course_page_fast_base(jsonb)', 'aa10ef7287e7937e476be26c6f157f91'")
  expect(mig).toContain("select pg_temp.edit_n('security.admin_pipeline_ops_read(text,jsonb)', '898e94c53630aee8e22466b121915e8a'")
  expect(mig).toContain("<> '9ebd485d949649a3959746692efbe511' then")
  // courses: the filters run once into the ids and sort keys; the page's rows are read in full; the order is kept
  expect(mig).toContain('  ), matched as materialized (\n    select b.id,b.canonical_title,b.provider_name,b.field_of_study,b.updated_at,b.last_verified_at from base b')
  expect(mig).toContain("'items',coalesce(jsonb_agg(to_jsonb(e)-'total_count'-'ord' order by e.ord),'[]'::jsonb),")
  // jobs: a register run's earlier batches hidden by one set-based match (v2.15.246 Fix 1); the run totals for the page rows only
  expect(mig).toContain('    ), runs as materialized (\n      select distinct on (j.id) j.id, q.actual_job_id run_last_job_id')
  expect(mig).toContain("select x.*,rq.run_id,rq.run_last_job_id,rq.run_summary,k.total_count,k.ord from keys k join projected x on x.id=k.id")
  expect(mig).toContain("create index if not exists jobs_regulatory_source_created_idx on pipeline.jobs (source_id, created_at) where job_type = 'regulatory_sync';")
  // providers: the counts, the adapter status and the evidence count for the page's rows; the total as before (0 past the end)
  expect(mig).toContain("'items',coalesce((select jsonb_agg((to_jsonb(o)-'ord')||jsonb_build_object('university_groups',security.provider_university_groups(o.id)) order by o.ord) from page o),'[]'::jsonb),")
  expect(mig).toContain("'total',coalesce((select max(total_count) from keys),0),")
  // permission checks are not edited, and the replaced providers function keeps its role check
  for (const o of replaced) expect(o).not.toContain('current_role_rank')
  expect(mig).toContain("if coalesce(v_rank,0)<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;\n\n  return (")
})

test('no budget, assertion or time-out was loosened to make the deployed tests pass', () => {
  const perf = fs.readFileSync('tests/uat/performance-deployed.spec.mjs', 'utf8')
  expect(perf).toContain('const RPC_BUDGET_MS = 3000')
  expect(perf).toContain('const DETAIL_BUDGET_MS = 3000')
  for (const f of ['performance-deployed.spec.mjs', 'cf-209-scheduler-jobs-operations-deployed.spec.mjs', 'cf-247-field-coverage-deployed.spec.mjs']) {
    const src = fs.readFileSync(`tests/uat/${f}`, 'utf8')
    expect(src, f).toContain('assertNoServerErrors(runtime)')
    expect(src, f).not.toMatch(/test\.(skip|fixme)\(/)
  }
})

test.describe('mocked browser', () => {
  test('Completeness shows when the coverage snapshot was built and last checked', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#coverage')
    const note = page.locator('[data-coverage-snapshot="snapshot"]')
    await expect(note).toContainText('Totals from the snapshot built')
    await expect(note).toContainText('last checked against the hourly build')
    await expect(note).toContainText('Course lists opened from these totals are always live.')
    await expect(note).toHaveAttribute('data-stale', 'false')
    await expect(page.locator('[data-snapshot-stale]')).toHaveCount(0)
  })

  test('a stale snapshot is marked in words', async ({ page }) => {
    await mockAdmin(page, { coverageStale: true })
    await page.goto('/#coverage')
    await expect(page.locator('[data-coverage-snapshot]')).toHaveAttribute('data-stale', 'true')
    await expect(page.locator('[data-snapshot-stale]')).toContainText('Stale: not checked for more than 30 minutes, so these numbers may be behind.')
  })
})
