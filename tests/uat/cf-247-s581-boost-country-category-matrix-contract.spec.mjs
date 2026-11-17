// Guards: Boost priority matrix (Platform Admin 17 Nov 2026 18:02): the setting country_category_boost in pipeline.environment_settings weights every (country, enrichment category) cell over the eight Layer 2/3 categories, with AU, NZ and CA ahead of UK, IE and US in every cell; the functions hold no weight; the matrix orders Boost work only and neither qualifies a model nor changes promotion, the gate or the job
// CF-247 S581. Migration 20261117183000_cf247_boost_country_category_matrix. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261117183000_cf247_boost_country_category_matrix.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const setting = JSON.parse(code.slice(code.indexOf('$json$') + 6, code.lastIndexOf('$json$')))
const CATEGORIES = ['identity_registers', 'geo_localities', 'tuition_fees', 'admissions_entry', 'intakes_delivery', 'study_rules', 'careers_outcomes', 'scholarships_accred']
const cell = (country, category) => setting.cells[`${country}.${category}`] ?? setting.country_weight[country] * setting.category_weight[category]

test('the setting is one environment_settings row with the eight enrichment categories and six countries', () => {
  expect(code).toContain("insert into pipeline.environment_settings (setting_key, category, display_name, setting_value, management_mode, environment_scope,")
  expect(code).toContain("values ('country_category_boost', 'boost',")
  expect(code).toContain('on conflict (setting_key) do nothing;')
  expect(setting.categories).toEqual(CATEGORIES)
  expect(Object.keys(setting.category_weight).sort()).toEqual([...CATEGORIES].sort())
  expect(Object.keys(setting.country_weight)).toEqual(['AU', 'NZ', 'CA', 'UK', 'IE', 'US'])
  expect(setting.tiers).toEqual([['AU', 'NZ', 'CA'], ['UK', 'IE', 'US']])
  expect(setting.country_alias).toEqual({ GB: 'UK' })
})

test('every AU, NZ and CA cell outweighs every UK, IE and US cell, and no weight is below 0', () => {
  const [ahead, behind] = setting.tiers
  const lowestAhead = Math.min(...ahead.flatMap((c) => CATEGORIES.map((g) => cell(c, g))))
  const highestBehind = Math.max(...behind.flatMap((c) => CATEGORIES.map((g) => cell(c, g))))
  expect(lowestAhead).toBeGreaterThan(highestBehind)
  for (const c of Object.keys(setting.country_weight)) for (const g of CATEGORIES) expect(cell(c, g), `${c}.${g}`).toBeGreaterThan(0)
  expect(code).toContain("raise exception 'post-check: AU, NZ and CA are not ahead of UK, IE and US'")
  expect(code).toContain("if not (v->>'ok')::boolean then raise exception 'post-check: the matrix is not valid: %'")
})

test('the functions read every weight from the setting and are closed to anon and authenticated', () => {
  const fns = code.slice(code.indexOf('create or replace function security.boost_country_category_matrix_v1'), code.indexOf('insert into pipeline.component_register'))
  expect(fns).toContain("from pipeline.environment_settings where setting_key = 'country_category_boost'")
  expect(fns).not.toMatch(/\b(100|95|90|50|45|40|0\.\d+)\b/)
  for (const sig of ['boost_country_category_matrix_v1()', 'boost_country_category_weight_v1(text, text)', 'boost_country_category_check_v1()']) {
    expect(code, sig).toContain(`revoke all on function security.${sig} from public, anon, authenticated;`)
    expect(code, sig).toContain(`comment on function security.${sig} is`)
  }
  expect(code).not.toMatch(/grant execute[^;]*(anon|authenticated)/)
  expect((code.match(/'20261117183000'\)/g) || []).length).toBe(3)
})

test('the matrix orders work only: no model is qualified and promotion, the gate and the job are not touched', () => {
  expect(code).not.toMatch(/insert into pipeline\.boost_model_qualifications/)
  expect(code).toContain("if exists (select 1 from pipeline.boost_model_qualifications) then raise exception 'post-check: no model may be qualified by this change'")
  for (const untouched of ['function security.boost_promote_v1', 'function security.boost_ingest_gate_v1', 'cron.schedule', 'cron.alter_job',
    'pipeline.platform_toolset_settings', 'catalogue.courses']) expect(code, untouched).not.toContain(untouched)
  expect(code).not.toMatch(/\b(drop|delete from|truncate)\b/i)
})
