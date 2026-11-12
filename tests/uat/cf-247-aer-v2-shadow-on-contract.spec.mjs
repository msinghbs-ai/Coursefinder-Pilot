// Guards: Decision 276 AER v2 step 1 (Platform Admin 12 Nov 2026 17:20): the shadow trial is switched on deliberately, with the decision as its reason, and changes nothing else
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('only aer.v2_shadow_on changes, from 0 to 1, with the decision as its reason', () => {
  const m = fs.readFileSync('supabase/migrations/20261113113100_cf247_aer_v2_shadow_on.sql', 'utf8')
  expect(m).toMatch(/set value = to_jsonb\(1\)[\s\S]*?reason = 'Decision 276 step 1[^']*'\n where toolset_key = 'pipeline' and key = 'aer\.v2_shadow_on' and value = to_jsonb\(0\)/)
  expect((m.match(/^update /gim) || []).length).toBe(1)
  expect(m).not.toMatch(/^\s*(delete|drop|insert|create)\b/im)
})
