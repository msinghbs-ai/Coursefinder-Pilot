// Guards: CF-247 s1038 AER provider host aliases (Platform Admin 24 Nov 2026 14:21, S2-RM-Design brief item 1; Standing Authority Charter): the machine admission host rule reads the list setting
// aer.provider_host_aliases ("<provider id>:<host>"), Adelaide University is the only entry, the edit is md5-guarded and anchored, and no other check or consumer object is touched.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261124170000_cf247_s1038_aer_provider_host_aliases_adelaide.sql', 'utf8')

test('the alias is a G2 list setting with Adelaide as its only entry', () => {
  expect(sql).toContain("'aer.provider_host_aliases'")
  expect(sql).toContain("'list', '[\"de2201a1-69ee-40ff-b6aa-0e54e535e6c0:adelaide.edu.au\"]'::jsonb")
  expect(sql).toMatch(/used_by|'security\.aer_matrix_machine_check_v1 \(rule source_not_official_host\)'/)
  expect(sql).not.toContain("pcdn.co:")  // Curtin's CDN host is not aliased
})
test('one md5-guarded anchored edit of the machine check, nothing else replaced', () => {
  expect(sql).toContain('d3d038ebe92f4c3b81c088ed0fbc4169')
  expect(sql).toContain("guard: host condition anchor absent or repeated")
  expect(sql).toMatch(/-- Replaces: nothing/)
  expect(sql).toMatch(/-- Retires: nothing/)
  expect((sql.match(/execute replace/g) || []).length).toBe(1)
  const code = sql.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
  expect(code).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(sql).toContain('75')
  expect(sql).toContain('manual locks changed')
})
