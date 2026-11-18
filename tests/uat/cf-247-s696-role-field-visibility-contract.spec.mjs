// Guards: Role-based field visibility (Platform Admin 18 Nov 2026 21:23): Viewer and Counsellor see student-facing data only (no change tags, rule_id, confidence, hook_detail, prompt_version, Layer 4 queue state or raw quote diagnostics); Editor and Platform Admin keep provenance, audit badges and diagnostics; "Preview as: Admin | Counsellor | Viewer" in the drawer header shows a lower role's view and never raises one.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { routeCorrelated } from './support/correlated-fixtures.mjs'
import { ROLE_TIERS, FIELD_VISIBILITY, PREVIEW_ROLES, tierOfRank, effectiveTier, canSee, canPreview, visibilityMatrix, studentHideCss } from '../../src/lib/field-visibility.js'

const HIDDEN = ['change_tag', 'rule_id', 'confidence', 'hook_detail', 'prompt_version', 'layer4_queue_state', 'raw_quote']

test('the matrix: four roles, internal fields for Editor and Platform Admin only', () => {
  expect(ROLE_TIERS.map((t) => t.label)).toEqual(['Viewer', 'Counsellor', 'Editor', 'Platform Admin'])
  expect([1, 2, 3, 4, 5, 6].map(tierOfRank)).toEqual(['viewer', 'counsellor', 'editor', 'editor', 'editor', 'platform_admin'])
  for (const f of HIDDEN) {
    expect(FIELD_VISIBILITY.find((x) => x.field === f)?.audience, f).toBe('internal')
    expect([canSee(f, 'viewer'), canSee(f, 'counsellor'), canSee(f, 'editor'), canSee(f, 'platform_admin')], f).toEqual([false, false, true, true])
  }
  for (const f of ['value', 'source_link', 'attribution_text', 'climate_icon']) expect(['viewer', 'counsellor'].every((t) => canSee(f, t)), f).toBe(true)
  expect(canSee('something_new', 'counsellor')).toBe(false) // an unlisted field is internal until listed
  expect(visibilityMatrix()).toHaveLength(FIELD_VISIBILITY.length)
  for (const f of FIELD_VISIBILITY.filter((x) => x.audience === 'internal')) expect(f.selector, f.field).toBeTruthy()
  expect(studentHideCss()).toContain('[data-view-audience="student"] [data-vis="rule_id"]')
})

test('Preview as only lowers: Admin, Counsellor, Viewer; shown to Editor and Platform Admin', () => {
  expect(PREVIEW_ROLES.map((r) => r.label)).toEqual(['Admin', 'Counsellor', 'Viewer'])
  expect(effectiveTier(6, 'admin')).toBe('platform_admin')
  expect(effectiveTier(6, 'counsellor')).toBe('counsellor')
  expect(effectiveTier(3, 'viewer')).toBe('viewer')
  expect(effectiveTier(1, 'admin')).toBe('viewer')
  expect(effectiveTier(1, 'counsellor')).toBe('viewer') // never raises
  expect([1, 2, 3, 6].map(canPreview)).toEqual([false, false, true, true])
})

test.describe('mocked browser', () => {
  test('Platform Admin previews the course drawer as a Counsellor and back', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    await routeCorrelated(page)
    await page.goto('/#courses?id=0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5')
    const drawer = page.locator('aside.m-drawer')
    await expect(drawer).toHaveAttribute('data-view-audience', 'internal')
    const share = drawer.locator('[data-cb-card="location"] [data-vis="confidence"]')
    await expect(share).toBeVisible()
    await expect(drawer.locator('[data-vis="raw_quote"]').first()).toBeVisible()
    await drawer.locator('[data-preview-role="counsellor"]').click()
    await expect(drawer).toHaveAttribute('data-view-tier', 'counsellor')
    await expect(drawer).toHaveAttribute('data-view-audience', 'student')
    await expect(share).toBeHidden()
    await expect(drawer.locator('[data-vis="raw_quote"]').first()).toBeHidden()
    await expect(drawer.locator('[data-vis="rule_id"]').first()).toBeHidden()
    await expect(drawer.locator('[data-vis="dataset_edition"]').first()).toBeHidden()
    // student-facing values stay
    await expect(drawer.locator('[data-cb-fact="summer"]')).toBeVisible()
    await expect(drawer.locator('[data-cb-attribution]')).toBeVisible()
    await drawer.locator('[data-preview-role="admin"]').click()
    await expect(share).toBeVisible()
  })

  test('a Counsellor gets no switcher, a student-facing drawer and the live figures (v2.16.47, s712)', async ({ page }) => {
    await mockAdmin(page, { rank: 2 })
    await routeCorrelated(page)
    await page.goto('/#courses?id=0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5')
    const drawer = page.locator('aside.m-drawer')
    await expect(drawer.locator('[data-correlated="course"]')).toBeVisible()
    await expect(drawer).toHaveAttribute('data-view-audience', 'student')
    await expect(drawer.locator('[data-preview-as]')).toHaveCount(0)
    await expect(drawer.locator('[data-cb-read-gap]')).toHaveCount(0)
    await expect(drawer.locator('[data-cb-fact="summer"]').first()).toBeVisible()
    await expect(drawer.locator('[data-cb-attribution]').first()).toBeVisible()
    await expect(drawer.locator('[data-vis="raw_quote"]').first()).toBeHidden()
  })

  test('a failed figure read shows one plain note, not an empty card (v2.16.47)', async ({ page }) => {
    await mockAdmin(page, { rank: 2 })
    await routeCorrelated(page)
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_destination_review', r => r.fulfill({ status: 403, json: { code: '42501', message: 'Curator role or above required' } }))
    await page.goto('/#courses?id=0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5')
    const drawer = page.locator('aside.m-drawer')
    await expect(drawer.locator('[data-correlated="course"]')).toBeVisible()
    await expect(drawer.locator('[data-cb-card="careers"] [data-cb-read-gap]')).toBeVisible()
  })
})
