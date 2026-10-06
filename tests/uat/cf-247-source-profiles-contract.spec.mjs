// v2.15.127 Layer 2 Source profiles: compact list, no internal governance text, no button that leaves the page;
// fetchers for a source are shown, added and tested in its detail panel (moved from Scrapers & fetchers).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

test('source: governance footer, pipeline banner and the routing panel on Scrapers & fetchers are gone', () => {
  const p = fs.readFileSync('src/layer2-platform-entry.jsx', 'utf8')
  expect(p).not.toContain('Governance: {CC}')
  expect(p).not.toContain('Configuration → Acquisition → Evidence')
  expect(p).not.toContain('>Acquisition providers</button>')
  expect(p).toContain("control('upsert_route',{profile_id:profileId,provider_id:p.id")
  const s = fs.readFileSync('src/layer2-provider-entry.jsx', 'utf8')
  expect(s).not.toContain("'Manage routes'")
  expect(s).toContain('Source profiles</strong> on this page') // v2.15.200: Source profiles moved here from Layer 2
})

test.describe('mocked browser', () => {
  test('list, open a source, see its fetchers and add one', async ({ page }) => {
    await mockAdmin(page)
    let routed = null
    await page.route('https://example.supabase.co/functions/v1/layer2-provider-control', r => { routed = r.request().postDataJSON(); return r.fulfill({ status: 200, contentType: 'application/json', body: '{"ok":true}' }) })
    await page.goto('/#scrapers')
    await page.locator('[data-card="scrapers.source-profiles"] .cf-card-toggle').click() // v2.15.200: cards start collapsed
    const list = page.getByRole('region', { name: 'Source profiles' })
    await expect(list.locator('tbody tr')).toHaveCount(2)
    await expect(list).not.toContainText('CF-CHG-')
    await list.getByRole('button', { name: 'RMIT University courses' }).click()
    const f = page.locator('[data-l2-fetchers]')
    await expect(f).toContainText('Direct HTTP')
    await f.getByLabel('Add a fetcher').selectOption({ label: 'Firecrawl' })
    await expect.poll(() => routed && { action: routed.action, profile: routed.payload.profile_id, provider: routed.payload.provider_id, priority: routed.payload.priority }).toEqual({ action: 'upsert_route', profile: 'lp1', provider: 'f1', priority: 20 })
  })
})
