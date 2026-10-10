// CF-247 v2.15.225 (Platform Admin, 9 Oct 2026): lists fill the page width and their columns resize; course and provider
// detail panels open on coloured pills and fact cards; evidence, regulatory and operational blocks are gone from them.
import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import * as F from './support/admin-fixtures.mjs'

const read = p => readFileSync(new URL(`../../${p}`, import.meta.url), 'utf8')
async function override(page, op, data) {
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
    let b = {}; try { b = route.request().postDataJSON() || {} } catch {}
    if (b.p_operation === op) return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(data) })
    return route.fallback()
  })
}
const many = ['VN', 'IN', 'CN', 'NP', 'LK', 'BD', 'PK', 'ID', 'MY', 'TH', 'PH', 'KE', 'NG', 'GH', 'BR', 'CO', 'MX', 'PE', 'CL', 'AR']

test('scholarship list: a long nationality list cannot push columns off screen; every column shows at 1900 px', async ({ page }) => {
  await page.setViewportSize({ width: 1900, height: 900 })
  await mockAdmin(page)
  const items = Array.from({ length: 5 }).map((_, i) => ({ ...F.scholarshipRow, id: 's' + i, name: 'Scholarship ' + i, nationalities: i === 2 ? many : [], mapped_course_count: i, application_close_date: '2027-03-08', value_label: 'A$5,000' }))
  await override(page, 'scholarships_page', { total: 5, items })
  await page.goto('/#scholarships')
  const wrap = page.locator('.m-table-wrap').first()
  await expect(page.locator('tbody tr')).toHaveCount(5)
  await expect.poll(() => wrap.evaluate(e => e.scrollWidth - e.clientWidth)).toBeLessThanOrEqual(1)
  for (const h of ['Value', 'Courses', 'Closes']) await expect(page.locator('thead th', { hasText: h })).toBeInViewport()
  await expect(page.locator('tbody')).toContainText('Vietnam, India +18 more')
  const tw = await page.locator('table.m-fit-table').evaluate(e => e.getBoundingClientRect().width)
  const ww = await wrap.evaluate(e => e.clientWidth)
  expect(Math.abs(tw - ww)).toBeLessThanOrEqual(2) // fills the card width
})

test('columns resize by dragging the heading edge and reset on double-click', async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 900 })
  await mockAdmin(page)
  await page.goto('/#courses')
  await expect(page.locator('tbody tr').first()).toBeVisible()
  const th = page.locator('thead th').nth(1)
  const before = await th.evaluate(e => e.getBoundingClientRect().width)
  const h = page.locator('[data-col-resize]').nth(1)
  const box = await h.boundingBox()
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2)
  await page.mouse.down(); await page.mouse.move(box.x + 120, box.y + box.height / 2, { steps: 6 }); await page.mouse.up()
  await expect.poll(() => th.evaluate(e => e.getBoundingClientRect().width)).toBeGreaterThan(before + 60)
  await h.dblclick()
  await expect.poll(() => th.evaluate(e => Math.round(e.getBoundingClientRect().width))).toBe(Math.round(before))
})

test('course panel: pills and fact cards first; no regulatory, evidence or operational blocks', async ({ page }) => {
  await mockAdmin(page)
  await override(page, 'course_detail', { ...F.courseDetail, level_name: 'Diploma', field_name: 'Media', english: [{ test_name: 'IELTS Academic', overall_score: 6.5 }], intakes: [{ label: 'February', status: 'active' }],
    fee_summary: { ...F.courseDetail.fee_summary, fee_used: { source: 'page', year: 2027, per_year: 27500, currency: 'AUD', reason: 'Course page fee' } }, regulatory_facts: [{ scheme: 'cricos' }], evidence: [{ id: 'e1' }], state_summary: { search: 3 } })
  await page.goto('/#courses?id=0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5')
  const s = page.locator('[data-course-summary]')
  await expect(s.locator('[data-ds-pills] .cf-chip', { hasText: 'Diploma' })).toBeVisible()
  await expect(s.locator('[data-ds-pills]')).toContainText('CRICOS 111279A')
  await expect(s.locator('[data-ds-card="fee"]')).toContainText('A$27,500 a year')
  await expect(s.locator('[data-ds-card="fee"] [data-fee-used="page"]')).toContainText('Course page')
  await expect(s.locator('[data-ds-card="english"] .cf-chip')).toHaveText('IELTS Academic 6.5')
  await expect(s.locator('[data-ds-card="intakes"] .cf-chip')).toHaveText('February')
  const drawer = page.locator('.m-drawer')
  for (const t of ['Regulatory facts', 'Operational state', 'Arrange sections', 'Open Evidence']) await expect(drawer.getByText(t, { exact: true })).toHaveCount(0)
  await expect(page.locator('[data-editor="course"] .re-grid')).toHaveCount(1)
  await expect(page.locator('[data-course-more]')).not.toHaveAttribute('open', '')
})

test('provider panel: pills and fact cards; no raw identifier or evidence lists', async ({ page }) => {
  await mockAdmin(page)
  await override(page, 'provider_detail', { id: 'p1', canonical_name: 'RMIT University', country_code: 'AU', course_count: 509, scholarship_count: 307, publication_status: 'published', university_groups: [{ code: 'atn', name: 'Australian Technology Network' }], registrations: [{ scheme: 'cricos', code: '00122A' }], campuses_page: { total: 1, items: [{ name: 'City', city: 'Melbourne', course_count: 439 }] }, evidence: [{ id: 'x', content_hash: 'abc' }], identifiers: [{ scheme: 'cricos', identifier: '00122A' }], stable_key: 'provider:cricos:00122a' })
  await page.goto('/#providers?id=p1')
  const s = page.locator('[data-provider-summary]')
  await expect(s.locator('[data-ds-pills]')).toContainText('Australian Technology Network')
  await expect(s.locator('[data-ds-pills]')).toContainText('CRICOS 00122A')
  await expect(s.locator('[data-ds-pills] .cf-chip.tone-success')).toHaveText('Published')
  await expect(s.locator('[data-ds-card="courses"]')).toContainText('509')
  await expect(s.locator('[data-ds-card="campuses"] .cf-chip')).toHaveText('Melbourne · 439')
  const drawer = page.locator('.m-drawer')
  await expect(drawer.locator('[data-provider-facts]')).toHaveCount(0)
  await expect(drawer.getByText('provider:cricos:00122a')).toHaveCount(0)
  await expect(drawer.getByText('International contacts', { exact: true })).toHaveCount(1) // the card label only
})

test('source: shared summary kit, tokens only, one table component', () => {
  const ds = read('src/DetailSummary.jsx')
  for (const c of ['export function PillRow', 'export function FactCards', 'export function FactCard', 'export function CourseSummary', 'export function ProviderSummary']) expect(ds).toContain(c)
  expect(read('src/detail-summary.css')).not.toMatch(/#[0-9a-f]{3,8}\b/i)
  const main = read('src/mature-main.jsx')
  expect(main).toContain("tableLayout:'fixed'")
  expect(main).not.toContain('<ObjectSections data={data} exclude={[\'contextual_insights\',\'international_contacts\'')
})

test('v2.15.226: provider read is slim; related insights load when More is opened', async ({ page }) => {
  const m = read('supabase/migrations-archive/20261009006000_cf247_provider_detail_slim.sql')
  expect(m).toContain("'4949564e124715c4b0aabc1a39ccaafb'")
  expect(m).toContain("security.admin_provider_detail(v_id)-'courses'-'courses_page'-'evidence'-'evidence_page'-'sources'-'history'")
  expect(m).not.toContain("'scholarship_context',security.admin_provider_scholarships")
  expect(m).not.toMatch(/\b(drop|truncate|cascade)\b/i)
  await mockAdmin(page)
  const calls = []
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
    let b = {}; try { b = route.request().postDataJSON() || {} } catch {}
    if (b.p_operation === 'provider_detail') return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ id: 'p1', canonical_name: 'RMIT University', country_code: 'AU' }) })
    if (b.p_operation === 'provider_insights') { calls.push(b); return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ contextual_insights: {} }) }) }
    return route.fallback()
  })
  await page.goto('/#providers?id=p1')
  await expect(page.locator('[data-provider-summary]')).toBeVisible()
  await page.waitForTimeout(400)
  expect(calls.length).toBe(0)
  await page.locator('[data-provider-more] > summary').click()
  await expect.poll(() => calls.length).toBe(1)
  expect(calls[0].p_args).toEqual({ id: 'p1' })
})

test('v2.15.231: course read is slim; course insights load when More is opened', async ({ page }) => {
  const m = read('supabase/migrations-archive/20261010006300_cf247_course_detail_slim.sql')
  expect(m).toContain("'c4e339a7a8fc58307804b796cdb5cfd6'")
  expect(m).toContain("if p_operation='course_insights' then")
  expect(m).not.toContain("jsonb_build_object('ranking_context',security.admin_course_rankings")
  expect(m).not.toMatch(/\b(drop|truncate|cascade)\b/i)
  await mockAdmin(page)
  const calls = []
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
    let b = {}; try { b = route.request().postDataJSON() || {} } catch {}
    if (b.p_operation === 'course_insights') { calls.push(b); return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ contextual_insights: {} }) }) }
    return route.fallback()
  })
  await page.goto('/#courses?id=0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5')
  await expect(page.locator('[data-course-summary]')).toBeVisible()
  await page.waitForTimeout(400)
  expect(calls.length).toBe(0)
  await page.locator('[data-course-more] > summary').click()
  await expect.poll(() => calls.length).toBe(1)
})

test('v2.15.231: Logos tab is a simple list — with a logo, no logo — and no candidate pipeline counts', async ({ page }) => {
  await mockAdmin(page)
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
    let b = {}; try { b = route.request().postDataJSON() || {} } catch {}
    if (b.p_operation === 'provider_asset_summary') return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ expected: 10, approved: 7, discovered: 9, acquired: 8, blocked: 1, missing: 2 }) })
    if (b.p_operation === 'provider_asset_coverage') return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ total: 2, items: [{ provider_id: 'p1', provider_name: 'RMIT University', country_code: 'AU', coverage_state: 'approved', primary_mime_type: 'image/png' }, { provider_id: 'p2', provider_name: 'Example College', country_code: 'AU', coverage_state: 'missing' }] }) })
    return route.fallback()
  })
  await page.goto('/#providers?tab=assets')
  const l = page.locator('[data-logo-list]')
  await expect(l).toContainText('With a logo')
  await expect(l).toContainText('70% of providers')
  await expect(l.locator('[data-logo-row="yes"] .cf-chip')).toHaveText('Has logo')
  await expect(l.locator('[data-logo-row="no"] .cf-chip')).toHaveText('No logo')
  for (const t of ['Discovered', 'Acquired', 'Blocked', 'Coverage matrix']) await expect(l.getByText(t, { exact: true })).toHaveCount(0)
})
