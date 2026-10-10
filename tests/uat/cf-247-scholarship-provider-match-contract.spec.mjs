import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('migration 1810 limits study-level and field scholarship scopes to the scholarship\'s own provider and is guarded', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261006001810_cf247_scholarship_selection_provider_match.sql', 'utf8')
  expect(m).toContain('3ace946099f640874935d9a3237cea73')
  expect(m).toContain('s.provider_id is null or s.provider_id=b.provider_id')
  expect(m).toContain('scholarship_selection_for_course_impl')
  expect(m).toContain("raise exception 'expected snippets not found exactly once'")
  expect(m).not.toMatch(/\b(drop|truncate|cascade)\b/i)
  expect(m).not.toMatch(/delete\s+from/i)
})

test('migration 1820 adds Canada and NZ scholarship runtime rows switched off and never enables or deletes', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261006001820_cf247_scholarship_runtime_ca_nz_off.sql', 'utf8')
  expect(m).toContain("('CA', false, 25, false, 168, 168")
  expect(m).toContain("('NZ', false, 25, false, 168, 168")
  expect(m).toContain('on conflict (country_code) do nothing')
  expect(m).toContain('"publication_authorised":false')
  expect(m).not.toMatch(/\b(drop|truncate|cascade)\b/i)
  expect(m).not.toMatch(/delete\s+from|do update/i)
})

test('migration 1830 queues review candidates for unscoped Canada and NZ scholarships and creates no links', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261006001830_cf247_scholarship_review_candidates_ca_nz.sql', 'utf8')
  expect(m).toContain('insert into scholarship.course_mapping_candidates')
  expect(m).toContain("k.iso_alpha2 in ('CA', 'NZ')")
  expect(m).toContain('c.provider_id = s.provider_id')
  expect(m).toContain('not exists (select 1 from scholarship.scopes sc where sc.scholarship_id = s.id)')
  expect(m).not.toContain('course_mappings')
  expect(m).not.toMatch(/\b(drop|truncate|cascade)\b/i)
  expect(m).not.toMatch(/delete\s+from|do update/i)
})

test('migration 1840 limits the course blade scholarship context to the scholarship\'s own provider and is guarded', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261006001840_cf247_contextual_scholarships_provider_match.sql', 'utf8')
  expect(m).toContain('60ca16d244029dad671c8d838558fb6b')
  expect(m).toContain('admin_contextual_insights')
  expect(m).toContain('s.provider_id is null or s.provider_id=v_provider')
  expect(m).toContain("raise exception 'expected snippets not found exactly twice'")
  expect(m).not.toMatch(/\b(drop|truncate|cascade)\b/i)
  expect(m).not.toMatch(/delete\s+from/i)
})
