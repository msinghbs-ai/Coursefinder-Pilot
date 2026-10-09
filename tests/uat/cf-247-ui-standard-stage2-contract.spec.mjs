// CF-247 v2.15.229, UI stage 2 (Layer 1 register, Layer 2, Coverage, Sources, Platform health): boxed filters keep their
// shape under the standard control style; repeated headers and jargon replaced with plain wording.
import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
const read = p => readFileSync(new URL(`../../${p}`, import.meta.url), 'utf8')

test('Sources: one slim description strip (no repeated title); boxed filter selects fit their box', async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 })
  await mockAdmin(page)
  await page.goto('/#pipeline-sources')
  await expect(page.locator('.ops-workspace-head.slim')).toBeVisible()
  await expect(page.locator('.ops-workspace-head h2')).toHaveCount(0)
  const box = page.locator('.ops-select').first()
  const sel = box.locator('select')
  const [b, s] = await Promise.all([box.boundingBox(), sel.boundingBox()])
  expect(s.y + s.height).toBeLessThanOrEqual(b.y + b.height + 1)
})

test('plain wording on Layer 1 batch runs and alerts', () => {
  const r = read('src/RegulatorySettings.jsx')
  for (const t of ['Layer 1 bounded ingestion', 'Bounded policy', 'Idempotency check', 'Full authoritative depth']) expect(r).not.toContain(t)
  expect(r).toContain('title="Save batch"')
  expect(read('src/layer1-operations-entry.jsx')).toContain('Nothing in Layer 1 needs action.')
})
