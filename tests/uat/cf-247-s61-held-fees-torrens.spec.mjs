// Guards: CF-247 (S61) 18 Oct 2026: held fees split by group; Torrens doctorates from their own pages (Platform Admin 18:53 choices).
// CF-247 (S61) 18 Oct 2026: held fees split by group; Torrens doctorates from their own pages (Platform Admin 18:53 choices).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const mig = fs.readFileSync('supabase/migrations/20261018120000_cf247_held_fees_and_torrens_items.sql', 'utf8')
test('only Layer 4 items are created; values are written by the person\'s decision; nothing dropped', () => {
  expect(mig).not.toMatch(/insert into catalogue\.|update catalogue\./i)
  expect(mig).not.toMatch(/^(delete|drop|truncate)\b/im)
  expect(mig).toContain("'basis', 'indicative_annual', 'audience', 'international'")
  expect(mig).toContain("abs(h.fee - h.reg) <= 0.05 * h.reg")
  expect(mig).toContain("pg.identity_basis = 'cricos_code'")
  expect(mig).toContain("if a <> 8 then raise exception")
  expect(mig).toContain("if t <> 6 then raise exception")
  expect(mig).toContain("kept for the Platform Admin''s decision (the adapter may not write this value)")
})
