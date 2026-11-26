// Guards: F-OPS.17 to F-OPS.21 (SS-Programme-Control 26 Nov 2026 14:25 and 15:04, "Final frontend accuracy and UAT" and "Final authenticated frontend UAT"): the Autonomous PIM block is shown only at rank 3 and above and is read only, and the Autonomous PIM block shows each gain with its gain_basis and never adds gains measured on different bases, keeps published-provider gain apart from verified consumer delivery, reads a measured zero as measured and a missing figure as Not measured (never summed as 0), and shows canonical field coverage apart from work-item counts.
// Desktop project (chromium-desktop, 1440 x 900). Mocked admin plus tests/uat/support/pim-mock.mjs; nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockLaneFunnels } from './support/lane-funnel-mock.mjs'
import { mockPim, PIM, PIM_FIELDS, ENTRY_BASIS, ENRICH_BASIS } from './support/pim-mock.mjs'

const OPERATIONS = '/#layer-2-discovery?tab=operations'
async function open(page, opts) {
  await mockAdmin(page); await mockLaneFunnels(page)
  const m = await mockPim(page, opts)
  await page.goto(OPERATIONS)
  const pim = page.locator('[data-dd-pim]')
  await expect(pim).toBeVisible({ timeout: 20_000 })
  await expect(pim.locator('[data-pim-matrix]')).toBeVisible()
  return { pim, ...m }
}

test.describe('gain basis and consumer delivery', () => {
  test('gains are shown per measurement basis, with the basis words, and are not added across bases', async ({ page }) => {
    const { pim } = await open(page)
    const groups = pim.locator('[data-pim-gain-group]')
    await expect(groups).toHaveCount(2)
    const entry = pim.locator(`[data-pim-gain-group][data-pim-basis="${ENTRY_BASIS}"]`)
    const enrich = pim.locator(`[data-pim-gain-group][data-pim-basis="${ENRICH_BASIS}"]`)
    await expect(entry.locator('[data-pim-gain-basis]')).toContainText('first active entry row was created')
    await expect(enrich.locator('[data-pim-gain-basis]')).toContainText('enrich items filled in the window')
    const sum = (rows, k) => rows.reduce((a, r) => a + (Number(r[k]) || 0), 0)
    const fmt = (n) => `+${n.toLocaleString('en-AU')}`
    await expect(entry.locator('[data-pim-gain="canonical"]')).toHaveText(fmt(sum(PIM_FIELDS.filter((r) => r.gain_basis === ENTRY_BASIS), 'canonical_gain_window')))
    await expect(enrich.locator('[data-pim-gain="canonical"]')).toHaveText(fmt(sum(PIM_FIELDS.filter((r) => r.gain_basis === ENRICH_BASIS), 'canonical_gain_window')))
    // there is no single blended gain tile across the two bases
    const all = sum(PIM_FIELDS, 'canonical_gain_window')
    await expect(pim.locator('[data-pim-gains]')).not.toContainText(fmt(all))
  })

  test('a country with one basis in scope shows one group; the matrix says Mixed bases where a cell spans two and lists the bases', async ({ page }) => {
    const { pim } = await open(page)
    await pim.locator('[data-pim-measure]').selectOption('published')
    await expect(pim.locator('[data-pim-domain-row="Entry"] [data-pim-cell="all"]')).toContainText('Mixed bases')
    await expect(pim.locator('[data-pim-domain-row="Entry"] [data-pim-cell="AU"]')).toContainText('not added')
    await expect(pim.locator('[data-pim-domain-row="Course page"] [data-pim-cell="all"]')).toContainText('+54')
    const legend = pim.locator('[data-pim-basis-legend]')
    await expect(legend).toContainText('not added')
    await expect(legend.locator('[data-pim-basis-item]')).toHaveCount(2)
    await expect(legend).toContainText('Entry')
    // switching off the gain measures hides the legend
    await pim.locator('[data-pim-measure]').selectOption('completeness')
    await expect(pim.locator('[data-pim-basis-legend]')).toHaveCount(0)
  })

  test('the field table names each row\'s basis, and published-provider gain is labelled as such, apart from verified consumer delivery', async ({ page }) => {
    const { pim } = await open(page)
    await pim.locator('[data-pim-country]').selectOption('AU')
    await pim.locator('[data-pim-domain="Entry"]').click()
    const row = pim.locator('[data-pim-fields] [data-pim-field="academic_entry"]')
    await expect(row.locator('[data-pim-row-basis]')).toContainText('first active entry row was created')
    await expect(row.locator('[data-pim-gain-cell]')).toContainText('547 published-provider')
    const eng = pim.locator('[data-pim-fields] [data-pim-field="english"]')
    await expect(eng.locator('[data-pim-row-basis]')).toContainText('enrich items filled')
    await expect(pim.locator('[data-pim-gains]')).toContainText('Published-provider gain')
    await expect(pim.locator('[data-pim-gains]')).not.toContainText('Consumer gain')
    const verified = pim.locator('[data-pim-gain-group-shared]').filter({ hasText: 'Verified consumer delivery' })
    await expect(verified.locator('[data-pim-unknown]').first()).toContainText('Not measured')
    await expect(verified).toContainText('not a delivery check')
  })
})

test.describe('measured zero and unavailable', () => {
  test('a measured zero reads as measured, and a missing figure is Not measured and is not summed as 0', async ({ page }) => {
    const rows = PIM_FIELDS.map((r) => (r.country === 'AU' && r.field === 'description' ? { ...r, canonical_gain_window: null, published_gain_window: null, throughput_per_hour: null } : r))
    const { pim } = await open(page, { pim: { ...PIM, fields: rows } })
    await pim.locator('[data-pim-country]').selectOption('AU')
    // enrich basis: other AU fields gained 1 (intakes), description is missing -> the sum says at least, never 0
    const enrich = pim.locator(`[data-pim-gain-group][data-pim-basis="${ENRICH_BASIS}"]`)
    await expect(enrich.locator('[data-pim-gain="canonical"]')).toHaveText('+1')
    await expect(enrich.locator('[data-pim-partial]').first()).toContainText('at least')
    await pim.locator('[data-pim-domain="Course page"]').click()
    const desc = pim.locator('[data-pim-fields] [data-pim-field="description"]')
    await expect(desc.locator('[data-pim-gain-cell] [data-pim-unknown]')).toContainText('Not measured')
    await expect(desc.locator('[data-label="Per hour"] [data-pim-unknown]')).toContainText('Not measured')
    // a field that gained nothing is a measured zero
    await pim.locator('[data-pim-domain="Location"]').click()
    const campus = pim.locator('[data-pim-fields] [data-pim-field="campus"]')
    await expect(campus.locator('[data-pim-gain-cell]')).toContainText('measured: none')
    await expect(campus.locator('[data-label="Per hour"]')).toContainText('measured: none gained')
    await expect(campus.locator('[data-pim-gain-cell] [data-pim-unknown]')).toHaveCount(0)
  })

  test('a missing count never becomes 0 in the funnel or the matrix', async ({ page }) => {
    const rows = PIM_FIELDS.map((r) => (r.country === 'NZ' ? { ...r, backlog: null, queued: null } : r))
    const { pim } = await open(page, { pim: { ...PIM, fields: rows } })
    await pim.locator('[data-pim-country]').selectOption('NZ')
    await expect(pim.locator('[data-pim-stage="backlog"] [data-pim-unknown]')).toContainText('Not measured')
    await expect(pim.locator('[data-pim-stage="queued"] [data-pim-unknown]')).toContainText('Not measured')
    await expect(pim.locator('[data-pim-stage="applicable"] strong')).not.toHaveText('0')
    await pim.locator('[data-pim-measure]').selectOption('backlog')
    await expect(pim.locator('[data-pim-domain-row="Study"] [data-pim-cell="NZ"]')).toContainText('Not measured')
    await expect(pim.locator('[data-pim-domain-row="Study"] [data-pim-cell="NZ"]')).not.toContainText(/^0\b/)
  })
})

test.describe('canonical backlog and work-item holds', () => {
  test('the funnel has two groups, work items are labelled per queue item, and holds can exceed the backlog without being subtracted', async ({ page }) => {
    const { pim } = await open(page)
    await expect(pim.locator('[data-pim-group="field"]')).toContainText('Canonical field coverage')
    await expect(pim.locator('[data-pim-group="items"]')).toContainText('Work items in the queue')
    const fieldStages = await pim.locator('[data-pim-funnel-group="field"] [data-pim-stage]').evaluateAll((els) => els.map((e) => e.getAttribute('data-pim-stage')))
    const itemStages = await pim.locator('[data-pim-funnel-group="items"] [data-pim-stage]').evaluateAll((els) => els.map((e) => e.getAttribute('data-pim-stage')))
    expect(fieldStages).toEqual(['applicable', 'completed', 'backlog'])
    expect(itemStages).toEqual(['queued', 'running', 'held', 'failed'])
    // AU description: held work items (94 + 35,262) are larger than the field backlog (13,018); both are shown as they are
    await pim.locator('[data-pim-country]').selectOption('AU')
    await pim.locator('[data-pim-domain="Course page"]').click()
    const desc = pim.locator('[data-pim-fields] [data-pim-field="description"]')
    await expect(desc.locator('[data-label="Backlog"]')).toHaveText('13,018')
    await expect(desc.locator('[data-label="Items held"]')).toContainText('35,356')
    await expect(pim.locator('[data-pim-funnel-note]')).toContainText('can be larger than it')
    await expect(pim.locator('[data-pim-funnel-note]')).toContainText('never subtracted')
    const heads = await pim.locator('[data-pim-fields] thead th').allTextContents()
    expect(heads).toEqual(expect.arrayContaining(['Items queued', 'Items running', 'Items held', 'Items failed']))
    await pim.locator('[data-pim-measure]').selectOption('backlog')
    await expect(pim.locator('[data-pim-measure-help]')).toContainText('Work-item holds are not subtracted')
  })
})

test.describe('role permissions', () => {
  async function openAt(page, rank) {
    await mockAdmin(page, { rank }); await mockLaneFunnels(page)
    await mockPim(page)
    await page.goto(OPERATIONS)
  }
  test('below rank 3 (counsellor) Data Delivery and the PIM block are not shown', async ({ page }) => {
    await openAt(page, 2)
    await page.waitForLoadState('networkidle')
    await expect(page.locator('[data-dd-pim]')).toHaveCount(0)
    await expect(page.locator('[data-data-delivery]')).toHaveCount(0)
  })
  for (const rank of [3, 4, 6]) {
    test(`rank ${rank} sees the PIM block, and it offers no control that changes data`, async ({ page }) => {
      await openAt(page, rank)
      const pim = page.locator('[data-dd-pim]')
      await expect(pim).toBeVisible({ timeout: 20_000 })
      await expect(pim.locator('input:not([data-pjm-search]), textarea, [data-pim-save], [data-pim-apply]')).toHaveCount(0)
      // every button is a view or navigation control, never an action on data
      const labels = await pim.locator('button:not([data-pim-cell])').allTextContents() // matrix cells are figures that open a country and domain
      for (const l of labels) expect(l).not.toMatch(/\b(save|apply|approve|delete|run now|retry now|activate)\b/i)
      await expect(pim.locator('[data-pim-link="layer4"]').first()).toHaveAttribute('href', /#layer-4-review/)
    })
  }
})
