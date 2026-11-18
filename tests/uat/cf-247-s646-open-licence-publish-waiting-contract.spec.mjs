// Guards: open-licence destination publishing (Platform Admin 18 Nov 2026 13:07 and 14:23): when the one-published-edition index refuses a publication, the approved rows stand and the run records why; replacing the index is a drop and goes to the Platform Admin as a paste file.
// CF-247 S646. supabase/migrations/20261118181500_cf247_open_licence_publish_keeps_approvals.sql.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261118181500_cf247_open_licence_publish_keeps_approvals.sql', 'utf8')

test('a refused publication keeps the approvals and says why; the index change is left to a paste file', () => {
  expect(M).toContain('      exception when unique_violation then')
  expect(M).toContain("v_res := jsonb_build_object('published', false, 'waiting',")
  expect(M).toContain('PASTE-20261118-destination-editions-published-per-owner.sql')
  expect(M).toContain("raise exception 'the ABS population edition must stay published';")
  expect(M).not.toMatch(/^\s*(delete from|drop |truncate )/im)
  expect(M).not.toMatch(/drop\s+index/i)
})
