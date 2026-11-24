// Guards: CF-247 s1070 AER mapping gap (Platform Admin / S2-AER brief 24 Nov 2026 16:50, item 1): only the one source-backed alias of an existing qualification (NCUK_IFY long form) is added; no region,
// scope word or blank country is mapped; the re-read is the existing governed one with no Firecrawl; G3 75/48 and manual locks are checked before and after.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261124260000_cf247_s1070_aer_ncuk_ify_alias_reread.sql', 'utf8')
const code = sql.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')

test('one alias of NCUK_IFY, nothing inferred', () => {
  expect(code).toContain("'northern consortium uk international foundation year ncuk ify'")
  expect(code).toContain("code = 'NCUK_IFY'")
  expect((code.match(/update ref\.aer_qualifications/g) || []).length).toBe(2)  // jsonb and array branch of the one edit
  expect(code).not.toMatch(/europe|pacific islands|reading\.entry_global_scope_tokens/i)
})
test('the re-read is the governed one, stored copy, no Firecrawl, nothing dropped', () => {
  expect(code).toContain('public.admin_entry_matrix_reread')
  expect(code).toContain('lock_not_available')
  expect(code).not.toMatch(/firecrawl/i)
  expect(code.replace(/on commit drop/g, '')).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(sql).toMatch(/-- Replaces: nothing/)
  expect(sql).toMatch(/-- Retires: nothing/)
})
test('G3 75/48 and manual locks are checked before and after', () => {
  expect((code.match(/<> 75/g) || []).length).toBe(2)
  expect((code.match(/<> 48/g) || []).length).toBe(2)
  expect(code).toContain('manual locks changed')
})
