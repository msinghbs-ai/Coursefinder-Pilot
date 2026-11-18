// Guards: Correlated read-only drawer sections (Platform Admin 18 Nov 2026 21:23; admin docs/platform/2026-11-18-correlated-blades-role-visibility-mockup.md): the Course drawer shows Location & weather (BOM, ABS), Career pathway (JSA, with an empty state while figures load), Visa & living-cost snapshot (Home Affairs) and Entry requirements & scholarships; the Provider drawer shows Rankings (QS, THE, ARWU, subject), Campus city profiles and Scholarships & accreditations. Joins are client-side over existing reads only (zero schema) and every card follows CARD_SPEC.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { routeCorrelated, L1, metrics, careers, ruleRows, courseDestination, providerDestination } from './support/correlated-fixtures.mjs'
import { CARD_SPEC, campusLocalities, cityProfile, careerOutlook, visaSnapshot, rankingSnapshot, EMPTY_CAREERS } from '../../src/lib/correlation-adapters.js'

const read = (p) => fs.readFileSync(p, 'utf8')

test('CARD_SPEC lists every card and its fields, each with a column and an audience', () => {
  expect(CARD_SPEC.course.map((c) => c.id)).toEqual(['location', 'careers', 'visa', 'entry'])
  expect(CARD_SPEC.provider.map((c) => c.id)).toEqual(['rankings', 'campus_cities', 'scholarships_accreditations'])
  for (const c of [...CARD_SPEC.course, ...CARD_SPEC.provider]) {
    expect(c.join.length).toBeGreaterThan(10)
    for (const f of c.fields) { expect(f.column, `${c.id}.${f.key}`).toBeTruthy(); expect(['student', 'internal']).toContain(f.audience) }
  }
  const keys = CARD_SPEC.course.find((c) => c.id === 'location').fields.map((f) => f.key)
  for (const k of ['summer_max', 'summer_min', 'winter_max', 'winter_min', 'rainfall', 'population', 'attribution']) expect(keys).toContain(k)
})

test('adapters: campus to city, city profile with icon, careers empty state, visa snapshot, rankings by system', () => {
  const locs = campusLocalities([{ name: 'RMIT University - 124 Latrobe Street, Melbourne' }], providerDestination.campuses)
  expect(locs).toHaveLength(1)
  expect(locs[0]).toMatchObject({ locality: { locality_id: L1, name: 'Melbourne' }, is_primary: true, match_share: 0.987 })
  // no course campus matched: the primary campus stands in
  expect(campusLocalities([{ name: 'Somewhere else' }], providerDestination.campuses)[0].campus).toContain('Latrobe')
  const p = cityProfile(L1, metrics)
  expect(p.climate).toEqual({ summer_max: 26.1, summer_min: 14.6, winter_max: 14.2, winter_min: 6.4, rainfall: 648 })
  expect(p.icon).toBe('rain')
  expect(p.population).toMatchObject({ value: 5350705, period: '2024' })
  expect(p.attribution).toHaveLength(2)
  expect(cityProfile(L1, metrics.map((x) => ({ ...x, status: 'draft' })), { student: true }).has_climate).toBe(false)
  expect(careerOutlook('asced-0803', careers).state).toBe('figures_loading')
  expect(careerOutlook('asced-0803', []).state).toBe('not_loaded')
  const linked = careerOutlook('asced-0803', [{ ...careers[0], study_area_code: '08', median_salary: 98000, job_outlook_rating: 'Strong', skill_shortage_status: 'Shortage' }])
  expect(linked).toMatchObject({ state: 'matched', items: [{ occupation: 'Accountant', median_salary: 98000, shortage: 'Shortage' }] })
  for (const k of ['not_loaded', 'figures_loading', 'no_field_link']) expect(EMPTY_CAREERS[k]).toBeTruthy()
  const v = visaSnapshot(courseDestination.study_rules, ruleRows)
  expect(v).toMatchObject({ rules: 3, work_hours_fortnight: 48, post_study_work: null, financial_capacity: null })
  expect(v.visa_fees[0]).toMatchObject({ amount: 2500, currency: 'AUD' })
  const r = rankingSnapshot([{ system_code: 'qs_wur', edition_year: 2026, rank_display: '140' }, { system_code: 'qs_wur', edition_year: 2027, rank_display: '123' }, { system_code: 'qs_subject_business', subject_name: 'Business', edition_year: 2026, rank_display: '51-100' }])
  expect(r.systems.map((s) => s.code)).toEqual(['qs_wur', 'the_wur', 'arwu'])
  expect(r.systems[0]).toMatchObject({ latest: { year: 2027, rank: '123' }, previous: { year: 2026, rank: '140' } })
  expect(r.subject).toEqual([{ label: 'Business', year: 2026, rank: '51-100' }])
})

test('zero schema: the sections read existing functions only, and no migration came with them', () => {
  const src = read('src/CorrelatedBlade.jsx')
  const rpcs = [...src.matchAll(/rpc\('([a-z0-9_]+)'/g)].map((x) => x[1]).filter((x, i, a) => a.indexOf(x) === i).sort()
  expect(rpcs).toEqual(['admin_course_destination_read', 'admin_destination_review', 'admin_entry_requirements', 'admin_provider_destination_read'])
  expect(src).toContain('api.providerRankingHistory(providerId)')
  expect(src).not.toMatch(/\.from\(|\.(insert|update|upsert)\(/)
  expect(fs.readdirSync('supabase/migrations').filter((f) => /correlat|role_visib|metric_type/i.test(f))).toEqual([])
  const main = read('src/mature-main.jsx')
  expect(main).toContain('<CourseCorrelated data={data} rank={rank}/>')
  expect(main).toContain('<ProviderCorrelated data={data} rank={rank}/>')
  expect(read('src/correlated-blade.css')).not.toMatch(/#[0-9a-fA-F]{3,8}\b/)
})

test.describe('mocked browser', () => {
  test('Course drawer: Melbourne weather and population, careers empty state, visa snapshot, entry and scholarships', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    await routeCorrelated(page)
    await page.goto('/#courses?id=0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5')
    const c = page.locator('[data-correlated="course"]')
    await expect(c).toBeVisible()
    const loc = c.locator('[data-cb-card="location"]')
    await expect(loc.locator('[data-cb-city="Melbourne"]')).toBeVisible()
    await expect(loc.locator('[data-cb-climate="rain"]')).toBeVisible()
    await expect(loc.locator('[data-cb-fact="summer"]')).toContainText('26.1°')
    await expect(loc.locator('[data-cb-fact="winter"]')).toContainText('14.2°')
    await expect(loc.locator('[data-cb-fact="rainfall"]')).toContainText('648 mm')
    await expect(loc.locator('[data-cb-fact="population"]')).toContainText('5,350,705')
    await expect(loc.locator('[data-cb-attribution]')).toContainText('Bureau of Meteorology')
    await expect(c.locator('[data-cb-card="careers"] [data-cb-empty="careers"]')).toContainText('salary, growth and shortage figures arrive')
    const visa = c.locator('[data-cb-card="visa"]')
    await expect(visa.locator('[data-cb-fact="work_hours"]')).toContainText('48 hours a fortnight')
    await expect(visa.locator('[data-cb-fact="visa_fee"]')).toContainText('2,500')
    await expect(visa.locator('[data-cb-fact="financial_capacity"]')).toContainText('Not held yet')
    await expect(c.locator('[data-cb-entry]')).toContainText('60 (ATAR)')
    await expect(c.locator('[data-cb-read-gap]')).toHaveCount(0)
    // nothing overflows the drawer
    const over = await c.evaluate((el) => [...el.querySelectorAll('.cb-card')].some((x) => x.scrollWidth > x.clientWidth + 1))
    expect(over).toBe(false)
  })

  test('Provider drawer: rankings by system, campus city profiles, scholarships and accreditations', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    await routeCorrelated(page)
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', (r) => (r.request().postDataJSON() || {}).p_operation === 'provider_detail'
      ? r.fulfill({ json: { id: 'p1', canonical_name: 'RMIT University', country_code: 'AU', course_count: 509, scholarship_count: 307, publication_status: 'published', accreditations: [{ body_code: 'AMBA', status: 'under_review' }] } }) : r.fallback())
    await page.goto('/#providers?id=p1')
    const p = page.locator('[data-correlated="provider"]')
    await expect(p).toBeVisible()
    await expect(p.locator('[data-cb-rank="qs_wur"]')).toContainText('#13')
    await expect(p.locator('[data-cb-rank="arwu"]')).toContainText('Not ranked')
    await expect(p.locator('[data-cb-subject]')).toContainText('No subject rank')
    await expect(p.locator('[data-cb-card="campus_cities"] [data-cb-city="Melbourne"] [data-cb-fact="population"]')).toContainText('5,350,705')
    await expect(p.locator('[data-cb-card="campus_cities"] [data-vis="layer4_queue_state"]')).toBeVisible()
    await expect(p.locator('[data-cb-fact="accreditations"]')).toBeVisible()
    // v2.16.47 (s712): accreditations come from provider_detail; a row under review is marked for Editors and up
    await expect(p.locator('[data-cb-accreditation="AMBA"]')).toContainText('AMBA (under review)')
    await expect(p.locator('[data-cb-fact="registration"]')).toContainText('00122A')
  })
})
