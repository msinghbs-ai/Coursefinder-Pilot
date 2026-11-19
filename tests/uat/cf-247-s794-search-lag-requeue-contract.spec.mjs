// Guards: Platform Admin 19 Nov 2026 23:15 AEDT handover (chat S1-Build, s794): catalogue data the search documents do not show yet is rebuilt through the existing refresh queue, never by writing search documents directly; the one-off covers only the measured lag (48 courses) and changes no table, job or setting.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261119191000_cf247_s794_search_lag_requeue.sql', 'utf8')
const body = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('the lag is queued for the existing search-course-refresh job, once per course', () => {
  expect(body).toContain("insert into search.course_refresh_requests (course_id, requested_at, requested_by)")
  expect(body).toContain("select l.course_id, now(), 's794_projection_lag'")
  expect(body).toContain('where not exists (select 1 from search.course_refresh_requests r where r.course_id = l.course_id and r.processed_at is null);')
  for (const k of ["i.status = 'active'", "e.status = 'active'", 'cd.official_course_url is null and c.course_url is not null', "cd.country_code in ('AU', 'NZ', 'CA')"]) expect(body).toContain(k)
})

test('no search document is written directly, nothing is deleted, and a runaway queue is refused', () => {
  expect(body).not.toMatch(/(insert into|update|delete from)\s+search\.course_documents/i)
  expect(body).not.toMatch(/^\s*(delete|drop|truncate|alter)\b/im)
  expect(body).not.toMatch(/create (table|function|or replace function|index)|cron\.schedule|platform_toolset_settings/i)
  expect(body).toContain("if v_q > 500 then raise exception")
  expect(M).toContain('-- Replaces: nothing. Retires: nothing.')
})
