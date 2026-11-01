// Guards: SS-016 UR-09 acceptance (usability review 1 Nov 2026 §4 UR-09 "Accept"; overnight mandate §4): every old address (LEGACY, old Administration sections, retired ?tab= names, old page labels) resolves to a current page and tab for every role rank, and lands either on its destination or on a safe fallback that names the role it needs (never the Dashboard by accident, never a silent tab switch); current routes replay with Back and Forward at each rank.
import { test, expect } from '@playwright/test'
import { PAGES, LEGACY, LEGACY_ADMIN_SECTIONS, resolveTarget, hrefFor, canOpen, effectiveTab, refusedTab, shownTabs } from '../../src/nav-map.js'
import { asRole, mockInbox, ROLE } from './support/role-fixtures.mjs'

// retired tab names still handled by resolveTarget (src/nav-map.js), as saved links carry them
const OLD_TABS = [
  ['layer-1-register', 'imports'], ['layer-1-register', 'dates'], ['layer-1-register', 'links'], ['layer-1-register', 'onboarding'], ['layer-1-register', 'scholarships'],
  ['reference-data', 'imports'], ['reference-data', 'dates'], ['reference-data', 'links'],
  ['scholarships', 'extraction'], ['scholarships', 'publishing'], ['scholarships', 'links'],
  ['coverage', 'flags'], ['coverage', 'domains'], ['coverage', 'universities'], ['coverage', 'reports'], ['coverage', 'progress', 'view=running'], ['coverage', 'progress', 'view=levers'],
  ['platform-health', 'readiness'], ['scheduled-jobs', 'schedules'], ['scheduled-jobs', 'priority'],
  ['layer-2-discovery', 'start'], ['layer-2-discovery', 'history'], ['layer-2-discovery', 'profiles'], ['layer-2-discovery', 'adapters'], ['layer-2-discovery', 'onboarding'],
  ['layer-4-review', 'sendback'], ['layer-4-review', 'review'], ['layer-4-review', 'aireview'], ['layer-4-review', 'websites'], ['layer-4-review', 'flags'], ['layer-4-review', 'rules'],
  ['layer-4-review', 'blocks'], ['layer-4-review', 'attributes'], ['layer-4-review', 'publishing'], ['providers', 'onboarding'], ['layer-3-ai', 'models'], ['layer3', 'control'],
]
const OLD_LABELS = ['Layer 4 — Human Resolution', 'Statistics & Rankings', 'Live activity', 'Scrapers & fetchers', 'Data quality readiness']
const bookmarks = () => [
  ...Object.keys(LEGACY).map((k) => [k, '']),
  ...Object.keys(LEGACY_ADMIN_SECTIONS).map((s) => ['administration', `section=${s}`]),
  ...OLD_TABS.map(([p, t, extra]) => [p, `tab=${t}${extra ? `&${extra}` : ''}`]),
  ...OLD_LABELS.map((l) => [l, '']),
]
/** What a person at this rank sees for an address: the page, the tab shown, and whether a handoff names the role it needs. */
function landing(route, query, rank) {
  const r = resolveTarget(route, new URLSearchParams(query))
  const href = hrefFor(r.page, r.tab, Object.fromEntries(r.params))
  if (!canOpen(r.page, rank)) return { r, href, outcome: 'page-handoff' }
  const shown = effectiveTab(r.page, r.tab, rank)
  if (refusedTab(r.page, r.tab, rank)) return { r, href, shown, outcome: 'tab-handoff' }
  return { r, href, shown, outcome: 'destination' }
}

test('every old address resolves to a current page and tab; none falls to the Dashboard unless it was the Dashboard', () => {
  const list = bookmarks()
  expect(list.length).toBeGreaterThan(90)
  for (const [route, query] of list) {
    const r = resolveTarget(route, new URLSearchParams(query))
    expect(r.unknown, `${route}?${query}`).toBeFalsy()
    expect(PAGES[r.page], `${route}?${query} -> ${r.page}`).toBeTruthy()
    expect(r.page, `${route}?${query}`).not.toBe('dashboard')
    if (r.tab) expect((PAGES[r.page].tabs || []).map((t) => t.key), `${route}?${query} -> ${r.page} tab ${r.tab}`).toContain(r.tab)
  }
})

test('at every rank each old address lands on its destination or on a handoff naming the role it needs', () => {
  const tally = {}
  for (let rank = 1; rank <= 6; rank++) {
    for (const [route, query] of bookmarks()) {
      const l = landing(route, query, rank)
      tally[`${rank}:${l.outcome}`] = (tally[`${rank}:${l.outcome}`] || 0) + 1
      if (l.outcome === 'destination') expect(l.shown, `${route}?${query} at ${rank}`).toBe(l.r.tab || effectiveTab(l.r.page, '', rank))
      if (l.outcome === 'tab-handoff') expect(refusedTab(l.r.page, l.r.tab, rank).min).toBeGreaterThan(rank)
    }
  }
  // the Platform Admin reaches every one; a Viewer is told who to ask for the rest
  expect(tally['6:page-handoff'] || 0).toBe(0)
  expect(tally['6:tab-handoff'] || 0).toBe(0)
  test.info().annotations.push({ type: 'UR-09', description: JSON.stringify(tally) })
})

// one journey per rank in the browser: six saved addresses, then Back and Forward through them
const JOURNEY = [['course-coverage', ''], ['layer-4-human-resolution', ''], ['layer-4-review', 'tab=aireview'], ['live-activity', ''], ['storage-retention', ''], ['administration', 'section=users-roles']]

test.describe('mocked browser', () => {
  for (let rank = 1; rank <= 6; rank++) {
    test(`${ROLE[rank][1]} (${rank}): saved addresses, then Back and Forward, each land on the destination or a named handoff`, async ({ page }) => {
      await asRole(page, rank)
      await mockInbox(page, rank)
      const steps = JOURNEY.map(([route, q]) => ({ addr: `#${route}${q ? `?${q}` : ''}`, ...landing(route, q, rank) }))
      const check = async (s) => {
        await expect.poll(() => page.evaluate(() => location.hash), { message: s.addr }).toBe(s.href)
        await expect(page.getByText('Workspace could not render')).toHaveCount(0)
        if (s.outcome === 'page-handoff') await expect(page.locator('[data-handoff]'), s.addr).toContainText(`${PAGES[s.r.page].label} opens from`)
        else await expect(page.locator('[data-handoff]'), s.addr).toHaveCount(0)
        if (s.outcome === 'tab-handoff') await expect(page.locator('[data-tab-handoff]'), s.addr).toContainText(`opens from`)
        else await expect(page.locator('[data-tab-handoff]'), s.addr).toHaveCount(0)
        if (s.outcome !== 'page-handoff' && shownTabs(PAGES[s.r.page], rank, s.shown).length > 1) {
          const label = PAGES[s.r.page].tabs.find((t) => t.key === s.shown).label
          await expect(page.locator('.cf-page-tabs [role="tab"][aria-selected="true"]'), s.addr).toHaveText(label)
        }
      }
      await page.goto('/#dashboard')
      for (const s of steps) { await page.goto('/' + s.addr); await check(s) }
      for (let i = steps.length - 2; i >= 0; i--) { await page.goBack(); await check(steps[i]) }
      for (let i = 1; i < steps.length; i++) { await page.goForward(); await check(steps[i]) }
    })
  }
})
