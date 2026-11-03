// Guards: SS-021 audit F2 (IQ-00077); Platform Admin overnight mandate 3 Nov 2026 21:59 §2 (provider-identity-check constraint fix released separately)
import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const mig = fs.readFileSync('supabase/migrations/20261104180000_cf247_identity_check_issue_values.sql', 'utf8')

test('the identity check writes its issues with values the integration queue accepts', () => {
  expect(mig).toContain(`'root_cause_class', 'data_drift', 'workstream', 'A10',`)
  expect(mig).toContain(`$o$'root_cause_class', 'data', 'workstream', 'G',$o$`)
})

test('a refused issue write is recorded in the run result and never rolls back the run', () => {
  expect(mig).toMatch(/exception when others then\s+v_issues := v_issues \|\| jsonb_build_object\(r\.check_code, 'issue not written: ' \|\| sqlerrm\);/)
})

test('md5-guarded edit from the live definition, each edit applied exactly once', () => {
  expect(mig).toContain(`pg_temp.edit_once('security.provider_identity_check_v1()', 'fe1df994ada824fcd5375fd84680f5be', 'ad78092b0138ca4760528c8bd7c2b8de',`)
  expect(mig).toContain('array[1, 1, 1]')
  expect(fs.existsSync('tests/fixtures/identity-check-values/run.sh')).toBe(true)
})
