// Guards: CF-247 A1 (Platform Admin mandate 29 Oct 2026 12:23): on Course detail the evidence button opens one evidence and history overlay with a single timeline (pages, reads, changes, AI, admissions, fees, cross-checks, changes by hand, entry requirements, scholarship links), the blade no longer embeds the history, the overlay is an accessible dialog (focus in and back, Escape, close, page held still) and fills the phone screen without sideways scrolling
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import * as F from './support/admin-fixtures.mjs'

const COURSE = '0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5'
const TITLE = 'Associate Degree in Business'
const reads = n => Array.from({ length: n }, (_, i) => ({ at: `2026-10-${String(5 + (i % 20)).padStart(2, '0')}T11:04:01Z`, via: 'direct', identity: 'cricos_code', url: 'https://www.rmit.edu.au/study/ad029', evidence_id: `ev${String(i).padStart(4, '0')}-0000-4000-8000-000000000000` }))
const auditData = (n = 3) => ({
  course: { canonical_title: TITLE, course_code: '111279A', duration_value: 104, duration_unit: 'weeks', delivery_mode: 'On campus', open_to_international: true },
  page: { url: 'https://www.rmit.edu.au/study/ad029', basis: 'firecrawl_search', status: 'bound', read_status: 'read', read_at: '2026-10-05T11:04:01Z', fetched_via: 'direct', identity_basis: 'cricos_code', bound_at: '2026-10-01T09:00:00Z' },
  reads: reads(n), searches: [{ stage: 'title', state: 'done', query: 'RMIT associate degree in business', results: 8, bound_url: 'https://www.rmit.edu.au/study/ad029', done_at: '2026-10-01T08:59:00Z' }],
  relinks: [{ old_url: 'https://www.rmit.edu.au/old/ad029', new_url: 'https://www.rmit.edu.au/study/ad029', reason: 'old page retired', at: '2026-10-02T10:00:00Z' }],
  ai_match: [{ attempt: 1, state: 'chosen', chosen_url: 'https://www.rmit.edu.au/study/ad029', candidates: 12, decided_at: '2026-10-01T08:58:00Z' }],
  field_fills: [{ field: 'campus', state: 'skipped', reason: 'the page names no campus', updated_at: '2026-10-14T04:20:00Z' }],
  admissions: [{ field_key: 'tuition', status: 'refused', reason_code: 'quote_not_on_page', decided_at: '2026-10-06T00:00:00Z' }],
  fee_rows: [{ amount_min: 37440, amount_max: 37440, currency_code: 'AUD', audience: 'international', fee_year: 2027, outcome: 'matched', note: 'annual fee', quote: 'A$37,440 per year', created_at: '2026-10-07T00:00:00Z' }],
  crosschecks: [{ field: 'duration', held_value: '104 weeks', page_value: '2 years', state: 'agree', found_at: '2026-10-08T00:00:00Z' }],
  scope: [], locks: [{ field: 'description', mode: 'manual', at: '2026-10-09T00:00:00Z' }],
  read_now: [{ at: '2026-10-10T00:00:00Z', detail: { reason: 'page changed; fee missing', page_read_again: true, ai_fields: ['campus'] } }],
  held: { fees: [], intakes: [{ label: 'February' }], english: [], campuses: [] }, can_read_now: true })
const aerRow = { kind: 'course', id: 'cer1', course_id: COURSE, course_title: TITLE, requirement_kind: 'minimum_grade', audience: 'domestic', description: '2026 ATAR 73.00', status: 'proposed', quote: '2026 ATAR 73.00', source_url: 'https://www.rmit.edu.au/study/ad029', evidence_id: 'ev-aer-1', as_at: '2026-10-28', updated_at: '2026-10-28T11:00:00+00:00' }
const scholarship = { mapping_id: 'map1', scholarship_id: 's1', name: 'RMIT Global Excellence', publication_status: 'published', lifecycle_status: 'active', mapping_basis: 'names_course', source_url: 'https://www.rmit.edu.au/scholarships/global', evidence_id: 'ev-sch-1' }

async function setup(page, { readsCount = 3 } = {}) {
  await mockAdmin(page)
  const calls = []
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
    let b = {}; try { b = route.request().postDataJSON() || {} } catch {}
    if (b.p_operation === 'course_detail') return route.fulfill({ json: { ...F.courseDetail, course_scholarships: { items: [scholarship] } } })
    return route.fallback()
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_course_audit', route => { calls.push('audit'); return route.fulfill({ json: auditData(readsCount) }) })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_aer', route => { const b = route.request().postDataJSON() || {}; calls.push(`aer:${b.p_action}:${b.p_args?.course}`); return route.fulfill({ json: { total: 1, rows: [aerRow] } }) })
  await page.goto(`/#courses?id=${COURSE}`)
  await expect(page.locator('.m-drawer-course')).toBeVisible()
  return calls
}

test('the evidence button opens one timeline from the existing reads; the blade no longer embeds it; Escape, close and focus return', async ({ page }) => {
  const errors = []; page.on('console', m => { if (m.type() === 'error' && !/Failed to load resource|favicon/.test(m.text())) errors.push(m.text()) })
  const calls = await setup(page)
  const blade = page.locator('.m-drawer-course')
  // the blade keeps Read with AI, not the history
  await expect(blade.locator('[data-course-read-ai]')).toBeVisible()
  await expect(blade.getByText('What happened to this course', { exact: true })).toHaveCount(0)
  await expect(blade.locator('[data-course-timeline], [data-course-audit]')).toHaveCount(0)

  const button = page.getByRole('button', { name: 'Evidence and history' })
  await expect(button).toHaveAttribute('aria-haspopup', 'dialog')
  await button.click()
  const dlg = page.getByRole('dialog', { name: TITLE })
  await expect(dlg).toHaveAttribute('aria-modal', 'true')
  await expect(dlg.getByRole('button', { name: 'Close evidence and history' })).toBeFocused()
  expect(await page.evaluate(() => document.body.style.overflow)).toBe('hidden')
  const tl = dlg.locator('[data-course-timeline]')
  // one timeline: every kind of step, with date, outcome, source and evidence reference
  for (const k of ['discovery', 'read', 'change', 'ai', 'admission', 'fee', 'check', 'manual', 'aer', 'scholarship']) await expect(tl.locator(`[data-ca-kind="${k}"]`).first()).toBeVisible()
  await expect(tl).toContainText('the page names no campus')
  await expect(tl).toContainText('Admission: tuition')
  await expect(tl).toContainText('Entry requirement: minimum grade')
  await expect(tl).toContainText('Waiting in Layer 4')
  await expect(tl).toContainText('Scholarship link: RMIT Global Excellence')
  await expect(tl.locator('[data-ca-kind="read"]').first().locator('[data-ca-evidence]')).toHaveAttribute('href', /evidence/)
  await expect(tl.locator('[data-ca-kind="aer"] a', { hasText: 'Source' })).toHaveAttribute('href', 'https://www.rmit.edu.au/study/ad029')
  await expect(tl.locator('[data-ca-kind="scholarship"] time')).toHaveText('Date not recorded')
  // newest first by default, oldest first on request; the undated entries stay last
  const firstTime = () => tl.locator('li time').first().getAttribute('datetime')
  expect(await firstTime()).toBe('2026-10-28')
  await dlg.locator('[data-ca-order]').click()
  expect(await firstTime()).toBe('2026-10-01T08:58:00Z')
  await expect(tl.locator('li').last().locator('time')).toHaveText('Date not recorded')
  // a filter by kind of step
  await dlg.locator('[data-ca-area="fee"]').click()
  await expect(tl.locator('li')).toHaveCount(1)
  // only the existing reads: the course audit, and the entry requirement list for this course
  expect(calls).toContain('audit')
  expect(calls).toContain(`aer:course_list:${COURSE}`)
  // Tab stays inside
  for (let i = 0; i < 25; i++) await page.keyboard.press('Tab')
  expect(await dlg.evaluate(d => d.contains(document.activeElement))).toBe(true)
  // Escape closes the overlay only: the course drawer stays, the focus goes back to the button, the page scrolls again
  await page.keyboard.press('Escape')
  await expect(dlg).toHaveCount(0)
  await expect(page.locator('.m-drawer-course')).toBeVisible()
  await expect(button).toBeFocused()
  expect(await page.evaluate(() => document.body.style.overflow)).toBe('')
  // the close button too
  await button.click()
  await page.getByRole('button', { name: 'Close evidence and history' }).click()
  await expect(page.getByRole('dialog', { name: TITLE })).toHaveCount(0)
  await expect(button).toBeFocused()
  expect(errors).toEqual([])
})

test('phone width: the evidence overlay fills the screen, scrolls inside, nothing sideways @responsive', async ({ page }) => {
  const width = page.viewportSize().width
  expect(width, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(480)
  await setup(page, { readsCount: 40 })
  await page.getByRole('button', { name: 'Evidence and history' }).tap()
  const dlg = page.getByRole('dialog', { name: TITLE })
  await expect(dlg.locator('[data-course-timeline] li').first()).toBeVisible()
  const box = await dlg.boundingBox()
  expect(box.x).toBeLessThanOrEqual(0.5)
  expect(box.y).toBeLessThanOrEqual(0.5)
  expect(box.width).toBeGreaterThanOrEqual(width - 1)
  expect(box.height).toBeGreaterThanOrEqual(page.viewportSize().height - 1)
  const body = dlg.locator('.cf-overlay-body')
  const m = await body.evaluate(e => ({ sh: e.scrollHeight, ch: e.clientHeight, sw: e.scrollWidth, cw: e.clientWidth, oy: getComputedStyle(e).overflowY }))
  expect(m.oy).toBe('auto'); expect(m.sh).toBeGreaterThan(m.ch); expect(m.sw - m.cw).toBeLessThanOrEqual(1)
  await dlg.locator('[data-course-timeline] li').last().scrollIntoViewIfNeeded()
  await expect(dlg.locator('[data-course-timeline] li').last()).toBeInViewport()
  expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1)
  // the close control is reachable and large enough to tap
  const close = dlg.getByRole('button', { name: 'Close evidence and history' })
  const c = await close.boundingBox()
  expect(c.x + c.width).toBeLessThanOrEqual(width + 1); expect(c.height).toBeGreaterThanOrEqual(24)
  await close.tap()
  await expect(dlg).toHaveCount(0)
})
