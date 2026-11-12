// Guards: F-SCH redesign (12 Nov 2026 20:05 audit, directive 12 Nov 2026 16:12 §6 cost per useful result): the version 3 answer limit is a setting, raised inside its range with a recorded reason
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('migration 20261113067000 changes only reading.answer_tokens.scholarship_page, 3000 to 4500, with a control event', () => {
  const m = fs.readFileSync('supabase/migrations/20261113067000_cf247_sch_answer_tokens.sql', 'utf8')
  expect(m.match(/update pipeline\.platform_toolset_settings/g)).toHaveLength(1)
  expect(m).toContain("key = 'reading.answer_tokens.scholarship_page' and value = to_jsonb(3000)")
  expect(m).toContain("set value = to_jsonb(4500)")
  expect(m).toContain("'reading.answer_tokens.scholarship_page 3000 -> 4500'")
})
