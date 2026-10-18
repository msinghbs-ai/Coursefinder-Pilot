// CF-247 (S63) v2.15.289: Adapter builder guide (Platform Admin 18 Oct 2026 22:03: "flow was not clear ... no movement or clear indication
// for next step ... find course pages are running 0-4 without me pressing anything. this has to be intutive").
import { test, expect } from '@playwright/test'

const sfs = (o = {}) => ({ provider_id: 'p-sf', name: 'Sydney Film School', country: 'AU', courses: 4, pages: { stored: 0, read: 0 }, adapter: null, qualify: null, suggested: [], can_manage: true,
  website: 'https://sydneyfilmschool.edu.au', contacts: { phone: '+61283993380', email: null, outcome: 'found' },
  central: [{ kind: 'fee_schedule', url: 'https://sydneyfilmschool.edu.au/fees', status: 'found', decision: null }], central_search: { state: 'done', found: 1, addresses: 114 },
  course_list: [1, 2, 3, 4].map(i => ({ course_id: 'c' + i, title: 'Course ' + i, code: '00000' + i + 'A', state: 'searching' })), ...o })


test.describe('mocked browser', () => {
  async function open(page, basics, queue = { queued: 4, asked: 4, sent: 0, ahead: 2, runs: true, why: null }) {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page)
    let n = 0
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_builder_basics', r => { n++; r.fulfill({ json: typeof basics === 'function' ? basics(n) : basics }) })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_builder', r => r.fulfill({ json: { budget: { used_usd: 0, limit_usd: 1.5 }, can_manage: true, drafts: [], pages: [], courses: [] } }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_provider_website_check', r => r.fulfill({ json: { website: 'https://sydneyfilmschool.edu.au', sites: ['https://sydneyfilmschool.edu.au'], can_check: true, can_change: true, checks: [] } }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_course_search_queue', r => r.fulfill({ json: queue }))
    await page.goto('/#layer-2-discovery?tab=builder&provider=p-sf')
  }

  test('course pages searching by themselves: the guide says nothing to press and lists what runs', async ({ page }) => {
    await open(page, sfs())
    const g = page.locator('[data-builder-guide]')
    await expect(g.locator('[data-builder-next="2.1"]')).toContainText('Nothing to press: course pages are being found and read by themselves')
    await expect(g.locator('[data-flow-step="1.1"]')).toContainText('Done')
    await expect(g.locator('[data-flow-step="2.1"]')).toContainText('Running by itself')
    await expect(g.locator('[data-flow-step="1.2"]')).toContainText('Done')
    await expect(g.locator('[data-builder-running]')).toContainText('Finding course pages: 4 of 4 courses being searched (2 asked-for searches ahead in the queue)')
    await expect(g.locator('[data-builder-running]')).toContainText('Reading 1 attached central page(s)')
    await expect(page.locator('[data-find-auto]')).toContainText('Queued for search')
  })

  test('search finished with 3 read pages: the next step is Capture samples, with Go to step', async ({ page }) => {
    await open(page, sfs({ pages: { stored: 3, read: 3 }, central: [], course_list: [1, 2, 3, 4].map(i => ({ course_id: 'c' + i, title: 'Course ' + i, state: i < 4 ? 'read' : 'not_found' })) }))
    const next = page.locator('[data-builder-next]')
    await expect(next).toHaveAttribute('data-builder-next', '2.2')
    await expect(next).toContainText('Next for you')
    await expect(next).toContainText('Press Capture samples')
    await expect(next.getByRole('button', { name: 'Go to step 2.2' })).toBeVisible()
    await expect(page.locator('[data-builder-running]')).toHaveCount(0)
  })

  test('nothing found and nothing running: the next step is Find the missing course pages', async ({ page }) => {
    await open(page, sfs({ central: [], course_list: [1, 2, 3, 4].map(i => ({ course_id: 'c' + i, title: 'Course ' + i, state: 'not_found' })) }))
    await expect(page.locator('[data-builder-next="2.1"]')).toContainText('Find the missing course pages')
    await expect(page.locator('[data-flow-step="2.1"]')).toContainText('Your turn')
  })

  test('the page refreshes by itself while work runs', async ({ page }) => {
    const done = sfs({ pages: { stored: 3, read: 3 }, central: [], course_list: [1, 2, 3, 4].map(i => ({ course_id: 'c' + i, title: 'Course ' + i, state: i < 4 ? 'read' : 'not_found' })) })
    let finished = false
    await page.clock.install()
    await open(page, () => (finished ? done : sfs()))
    await expect(page.locator('[data-builder-next="2.1"]')).toBeVisible()
    finished = true
    await page.clock.runFor(16000)
    await expect(page.locator('[data-builder-next="2.2"]')).toBeVisible()
  })

  test('v2.15.290: searches waiting on a rule are not shown as running; the guide says why and it is your turn', async ({ page }) => {
    await open(page, sfs({ central: [] }), { queued: 4, asked: 0, sent: 0, ahead: 0, runs: false, why: 'waiting: outside the focus providers, so it runs only when asked for; press Find every missing page' })
    await expect(page.locator('[data-builder-next="2.1"]')).toContainText('Course-page search is not running: waiting: outside the focus providers')
    await expect(page.locator('[data-builder-next="2.1"]')).toContainText('Next for you')
    await expect(page.locator('[data-flow-step="2.1"]')).toContainText('Your turn')
    await expect(page.locator('[data-builder-running]')).toHaveCount(0)
  })
})
