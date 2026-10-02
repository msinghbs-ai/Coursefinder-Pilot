// CF-247 Decisions 226+ (v2.15.153): concentrate on intakes and English requirements.
import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'

test('Decision 226: quote failures sent back to Layer 3; tuition retry respects the regulator gate', async () => {
  const m = await fs.readFile('supabase/migrations/20261002182700_cf247_quote_failures_rerun.sql', 'utf8')
  expect(m).toContain("l.field_code in ('course_intake', 'course_english')")
  expect(m).toContain("like 'The AI quoted text that is not on the saved page%'")
  expect(m).toContain("status = 'superseded'")
  expect(m).toContain('9e8d37c5fa530978105e50ceb3a9f3eb')
  expect(m).toContain('security.tuition_chase_enabled((select c.provider_id from catalogue.courses c where c.id=entity_id))')
  expect(m).not.toMatch(/\bdrop\s|delete\s+from|truncate/i)
})
