// Guards: CF-247 AER live visual acceptance (Platform Admin decision 29 Oct 2026 09:57 item 5): at phone width a matrix row tap opens the drawer with its quote, and the shell notice shows its full text without overlap
import { test, expect } from '@playwright/test'

const NOTICE = [{ level: 'warning', tool: 'OpenRouter', text: 'OpenRouter credit is low: US$7.37 left on the key' }]
const row = i => ({ kind: 'matrix', id: `m${i}`, provider_id: 'p-rmit', provider_name: 'RMIT University (RMIT)', country: 'IN', country_name: 'India', level_label: 'Bachelor degrees', level_code: 'BA', level_name: 'Bachelor',
  matrix_kind: 'band_ladder', qualification: `CBSE Year 12 band ${i}`, band: `${50 + i}%`, min_grade: '75%', min_value: null, scale: 'percentage', conditions: { best_n: 4, subject_minimums: [], alternatives: [] }, audience: 'international',
  edition: '2027', intake_year: null, as_at: '2026-10-26', status: 'active', status_reason: null, quote: `CBSE Year 12 | ${50 + i}% | 75% (row ${i})`, source_url: 'https://www.rmit.edu.au/india', evidence_id: 'ev1', version: 3, manual: false,
  run_id: 'r1', review_item_id: 'li1', review_status: 'approved', created_at: '2026-10-26T10:00:00Z', updated_at: '2026-10-27T10:00:00Z' })
const ROWS = Array.from({ length: 50 }, (_, i) => row(i + 1))
const history = Array.from({ length: 30 }, (_, i) => ({ at: '2026-10-29T08:00:00Z', field: 'edition', action: 'edit', before: '2026', after: '2027', reason: `corrected from the 2027 table (${i + 1})`, actor: 'curator@example.test' }))

// the realistic shell: the signed-in Platform Admin, the OpenRouter low-credit notice, 343 active rows and a list that takes a while to load
async function shell(page, { listDelayMs = 0 } = {}) {
  const { mockAdmin } = await import('./support/admin-mock.mjs')
  await mockAdmin(page, { creditNotices: NOTICE })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_aer', async route => {
    const b = route.request().postDataJSON() || {}, a = b.p_args || {}
    const j = json => route.fulfill({ json })
    if (b.p_action === 'summary') return j({ matrix: { active: 343, proposed: 776, unverified: 20, inactive: 4, superseded: 171 }, course: { proposed: 3 }, sources: { total: 102, held: 15, fetch_failed: 3, reading: 2, read: 84 }, courses_with_active: 0, courses_waiting: 1, can_edit: true, can_reread: true })
    if (b.p_action === 'options') return j({ providers: [{ id: 'p-rmit', name: 'RMIT University (RMIT)' }], countries: [{ code: 'IN', name: 'India' }], statuses: ['active', 'proposed'] })
    if (b.p_action === 'matrix_list') { if (listDelayMs) await new Promise(r => setTimeout(r, listDelayMs)); return j({ total: 343, offset: a.offset || 0, page_size: 50, rows: ROWS }) }
    if (b.p_action === 'row') return j({ ...ROWS.find(r => r.id === a.id), evidence: { id: 'ev1', source_url: 'https://www.rmit.edu.au/india', captured_at: '2026-10-26T09:00:00Z', mime: 'text/html', stored: true }, history, can_edit: true })
    return j({})
  })
}
const table = page => page.locator('table[data-table="aer-matrix"]')

test.describe('phone width', () => {
  test('a matrix row tap opens the drawer with its quote; the shell notice shows its full text without overlap @responsive', async ({ page }) => {
    expect(page.viewportSize().width).toBeLessThan(500)
    const errors = []; page.on('console', m => { if (m.type() === 'error' && !/Failed to load resource|favicon/.test(m.text())) errors.push(m.text()) })
    await shell(page, { listDelayMs: 1500 })
    await page.goto('/#entry-requirements')
    // while the list loads: loading rows only (never a false "No records match"), and they are not record rows
    await expect(table(page).locator('tbody tr[data-skeleton]').first()).toBeVisible()
    await expect(table(page)).not.toContainText('No records match')
    await expect(table(page).locator('tbody tr[data-row]')).toHaveCount(0)
    await expect(table(page).locator('tbody tr[data-row]')).toHaveCount(50)

    // the notice: wrapped, not scrolling; its first letter is clear of the icon and inside the banner
    const banner = page.locator('[data-credit-banner]')
    await expect(banner).toContainText('OpenRouter: OpenRouter credit is low: US$7.37 left on the key')
    await expect(banner).not.toHaveClass(/is-scrolling/)
    const geo = await banner.evaluate(b => {
      const icon = b.querySelector(':scope > svg').getBoundingClientRect(), track = b.querySelector('.cf-credit-track').getBoundingClientRect(), box = b.getBoundingClientRect()
      const strong = b.querySelector('[data-credit-notice] strong'), r = document.createRange(); r.setStart(strong.firstChild, 0); r.setEnd(strong.firstChild, 1)
      const first = r.getBoundingClientRect(), notice = b.querySelector('[data-credit-notice]').getBoundingClientRect()
      return { icon: [icon.left, icon.right, icon.top, icon.bottom], first: [first.left, first.right, first.top, first.bottom], track: [track.left, track.right], box: [box.left, box.right], notice: [notice.left, notice.right], char: strong.textContent[0] }
    })
    expect(geo.char).toBe('O')
    const overlap = !(geo.first[0] >= geo.icon[1] || geo.first[1] <= geo.icon[0] || geo.first[2] >= geo.icon[3] || geo.first[3] <= geo.icon[2])
    expect(overlap, JSON.stringify(geo)).toBe(false)
    expect(geo.first[0]).toBeGreaterThanOrEqual(geo.track[0] - 0.5)  // not cut at the left of the text area
    expect(geo.notice[1]).toBeLessThanOrEqual(geo.track[1] + 0.5)    // nor at the right
    expect(geo.box[1]).toBeLessThanOrEqual(page.viewportSize().width)

    // a row deep in the list, tapped on a middle cell as a person would; nothing lies over the tap point
    const tr = table(page).locator('tbody tr[data-row="m21"]')
    await tr.scrollIntoViewIfNeeded()
    const cell = tr.locator('td').nth(3), bb = await cell.boundingBox()
    const hit = await page.evaluate(([x, y]) => document.elementFromPoint(x, y)?.closest('tr')?.getAttribute('data-row'), [bb.x + Math.min(20, bb.width / 2), bb.y + bb.height / 2])
    expect(hit).toBe('m21')
    await cell.tap()
    const d = page.getByRole('dialog', { name: 'RMIT University (RMIT) · IN' })
    await expect(d).toHaveAttribute('data-aer-drawer', 'matrix')
    await expect(d.locator('[data-aer-quote]')).toContainText('CBSE Year 12 | 71% | 75% (row 21)')
    // full screen, on top, its own scrolling to the last history line, and nothing sideways
    const box = await d.boundingBox()
    expect(box.x).toBeLessThanOrEqual(0.5); expect(box.width).toBeGreaterThanOrEqual(page.viewportSize().width - 1)
    await expect(d.getByRole('button', { name: 'Close detail' })).toBeFocused()
    await d.locator('[data-aer-history] tr').last().scrollIntoViewIfNeeded()
    await expect(d.locator('[data-aer-history]')).toContainText('(30)')
    await expect(d.locator('[data-aer-history] tr').last()).toBeInViewport()
    expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBeLessThanOrEqual(1)
    expect(await d.evaluate(e => e.querySelector('.cf-overlay-body').scrollWidth - e.querySelector('.cf-overlay-body').clientWidth)).toBeLessThanOrEqual(1)
    await page.keyboard.press('Escape')
    await expect(page.locator('[data-aer-drawer]')).toHaveCount(0)
    // the sticky first cell opens it too
    await table(page).locator('tbody tr[data-row="m2"] td.sticky-col').tap()
    await expect(page.locator('[data-aer-drawer="matrix"] [data-aer-quote]')).toContainText('(row 2)')
    expect(errors).toEqual([])
  })
})

test('desktop is unchanged: a notice longer than the banner still scrolls sideways', async ({ page }) => {
  const { mockAdmin } = await import('./support/admin-mock.mjs')
  await mockAdmin(page, { creditNotices: [...NOTICE, { level: 'critical', tool: 'Firecrawl', text: 'Firecrawl credits: 180 left, below the reserve of 500; searches and page reads wait. '.repeat(3) }] })
  await page.goto('/#dashboard')
  await expect(page.locator('[data-credit-banner]')).toHaveClass(/is-scrolling/)
  await expect(page.locator('[data-credit-banner]')).not.toHaveClass(/is-wrapped/)
})
