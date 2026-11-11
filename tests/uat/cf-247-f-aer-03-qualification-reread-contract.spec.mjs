// Guards: F-AER.03 country and qualification variants: stored entry pages whose reads dropped international-qualification rows are read again through the governed re-read
// Only sources whose provider has no entry-matrix item waiting for a person are read again (no second item beside a waiting one); active rows stay until a person approves.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261112070000_cf247_aer_qualification_reread.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('the governed re-read is used for exactly the 8 sources with no waiting item, with a reason; nothing else changes', () => {
  expect(code).toContain('v := public.admin_entry_matrix_reread(array[')
  expect((code.match(/'[0-9a-f-]{36}'/g) || []).length).toBe(8)
  expect(code).toContain("'F-AER.03 qualification-first (worker v0.70.0)")
  expect(code).not.toMatch(/\b(update|insert|delete|drop|truncate|alter)\b/i)
  expect(m).toMatch(/^-- Replaces: nothing\. Retires: nothing\./m)
  expect(fs.readdirSync('supabase/migrations').filter((f) => f.startsWith('20261112070000_'))).toEqual(['20261112070000_cf247_aer_qualification_reread.sql'])
})
