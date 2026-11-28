// Guards: DR-19 isolate-record-continue and E16-1 (Platform Admin 2 Nov 2026 07:21) for the site-map binder (coverage-bind, job 47), s1363 (Platform Admin 28 Nov 2026 22:03): each university binds in its own subtransaction under a time budget; rows the ON CONFLICT WHERE never updates are not proposed; an unchanged page is identity-checked once per mapping cycle through the original write; no timeout change, job or queue.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261201161500_cf247_s1363_coverage_bind_provider_isolation.sql', 'utf8')
const body = (name) => {
  const i = sql.indexOf(`create or replace function security.${name}(`)
  expect(i, name).toBeGreaterThan(-1)
  return sql.slice(i, sql.indexOf('$function$;', i))
}

test('s1363: the tick isolates each university and stops on a G2 time budget', () => {
  const t = body('coverage_bind_tick_v1')
  expect(t).toContain("security.pipeline_num_v1('binding.tick_budget_seconds', 50)")
  expect(t).toContain("set_config('cf.coverage_bind_deadline', v_deadline::text, true)")
  expect(t).toMatch(/begin\s+v_res := security\.coverage_bind_v2\(r\.provider_id\);\s+exception when others then/)
  // a timeout is never caught: the budget, not an exception handler, keeps the run under the statement time-out
  expect(t).not.toMatch(/query_canceled/)
  expect(t).toContain("'parked', true")
  // the same eligibility, order and cap as before
  expect(t).toContain('where mapped_at is not null and (bound_at is null or bound_at<mapped_at)')
  expect(t).toContain('order by mapped_at limit greatest(1,least(p_limit,50))')
})

test('s1363: the binder keeps the original checked write for every row it may change', () => {
  const b = body('coverage_bind_v2')
  // the original INSERT ... ON CONFLICT and its WHERE, verbatim, so the E16 trigger checks each written row as before
  expect(b).toContain('on conflict (course_id) do update set url=excluded.url, score=excluded.score, runner_up=excluded.runner_up, basis=excluded.basis,')
  expect(b).toContain("where (pipeline.coverage_course_pages.status not in ('mismatch') or pipeline.coverage_course_pages.url is distinct from excluded.url)")
  expect(b).toContain('where not security.page_refused_v1(b.course_id, b.url);  -- S1: the site-map binder skips refused pages')
  // a row is reused only when the same page was written since this mapping cycle began
  expect(b).toContain("when p.url is not distinct from b.url and p.status in ('bound','ambiguous') and p.bound_at >= v_mapped then 'same'")
  expect(b).toContain('select d.mapped_at from pipeline.coverage_provider_discovery d where d.provider_id = p_provider_id')
  // skip mirrors the ON CONFLICT WHERE exactly (a null there is no update)
  expect(b).toMatch(/when not coalesce\(\(p\.status not in \('mismatch'\) or p\.url is distinct from b\.url\)[\s\S]*?, false\) then 'skip'/)
  // chunks of a G2 size; release and bound_at only after the last chunk
  expect(b).toContain("security.pipeline_num_v1('binding.bind_chunk_rows', 15)")
  expect(b).toMatch(/if not v_partial then[\s\S]*update pipeline\.coverage_provider_discovery set bound_at=now\(\)/)
})

test('s1363: settings exist, live definitions are anchored by md5, guards on G3, locks and jobs, nothing scheduled or dropped', () => {
  for (const k of ["'binding.tick_budget_seconds'", "'binding.bind_chunk_rows'"]) expect(sql).toContain(k)
  expect(sql).toMatch(/used_by[\s\S]*'security\.coverage_bind_tick_v1, security\.coverage_bind_v2 \(s1363\)'/)
  expect(sql).toContain("'56168ae1c9f753ed7dde4092d0c5e16c'")
  expect(sql).toContain("'cb0496b37152c2b819918f1949738c2a'")
  expect(sql).toContain('security.consumer_api_check_v1()')
  expect(sql).toContain('manual locks changed')
  expect(sql).toContain('active job count changed')
  expect(sql).not.toMatch(/statement_timeout/)
  expect(sql).not.toMatch(/cron\.schedule/)
  expect(sql).not.toMatch(/course_page_check_v1\s*\(/)  // the identity check itself is not changed here
  expect(sql).toMatch(/^-- Replaces: /m)
  expect(sql).toMatch(/^-- Retires: nothing/m)
})
