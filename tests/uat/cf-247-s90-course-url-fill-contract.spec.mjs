// CF-247 NZ brief item 5, Option A (Platform Admin 23 Oct 2026 20:42; built on the 24 Oct 2026 00:35 mandate): course_url filled from a
// proven course-page binding, with the four guards. Contracts on the migration source.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261024001000_cf247_course_url_fill.sql', 'utf8')

test('register, settings with ranges, catalogue row before the schedule, component register', () => {
  expect(m).toMatch(/^-- Replaces: /m); expect(m).toMatch(/^-- Retires: /m); expect(m).not.toMatch(/^\s*(drop|truncate|delete\s+from)\b/im)
  expect(m).toContain('create table if not exists pipeline.course_url_fills (')
  expect(m).toContain('comment on table pipeline.course_url_fills is')
  expect(m).toContain('alter table pipeline.course_url_fills enable row level security;')
  for (const k of ["'course_url.fill_enabled'", "'course_url.max_retraction_pct'", "'batch.course_url_fill'", "'course_url.fill_countries'"]) expect(m).toContain(k)
  expect(m).toContain("'number', '5'::jsonb, '1', '20', '%', 602, 'Official link'")
  expect(m).toContain("'number', '2000'::jsonb, '100', '5000', 'courses', 603, 'Job sizes'")
  expect(m).toContain(`'list', '["NZ"]'::jsonb`)
  expect(m.indexOf("insert into pipeline.automation_catalogue(jobname")).toBeLessThan(m.indexOf("select cron.schedule('course-url-fill'"))
  expect(m).toContain("select cron.schedule('course-url-fill', '23 2 * * *', $$select security.course_url_fill_v1()$$);")
})

test('the four guards are in the fill job', () => {
  // 1 proven binding only, with the country's official_url proof policy
  expect(m).toContain("and p.status = 'bound' and p.identity_basis is not null and p.read_status = 'read' and p.evidence_id is not null")
  expect(m).toContain("and security.coverage_identity_allowed(p.provider_id, p.identity_basis, 'official_url')")
  // 2 manual locks honoured; only an empty course_url is written
  expect(m).toContain("and not exists (select 1 from pipeline.manual_locks m where m.entity = 'course' and m.entity_id = c.id and m.field = 'course_url')")
  expect(m).toContain("where c.id = f.course_id and c.course_url is null")
  // 3 re-fill on binding change: retract, empty only when it still equals the filled value, fill again
  expect(m).toContain("retract_reason = case when p.course_id is null or p.status <> 'bound' then 'page no longer bound' else 'binding changed' end")
  expect(m).toContain("where c.id = g.course_id and c.course_url = g.url")
  expect(m).toContain("on conflict (course_id) do update set url = excluded.url, evidence_id = excluded.evidence_id, identity_basis = excluded.identity_basis, filled_at = v_now, retracted_at = null, retract_reason = null")
  // 4 30-day retraction monitoring pauses the job
  expect(m).toContain("create or replace function security.course_url_retraction_30d_v1() returns jsonb")
  expect(m).toContain("> security.pipeline_num_v1('course_url.max_retraction_pct', 5) then")
  expect(m).toContain("values ('catalogue', 'course_url_fill_paused', 'course_url.fill_enabled', v_rate, null);")
  // an admission is logged
  expect(m).toContain("values ('catalogue', 'course_url_filled', 'courses.course_url',")
})
