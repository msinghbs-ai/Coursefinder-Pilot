// CF-247 v2.15.265 (S29): Platform Admin, 13 Oct 2026: credit waste by university. "Block directory sites", "Universities only",
// "Refusals per university", "Reset cap for top-50"; course search "Australia and 30+ courses first", "Flag Victoria Uni and Adelaide Uni",
// "Never search directory sites", "CRICOS code before title"; "use training.gov.au or ASQA ... CRICOS/RTO code, flag the exceptions".
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261013012200_cf247_firecrawl_waste_fixes.sql', 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')

test('every Firecrawl spend on a directory site is refused, and refusals are counted per university', () => {
  expect(mig).toContain("if v_host is not null and security.third_party_host_v1('https://' || v_host) then\n    v_why := 'directory_site';")
  expect(mig).toContain('insert into pipeline.firecrawl_refusals_by_provider(day, provider_id, grp, reason, n, last_at)')
  expect(mig).toMatch(/fc_spend_host_v1\('"Diploma" site:search\.acir\.com\.au'\) <> 'search\.acir\.com\.au'/)
  // directory recipes and scholarship rows are switched off, never deleted
  expect(mig).toContain('update pipeline.course_link_recipes rc set active = false')
  expect(mig).toContain("update pipeline.scholarship_discovery_providers d set status = 'directory_site'")
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('search order: top-50, Australian 30+ courses, overseas, small providers; CRICOS code first within each', () => {
  expect(mig).toContain("order by security.fc_provider_tier_v1(s.provider_id), (s.stage <> 'cricos'), coalesce(pp.rank, 100000)")
  expect(mig).toContain("and not security.third_party_host_v1('https://' || rc.search_domain)")
  expect(mig).toMatch(/fc_provider_tier_v1[\s\S]*cohort = 'au-top-2026-10-12'\) then 0[\s\S]*is distinct from 'AU' then 2[\s\S]*>= 30 then 1 else 3/)
})

test('scholarships: Australian providers with 30+ courses, cap counted from joining onboarding, held universities not picked', () => {
  expect(mig).toContain("'scholarship_min_courses', '30'")
  expect(mig).toContain('x.at > security.fc_sch_cap_since_v1(p_provider_id)')
  expect(mig).toMatch(/fc_sch_cap_since_v1[\s\S]*max\(o\.picked_at\)[\s\S]*max\(po\.started_at\)/)
  for (const fn of ['svc_scholarship_candidate_next', 'svc_scholarship_listing_next', 'svc_scholarship_discover_next']) {
    const body = mig.slice(mig.indexOf(`FUNCTION public.${fn}(`)); expect(body.slice(0, 4000)).toContain('security.fc_sch_held_v1(')
  }
  // scholarships already on record are still read again (cap only)
  expect(mig).toContain('and not security.fc_sch_held_v1(s.provider_id, false)')
})

test('Victoria University and Adelaide University held for an adapter check, shown by name', () => {
  expect(mig).toContain("('bac82321-ded7-4e10-a71d-b18f3ae4d1c7'")
  expect(mig).toContain("('de2201a1-69ee-40ff-b6aa-0e54e535e6c0'")
  expect(mig).toContain("'key', 'firecrawl:2:search_held'")
  expect(mig).toContain("'key', 'firecrawl:2:no_official_site'")
  expect(mig).toContain("'key', 'firecrawl:2:shared_site'")
})

test('worker v0.21.6: official registers first, website accepted only with the CRICOS code or a name-fitting address', () => {
  expect(worker).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(21\.(6|7)|2[2-9]\.\d+|3\d\.\d+)";/) // v0.21.7 (v2.15.269) reads Firecrawl settings
  expect(worker).toContain('{ key: "training_gov_au", site: "training.gov.au"')
  expect(worker).toContain('{ key: "teqsa", site: "teqsa.gov.au"')
  expect(worker).toContain('if (codeOn || fits) return { accepted: new URL(finalUrl).origin, basis: `register_${reg.key}_${codeOn ? "code" : "name"}`')
  expect(worker).toContain('if (!about) continue;')
  // the register lists exactly one website, which answers: accepted as listed
  expect(worker).toContain('if (soleOk) return { accepted: soleOk, basis: `register_${reg.key}_listed`')
  // registers are looked up before the CRICOS-code web search
  expect(worker.indexOf('const regFind = await registerSite(p, code, codeRe);')).toBeLessThan(worker.indexOf('query: `${p.name} CRICOS ${code}`, limit:'))
})

test.describe('mocked browser', () => {
  test('Credits by university lists today’s refusals by university, reason and search order; a held search can be released', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    page.on('dialog', d => d.accept('Adapter checked: vu.edu.au course pages'))
    await mockAdmin(page)
    await page.goto('/#models-services?tab=limits')
    const card = page.locator('[data-fc-by-uni]')
    await card.locator('.cf-card-toggle').first().click()
    const sch = card.locator('[data-fc-refused-uni="u-sch"]')
    await expect(sch).toContainText('Small provider')
    await expect(sch).toContainText('fewer than 30 courses (scholarships) 30')
    await expect(sch).toContainText('directory site (scholarships) 10')
    const vu = card.locator('[data-fc-refused-uni="u-vu"]')
    await expect(vu).toContainText('Top 50')
    await expect(vu).toContainText('Search held')
    await vu.getByRole('button', { name: 'Search again' }).click()
    await expect.poll(() => page.l3calls.find(c => c.fcResume)).toEqual({ fcResume: 'u-vu', reason: 'Adapter checked: vu.edu.au course pages' })
  })
})
