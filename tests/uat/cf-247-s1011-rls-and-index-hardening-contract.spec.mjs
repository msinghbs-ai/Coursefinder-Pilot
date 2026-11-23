// Guards: Platform Admin 23 Nov 2026 20:38 AEDT (S1-Build hardening slice from the architecture audit bundle: row-level security on every application table, saved-courses policies read auth.uid() once, foreign-key indexes; G3 frozen; nothing dropped by a migration).
// s1011: the 93 postgres-owned tables that had row-level security off turn it on (owner and bypass roles unaffected; the one table signed-in users
// read keeps an explicit read policy); the saved-courses policies use (select auth.uid()); two foreign-key indexes are added under a short lock retry.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261123220000_cf247_s1011_rls_and_index_hardening.sql', 'utf8')

test('s1011: row-level security on all 93 tables, including the Zoho credential tables, each under a lock retry', () => {
  const list = MIG.slice(MIG.indexOf('create temp table s1011_rls'), MIG.indexOf(']::text[]) nm;'))
  expect((list.match(/^ {4}'[a-z_]+\.[a-z0-9_]+'/gm) || []).length).toBe(93)
  for (const t of ['private.zoho_integration_credentials', 'private.zoho_integration_rate_windows', 'catalogue.course_identifiers', 'catalogue.provider_qualification_requirements', 'scholarship.audience_readings', 'scholarship.nationality_readings']) expect(list).toContain(`'${t}'`)
  expect(MIG).toContain("execute format('alter table %s enable row level security', t.nm);")
  expect(MIG).toContain("is not owned by postgres; this change was written for postgres-owned tables")
  expect(MIG).toContain('create policy nationality_terms_read on ref.nationality_terms for select to authenticated using (true);')
  expect(MIG).not.toMatch(/force row level security/i)
  expect(MIG).toContain('post-check: a table still has row-level security off')
})

test('s1011: saved-courses policies read auth.uid() once per statement, with the same rows allowed', () => {
  for (const p of ['saved_courses_own_select', 'saved_courses_own_delete']) expect(MIG).toContain(`alter policy ${p} on pipeline.saved_courses using (user_id = (select auth.uid()));`)
  expect(MIG).toContain('alter policy saved_courses_own_insert on pipeline.saved_courses with check (user_id = (select auth.uid()));')
})

test('s1011: two foreign-key indexes, built under a short lock retry; the duplicate indexes go to a paste file, not here', () => {
  expect(MIG).toContain("'create index if not exists course_entry_requirements_country_id_idx on catalogue.course_entry_requirements (country_id)'")
  expect(MIG).toContain("'create index if not exists provider_entry_matrix_study_level_id_idx on catalogue.provider_entry_matrix (study_level_id)'")
  expect(MIG).toContain('exception when lock_not_available then')
  expect(MIG).not.toMatch(/\bdrop\s+index\b/i)
})

test('s1011: G3 guarded before and after, locks and cron unchanged, no job, nothing dropped or deleted', () => {
  expect(MIG).toMatch(/^-- Replaces: /m)
  expect(MIG).toMatch(/^-- Retires: /m)
  expect((MIG.match(/\(v->>'functions'\)::int <> 75|\(v_api->>'functions'\)::int <> 75/g) || []).length).toBe(2)
  expect(MIG).toContain('post-check: manual locks changed')
  expect(MIG).toContain('post-check: the number of active cron jobs changed')
  expect(MIG).not.toMatch(/cron\.(schedule|unschedule|alter_job)|\bdrop (table|function|index|schema|view|trigger|policy)|delete from |truncate /i)
})
