import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('migration 1870 gives the default Evidence view a fast path, guarded on the live definition', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261006001870_cf247_evidence_page_default_view_fast_path.sql', 'utf8')
  expect(m).toContain('9f9c653d52525119c59f9143724366c5')
  expect(m).toContain('security.admin_evidence_page')
  expect(m).toContain('v_fast')
  expect(m).toContain("v_sort='captured' and v_direction='desc'")
  expect(m).toContain("raise exception 'total anchor not unique'")
  expect(m).not.toMatch(/\b(drop|truncate|cascade)\b/i)
})
