// CF-247 v2.15.171 (Platform Admin, 3 Oct 2026 23:27 and 23:30): the live scholarship screens follow the mockup —
// the list (columns, status pills, courses line), the record drawer (one row per fact, source, Change, hand back),
// Scholarship publishing (four tiles, reasons with what they mean) and the course drawer's scholarship cards.
import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import * as F from './support/admin-fixtures.mjs'

const read = p => readFileSync(new URL(`../../${p}`, import.meta.url), 'utf8')
const SCH = '5f92fc8c-ad2b-5182-a3b7-2e9bba5b3d99'

async function override(page, op, data) {
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
    let b = {}; try { b = route.request().postDataJSON() || {} } catch {}
    if (b.p_operation === op) { (page.readCalls ||= []).push(b); return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(data) }) }
    return route.fallback()
  })
}

test('migrations shaped: status, record read, hand edits for audience and nationalities, publishing failing list', () => {
  for (const f of ['20261003003000_cf247_scholarships_page_status', '20261003003100_cf247_scholarship_screens_to_mockup']) {
    const m = read(`supabase/migrations-archive/${f}.sql`)
    for (const word of ['drop', 'delete from', 'truncate', 'on delete cascade']) expect(m.toLowerCase()).not.toContain(word)
    expect(m).not.toMatch(/set\s+publication_status\s*=\s*'published'/)
  }
  const m = read('supabase/migrations-archive/20261003003100_cf247_scholarship_screens_to_mockup.sql')
  expect(m).toContain("k.field in ('award_amount', 'award_percentage', 'award_value_type', 'award_value_text')")
  expect(m).toContain("perform security.manual_lock_set('scholarship', p_scholarship_id, 'audience', 'value');")
  expect(m).toContain("perform security.manual_lock_set('scholarship', p_scholarship_id, 'nationalities', 'value');")
  expect(m).toContain('create or replace function public.admin_scholarship_record_read(p_id uuid)')
  expect(m).toContain("'published_failing',")
  for (const h of ['994d9c4de7d9d1837b8a9d625b9df0d6', '1e8c07f7235810fa7925d367ece9fac1', 'f4f6a010181049c35283bb072a4b7e30', 'f21f413bfeff5ac2479df06e5258036f']) expect(m).toContain(`is distinct from '${h}'`)
})

test('browser: list shows published scholarships only — no status pills or status filters (v2.15.172)', async ({ page }) => {
  await mockAdmin(page)
  const row = { ...F.scholarshipRow, value_label: 'A$10,000 a year', nationalities: ['VN'], status: 'held', held_reasons: ['no linked course'], mapped_course_count: 12, application_close_date: '2027-03-08' }
  await override(page, 'scholarships_page', { total: 1, items: [row], status_counts: { published: 123, ready: 268, held: 844, inactive: 25 } })
  await page.goto('/#scholarships')
  for (const h of ['Scholarship', 'Provider', 'Type', 'Who it is for', 'Value', 'Courses', 'Closes']) {
    const th = page.locator('thead th', { hasText: h }).first()
    await expect(th).toBeVisible()
    await expect(th.locator('button')).toBeEnabled() // v2.15.223: every column heading sorts
  }
  await expect(page.locator('thead th', { hasText: 'Status' })).toHaveCount(0)
  await expect(page.locator('[data-scholarship-status]')).toHaveCount(0)
  for (const l of ['Lifecycle', 'Publication']) await expect(page.locator('.m-filter-bar').getByText(l, { exact: true })).toHaveCount(0)
  await expect.poll(() => (page.readCalls || []).filter(c => c.p_operation === 'scholarships_page').map(c => c.p_args?.status)).toContain('published')
  await expect(page.locator('[data-sch-courses]').first()).toContainText('12 linked')
  // v2.15.224: coloured pills (shared StatusChip tones) for courses, type, who it is for and the closing date
  await expect(page.locator('[data-sch-courses] .cf-chip.tone-success')).toHaveCount(1)
  await expect(page.locator('tbody .cf-chip.tone-violet', { hasText: 'International students' })).toHaveCount(1)
  await expect(page.locator('tbody td').last().locator('.cf-chip')).toHaveCount(1)
  // v2.15.223: the columns fit the screen (no sideways scroll at 1280 px)
  await page.setViewportSize({ width: 1280, height: 760 })
  await expect.poll(() => page.locator('.m-table-wrap').first().evaluate(e => e.scrollWidth - e.clientWidth)).toBeLessThanOrEqual(1)
  await expect(page.locator('tbody')).toContainText('Vietnam')
  await expect(page.locator('tbody')).toContainText('A$10,000 a year')
})

test('browser: record drawer — rows with their source, change who it is for, hand a value back', async ({ page }) => {
  await mockAdmin(page)
  page.on('dialog', d => d.accept())
  await page.goto(`/#scholarships?id=${SCH}`)
  const r = page.locator('[data-scholarship-record]')
  await expect(r.locator('[data-sch-record-status]')).toHaveCount(0)
  await expect(r.locator('[data-sr-row="courses"]')).toContainText('Bachelor 1')
  await r.locator('[data-sr-courses] summary').click()
  await expect(r.locator('[data-sr-courses] li')).toContainText('Bachelor of Business')
  await expect(r.locator('[data-sr-row="value"]')).toContainText('A$10,000 a year')
  await expect(r.locator('[data-sr-row="value"]')).toContainText('Page: “AUD $10,000 annually”')
  await expect(r.locator('[data-sr-row="nationalities"]')).toContainText('Vietnam')
  await expect(r.locator('[data-sr-row="audience"] [data-sr-source]')).toHaveText('Entered by hand')
  await expect(r.locator('[data-sr-row="value"] [data-sr-source]')).toHaveText('Read from page')
  await r.getByRole('button', { name: 'Change Who it is for' }).click()
  await r.locator('[data-sr-row="audience"] select').selectOption('international_and_domestic')
  await r.locator('[data-sr-row="audience"]').getByRole('button', { name: 'Save' }).click()
  await expect.poll(() => page.l3calls.find(c => c.p_action === 'set_audience')?.p_args?.value).toBe('international_and_domestic')
  await r.locator('[data-sr-row="audience"]').getByRole('button', { name: 'Let automation update this' }).click()
  await expect.poll(() => page.l3calls.find(c => c.p_action === 'release')?.p_args).toEqual({ field: 'audience' })
  await r.getByRole('button', { name: 'Change Nationalities' }).click()
  await r.locator('[data-sr-row="nationalities"]').getByLabel('India').check()
  await r.locator('[data-sr-row="nationalities"]').getByRole('button', { name: 'Save' }).click()
  await expect.poll(() => page.l3calls.find(c => c.p_action === 'set_nationalities')?.p_args?.value).toEqual(['VN', 'IN'])
})

test('browser: publishing — four tiles and the reasons with what they mean', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#layer-4-review?tab=publishing')
  await expect(page.getByText('Published but now failing a check').first()).toBeVisible()
  const why = page.locator('[data-publishing-reasons]')
  await why.locator('[data-reason="no linked course"]').click()
  await expect(why.locator('[data-reason-detail]')).toContainText('It applies to no course in StudySearch yet.')
  await expect(why.locator('[data-reason-detail] a')).toHaveCount(0) // v2.15.174: Course links retired; links come from the page
})

test('browser: course drawer — published scholarship cards with saving and estimate', async ({ page }) => {
  await mockAdmin(page)
  const items = [
    { mapping_id: 'm1', scholarship_id: 's1', name: 'Global Excellence Scholarship', audience: 'international', nationalities: [], value_label: '25% of tuition fees', publication_status: 'published', lifecycle_status: 'active', application_close_date: null, source_url: 'https://example.edu/ges', calculation: { fee_basis: 'estimated_annual_from_registered_total', scholarship_saving_amount: 8000, net_fee_amount: 24000, currency_code: 'AUD' } },
    { mapping_id: 'm2', scholarship_id: 's2', name: 'Vietnam Pathway Award', audience: 'international', nationalities: ['VN'], value_label: 'A$5,000', publication_status: 'unpublished', lifecycle_status: 'active' },
  ]
  await override(page, 'course_detail', { ...F.courseDetail, course_scholarships: { items } })
  await page.goto('/#courses?id=0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5')
  const p = page.locator('[data-course-scholarships]')
  await expect(p.locator('[data-cs-card]')).toHaveCount(1)
  await expect(p.locator('[data-cs-saving]')).toContainText('estimate from the registered CRICOS course cost')
  // v2.15.172: published only — no toggle and no status chips
  await expect(p.getByLabel('Include not yet published')).toHaveCount(0)
  await expect(p).not.toContainText('Not published')
})

// Decision 250 (v2.15.172): New Zealand and Canadian scholarships
async function loadReader() {
  const { execFileSync } = await import('node:child_process'); const os = await import('node:os'); const path = await import('node:path')
  const out = path.join(os.tmpdir(), `sch-nzca-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', ['supabase/functions/coverage-sweep/scholarship.ts', '--bundle', '--format=esm', `--outfile=${out}`])
  return import(out)
}
test('reader v0.6.0: amounts in the provider country currency; NZ and Canadian domestic wording', async () => {
  const { scholarshipValue, internationalEligibility } = await loadReader()
  const nz = 'The scholarship is worth $10,000 for international students.'
  expect(scholarshipValue(nz, '', 'NZD')).toMatchObject({ type: 'fixed_amount', amount: 10000, currency: 'NZD' })
  expect(scholarshipValue('The award is valued at NZ$5,000 per year.', '', 'NZD')).toMatchObject({ type: 'fixed_amount', amount: 5000, currency: 'NZD' })
  expect(scholarshipValue('The award is valued at C$8,000 per year.', '', 'CAD')).toMatchObject({ type: 'fixed_amount', amount: 8000, currency: 'CAD' })
  // an Australian page naming a New Zealand dollar amount is no longer read as AUD
  expect(scholarshipValue('The scholarship is worth NZ$5,000.', '', 'AUD')).toMatchObject({ type: 'ambiguous', foreign_currency: true })
  // Australia unchanged
  expect(scholarshipValue('The scholarship is worth A$10,000 per year.')).toMatchObject({ type: 'fixed_amount', amount: 10000, currency: 'AUD' })
  expect(internationalEligibility('Open to Canadian citizens or permanent residents only.').excluded).toBe(true)
  expect(internationalEligibility('Must be a New Zealand citizen.').excluded).toBe(true)
  expect(internationalEligibility('Students holding a valid study permit are eligible.').explicit).toBe(true)
})
test('migration 20261004000100 shaped: currency, universities, discovery, Layer 1 sources', () => {
  const m = read('supabase/migrations-archive/20261004000100_cf247_scholarships_nz_ca.sql')
  for (const word of ['drop', 'delete from', 'truncate', 'on delete cascade']) expect(m.toLowerCase()).not.toContain(word)
  expect(m).toContain('create or replace function scholarship.provider_currency(p_provider_id uuid)')
  expect(m).toContain('create or replace function security.scholarship_university(p_provider_id uuid)')
  expect(m).toContain("'nz_mfat_manaaki'")
  expect(m).toContain("'ca_gac_study_in_canada'")
  expect(m).toContain('pipeline.coverage_provider_discovery')
  expect(m).not.toMatch(/set\s+publication_status\s*=\s*'published'/)
  const idx = read('supabase/functions/coverage-sweep/index.ts')
  expect(idx).toMatch(/scholarship-sweep-v0\.[4-9]\.\d/)
  expect(idx).toContain('scholarshipFacts(pg.html, titleOf(pg.html) + " " + h1Of(pg.html), adm.name || "", it.currency || "AUD")')
})

test('reader v0.6.1: numeric character references in a scholarship title are decoded', async () => {
  const { scholarshipTitle } = await loadReader()
  expect(scholarshipTitle('<html><head><title>x</title></head><body><h1>Vice-Chancellor&#039;s International Excellence Scholarship</h1></body></html>')).toBe("Vice-Chancellor's International Excellence Scholarship")
  expect(scholarshipTitle('<h1>UTS President&#x27;s Scholarship</h1>')).toBe("UTS President's Scholarship")
})
