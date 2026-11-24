// Guards: UI/UX Unification v1.2 (Platform Admin brief 24 Nov 2026 12:42): the Evidence panel shows a compact metadata strip and opens the saved snapshot inline at once, with a Page and a Text view and a way to find a supplied value (quote) in the page text; the panel's earlier contents and one access call per opened panel are unchanged.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'

const ROW = { id: 'ev-1', evidence_type: 'source_snapshot', mime_type: 'text/html', captured_at: '2026-10-18T02:00:00Z', source_label: 'Alpha University', status: 'active', extraction_state: 'extracted', freshness_state: 'current', observation_count: 0, content_hash: 'abc', storage_available: true }
const SUMMARY = {
  id: 'ev-1', evidence_type: 'source_snapshot', captured_at: '2026-10-18T02:00:00Z', page_url: 'https://alpha.edu.au/courses/master-of-test', layer: 'L2', status: 'active', freshness_state: 'current',
  source: { label: 'Alpha University' }, fetched_via: 'firecrawl', course: { id: 'c1', title: 'Master of Test', code: '012345A', provider: 'Alpha University' },
  accepted: { basis: 'exact_title', in_use: true }, supplied: { total: 2, items: [{ field: 'Fee', value: 'AUD 45,600 a year', status: 'active' }, { field: 'Intake', value: 'July 2099', status: 'active' }] },
  copies: { earlier: 0, later: 0 }, file: { available: true, size_bytes: 2048, mime_type: 'text/html', content_hash: 'abc', storage_path: 'aer-artifacts/u1/page.html' },
}
const PAGE = { evidence_id: 'ev-1', mode: 'preview', mime_type: 'text/html', kind: 'html', file_name: 'page.html', content: '<!doctype html><html><body><h1>Master of Test</h1><style>.x{}</style><p>Tuition is AUD 45,600 a year for 2027.</p><script>window.hacked=1</script></body></html>' }

async function open(page, access) {
  await page.setViewportSize({ width: 1440, height: 900 })
  await mockAdmin(page)
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async r => { const b = r.request().postDataJSON() || {}; if (b.p_operation === 'evidence_page') return r.fulfill({ json: { total: 1, items: [ROW] } }); return r.fallback() })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_evidence_summary', r => r.fulfill({ json: SUMMARY }))
  await page.route('https://example.supabase.co/functions/v1/admin-evidence-access', async r => { access.push(r.request().postDataJSON().mode); return r.fulfill({ json: PAGE }) })
  await page.goto('/#evidence')
  await page.locator('.evidence-table tbody tr').first().click()
  return page.locator('aside.evidence-drawer')
}

test.describe('mocked browser', () => {
  test('metadata strip, instant inline preview, quote lookup, and one access call', async ({ page }) => {
    const access = []; const d = await open(page, access)
    const meta = d.locator('[data-ev-meta]')
    await expect(meta.locator('[data-ev-meta-item="origin"]')).toContainText('AER snapshot')
    await expect(meta.locator('[data-ev-meta-item="format"]')).toContainText('HTML')
    const pv = d.locator('[data-ev-preview="ready"]')
    await expect(pv).toBeVisible()
    await expect(pv.locator('iframe')).toHaveAttribute('sandbox', '')
    await pv.getByRole('tab', { name: 'Text' }).click()
    const text = pv.locator('[data-ev-preview-text]')
    await expect(text).toContainText('Tuition is AUD 45,600 a year')
    await expect(text).not.toContainText('window.hacked')   // scripts and styles are not text
    await expect(text).not.toContainText('.x{}')
    await pv.locator('[data-ev-quote="Fee"]').click()
    await expect(pv.locator('[data-ev-quote-state="found"]')).toBeVisible()
    await expect(text.locator('mark')).toHaveText('AUD 45,600 a year')
    await pv.locator('[data-ev-quote="Intake"]').click()
    await expect(pv.locator('[data-ev-quote-state="missing"]')).toBeVisible()
    await d.getByRole('button', { name: 'View page' }).click()           // reuses the loaded page: no second call
    await expect(page.getByRole('dialog', { name: 'Saved page' })).toBeVisible()
    expect(access).toEqual(['preview'])
  })

  test('phone @responsive: the panel and preview fit the phone', async ({ page }) => {
    expect(page.viewportSize()?.width || 9999).toBeLessThanOrEqual(480)
    const access = []
    await mockAdmin(page)
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async r => { const b = r.request().postDataJSON() || {}; if (b.p_operation === 'evidence_page') return r.fulfill({ json: { total: 1, items: [ROW] } }); return r.fallback() })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_evidence_summary', r => r.fulfill({ json: SUMMARY }))
    await page.route('https://example.supabase.co/functions/v1/admin-evidence-access', async r => { access.push(1); return r.fulfill({ json: PAGE }) })
    await page.goto('/#evidence')
    await page.locator('.evidence-table tbody tr').first().click()
    const pv = page.locator('aside.evidence-drawer [data-ev-preview="ready"]')
    await expect(pv).toBeVisible()
    // the panel slides in, so wait for it to settle before measuring
    const w = page.viewportSize().width
    await expect.poll(async () => { const b = await pv.boundingBox(); return b.x >= 0 && b.x + b.width <= w }).toBe(true)
    expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1)
  })
})
