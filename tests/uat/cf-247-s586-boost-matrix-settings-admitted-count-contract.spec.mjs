// Guards: Boost priority matrix and promotion count (Platform Admin 17 Nov 2026 21:18, decisions 2 to 5): the matrix is the boost.matrix.* settings on Settings › Pipeline settings (changed with a reason), over the single category list ref.enrichment_categories, with study_load under Intakes & deadlines and course_description under Course basics; AU, NZ and CA outweigh UK, IE and US in every cell and a change that breaks this is refused; the matrix orders work only and security.boost_promote_v1 does not read it; one batch admits one row per course
// CF-247 S586. Migration 20261117223000_cf247_boost_matrix_settings_and_admitted_count. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations-archive/20261117223000_cf247_boost_matrix_settings_and_admitted_count.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const pairs = (re) => Object.fromEntries([...code.matchAll(re)].map((m) => [m[1], Number(m[2])]))
const country = pairs(/\('([A-Z]{2})', '[A-Za-z ]+', (\d+), \d\)/g)
const category = pairs(/\('([a-z_]+)', (\d\.\d\d)\)/g)
const CATEGORIES = ['course_basics', 'fees', 'entry_requirements', 'intakes_deadlines', 'campus_location', 'provider_profile', 'recognition_registration', 'scholarships']
const promote = code.slice(code.indexOf('create or replace function security.boost_promote_v1'), code.indexOf('insert into pipeline.component_register'))

test('the matrix is settings on Pipeline settings › Boost, with a range, a unit and what uses each', () => {
  expect((code.match(/insert into pipeline\.platform_toolset_settings \(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by\)/g) || []).length).toBe(3)
  expect(code).toContain("'boost.matrix.country_weight.' || c.cc")
  expect(code).toContain("'boost.matrix.category_weight.' || k.category_key")
  for (const key of ['boost.matrix.tier_1', 'boost.matrix.tier_2', 'boost.matrix.country_aliases', 'boost.matrix.lane_categories']) expect(code, key).toContain(`('pipeline', '${key}',`)
  expect(code).toContain("'number', to_jsonb(c.w), 0, 100, 'weight'")
  expect(code).toContain("'number', to_jsonb(w.w), 0, 1, 'weight (0 to 1)'")
  expect((code.match(/'Boost',\s*'security\.boost_/g) || []).length).toBe(6)
  expect(code).not.toMatch(/insert into pipeline\.environment_settings/)
  expect(code).toContain("set status = 'not_applicable'")
})

test('the categories are the single list, and the lanes sit where decided', () => {
  expect(Object.keys(category).sort()).toEqual([...CATEGORIES].sort())
  expect(code).toContain('from ref.enrichment_categories k where k.active')
  expect(code).toContain('"study_load=intakes_deadlines", "course_description=course_basics", "course_fees=fees", "aer_entry=entry_requirements", "provider_accreditations=recognition_registration"')
  for (const old of ['identity_registers', 'geo_localities', 'tuition_fees', 'admissions_entry', 'intakes_delivery', 'study_rules', 'careers_outcomes', 'scholarships_accred']) {
    expect(code.replace("weight_v1('AU', 'tuition_fees') <> 0", ''), old).not.toContain(`'${old}'`)
  }
})

test('every AU, NZ and CA cell outweighs every UK, IE and US cell, and a change that breaks it is refused', () => {
  expect(Object.keys(country)).toEqual(['AU', 'NZ', 'CA', 'UK', 'IE', 'US'])
  expect(code).toContain(`'list', '["AU", "NZ", "CA"]'::jsonb`)
  expect(code).toContain(`'list', '["UK", "IE", "US"]'::jsonb`)
  const cells = (ccs) => ccs.flatMap((c) => CATEGORIES.map((g) => country[c] * category[g]))
  expect(Math.min(...cells(['AU', 'NZ', 'CA']))).toBeGreaterThan(Math.max(...cells(['UK', 'IE', 'US'])))
  expect(Math.min(...cells(Object.keys(country)))).toBeGreaterThan(0)
  expect(code).toMatch(/create constraint trigger boost_matrix_check after insert or update on pipeline\.platform_toolset_settings\s+deferrable initially deferred for each row\s+when \(new\.toolset_key = 'pipeline' and new\.key like 'boost\.matrix\.%'\)\s+execute function security\.boost_matrix_settings_guard_v1\(\);/)
  expect(code).toContain("raise exception 'Boost priority matrix not saved: %'")
  expect(code).toContain("raise exception 'post-check: a tier 2 weight equal to a tier 1 weight was not caught'")
})

test('the functions hold no weight and are closed to anon and authenticated', () => {
  const fns = code.slice(code.indexOf('create or replace function security.boost_country_category_matrix_v1'), code.indexOf('update pipeline.environment_settings'))
  expect(fns).not.toMatch(/\b(100|95|90|50|45|40|0\.\d+|1\.00)\b/)
  for (const sig of ['boost_country_category_matrix_v1()', 'boost_country_category_weight_v1(text, text)', 'boost_lane_category_v1(text)', 'boost_country_category_check_v1()',
    'boost_matrix_settings_guard_v1()']) {
    expect(code, sig).toContain(`revoke all on function security.${sig} from public, anon, authenticated;`)
    expect(code, sig).toContain(`comment on function security.${sig} is`)
  }
  expect(code).not.toMatch(/grant execute[^;]*(anon|authenticated)/)
})

test('the matrix orders work only: promotion does not read it and no model is qualified', () => {
  expect(promote).not.toMatch(/boost_country_category|boost_lane_category|boost\.matrix/)
  expect(code).not.toMatch(/insert into pipeline\.boost_model_qualifications/)
  expect(code).toContain("if exists (select 1 from pipeline.boost_model_qualifications) then raise exception 'post-check: no model may be qualified by this change'")
  for (const untouched of ['function security.boost_ingest_gate_v1', 'cron.schedule', 'cron.alter_job']) expect(code, untouched).not.toContain(untouched)
  expect(code.replace('on commit drop', '').replace('truncate cf_boost_plan', '')).not.toMatch(/\b(drop|delete from|truncate)\b/i)
})

test('one batch admits one row per course: later rows for the same course are refused before anything is written', () => {
  expect(code).toContain("<> '15be1ce6c5c3e4ae4a3bde0063f6f176' then")
  const fix = promote.indexOf("set state = 'refused', note = 'an earlier row of this batch fills this course''s study load'")
  expect(fix).toBeGreaterThan(promote.indexOf('limit v_rows;'))
  expect(fix).toBeLessThan(promote.indexOf('if not p_dry then'))
  expect(promote).toContain("and exists (select 1 from cf_boost_plan f where f.state = 'admitted' and f.lane = p.lane and f.entity_id = p.entity_id and f.id < p.id);")
  expect(promote).toContain("where c.id = p.entity_id and c.study_load is null;")
  expect(promote).not.toContain('updated_at =')
})
