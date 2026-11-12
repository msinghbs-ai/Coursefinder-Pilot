// Guards: F-SCH.01 eligibility reader activation (Platform Admin 12 Nov 2026 11:50 decision 2: act on evidence-proven cases after validation succeeds, through the existing admission rule; a passing qualification never switches anything on by itself, so activation is its own recorded step)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('migration 20261113061000 switches only sch_elig.apply_on on, records the validation evidence, and re-acts only the shadow proofs', () => {
  const m = fs.readFileSync('supabase/migrations/20261113061000_cf247_sch_eligibility_live.sql', 'utf8')
  expect(m).toContain("where toolset_key = 'pipeline' and key = 'sch_elig.apply_on' and value is distinct from to_jsonb(1)")
  expect(m.match(/update pipeline\.platform_toolset_settings/g)).toHaveLength(1) // silent_resolves and every other switch are untouched
  expect(m).not.toMatch(/silent_resolves'\s*and|key = 'sch_elig\.silent_resolves'/)
  expect(m).toContain("'wrong_admissions_possible', 0")
  expect(m).toContain("where outcome = 'proven' and applied->>'mode' = 'shadow'")
  expect(m).toMatch(/^-- Replaces: the shadow mode of the eligibility reader\. Retires: nothing\./m)
})
