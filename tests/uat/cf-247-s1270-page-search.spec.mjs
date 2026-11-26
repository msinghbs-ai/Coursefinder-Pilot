// Guards: Platform Admin request 26 Nov 2026 (SS-Programme-Control 17:47, "Searchable Admin page navigation and settings"; Operating Model v1.26): a search bar at the top of long Admin pages finds sections, settings (by label, key, what uses them and plain synonyms) and controls, opens the tab and the card, fold or view that holds them, scrolls to the control, highlights it and moves focus there. It reuses the existing page layout, tabs and settings read (no new backend, setting or Consumer API call), and offers only what the signed-in role was given.
// Desktop project (chromium-desktop, 1440 x 1100). Mocked admin plus tests/uat/support/pim-mock.mjs; nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockLaneFunnels } from './support/lane-funnel-mock.mjs'
import { mockPim } from './support/pim-mock.mjs'
import { terms, expand, rank, prepare, dedupe } from '../../src/lib/page-search.js'

const OPERATIONS = '/#layer-2-discovery?tab=operations'
async function openOperations(page, opts = {}) {
  await page.clock.setFixedTime(new Date('2026-11-26T02:10:00Z'))
  const m = await mockAdmin(page, opts); await mockLaneFunnels(page); await mockPim(page)
  await page.goto(OPERATIONS)
  await expect(page.locator('[data-dd-pim]')).toBeVisible({ timeout: 20_000 })
  return m
}
const bar = (page) => page.locator('[data-page-search]')
const input = (page) => page.locator('[data-page-search-input]')
async function search(page, text) { await input(page).fill(text); return page.locator('[data-page-search-results]') }
const inView = (page, sel) => page.evaluate((s) => { const r = document.querySelector(s)?.getBoundingClientRect(); return Boolean(r) && r.top >= 0 && r.bottom <= innerHeight }, sel)

test.describe('matching (pure)', () => {
  test('words, plain synonyms and keys are matched; every word must be found; ranking puts the label first', () => {
    expect(terms('  Batch.Coverage_Admit  ')).toEqual(['batch', 'coverage', 'admit'])
    expect(expand('cap')).toEqual(expect.arrayContaining(['limit', 'ceiling', 'maximum']))
    expect(expand('heartbeat')).toEqual(expect.arrayContaining(['stalled', 'stuck']))
    const E = [
      { id: 'a', kind: 'setting', label: 'Course-page search cap', key: 'search.cap', path: 'Pipeline steps', help: 'Searches wait when the cap would be passed' },
      { id: 'b', kind: 'setting', label: 'Read course pages', key: 'batch.coverage_read', path: 'Job sizes', help: 'Pages read each run' },
      { id: 'c', kind: 'section', label: 'Workers (scheduled jobs)', path: 'Autonomous PIM', keywords: 'stalled stuck last success' },
    ].map(prepare)
    expect(rank(E, 'limit').map((e) => e.id)).toEqual(['a'])           // a synonym of cap
    expect(rank(E, 'batch coverage read').map((e) => e.id)).toEqual(['b']) // the key
    expect(rank(E, 'heartbeat').map((e) => e.id)).toEqual(['c'])        // a synonym of stalled
    expect(rank(E, 'course nothing')).toEqual([])                       // every word must be found
    expect(rank(E, 'read course pages')[0].id).toBe('b')
    expect(dedupe([{ id: '1', kind: 'section', label: 'X', path: 'P' }, { id: '2', kind: 'section', label: 'x', path: 'p' }])).toHaveLength(1)
  })
})

test.describe('Layer 2/3 Operations, Data Delivery and the PIM block', () => {
  test('the bar is at the top of the page, above the Data Delivery block, and is a labelled search field', async ({ page }) => {
    await openOperations(page)
    await expect(bar(page)).toBeVisible()
    await expect(bar(page)).toHaveAttribute('role', 'search')
    await expect(input(page)).toHaveAttribute('role', 'combobox')
    const b = await bar(page).boundingBox(), dd = await page.locator('[data-dd-pim]').boundingBox()
    expect(b.y, 'the bar sits above the Data Delivery block').toBeLessThan(dd.y)
  })

  test('"stalled" finds Workers; choosing it opens the PIM matrix view, scrolls to the table heading, highlights it and moves focus', async ({ page }) => {
    await openOperations(page)
    await page.locator('[data-pim-tab="refresh"]').click()                  // start on another view: the jump must switch back
    const list = await search(page, 'stalled')
    const hit = list.locator('[data-ps-id="pim:sec:workers"]')
    await expect(hit).toBeVisible()
    await expect(hit).toContainText('Section')
    await expect(hit).toContainText('Data Delivery › Autonomous PIM')
    await hit.locator('button').click()
    await expect(page.locator('[data-pim-view="matrix"]')).toBeVisible()
    const target = page.locator('[data-pim-section="workers"]')
    await expect(target).toHaveClass(/ps-hit/)
    await expect.poll(() => inView(page, '[data-pim-section="workers"]')).toBe(true)
    await expect(target).toBeFocused()
    await expect(page.locator('[data-page-search-msg]')).toContainText('Opened')
    const c = await page.evaluate(() => ({ top: document.querySelector('[data-pim-section="workers"]').getBoundingClientRect().top, bar: document.querySelector('[data-page-search]').getBoundingClientRect().bottom }))
    expect(c.top, 'the heading is clear of the bar, including its status line').toBeGreaterThanOrEqual(c.bar)
    await expect(target).not.toHaveClass(/ps-hit/, { timeout: 8000 })    // the highlight fades
  })

  test('a synonym finds the section: "heartbeat" finds Workers, "website delivery" finds Verified consumer read-back, "stale country" finds Freshness by country', async ({ page }) => {
    await openOperations(page)
    await expect((await search(page, 'heartbeat')).locator('[data-ps-id="pim:sec:workers"]')).toBeVisible()
    await expect((await search(page, 'website delivery')).locator('[data-ps-id="pim:sec:consumer"]')).toBeVisible()
    await expect((await search(page, 'stale country')).locator('[data-ps-id="pim:sec:fresh-country"]')).toBeVisible()
  })

  test('a section in a closed view opens that view: Freshness by country opens Refresh & maintenance and lands on its heading', async ({ page }) => {
    await openOperations(page)
    await expect(page.locator('[data-pim-fresh-by-country]')).toHaveCount(0)
    const list = await search(page, 'freshness by country')
    await list.locator('[data-ps-id="pim:sec:fresh-country"] button').click()
    await expect(page.locator('[data-pim-view="refresh"]')).toBeVisible()
    await expect(page.locator('[data-pim-section="fresh-country"]')).toHaveClass(/ps-hit/)
    await expect.poll(() => inView(page, '[data-pim-section="fresh-country"]')).toBe(true)
  })

  test('a view is a result of its own: Requests & feedback', async ({ page }) => {
    await openOperations(page)
    await (await search(page, 'requests feedback')).locator('[data-ps-id="pim:view:requests"] button').click()
    await expect(page.locator('[data-pim-view="requests"]')).toBeVisible()
    await expect(page.locator('[data-pim-panel="requests"]')).toHaveClass(/ps-hit/)
  })

  test('a Data Delivery stream is found by its title and opened', async ({ page }) => {
    await openOperations(page)
    const list = await search(page, 'provider descriptions')
    const hit = list.locator('[data-ps-kind="section"]').filter({ hasText: 'Provider descriptions' }).first()
    await expect(hit).toBeVisible()
    await hit.locator('button').click()
    const stream = page.locator('[data-dd-stream="pdesc"]')
    await expect(stream).toHaveAttribute('open', '')
    await expect(stream).toHaveClass(/ps-hit/)
  })

  test('another tab of the page is a result and opens through the existing route', async ({ page }) => {
    await openOperations(page)
    const list = await search(page, 'flags')
    const tab = list.locator('[data-ps-id="tab:flags"]')
    await expect(tab).toContainText('Tab')
    await tab.locator('button').click()
    await expect(page).toHaveURL(/tab=flags/)
    await expect(page.locator('.cf-page-tabs button.active')).toHaveText(/Flags/)
  })

  test('keyboard: "/" focuses the bar, arrows move, Enter opens, Escape clears; no match says so and the result list is a labelled listbox', async ({ page }) => {
    await openOperations(page)
    await page.locator('body').click({ position: { x: 5, y: 300 } })
    await page.keyboard.press('/')
    await expect(input(page)).toBeFocused()
    await page.keyboard.type('workers')
    await expect(page.locator('[data-page-search-results]')).toHaveAttribute('role', 'listbox')
    await page.keyboard.press('ArrowDown')
    await page.keyboard.press('Enter')
    await expect(page.locator('[data-pim-section]').first()).toBeVisible()
    await input(page).fill('zzzz nothing here')
    await expect(page.locator('[data-page-search-none]')).toContainText('Nothing on this page matches')
    await page.keyboard.press('Escape')
    await expect(input(page)).toHaveValue('')
  })

  test('it reads nothing new from the backend: the Data Delivery read count does not change while searching and jumping', async ({ page }) => {
    const reads = []
    page.on('request', (r) => { if (/\/rest\/v1\/rpc\//.test(r.url())) reads.push(r.url().split('/').pop()) })
    await openOperations(page)
    await page.waitForTimeout(800)
    const before = reads.length
    await (await search(page, 'workers')).locator('[data-ps-kind]').first().locator('button').click()
    await page.waitForTimeout(800)
    expect(reads.slice(before), 'no backend call is made by searching or jumping').toEqual([])
  })
})

test.describe('Settings', () => {
  const SETTINGS = '/#environment'
  async function openSettings(page, opts = {}) {
    const m = await mockAdmin(page, opts)
    await page.goto(SETTINGS)
    await expect(page.locator('[data-settings-register]').first()).toBeAttached({ timeout: 20_000 })   // the register sits in the closed Advanced System Keys drawer
    await expect(bar(page)).toBeVisible()
    return m
  }

  test('a setting is found by its label, by its key and by what uses it; choosing it opens its group and card, scrolls to the row, highlights it and focuses its field', async ({ page }) => {
    await openSettings(page)
    await expect(bar(page)).toBeVisible()
    for (const q of ['read course pages', 'batch.coverage_read', 'coverage-read']) {
      const list = await search(page, q)
      await expect(list.locator('[data-ps-id="reg-setting:batch.coverage_read"]'), `found by "${q}"`).toBeVisible()
    }
    const list = await search(page, 'batch coverage read')
    const hit = list.locator('[data-ps-id="reg-setting:batch.coverage_read"]')
    await expect(hit).toContainText('Setting')
    await expect(hit).toContainText('batch.coverage_read')
    await hit.locator('button').click()
    const row = page.locator('[data-register-setting="batch.coverage_read"]')
    await expect(row).toHaveClass(/ps-hit/)
    await expect.poll(() => inView(page, '[data-register-setting="batch.coverage_read"]')).toBe(true)
    await expect(row.locator('input').first()).toBeFocused()
  })

  test('a setting in another group opens that group: Onboarding is under Pipeline steps and Job sizes under Schedulers & Cadence', async ({ page }) => {
    await openSettings(page)
    const list = await search(page, 'adapter proposals')
    await list.locator('[data-ps-id="reg-setting:onboarding.proposal_attempts"] button').click()
    await expect(page.locator('[data-register-setting="onboarding.proposal_attempts"]')).toHaveClass(/ps-hit/)
    await expect.poll(() => inView(page, '[data-register-setting="onboarding.proposal_attempts"]')).toBe(true)
  })

  test('a plain synonym finds a setting: "retry" finds the re-read and retry group, and a section is a result of its own', async ({ page }) => {
    await openSettings(page)
    const list = await search(page, 'retry')
    await expect(list.locator('[data-ps-id="reg-setting:reread.scholarship_page_days"]')).toBeVisible()
    await expect(list.locator('[data-ps-id="reg-section:Re-read and retry"]')).toBeVisible()
    await list.locator('[data-ps-id="reg-section:Re-read and retry"] button').click()
    await expect(page.locator('[data-register-section="Re-read and retry"]')).toHaveClass(/ps-hit/)
  })

  test('it uses the settings read already made: searching and jumping make no further settings read', async ({ page }) => {
    const reads = []
    page.on('request', (r) => { if (/admin_settings_register_read|admin_pipeline_settings_read/.test(r.url())) reads.push(r.url()) })
    await openSettings(page)
    const before = reads.length
    await (await search(page, 'coverage')).locator('[data-ps-kind="setting"]').first().locator('button').click()
    await page.waitForTimeout(600)
    expect(reads.length).toBe(before)
  })

  test('the Settings tab entries come from the page tabs for the role, not a typed list', async ({ page }) => {
    await openSettings(page)
    const list = await search(page, 'integrations')
    await expect(list.locator('[data-ps-id="tab:integrations"]')).toBeVisible()
  })
})

test.describe('role permissions', () => {
  test('the tabs offered are the tabs the role can open: Adapter builder (minimum rank 5) is offered to a Data Manager and not to a Pipeline Operator', async ({ page }) => {
    await mockAdmin(page, { rank: 4, role: 'pipeline_operator' })
    await page.goto(OPERATIONS)
    await expect(bar(page)).toBeVisible({ timeout: 20_000 })
    await expect(page.locator('.cf-page-tabs button', { hasText: 'Adapter builder' })).toHaveCount(0)
    const none = await search(page, 'adapter builder')
    await expect(none.locator('[data-ps-id="tab:builder"]')).toHaveCount(0)
    await expect(none.locator('[data-ps-id="tab:universities"]')).toHaveCount(0)   // "builder" alone is not a keyword of Universities
  })

  test('a Data Manager (rank 5) is offered the Adapter builder tab', async ({ page }) => {
    await mockAdmin(page, { rank: 5, role: 'data_manager' })
    await page.goto(OPERATIONS)
    await expect(bar(page)).toBeVisible({ timeout: 20_000 })
    const list = await search(page, 'adapter builder')
    await expect(list.locator('[data-ps-id="tab:builder"]')).toBeVisible()
  })

  test('a Counsellor (rank 2) cannot open Build & enrich, is taken to Courses, and no search bar is drawn there', async ({ page }) => {
    await mockAdmin(page, { rank: 2, role: 'counsellor' })
    await page.goto(OPERATIONS)
    await expect(page.locator('[data-gpa-panel]')).toBeVisible({ timeout: 20_000 })
    await expect(bar(page)).toHaveCount(0)
  })

  test('a page that does not opt in has no bar (Courses)', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#courses')
    await expect(page.locator('.cf-page').first()).toBeVisible({ timeout: 20_000 })
    await expect(bar(page)).toHaveCount(0)
  })
})
