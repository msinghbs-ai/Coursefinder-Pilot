// Guards: Global Autonomous PIM step 1 (Platform Admin 25 Nov 2026 21:37): field-state contract with partial completeness and the course, provider, award and country/edition grains; G2, G3, locks, cron.
// s1164: security.field_state_entity_v1 dispatches by the register's grain, adds partial, measures campus_city and the provider fields, and leaves unmeasured fields unmeasured.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261128030000_cf247_s1164_pim_field_state_completion.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1164: completeness is verified, partial, none or unmeasured; partial comes from active rows with no stored evidence', () => {
  expect(code).toContain("'partial'")
  expect(code).toContain("evidence_id is null")
  for (const f of ['english', 'academic_entry', 'intakes', 'campus', 'campus_city']) expect(code).toContain(`'${f}'`)
})

test('s1164: the provider grain reads its own columns; award and country/edition grains are unmeasured until registered', () => {
  for (const f of ['p_address', 'p_contact', 'p_description', 'p_international', 'p_logo', 'p_type', 'p_website', 'p_campuses']) expect(code).toContain(`'${f}'`)
  expect(code).toContain("'grain_not_registered'")
  expect(code).toContain("'field_not_registered'")
  expect(code).not.toContain("when 'p_scholarships'")
})

test('s1164: the live course function is called, not replaced; service role only', () => {
  expect(code).toContain('security.field_state_v1(p_field, p_entity)')
  expect(code).not.toMatch(/create or replace function security\.field_state_v1/)
  expect(code).toContain('grant execute on function security.field_state_entity_v1(text, uuid) to service_role')
})

test('s1164: nothing dropped, G3 75/48, locks and cron guarded', () => {
  expect((code.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(code).not.toMatch(/\b(delete\s+from|truncate|cron\.schedule|drop\s+(table|function|column|constraint))\b/i)
  expect(MIG).toContain('-- Replaces:')
})
