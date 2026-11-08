// Guards: CF-247 F-CDESC.04 (feature acceptance contract: course description review capacity, flags and the by-university pack work on a phone, mobile acceptance) and F-OPS.04 (admin drill-down on desktop and phone; a preview is read-only)
// These tests run on the phone project only (chromium-mobile, Pixel 7, 412 px; `@responsive`). Each first asserts it really is at phone width.
// Mocked admin (tests/uat/support/admin-mock.mjs); nothing reaches a real backend. The desktop behaviour of the capacity line and the pack is held by s360.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'

const PHONE_MAX = 480
// WCAG 2.2 AA target size (2.5.8), the same floor as the Layer 4 phone test (s121). Measured 9 Nov 2026 (Pixel 7, 412 px): the order buttons are 26 px high,
// so they pass this floor; raising them to the 44 px used by the lane funnels is a proposal for the Platform Admin, not done here.
const TAP_MIN = 24
async function atPhoneWidth(page) {
  const w = page.viewportSize()?.width || 9999
  expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
  return w
}
const pageOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)
async function within(locator, width) {
  await locator.scrollIntoViewIfNeeded()
  const b = await locator.boundingBox()
  expect(b, 'element has a box').toBeTruthy()
  expect(b.x).toBeGreaterThanOrEqual(-1)
  expect(b.x + b.width).toBeLessThanOrEqual(width + 1)
  return b
}

const SUMMARY = { provider_id: 'p1', pending: 3, by_class: { ready: 2, fails_now: 1 }, by_country: { AU: { pending: 3, ready: 2 } }, proposed_in_layer4: 3, admitted_by_person: 0, published_to_the_website: 0,
  admitted_without_a_person: 0, waiting_behind_provider_cap: 5, review_first: 100000, reask_max: 0, limits: { min_sentences: 1, max_sentences: 4, min_chars: 80, max_chars: 700 }, rechecked: 3 }
const CAPACITY = { pending: 3, minutes_an_item: 3, pace_basis: 'default', hours_to_clear_waiting: 0.2, held_first_readings_behind_the_provider_cap: 5, hours_to_clear_waiting_and_held: 0.4,
  target_days: 7, items_a_day_needed_incl_arrivals: 4, reviewer_hours_a_day_needed: 0.2, arriving_a_day: 1.5, window_days: 7, decided_in_window: 0, back_pressure: { on: true, global_max: 1500, new_readings_paused: false } }
const ITEM = (n, pack) => ({ kind: 'provider_description', ref: `0000000${n}-0000-4000-a000-000000000000`, provider_id: 'p1', provider: 'Queue University', subject: `Bachelor of Queue ${n}`,
  why: 'Course description read from the course\'s own page.', created_at: '2026-11-04T01:00:00Z', ready: true,
  detail: { field_code: 'course_description_first_read', course_id: `c${n}`, before: {}, proposed: { description: 'This degree covers planning. You complete a capstone project.',
    checks: { sentences: 2, chars: 183 }, sentences: [{ text: 'This degree covers planning.', quote: 'This degree covers planning.' }] }, pack } })
const PACK = [
  { flags: [], flag_count: 0, same_words_on_other_courses: 0, held_readings_this_decision_can_free: 4, waiting_in_university: 2, university_rank: 1 },
  { flags: ['same_words_elsewhere', 'money_or_year'], flag_count: 2, same_words_on_other_courses: 3, held_readings_this_decision_can_free: 4, waiting_in_university: 2, university_rank: 1 },
]
const KINDS = { provider_description: { label: 'University description', order: 1, choices: [{ key: 'approve', label: 'Approve as read', rank: 4, returns: 'The description is published.' }, { key: 'reject', label: 'Reject', rank: 4, returns: 'It is read again later.' }] } }

async function openPack(page, calls) {
  await mockAdmin(page, { rank: 4 })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
    const b = route.request().postDataJSON(); calls.inbox.push(b)
    if (b.p_action === 'summary') return route.fulfill({ json: { kinds: KINDS, target_days: 7, rank: 4, total: 3, universities: 1, late: 0, by_kind: { provider_description: { n: 3 } } } })
    if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [{ provider_id: 'p1', name: 'Queue University', country: 'AU', courses: 25, n: 3, oldest: '2026-11-04T01:00:00Z', late: false, by_kind: { provider_description: 3 } }] } })
    if (b.p_action === 'items') return route.fulfill({ json: { total: 3, items: [ITEM(1), ITEM(2), ITEM(3)] } })
    if (b.p_action === 'decide') return route.fulfill({ json: { ok: true, returns: 'Done.' } })
    return route.fulfill({ json: {} })
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_course_description_queue', async (route) => {
    const b = route.request().postDataJSON(); calls.cd.push(b)
    if (b.p_action === 'summary') return route.fulfill({ json: SUMMARY })
    if (b.p_action === 'capacity') return route.fulfill({ json: CAPACITY })
    if (b.p_action === 'pack') return route.fulfill({ json: { total: 2, offset: 0, limit: 25, items: [ITEM(1, PACK[0]), ITEM(2, PACK[1])] } })
    if (b.p_action === 'items') return route.fulfill({ json: { total: 2, offset: 0, limit: 25, items: [ITEM(1), ITEM(2)] } })
    return route.fulfill({ json: {} })
  })
  await page.goto('/#layer-4-review')
  await expect(page.locator('[data-l4-inbox]')).toBeVisible()
  await page.locator('[data-l4-pill="provider_description"]').first().click()
}

test.describe('course description review capacity and pack on a phone @responsive', () => {
  test('the capacity line is whole on a phone: every figure is readable inside the screen and the page does not scroll sideways', async ({ page }) => {
    const w = await atPhoneWidth(page)
    const calls = { inbox: [], cd: [] }
    await openPack(page, calls)
    const cap = page.locator('[data-l4-cd-capacity]')
    await expect(cap).toContainText('about 3 minutes an item (Layer 4 default, not yet measured for descriptions)')
    await expect(cap).toContainText('4 decisions a day')
    await expect(cap).toContainText('new readings run (limit 1,500)')
    await within(cap, w)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('the order buttons (Ready, Review pack, Trust-policy sample) are tap targets that stay inside the screen', async ({ page }) => {
    const w = await atPhoneWidth(page)
    const calls = { inbox: [], cd: [] }
    await openPack(page, calls)
    for (const sel of ['[data-l4-cd-ready]', '[data-l4-cd-pack]', '[data-l4-cd-sample]']) {
      const b = await within(page.locator(sel), w)
      expect(b.height, `${sel} tap target`).toBeGreaterThanOrEqual(TAP_MIN)
      expect(b.width, `${sel} tap target`).toBeGreaterThanOrEqual(TAP_MIN)
    }
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('the review pack on a phone: flags read in full on each card, "All waiting" returns, and opening the pack decides nothing', async ({ page }) => {
    const w = await atPhoneWidth(page)
    const calls = { inbox: [], cd: [] }
    await openPack(page, calls)
    await page.locator('[data-l4-cd-pack]').click()
    await expect.poll(() => calls.cd.some((c) => c.p_action === 'pack' && c.p_args.offset === 0)).toBe(true)
    const cards = page.locator('[data-l4-cd-list] [data-l4-item="provider_description"]')
    await expect(cards).toHaveCount(2)
    const f0 = cards.nth(0).locator('[data-l4-cd-flags]'), f1 = cards.nth(1).locator('[data-l4-cd-flags]')
    await expect(f0).toContainText('No flag')
    await expect(f1).toContainText('same words as another course; names a price or a year (3 other)')
    await expect(f1).toContainText('lets up to 4 held readings')
    await within(f0, w); await within(f1, w)
    const all = page.locator('[data-l4-cd-all]')
    await expect(all).toBeVisible()
    const ab = await within(all, w)
    expect(ab.height, 'All waiting tap target').toBeGreaterThanOrEqual(TAP_MIN)
    // reading the pack decided nothing and asked the database for nothing but reads
    expect(calls.inbox.filter((c) => c.p_action === 'decide')).toHaveLength(0)
    for (const c of calls.cd) expect(['summary', 'capacity', 'pack', 'items']).toContain(c.p_action)
    await all.click()
    await expect(page.locator('[data-l4-cd-all]')).toHaveCount(0)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })
})
