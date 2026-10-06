import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('migration 1810 limits study-level and field scholarship scopes to the scholarship\'s own provider and is guarded', () => {
  const m = fs.readFileSync('supabase/migrations/20261006001810_cf247_scholarship_selection_provider_match.sql', 'utf8')
  expect(m).toContain('3ace946099f640874935d9a3237cea73')
  expect(m).toContain('s.provider_id is null or s.provider_id=b.provider_id')
  expect(m).toContain('scholarship_selection_for_course_impl')
  expect(m).toContain("raise exception 'expected snippets not found exactly once'")
  expect(m).not.toMatch(/\b(drop|truncate|cascade)\b/i)
  expect(m).not.toMatch(/delete\s+from/i)
})
