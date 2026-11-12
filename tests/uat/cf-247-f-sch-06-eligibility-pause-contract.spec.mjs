// Guards: F-SCH.01 eligibility reader pause (12 Nov 2026 16:55: false positives found after activation; unsupported claims stay protected, directive 12 Nov 2026 16:12 §14 item 5)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('migration 20261113062000 returns the reader to shadow and withdraws only its live admissions through the existing rule', () => {
  const m = fs.readFileSync('supabase/migrations/20261113062000_cf247_sch_eligibility_pause.sql', 'utf8')
  expect(m).toContain("where toolset_key = 'pipeline' and key = 'sch_elig.apply_on' and value is distinct from to_jsonb(0)")
  expect(m.match(/update pipeline\.platform_toolset_settings/g)).toHaveLength(1)
  expect(m).toContain('select security.scholarship_admission_withdraw_v1(c.admitted_scholarship_id,')
  expect(m).toContain("where r.outcome = 'proven' and r.applied->>'mode' = 'live' and r.applied->>'action' = 'admit' and c.admitted_scholarship_id is not null")
  expect(m).toMatch(/^-- Replaces: the live mode of the eligibility reader \(back to shadow\)\. Retires: nothing\./m)
})
