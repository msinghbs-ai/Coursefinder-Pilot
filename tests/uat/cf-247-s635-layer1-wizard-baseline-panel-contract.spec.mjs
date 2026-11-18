// Guards: Platform Admin 18 Nov 2026 10:31, 10:33 and 12:21 (Layer 1 wizard "What this source will create"): step 1 of Layer 1 › + Add source says, before anything is saved, which baseline records the chosen record type creates, the rule each follows and the API v3 fields its mapping fills; the panel writes nothing.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const P = fs.readFileSync('src/Layer1BaselinePreview.jsx', 'utf8')
const W = fs.readFileSync('src/Layer1InductionWizard.jsx', 'utf8')
const M = fs.readFileSync('supabase/migrations-archive/20261118124000_cf247_layer1_induction_v3_fields_baseline.sql', 'utf8')

test('every record type the Layer 1 parser targets name has a panel entry', () => {
  for (const t of ['course_register', 'provider_register', 'campuses', 'provider_accreditations', 'grade_scale_conversions']) {
    if (t !== 'provider_register') expect(M).toContain(`'${t}'`)
    expect(P).toMatch(new RegExp(`\\n  ${t}:\\{creates:`))
  }
  for (const f of ['study_load', 'empty_reason_code', 'is_primary', 'body_code', 'raw_grade_label']) expect(P).toContain(`'${f}'`)
})

test('the panel only describes: no server call, and it sits on the Country & scheme step after the record type', () => {
  expect(P).not.toMatch(/\b(call|rpc|fetch|supabase)\(/)
  expect(P).toContain('Nothing is published, overwritten or deleted')
  expect(W).toMatch(/import Layer1BaselinePreview from ?'\.\/Layer1BaselinePreview'/)
  expect(W.indexOf('data-l1i-record-type')).toBeLessThan(W.indexOf('<Layer1BaselinePreview'))
})

test('mocked browser: choosing a record type shows what the source will create, and changes with the type', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#layer-1-register')
  await page.locator('[data-l1-sources]').getByRole('button', { name: 'Add source' }).click()
  const a = page.locator('[data-l1-induction-wizard]')
  await a.locator('[data-l1i-country]').selectOption('CA')
  await expect(a.locator('[data-l1i-baseline]')).toHaveCount(0)
  await a.locator('[data-l1i-record-type]').selectOption('course_register')
  const b = a.locator('[data-l1i-baseline="course_register"]')
  await expect(b).toContainText('What this source will create for Canada')
  await expect(b).toContainText('only on courses that hold none')
  await expect(b.locator('[data-l1i-baseline-fields]')).toContainText('study_load')
  await expect(b).toContainText('item.study_load')
  await a.locator('[data-l1i-record-type]').selectOption('tuition_fees')
  await expect(a.locator('[data-l1i-baseline="tuition_fees"]')).toContainText('staged for a person to review')
  await expect(a.locator('[data-l1i-baseline="course_register"]')).toHaveCount(0)
})
