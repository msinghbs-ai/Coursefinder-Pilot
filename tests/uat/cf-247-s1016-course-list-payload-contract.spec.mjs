// Guards: Platform Admin 24 Nov 2026 00:30 AEDT (S1-Build Deployed UAT recovery: the Course list page carries what the list shows: the admission tooltip's 160-character preview, and only the field states the screen names; same rows and order; G3 frozen; nothing dropped)
// s1016: security.course_list_trim_v1 trims each Course list page (admission before and after to the preview; field_states to the named keys when
// the caller names them); security.admin_course_page_fast passes its three returns through it, edited in place from its md5-guarded live definition.
// The layer2-provider deployed check asserts the credential boundary on today's Services & limits screen.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261124001000_cf247_s1016_course_list_payload.sql', 'utf8')

test('s1016: the trim keeps the tooltip preview and only named field states; a caller naming none keeps every field state', () => {
  expect(MIG).toContain('CREATE OR REPLACE FUNCTION security.course_list_trim_v1(p_args jsonb, p_page jsonb)')
  expect((MIG.match(/left\(x #>> '\{last_admitted,(before|after)\}', 160\)/g) || []).length).toBe(2)
  expect(MIG).toContain("when jsonb_typeof(p_args -> 'field_states_keys') = 'array'")
  expect(MIG).toContain('else y end')
  expect(MIG).toContain('order by o)')
  expect(MIG).toContain('revoke all on function security.course_list_trim_v1(jsonb, jsonb) from public, anon, authenticated;')
})

test('s1016: admin_course_page_fast passes each of its three returns through the trim, md5-guarded before and after', () => {
  expect(MIG).toContain("<> '8308868bb7211775018e0136e87241fc' then")
  expect(MIG).toContain("<> 'cd2d1610e25ca4fca3cefc33f77b4dc3' then")
  expect((MIG.match(/return security\.course_list_trim_v1\(p_args, security\.course_list_with_extras_v1\(/g) || []).length).toBe(3)
  expect(MIG).toContain("guard: return % is not found exactly once")
})

test('s1016: no drop or delete; G3, manual locks and cron checked; the provider registry check asserts the credential boundary', () => {
  expect(MIG.replace(/on commit drop/g, '')).not.toMatch(/drop |delete from|truncate /i)
  for (const s of ['guard: the consumer API is not at its baseline before this change', 'post-check: the consumer API moved', 'post-check: manual locks changed', 'post-check: the number of active cron jobs changed']) expect(MIG).toContain(s)
  const l2p = fs.readFileSync('tests/uat/layer2-provider-deployed.spec.mjs', 'utf8')
  expect(l2p).toContain("await expect(row).toContainText(/Credential set|Credential missing|No credential/)")
  expect(l2p).toContain("for(const input of await page.locator('input[type=\"password\"]').all())await expect(input).toHaveValue('');")
  expect(l2p).toContain('not.toMatch(/sb_secret_|service_role|SUPABASE_SERVICE_ROLE_KEY/i)')
  expect(l2p).toContain("drawer.getByText(/Configured in Vault|Not configured/)")
  const qilt = fs.readFileSync('tests/uat/cf-061-qilt-prisms-comparison-deployed.spec.mjs', 'utf8')
  expect(qilt).toContain("page.locator('details[data-ci-fold=\"course\"]').first()")
  expect(qilt).toContain("await expect(page.locator('.ci-outcome-card').first()).toBeVisible()")
})
