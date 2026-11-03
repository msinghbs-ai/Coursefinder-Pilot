// Guards: CF-247 D7 CRICOS identity guard (Platform Admin decision pack 3 Nov 2026 21:50 item 7; overnight mandate 21:59 D7): a page is never bound
// to a course by its title alone when the same page is the CRICOS-proved page of another active course of the same provider; shipped off, with a
// read-only evaluation first; a page set by hand, a course locked by hand and a code-proved binding are never touched. The behaviour runs on
// isolated fixtures by tests/fixtures/cricos-identity-guard/run.sh (scratch PostgreSQL; the E16 guard and refusal route as live, checked against
// the live md5s; the migration applied, applied again unchanged; every case asserted).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104360000_cf247_cricos_identity_guard.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/cricos-identity-guard'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')

test('the E16 guard is not edited; the new trigger runs after it and checks the live definition first', () => {
  expect(m).toContain("if md5(pg_get_functiondef('security.coverage_page_refused_host_guard()'::regprocedure)) <> 'f2e4102f8788816c3f22f26945785f55' then")
  expect(m).not.toMatch(/create or replace function security\.(coverage_page_refused_host_guard|binding_refusal_route_v1|course_page_check_v1)\b/)
  expect(m).toContain('create trigger coverage_page_refused_host_zz_cricos before insert or update of url, status, identity_basis on pipeline.coverage_course_pages')
  expect(run).toContain('applied: no existing function changed; applied twice: the second run changed nothing')
  expect(fixtures).toContain("array['coverage_page_refused_host', 'coverage_page_refused_host_zz_cricos']")
})

test('ships off: the switch is a setting at 0 and the trigger returns unchanged while it is off', () => {
  expect(m).toMatch(/'binding\.cricos_identity_guard_on', 'Course pages: refuse a title match on a page that proves another course',[\s\S]*?to_jsonb\(0\), 0, 1/)
  expect(m).toContain("if security.pipeline_num_v1('binding.cricos_identity_guard_on', 0) < 1 then return new; end if;")
  expect(m).toContain("security.pipeline_list_v1('binding.title_identity_bases', '[]'::jsonb)")
  expect(fixtures).toContain("raise notice 'G1 ok")
})

test('when on, a title-only binding on a page that proves another course is refused, recorded and routed; never by hand or locked', () => {
  expect(m).toContain('perform security.binding_refusal_route_v1(new.course_id, new.url,')
  expect(m).toContain("'cricos_identity_refused'")
  expect(m).toMatch(/manual_locks/)
  expect(m).toMatch(/basis[^\n]*'manual'/)
  expect(fixtures).toContain("raise notice 'G3 ok")
})

test('evaluation is read-only and reports what the guard would refuse', () => {
  expect(m).toContain('create or replace function security.cricos_identity_guard_evaluate_v1(p_provider uuid default null) returns jsonb')
  expect(m).toMatch(/cricos_identity_guard_evaluate_v1\(p_provider uuid default null\) returns jsonb\s+language sql stable/)
  expect(fixtures).toContain("raise exception 'G2: the evaluation changed a binding'")
  expect(fixtures).toContain("raise notice 'G2 ok")
})

test('nothing is dropped or deleted', () => {
  expect(m).not.toMatch(/\bdelete from\b|\bdrop (table|function|trigger)\b/i)
  expect(fixtures).toContain("raise notice 'G4 ok")
})
