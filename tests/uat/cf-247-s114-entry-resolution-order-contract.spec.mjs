// Guards: CF-247 Track C Step B decision 28 Oct 2026 (Platform Admin mandate 20:36; admin docs/platform/ENTRY-REQUIREMENTS-STEP-B-DECISION-2026-10-28.md section 5, plan ENTRY-REQUIREMENTS-IMPLEMENTATION.md 2.4): the five-rule entry resolution over active rows — course override, per-course country row, band ladder, provider minimum, contact the provider; case by case kept; edu_country validated; pure lookup
// Live proof of each rule is the rolled-back fixture dry run recorded in the admin build log (28 Oct 2026); this spec holds the shape.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261028001000_cf247_entry_step_b_course_read_resolver.sql', 'utf8')
const code = m.split('\n').filter(l => !/^\s*--/.test(l)).join('\n')
const fn = code.slice(code.indexOf('create or replace function security.entry_resolve_v1'), code.indexOf('revoke all on function security.entry_resolve_v1'))

test('the five rules run in the approved order and stop at the first that applies', () => {
  const at = s => { const i = fn.indexOf(s); expect(i, s).toBeGreaterThan(0); return i }
  const o1 = at("r.kind = 'override'"), o2 = at("when 2 then m.course_id = c.id"), o3 = at("m.matrix_kind = 'band_ladder' and m.benchmark_band = v_band"),
        o4 = at("m.matrix_kind = 'provider_minimum'"), o5 = at("'rule', 'contact_provider'")
  expect(o1).toBeLessThan(o2); expect(o2).toBeLessThan(o3); expect(o3).toBeLessThan(o4); expect(o4).toBeLessThan(o5)
  expect(fn).toContain("for i in 2 .. 4 loop")
  for (const r of ["'course_override'", "'course_country_row'", "'band_ladder'", "'provider_minimum'", "'contact_provider'"]) expect(fn).toContain(r)
})

test('only active rows are used; proposed and quarantined rows never resolve', () => {
  expect((fn.match(/r\.status = 'active'/g) || []).length).toBeGreaterThanOrEqual(2)
  expect(fn).toContain("m.status = 'active' and m.country_code = v_cc")
  expect(fn).not.toMatch(/status\s*(=|in)\s*\(?'proposed'/)
})

test('the band comes only from an admitted course row; band and provider rows match the course level or its set equivalents', () => {
  expect(fn).toContain("r.benchmark_band is not null and r.audience in ('international', 'all')")
  expect(fn).toContain("if v_band is null then continue; end if;")
  expect(fn).toContain("security.toolset_setting('pipeline', 'entry.level_equivalents')")
  expect(fn).toContain("m.study_level_id = any (v_levels)")
  expect(m).toContain("'entry.level_equivalents', 'Entry resolution: level equivalents'")
})

test('three outcomes kept apart: a published minimum, case by case, contact the provider', () => {
  expect(fn).toContain("'case_by_case', m.min_grade is null or m.grade_scale = 'none'")
  expect(fn).toContain("then 'minimum_published' else 'case_by_case' end")
  expect(fn).toContain("'outcome', 'contact_provider'")
  expect(fn).toContain('The provider publishes a band table for this country, but the course page prints no band to enter it with.')
})

test('edu_country is a known ISO alpha-2 code; nothing is calculated beyond the lookup', () => {
  expect(fn).toContain("if v_cc !~ '^[A-Z]{2}$' or not exists (select 1 from ref.countries k where k.iso_alpha2 = v_cc) then")
  expect(fn).toContain("raise exception 'INVALID_INPUT: edu_country must be a known ISO 3166 alpha-2 country code' using errcode = '22023';")
  expect(fn).toMatch(/language plpgsql stable security definer/)
  expect(fn).not.toMatch(/\b(insert|update|delete)\b/i)
  expect(fn).not.toMatch(/min_value\s*[<>]=?|>=\s*m\.|eligible/i)  // no comparison of a student's grade: resolution only
})
