// Guards: CF-247 s1114 (S2-AER, Admin #1054): only failed course reads of the 30 named AU providers are read again through the existing course-level reader, stored page, capped by setting; nothing admitted or dropped; G3 75/48 and manual locks checked.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261126130000_cf247_s1114_au_aer_wave1_failed_course_reads_reread.sql', 'utf8')
const code = sql.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')

test('scope is failed course reads only, size from the setting', () => {
  expect(code).toContain("f.state = 'failed'")
  expect(code).toContain("f.state <> 'failed'")
  expect(code).toContain("security.pipeline_num_v1('entry.course_batch_size', 50)")
})
test('uses the existing course reader, no Firecrawl, nothing admitted or dropped', () => {
  expect(code).toContain('security.course_entry_read_enqueue_v1')
  expect(code).toContain('credit_floor_usd')
  expect(code).not.toMatch(/firecrawl/i)
  expect(code.replace(/on commit drop/g, '')).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(code).not.toMatch(/update catalogue|insert into catalogue/i)
  expect(sql).toMatch(/-- Replaces: nothing/)
  expect(sql).toMatch(/-- Retires: nothing/)
})
test('G3 75/48 and manual locks are checked after', () => {
  expect(code).toContain('<> 75')
  expect(code).toContain('<> 48')
  expect(code).toContain('manual locks changed')
})
