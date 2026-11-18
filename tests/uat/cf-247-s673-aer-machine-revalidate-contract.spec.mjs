// Guards: S673 AER course machine admission re-validation (Platform Admin standing mandate 18 Nov 2026 19:28 AEDT, session S1-AER step 1): the 7-day validation is re-run under the live md5 of security.aer_machine_validate_v1; no switch, threshold (0.8 confidence, 8-character quote), hold or rule changes (Decision 276); a passing validation is recorded, never switches anything on by itself.
// CF-247 S673. Migration 20261118234000_cf247_s673_aer_machine_revalidate.
// G2, G3 and housekeeping are guarded centrally by s32, s57 and s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261118234000_cf247_s673_aer_machine_revalidate.sql', 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')

test('the validation runs only under the live definition checked on 18 Nov and records one audit event', () => {
  expect(M).toContain("v_md5 constant text := '945077fe5dc291cc0893976f8fe65aef'")
  expect(M).toContain("md5(pg_catalog.pg_get_functiondef('security.aer_machine_validate_v1()'::regprocedure)) <> v_md5")
  expect(code(M)).toContain('v := security.aer_machine_validate_v1();')
  expect(code(M).match(/insert into pipeline\.admin_control_events/g)).toHaveLength(1)
  expect(M).toContain("'authority', 'Platform Admin standing mandate 18 Nov 2026 19:28 AEDT (S1-AER step 1)'")
})

test('nothing is switched or loosened: mode, thresholds, holds and AER v1 rules are untouched (Decision 276)', () => {
  const c = code(M)
  expect(c).not.toMatch(/update pipeline\.platform_toolset_settings/i)
  expect(c).not.toMatch(/create\s+(or\s+replace\s+)?(function|table|view|trigger|materialized)/i)
  expect(c).not.toMatch(/layer4_decisions|update pipeline\.layer4_review_items|update catalogue\.|insert into catalogue\.|delete from|drop (table|function)|truncate/i)
  expect(c).toContain("security.pipeline_num_v1('aer.machine_min_confidence', -1) <> 0.8")
  expect(c).toContain("security.pipeline_num_v1('aer.machine_min_quote_chars', -1) <> 8")
  expect(c).toContain('consumer_api_functions_v1()) <> 75')
  expect(c).toContain('consumer_api_relations_v1()) <> 48')
  expect(M).toContain('-- Replaces: nothing. Retires: nothing.')
})
