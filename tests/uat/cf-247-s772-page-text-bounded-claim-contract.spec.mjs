// Guards: page-text claim bounded (Platform Admin 19 Nov 2026 14:24, IQ-00606): the claim walks each country's bound pages in claim order (Boost weight, then course id) through a partial index and stops at its limit, never sorts the whole backlog, never waits for another claim, and keeps the claim rows, items and order it had.
// CF-247 S772. supabase/migrations/20261119150000_cf247_s772_page_text_bounded_claim.sql
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261119150000_cf247_s772_page_text_bounded_claim.sql', 'utf8')
const code = M.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')

test('guarded by the live body md5 and replaces only svc_page_text_next_v1, with the same signature and settings', () => {
  expect(M).toContain("<> '007c7250542efd4de3867223e5c9be2d'")
  expect((code.match(/create or replace function/gi) || []).length).toBe(1)
  expect(M).toContain('create or replace function public.svc_page_text_next_v1(p_limit integer)')
  expect(M).toContain("security definer\n set search_path to ''")
})

test('a partial index of the bound, read pages in course order with their stored page', () => {
  expect(M).toContain("create index if not exists coverage_course_pages_bound_read_course_idx on pipeline.coverage_course_pages (course_id) include (evidence_id)\n  where status = 'bound' and read_status = 'read';")
  expect(M).toContain('comment on index pipeline.coverage_course_pages_bound_read_course_idx is')
})

test('countries in Boost weight order, each walked by course id and stopped at the limit; no whole-set sort', () => {
  expect(M).toContain('order by mx.weight desc, k.iso_alpha2')
  expect(M).toContain('exit when v_found >= v_lim;')
  expect(M).toContain('order by cp.course_id\n             limit v_lim - v_found) z;')
  expect(code).not.toMatch(/order by mx\.weight desc, csort, cp\.course_id\s+limit v_lim\)/)
  expect(M).toContain("where exists (select 1 from catalogue.providers p join catalogue.courses c on c.provider_id = p.id and c.lifecycle_status = 'active' where p.country_id = k.id)")
})

test('the same eligibility checks, claim lease and retry interval; one claim at a time without waiting', () => {
  for (const s of ["x.outcome in ('done', 'too_short')", "x.claimed_at > now() - interval '10 minutes'", "x.claimed_at > now() - interval '1 day'",
    "(c.study_load is null or nullif(btrim(c.description), '') is null)", 'security.provider_hidden_v1', "e.evidence_type = 'source_snapshot' and e.storage_path is not null",
    "t.evidence_type = 'provider_course_page_text'", 'select distinct on (evidence_id) evidence_id, course_id']) expect(M).toContain(s)
  expect(M).toContain("if not pg_try_advisory_xact_lock(hashtext('cf247:page_text_next')) then")
  expect(code).not.toMatch(/perform pg_advisory_xact_lock/)
})

test('no new table or function; nothing dropped; the claim is not called by the deploy; consumer API checked', () => {
  expect(code).not.toMatch(/create table|create (or replace )?function (security|pipeline|api|search|destination|catalogue)\./i)
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(code).not.toMatch(/perform public\.svc_page_text_next_v1|select public\.svc_page_text_next_v1/)
  expect(M).toContain('v_drift := security.consumer_api_check_v1();')
  expect(M).toMatch(/^-- Replaces: /m)
  expect(M).toMatch(/^-- Retires: /m)
})
