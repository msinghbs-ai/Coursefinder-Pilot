// Guards: F-AER.03 country and qualification variants (decision delivery item 4, 11 Nov 2026): the pending qualification re-reads are recovered without duplicate Layer 4 items
// The governed re-read supersedes each source's own waiting item before queuing the run again, so each source keeps one item; a source whose item a person has taken is left.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261112153700_cf247_aer_qualification_reread_waiting.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('the governed re-read for the 14 remaining sources, leaving any item a person has taken; nothing else changes', () => {
  expect(code).toContain('v := public.admin_entry_matrix_reread(ids,')
  expect((code.match(/'[0-9a-f-]{36}'/g) || []).length).toBe(14)
  expect(code).toContain("and (li.claimed_at is not null or li.assigned_to is not null)")
  expect(code).not.toMatch(/\b(update|insert|delete|drop|truncate|alter)\b/i)
  expect(m).toMatch(/^-- Replaces: nothing\./m)
  expect(m).toMatch(/^-- Retires: nothing\./m)
  expect(fs.readdirSync('supabase/migrations').filter((f) => f.startsWith('20261112153700_'))).toEqual(['20261112153700_cf247_aer_qualification_reread_waiting.sql'])
})
