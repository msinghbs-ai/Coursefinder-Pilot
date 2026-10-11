// CF-247 v2.15.173 (Decision 251, Platform Admin 4 Oct 2026 01:24): scholarships shown and controlled at each layer —
// sources per country and their use (Layer 1), discovery and reading with the per-run limits (Layer 2), the AI check
// (Layer 3) and the jobs after publishing (Layer 4).
import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { PAGES } from '../../src/nav-map.js'

const read = p => readFileSync(new URL(`../../${p}`, import.meta.url), 'utf8')

// v2.15.243 (Platform Admin, 11 Oct 2026): Layer 3 › Scholarships (AI runs on the retired candidate table) removed
test('nav: a Scholarships tab on Layers 1 and 2; none on Layer 3', () => {
  for (const l of ['layer1', 'layer2']) expect(PAGES[l].tabs.map(t => t.key)).toContain('scholarships')
  expect(PAGES.layer3.tabs.map(t => t.key)).not.toContain('scholarships')
})

test('migration 20261004000300 shaped: settings read by the jobs, roles, reference sites, Platform Admin writes', () => {
  const m = read('supabase/migrations-archive/20261004000300_cf247_scholarship_layer_settings.sql')
  for (const word of ['drop', 'delete from', 'truncate', 'on delete cascade']) expect(m.toLowerCase()).not.toContain(word)
  expect(m).toContain("security.scholarship_setting('discover_limit',6)")
  expect(m).toContain("security.scholarship_setting('read_limit',20)")
  expect(m).toContain("security.scholarship_setting('refill_keep',30)")
  expect(m).toContain("is distinct from 'a1a5a4f3e5849f78300aa3ac3634fc4b'")
  for (const u of ['internationalscholarships.com', 'iefa.org', 'internationalstudent.com', 'edupass.org']) expect(m).toContain(u)
  expect(m).toContain("raise exception 'Platform Admin required'")
  expect(m).toContain("'no reader exists for this source yet; it stays registered'")
  expect(m).not.toMatch(/set\s+publication_status/)
})

// v2.15.243 (Platform Admin, 11 Oct 2026): scholarships come only from providers' own pages; the national register and
// reference sources (Study Australia and others) are no longer listed or added on Layer 1
test('browser: Layer 1 Scholarships — countries only, no register sources', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#layer-1-register?tab=scholarships')
  const c = page.locator('[data-sl-countries]')
  await expect(c.locator('[data-sl-country="NZ"]')).toContainText('NZD')
  await expect(page.locator('[data-sl-sources]')).toHaveCount(0)
  await expect(page.locator('[data-sl-add]')).toHaveCount(0)
})

test('browser: Layer 2 Scholarships — outcomes by country, settings change and job pause', async ({ page }) => {
  await mockAdmin(page)
  page.on('dialog', d => d.accept('Testing a smaller run'))
  await page.goto('/#layer-2-discovery?tab=scholarships')
  const nz = page.locator('[data-sl-l2-country="NZ"]')
  await expect(nz).toContainText('Added as a scholarship')
  await expect(nz).toContainText('Page does not say international students can apply')
  await expect(page.locator('[data-sl-worker]')).toContainText('Find pages')
  const s = page.locator('[data-sl-setting="discover_limit"]')
  await s.getByRole('textbox').fill('4')
  await s.getByRole('button', { name: 'Save' }).click()
  await expect.poll(() => page.l3calls.find(x => x.p_action === 'setting')?.p_args).toMatchObject({ key: 'discover_limit', value: '4' })
  await expect(page.locator('[data-sl-job="scholarship-discover"]')).toContainText('Every 10 minutes')
  await page.getByRole('button', { name: 'Pause Find university scholarship pages' }).click()
  await expect.poll(() => page.l3calls.find(x => x.p_action === 'job')?.p_args).toMatchObject({ jobname: 'scholarship-discover', active: false })
})

test('browser: Layer 3 has no scholarship AI screen; Layer 4 jobs under publishing', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#layer-3-ai?tab=scholarships')
  await expect(page.locator('[data-sl-ai-state]')).toHaveCount(0)
  await page.goto('/#layer-4-review?tab=publishing')
  await expect(page.locator('[data-scholarship-layer="4"] [data-sl-job="scholarship-publication-review"]')).toContainText(/Daily at \d{1,2}:17 ?[ap]m Melbourne time/)
})

test('Firecrawl cap and reserve: Layer 2 settings the worker reads; none left in the code', async ({ page }) => {
  const idx = read('supabase/functions/coverage-sweep/index.ts')
  expect(idx).not.toContain('SCH_FC_CAP')
  expect(idx).not.toMatch(/schLeft > \d/)
  expect(idx).toContain('await rpc("svc_scholarship_fc_budget", {})')
  const m = read('supabase/migrations-archive/20261004000400_cf247_scholarship_firecrawl_cap_setting.sql')
  expect(m).toContain("('firecrawl_cap', 2,")
  expect(m).toContain("('firecrawl_reserve', 2,")
  await mockAdmin(page)
  await page.goto('/#layer-2-discovery?tab=scholarships')
  const c = page.locator('[data-sl-credits]')
  await expect(c).toContainText('304 left of 3,000')
  await expect(c.locator('[data-sl-credit-state]')).toContainText('Close to the cap') // v2.15.243: scraper only, pages wait at the cap
})
