// v2.15.121 Reference sources and Key dates: third-party sites and how each is used are managed in the admin and read
// by the platform; key dates are edited in place.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES } from '../../src/nav-map.js'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')

test('database: the list drives the checks that used fixed site patterns; changes are role-checked, reasoned and logged', () => {
  const m = read('supabase/migrations/20261001110000_cf247_reference_sources.sql')
  for (const use of ['reference', 'data_source', 'not_provider_site', 'not_course_page', 'scholarship_placeholder', 'logo_directory', 'ranking_publisher']) expect(m).toContain(`'${use}'`)
  expect(m).toContain("$s$security.reference_url_has_use(v_url, 'not_course_page')$s$")
  expect(m).toContain("$s$not security.reference_url_has_use(s.url, 'not_provider_site')$s$")
  expect(m).toContain("'security.scholarship_publishability_v1()', 'b80870edd30933a6d050a8f109883163'")
  expect(m).toContain("raise exception 'PIM Operator role or above required to add a site or change how it is used'")
  expect(m).toContain("active scholarships are sourced only from this site; they would look publishable")
  expect(m).toContain("insert into pipeline.admin_control_events(area, action, target, detail, actor)")
  expect(m).toContain('grant execute on function public.svc_reference_domains(text) to service_role;')
  expect(m).toContain('revoke all on function public.svc_reference_domains(text) from public, anon, authenticated;')
  const d = read('supabase/migrations/20261001112000_cf247_key_dates_edit.sql')
  expect(d).toContain("if auth.uid() is null or security.current_role_rank() < 3 then raise exception 'Curator role or above required'")
  expect(d).toContain("'a vague date needs the wording from the source'")
})

test('no fixed third-party site patterns remain in the coverage sweep or the ranking import form', () => {
  const sweep = read('supabase/functions/coverage-sweep/index.ts')
  expect(sweep).toContain('await rpc("svc_reference_domains", { p_use: "not_provider_site" })')
  expect(sweep).not.toMatch(/hotcourses\|idp\\\.com/)
  const main = read('src/mature-main.jsx')
  expect(main).not.toContain('www.shanghairanking.com')
  expect(main).not.toContain('www.topuniversities.com')
  expect(main).toContain("(x.uses||[]).includes('ranking_publisher')")
  expect(PAGES.reference.tabs.find(t => t.key === 'links').label).toBe('Reference sources')
})

test.describe('mocked browser', () => {
  test('change uses (with reason), rename in place, check a site, and the placeholder count is shown', async ({ page }) => {
    await mockAdmin(page)
    page.on('dialog', d => d.accept('Logos only from now on'))
    await page.goto('/#reference-data?tab=links')
    const t = page.locator('[data-reference-sources]')
    await expect(t.locator('tbody tr')).toHaveCount(3)
    await expect(t.locator('[data-site="Study Australia Scholarship Search"]')).toContainText('111 scholarships sourced only here')
    await t.getByRole('button', { name: 'Change uses of Hotcourses Abroad' }).click()
    await page.getByRole('dialog', { name: 'Uses of Hotcourses Abroad' }).getByLabel('Never a course page').uncheck()
    await page.getByRole('dialog', { name: 'Uses of Hotcourses Abroad' }).getByRole('button', { name: 'Save' }).click()
    await expect.poll(() => page.l3calls.find(c => c.refSave?.p_fields?.uses)?.refSave).toEqual({ p_id: 'r1', p_fields: { uses: ['logo_directory', 'not_provider_site'] }, p_reason: 'Logos only from now on' })
    await t.getByRole('button', { name: 'Edit Name of QS World University Rankings' }).click()
    await t.getByLabel('Name of QS World University Rankings').fill('QS World University Rankings (QS)')
    await t.getByLabel('Name of QS World University Rankings').press('Enter')
    await expect.poll(() => page.l3calls.find(c => c.refSave?.p_fields?.name)?.refSave).toEqual({ p_id: 'r3', p_fields: { name: 'QS World University Rankings (QS)' }, p_reason: null })
    await t.getByRole('button', { name: 'Check Hotcourses Abroad now' }).click()
    await expect.poll(() => page.l3calls.find(c => c.refAction)?.refAction).toEqual({ p_id: 'r1', p_action: 'check', p_reason: null })
  })

  test('key dates: list first, edit a title in place, cancel a date, add one from the short form', async ({ page }) => {
    await mockAdmin(page)
    page.on('dialog', d => d.accept())
    await page.goto('/#reference-data?tab=dates')
    const t = page.locator('[data-key-dates]')
    await expect(t.locator('tbody tr')).toHaveCount(2)
    await expect(t).toContainText('30/11/2026')
    await t.getByRole('button', { name: 'Edit Title of QILT GOS 2026 release' }).click()
    await t.getByLabel('Title of QILT GOS 2026 release').fill('QILT Graduate Outcomes 2026 release')
    await t.getByLabel('Title of QILT GOS 2026 release').press('Enter')
    await expect.poll(() => page.l3calls.find(c => c.dateSave)?.dateSave).toEqual({ p_id: 'd2', p_fields: { title: 'QILT Graduate Outcomes 2026 release' } })
    await t.locator('[data-date="UQ Semester 1 2027 international application deadline"]').getByRole('button', { name: 'Cancel date' }).click()
    await expect.poll(() => page.l3calls.find(c => c.dateAction)?.dateAction).toEqual({ p_id: 'd1', p_action: 'cancel' })
    await page.getByRole('button', { name: 'Add date' }).first().click()
    const f = page.locator('[data-add-date]')
    await f.getByLabel('What').fill('Monash Semester 1 2027 starts')
    await f.getByLabel('Date', { exact: true }).fill('2027-02-22')
    await f.getByLabel('Source address').fill('https://www.monash.edu/dates')
    await f.getByRole('button', { name: 'Add date' }).click()
    await expect.poll(() => page.l3calls.find(c => c.dateSave?.p_id === null)?.dateSave?.p_fields?.title).toBe('Monash Semester 1 2027 starts')
  })
})
