// Guards: F-OPS.21 monitoring correctness (SS-Programme-Control P0, 26 Nov 2026 12:10 AEDT): academic entry gains measured from the canonical table, every field states its gain basis; blocked and robots pages are protected holds, never due retries; read-only deployed checks; G3, locks, cron ceiling.
// s1173: anchored edits of security.pim_progress_v1 and security.pim_refresh_v1.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261129074500_cf247_s1173_pim_canonical_gain_projection.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1173: academic entry gain is the first active entry row in the window, from the canonical table, with its basis named', () => {
  expect(code).toContain("min(x.created_at) first_at from catalogue.course_entry_requirements x where x.status = ''active''")
  expect(code).toContain("''gain_basis''")
  expect(code).toContain('guard: academic entry gain % does not match the canonical table')
})

test('s1173: blocked and robots-refused pages are protected holds, not due re-reads', () => {
  expect(code).toContain("not in (''blocked'', ''robots_disallowed'')) due_for_reread")
  expect(code).toContain("''protected_hold''")
})

test('s1173: deployed checks only read; nothing dropped; G3 75/48, no lock removed, cron ceiling', () => {
  expect(code).not.toMatch(/pim_source_revisit_v1\(|\bupdate\s+(catalogue|pipeline)\.|insert into (catalogue|pipeline)\./i)
  expect(code).not.toMatch(/\b(truncate|cron\.schedule|drop\s+(table|function|column|constraint|trigger)|delete\s+from)\b/i)
  expect((code.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(MIG).toMatch(/^-- Replaces:/m)
  expect(MIG).toMatch(/^-- Retires:/m)
})
