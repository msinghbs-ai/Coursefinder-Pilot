// Guards: Platform Admin 19 Nov 2026 16:18 (chat S1-RM-Design, s767): Layer 4 Review › Grid filters by Country (All, Australia, New Zealand, Canada) and Provider type (All, University, VET / College, School, HEI) beside the kind and reason filters; the server filters before it pages, so the count and the rows agree; a read only change that is not the consumer API (Decision 266, G3).
// CF-247 S1-RM-Design s767 (the file name is distinct: other lanes also hold an s767 spec for a different change). supabase/migrations/20261119173000_cf247_s767_layer4_grid_country_type_filters.sql, src/Layer4Grid.jsx
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const M = fs.readFileSync('supabase/migrations/20261119173000_cf247_s767_layer4_grid_country_type_filters.sql', 'utf8')
const G = fs.readFileSync('src/Layer4Grid.jsx', 'utf8')

test('the migration is md5-guarded, filters before the page is cut, and groups the register types as the screen names them', () => {
  expect(M).toContain('3bbc37e32eb9ae7fe5e63cd7ea216c16')
  expect(M).toContain("k.iso_alpha2::text = v_cty")
  expect(M).toContain("v_pt <> all (array[''university'', ''hei'', ''vet_college'', ''school''])")
  expect(M).toContain("when ''university'' then array[''university'', ''university_college'', ''wananga'']")
  expect(M).toContain("when ''hei'' then array[''higher_education_institute'']")
  expect(M).toContain("when ''vet_college'' then array[''tafe_polytechnic'', ''private_vet'']")
  expect(M).toContain("else array[''school'']")
  expect(M).toMatch(/^-- Replaces: .+/m)
  expect(M).toMatch(/^-- Retires: nothing$/m)
  const code = M.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
  expect(code).not.toMatch(/\bcreate\s+(table|function)\b|\bdelete\s+from\b|\bdrop\b|\binsert\s+into\b|\bupdate\s+(pipeline|catalogue)\./i)
})

test('the grid sends both filters and offers exactly the pills the Platform Admin named', () => {
  expect(G).toContain("country:cty||undefined,provider_type:ptype||undefined")
  // s930 (S1-Dynamic-Lookups): the country pills are the live target countries, labelled name (code), with All first
  expect(G).toContain("const countryPills=lk=>[['','All'],...countryPairs(lk,{label:c=>`${c.name} (${c.code})`})]")
  expect(G).toContain("[['','All'],['university','University'],['vet_college','VET / College'],['school','School'],['hei','HEI']]")
  expect(G).toContain('[kind,why,sort,cty,ptype]')
})

const kinds = { provider_description: { label: 'Provider description', order: 1, choices: [] } }
async function openGrid(page, calls) {
  await mockAdmin(page, { rank: 6 })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
    const b = route.request().postDataJSON()
    if (b.p_action === 'summary') return route.fulfill({ json: { kinds, target_days: 7, rank: 6, total: 3, universities: 2, late: 0, by_kind: { provider_description: { n: 3 } } } })
    return route.fulfill({ json: { total: 0, items: [] } })
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_saved_views_read_v1', (route) => route.fulfill({ json: { views: [], grid_kinds: ['provider_description'], can_edit_shared: true } }))
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_grid_read_v1', async (route) => {
    const a = route.request().postDataJSON().p_args; calls.push(a)
    const rows = [
      { kind: 'provider_description', ref: 'r1', provider: 'Monash University', country: 'AU', subject: 'Provider description', why: 'audit_sample', created_at: '2026-11-10T00:00:00Z', age_days: 9 },
      { kind: 'provider_description', ref: 'r2', provider: 'Massey University', country: 'NZ', subject: 'Provider description', why: 'audit_sample', created_at: '2026-11-11T00:00:00Z', age_days: 8 }]
    const out = rows.filter((r) => !a.country || r.country === a.country)
    return route.fulfill({ json: { total: out.length, offset: a.offset || 0, limit: 200, kind: a.kind, sort: 'oldest', export: false, kind_label: 'Provider description', rank: 6, rows: a.offset > 1000 ? [] : out } })
  })
  await page.goto('/#layer-4-review?view=grid')
  await expect(page.locator('[data-l4g-grid]')).toBeVisible()
  await page.locator('[data-l4g-kind]').selectOption('provider_description')
  await expect(page.locator('[data-l4g-total]')).toContainText('2 waiting')
}

test.describe('mocked browser', () => {
  test('Country and Provider type pills narrow the grid: the request carries the choice, the count follows, All clears it', async ({ page }) => {
    const calls = []
    const main = () => calls.filter((a) => !(a.offset > 1000)) // the pill counts are read with an offset past the end
    await openGrid(page, calls)
    // s767 (19:26): drawn flags, the country code in the label, and a live count on each pill
    await expect(page.locator('[data-l4g-country-pills] button')).toHaveText([/^All/, /^Australia \(AU\)/, /^New Zealand \(NZ\)/, /^Canada \(CA\)/])
    await expect(page.locator('[data-l4g-ptype-pills] button')).toHaveText([/^All/, /^University/, /^VET \/ College/, /^School/, /^HEI/])
    for (const c of ['AU', 'NZ', 'CA']) await expect(page.locator(`[data-l4g-country="${c}"] svg.pl-flag`)).toHaveCount(1)
    await expect(page.locator('[data-l4g-country="all"] [data-l4g-n]')).toHaveText('2')
    await expect(page.locator('[data-l4g-country="AU"] [data-l4g-n]')).toHaveText('1')
    await expect(page.locator('[data-l4g-country="NZ"] [data-l4g-n]')).toHaveText('1')
    await expect(page.locator('[data-l4g-country="CA"] [data-l4g-n]')).toHaveText('0')
    await expect(page.locator('[data-l4g-country="all"]')).toHaveAttribute('aria-pressed', 'true')
    await page.locator('[data-l4g-country="NZ"]').click()
    await expect(page.locator('[data-l4g-total]')).toContainText('1 waiting')
    expect(main().at(-1)).toMatchObject({ kind: 'provider_description', country: 'NZ' })
    expect(main().at(-1).provider_type).toBeUndefined()
    await page.locator('[data-l4g-ptype="vet_college"]').click()
    await expect.poll(() => main().at(-1).provider_type).toBe('vet_college')
    expect(main().at(-1)).toMatchObject({ country: 'NZ', provider_type: 'vet_college' })
    await expect(page.locator('[data-l4g-ptype="vet_college"]')).toHaveAttribute('aria-pressed', 'true')
    await page.locator('[data-l4g-country="all"]').click()
    await page.locator('[data-l4g-ptype="all"]').click()
    await expect(page.locator('[data-l4g-total]')).toContainText('2 waiting')
    expect(main().at(-1).country).toBeUndefined()
    expect(main().at(-1).provider_type).toBeUndefined()
  })
})

test.describe('phone @responsive', () => {
  test('the pills wrap inside the screen at phone width and each is a usable tap target', async ({ page }) => {
    const w = page.viewportSize().width
    expect(w, 'this test runs on the phone project only').toBeLessThanOrEqual(480)
    await openGrid(page, [])
    for (const sel of ['[data-l4g-country-pills] button', '[data-l4g-ptype-pills] button']) {
      for (const b of await page.locator(sel).all()) {
        const r = await b.boundingBox()
        expect(r.x + r.width, 'inside the screen').toBeLessThanOrEqual(w + 1)
        expect(r.height, 'tap target').toBeGreaterThanOrEqual(24)
      }
    }
    expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(1)
  })
})
