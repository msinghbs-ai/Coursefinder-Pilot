// CF-247 v2.15.268 (S31): Platform Admin, 13 Oct 2026 14:56: "these notification are asking for cant be fixed and if followed the link
// its doesnt open the specific card to adjust the values if required". Chose all four: each notice opens its exact card or setting, says
// plainly whether anything needs doing, lists the universities with the fix in place, and information-only notices stay on Toolsets and limits.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const mig = fs.readFileSync('supabase/migrations/20261013012800_cf247_actionable_notices.sql', 'utf8')

test('migration: held, stopped and no-website notices list their universities; stopped excludes held; nothing dropped', () => {
  expect(mig).toContain("'items', s.items)")
  expect(mig).toContain("'items', jsonb_agg(jsonb_build_object('provider_id', h.provider_id")
  expect(mig).toContain("'items', jsonb_agg(jsonb_build_object('provider_id', d.provider_id")
  expect(mig).toMatch(/where f\.searches > 0\s+and not exists \(select 1 from pipeline\.firecrawl_search_holds h/)
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test.describe('mocked browser', () => {
  test('layer page: only notices that need a person; each says what to do; held search released in the notice', async ({ page }) => {
    page.on('dialog', d => d.accept('Adapter checked: vu.edu.au'))
    await mockAdmin(page)
    await page.goto('/#layer-2-discovery?tab=onboarding')
    const strip = page.locator('[data-layer-notices="2"]')
    await expect(strip.locator('[data-notice="firecrawl:2:daily:scholarships:2026-10-13"]')).toHaveCount(0)
    await expect(strip.locator('[data-layer-notice-infos]')).toContainText('2 information-only notices (nothing to do)')
    const held = strip.locator('[data-notice="firecrawl:2:search_held"]')
    await expect(held.locator('.tn-need')).toContainText('Action needed')
    await held.locator('[data-notice-items] summary').click()
    await held.locator('[data-notice-item="u-vu"]').getByRole('button', { name: 'Search again' }).click()
    await expect.poll(() => page.l3calls.find(c => c.fcResume)).toEqual({ fcResume: 'u-vu', reason: 'Adapter checked: vu.edu.au' })
    const site = strip.locator('[data-notice="firecrawl:2:no_official_site"]')
    await expect(site.locator('.tn-need')).toContainText('Optional')
    await site.locator('[data-notice-items] summary').click()
    await site.getByLabel('Website for Achievers Global Pty Ltd').fill('https://achievers.edu.au')
    await site.locator('[data-notice-item="p-ach"]').getByRole('button', { name: 'Save website' }).click()
    await expect.poll(() => page.l3calls.find(c => c.websiteSet)?.websiteSet).toEqual({ p_provider_id: 'p-ach', p_url: 'https://achievers.edu.au' })
  })

  test('Go to opens the exact card and scrolls to it', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-2-discovery?tab=onboarding')
    await page.locator('[data-notice="firecrawl:2:search_held"] [data-notice-go]').click()
    await expect(page).toHaveURL(/tab=limits/)
    await expect(page.locator('[data-card="services.toolset.firecrawl.credits"]')).toHaveAttribute('data-card-open', 'true')
    await expect(page.locator('[data-fc-refused-uni="u-vu"]')).toBeVisible()
  })

  test('information-only notices on Toolsets and limits: Nothing to do, and Go to opens the Daily budget settings', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#models-services?tab=limits')
    await page.locator('[data-card="services.toolsets"] .cf-card-toggle').click()
    const n = page.locator('[data-toolset-notices] [data-notice="firecrawl:2:daily:scholarships:2026-10-13"]')
    await expect(n.locator('.tn-need')).toContainText('Nothing to do: this work carries on by itself after midnight')
    await expect(n).toHaveClass(/tn-info/)
    await n.locator('[data-notice-go]').click()
    await expect(page).toHaveURL(/at=firecrawl/)
    await expect(page.locator('[data-card="services.toolset.firecrawl"]')).toHaveAttribute('data-card-open', 'true')
    await expect(page.locator('[data-toolset-section="firecrawl:Daily budget"]')).toBeInViewport()
  })
})
