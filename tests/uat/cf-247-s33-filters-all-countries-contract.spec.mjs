// CF-247 v2.15.270 (S33): Platform Admin, 14 Oct 2026 07:13: "Bug/fix: Courses > state filter is not showing options for nz and Canada.
// Cross check all filters across all pages and report all relevant drop down options are visible."
// A course's region falls back to its provider's region when no campus region is recorded (all NZ and Canadian courses); delivery reads the
// course's own mode first; an empty filter says why; Data Quality, Enrichment operations, Provider assets, Key dates, Regulatory sources,
// the Layer 4 currency, the contacts provider picker and Websites to find cover every catalogue country.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const read = f => fs.readFileSync(f, 'utf8')
const mig = read('supabase/migrations/20261014013000_cf247_filters_all_countries.sql')
const fix = read('supabase/migrations/20261014013100_cf247_provider_assets_country_fix.sql')

test('regions: campus region, else the provider region, in the options, the filter and the list', () => {
  expect(mig).toContain('join ref.subdivisions s on s.id=p.subdivision_id')
  expect(mig).toContain("or (p.subdivision_id=v_sub_id and not exists(")
  expect(mig).toContain("case when coalesce(geo.region_count,0)>0 then 'campus' when psd.id is not null then 'provider' else null end region_source")
  expect(mig).toContain('(v_has_state is null or (p.subdivision_id is not null or exists(')
  // both list paths (filtered and first page) use the provider region
  expect(mig.split('left join ref.subdivisions psd on psd.id=(select p2.subdivision_id from catalogue.providers p2 where p2.id=pg.provider_id)').length).toBe(3)
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(mig).toContain("raise exception 'v2.15.270 post-check: % not as intended'")
})

test('delivery: the course mode first, readable labels; empty filters say why', () => {
  expect(mig).toContain("coalesce(nullif(btrim(c.delivery_mode),''),cc.delivery_mode) m")
  expect(mig).toContain("upper(left(replace(m,'_',' '),1))||substr(replace(m,'_',' '),2) label")
  expect(mig).toContain("coalesce(nullif(btrim(pg.canonical_delivery_mode),''),case when dm.mode_count=1")
  expect(mig).toContain("when 'university_group' then 'No university groups are set up for this country.'")
  expect(mig).toContain("when 'field' then 'Field of study is not classified for this country yet.'")
  expect(read('src/mature-main.jsx')).toContain("{(!search&&data.empty_reason)||'No matching options'}")
})

test('every catalogue country: Data Quality, Enrichment operations, Provider assets and the screens', () => {
  expect(mig).toContain('CREATE OR REPLACE FUNCTION security.catalogue_country_codes_v1()')
  expect(mig).toContain("if v_country is not null and not (v_country = any(security.catalogue_country_codes_v1())) then")
  expect(mig).toContain("'refresh_mode','computed_when_opened'")
  expect(mig).not.toMatch(/not in ?\('AU', ?'NZ'\)/)
  expect(fix).toContain('v_codes text[]:=security.catalogue_country_codes_v1();')
  expect(fix).not.toContain('any((select')
  expect(read('src/data-quality-entry.jsx')).toContain("const DQ_COUNTRY={AU:'Australia',NZ:'New Zealand',CA:'Canada'}")
  expect(read('src/KeyDates.jsx')).toContain("CA:'Canada'")
  expect(read('src/RegulatorySettings.jsx')).toContain("const IN_SCOPE = ['AU', 'NZ', 'CA']")
  expect(read('src/m2-3-intelligence-entry.jsx')).toContain('<option>CAD</option>')
  expect(read('src/ScholarshipRecord.jsx')).not.toContain('A$)')
  expect(read('src/ProviderContactsWorkspace.jsx')).toContain("country={filters.country||''}")
  expect(read('src/WebsitesToFind.jsx')).toContain('allCounts||data.countries')
  expect(read('src/PriorityQueue.jsx')).toContain('<option value="state">State or region</option>')
})

test.describe('mocked browser', () => {
  test('Courses: an empty university group list says why', async ({ page }) => {
    await mockAdmin(page)
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
      let b = {}
      try { b = route.request().postDataJSON() || {} } catch {}
      if (b.p_operation !== 'catalogue_filter_page') return route.fallback()
      const k = b.p_args?.filter_kind
      const body = k === 'university_group'
        ? { items: [], total: 0, limit: 10, offset: 0, has_more: false, empty_reason: 'No university groups are set up for this country.' }
        : { items: k === 'subdivision' ? [{ value: 'NZ-AUK', label: 'Auckland', meta: 'NZ-AUK' }] : [], total: k === 'subdivision' ? 1 : 0, limit: 10, offset: 0, has_more: false }
      return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) })
    })
    await page.goto('/#courses')
    const group = page.locator('.m-filter-select').filter({ hasText: 'University group' }).first()
    await group.locator('.m-filter-button').click()
    await expect(group.locator('[data-empty-reason]')).toHaveText('No university groups are set up for this country.')
  })
})
