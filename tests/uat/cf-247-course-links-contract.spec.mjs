// v2.15.133 (Decisions 200–203): course links of every kind, who can apply, link refresh schedules, and admission rules
// per country (NZ programme code or exact title in NZD; AU exact title for links and intakes).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')
const COURSE = '0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5'

test('database: link types, manual lock per link type, applicants, guarded edits, grants', () => {
  const m = read('supabase/migrations/20261001170000_cf247_course_links_and_applicants.sql')
  for (const t of ['official_course', 'handbook', 'international_page', 'application', 'admission_centre', 'regulator_listing']) expect(m).toContain(`('${t}',`)
  expect(m).toContain("then 'official_url' else 'link:' || (r->>'link_type') end")
  expect(m).toContain("'8c7fe38930baf6eb8e666ccdabf472bb'")
  expect(m).toContain("set open_to_international = true, applicant_basis = 'CRICOS course registration'")
  expect(m).toContain("'https://www.nzqa.govt.nz/nzqf/search/viewQualification.do?selectedItemKey=' || upper(btrim(r.registration_code))")
  expect(m).toContain("perform public.admin_course_edit(p_course_id, 'set_official_url'")
  expect(m).toContain("if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required'")
  expect(m).toContain("if auth.uid() is null or v_rank < 4 then raise exception 'Pipeline Operator role or above required'")
  expect(m).toContain("and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id and k.field = 'open_to_international')")
  for (const f of ['admin_course_links_read(uuid)', 'admin_course_link_edit(uuid, text, jsonb)', 'admin_course_applicants_edit(uuid, jsonb)', 'admin_provider_applicants_edit(uuid, jsonb)']) {
    expect(m).toContain(`revoke all on function public.${f} from public, anon;`)
    expect(m).toContain(`grant execute on function public.${f} to authenticated;`)
  }
  const o = read('supabase/migrations/20261001171000_cf247_link_counts_official_only.sql')
  expect(o).toContain("if added <> refs then raise exception")
  expect(o).toContain("array['search','refresh_course_documents_v2','be471e0af75dc59c275ef7ec1e772b1b']")
})

test('database: link refresh by country and provider; portals; never changes hand-set or reviewed links', () => {
  const m = read('supabase/migrations/20261001172000_cf247_link_refresh_and_portals.sql')
  expect(m).toContain('constraint link_refresh_policies_scope_key unique nulls not distinct (country_id, provider_id, link_type)')
  expect(m).toContain("order by (r.provider_id is not null) desc, (r.country_id is not null) desc")
  expect(m).toContain("and l.source_id is distinct from v_manual and l.source_id is distinct from v_l4")
  expect(m).toContain("p.read_status = 'fetch_failed' and p.http_status in (404, 410) and p.read_attempts >= 2")
  expect(m).toContain("select cron.schedule('link-refresh', '*/10 * * * *', $$select security.link_refresh_tick_v1(500)$$);")
  for (const p of ["('nzqa'", "('uac'", "('vtac'", "('qtac'", "('satac'", "('tisc'", "('study_australia'"]) expect(m).toContain(p)
})

test('database: admission rules per country; NZ in NZD only; AU exact title for links and intakes only', () => {
  const m = read('supabase/migrations/20261001173000_cf247_country_admission_rules.sql')
  expect(m).toContain(`('AU', 'AUD', '{"official_url":["cricos_code","exact_title"],"intakes":["cricos_code","exact_title"],"english":["cricos_code"],"tuition":["cricos_code"]}'`)
  expect(m).toContain(`('NZ', 'NZD', '{"official_url":["cricos_code","exact_title"],"intakes":["cricos_code","exact_title"],"english":["cricos_code","exact_title"],"tuition":[]}'`)
  expect(m).toContain("if v_cur is distinct from c.currency_code then raise exception 'fee currency % does not match the country currency %'")
  expect(m).toContain("raise exception '%.%: anchor not found exactly once: %'")
  for (const h of ['2a55770ca342b56d9eb9c797dc12194b', 'c268e676e04011b4e981225cdf6dc018', '995ced9d6892b1512c5e168aafe2cbe3', '58751c63f6d4b573c1fd6697c93c019e', 'd767d484948e4fd03f8cc52fd3e64d88']) expect(m).toContain(`'${h}'`)
  const f = read('supabase/migrations/20261001163000_cf247_tuition_handoff_au_only.sql')
  expect(f).toContain("join ref.countries k on k.id=pr.country_id and k.iso_alpha2='AU'")
})

test.describe('mocked browser', () => {
  test('course: add a handbook link, change who can apply, remove a link, hand a link type back', async ({ page }) => {
    await mockAdmin(page)
    page.on('dialog', d => d.accept())
    await page.goto(`/#courses?id=${COURSE}`)
    const panel = page.locator('[data-editor="course"]')
    await panel.getByRole('button', { name: /Edit this course/ }).click()
    const links = panel.locator('[data-course-links]')
    await expect(links).toContainText('International students: Yes')
    await expect(links).toContainText('An English requirement is expected for international applicants.')
    await expect(links.locator('[data-link-type="handbook"]')).toContainText('Entered by hand')
    await links.getByRole('button', { name: 'Add link' }).click()
    await links.getByLabel('Link type').selectOption('international_page')
    await links.getByLabel('Web address').fill('https://www.rmit.edu.au/international/bp343')
    await links.getByRole('button', { name: 'Save' }).click()
    await expect.poll(() => page.l3calls.find(c => c.linkEdit?.p_action === 'add')?.linkEdit).toEqual({ p_course_id: COURSE, p_action: 'add', p_args: { link_type: 'international_page', url: 'https://www.rmit.edu.au/international/bp343', label: '' } })
    await links.getByRole('button', { name: 'Change who can apply' }).click()
    await links.getByLabel('Open to international students').selectOption('false')
    await links.getByLabel('Open to domestic students').selectOption('true')
    await links.getByRole('button', { name: 'Save' }).click()
    await expect.poll(() => page.l3calls.find(c => c.applicants)?.applicants?.p_args).toEqual({ open_to_international: false, open_to_domestic: true })
    await expect(links).toContainText('Domestic only: an English requirement is not expected.')
    await links.getByRole('button', { name: 'Remove Handbook entry' }).click()
    await expect.poll(() => page.l3calls.find(c => c.linkEdit?.p_action === 'remove')?.linkEdit?.p_args).toEqual({ link_id: 'l-hb' })
    await links.locator('[data-link-type="handbook"]').getByRole('button', { name: 'Let automation update this' }).click()
    await expect.poll(() => page.l3calls.find(c => c.linkEdit?.p_action === 'release')?.linkEdit?.p_args).toEqual({ link_type: 'handbook' })
  })

  test('courses: filter by who can apply', async ({ page }) => {
    await mockAdmin(page)
    const reads = []
    page.on('request', r => { if (r.url().endsWith('/rpc/admin_read')) { try { reads.push(r.postDataJSON()) } catch {} } })
    await page.goto('/#courses')
    await page.getByRole('button', { name: /International students/ }).click()
    await page.getByRole('button', { name: 'Domestic only' }).click()
    await expect.poll(() => reads.some(b => b.p_operation === 'courses_page' && b.p_args?.applicant === 'domestic_only')).toBe(true)
  })

  test('coverage: link refresh schedules and portals', async ({ page }) => {
    await mockAdmin(page)
    page.on('dialog', d => d.accept())
    await page.goto('/#coverage')
    const lr = page.locator('[data-link-refresh]')
    await expect(lr).toContainText('295 links re-confirmed')
    await expect(lr.locator('[data-portal="nzqa"]')).toContainText('Regulator')
    await lr.getByRole('button', { name: 'Add schedule' }).click()
    await lr.getByLabel('Country').selectOption('NZ')
    await lr.getByLabel('Every how many days').fill('14')
    await lr.getByRole('button', { name: 'Save' }).click()
    await expect.poll(() => page.l3calls.find(c => c.linkRefresh?.p_action === 'save_policy')?.linkRefresh?.p_args).toEqual({ country: 'NZ', link_type: 'official_course', every_days: '14' })
    await lr.getByLabel('UAC course search (NSW, ACT) on').click()
    await expect.poll(() => page.l3calls.find(c => c.linkRefresh?.p_action === 'portal')?.linkRefresh?.p_args).toEqual({ code: 'uac', active: true })
  })

  test('viewer: links shown, no editing', async ({ page }) => {
    await mockAdmin(page, { rank: 1 })
    await page.goto('/#coverage')
    await expect(page.locator('[data-link-refresh]')).toBeVisible()
    await expect(page.getByRole('button', { name: 'Add schedule' })).toHaveCount(0)
  })
})

test('worker: course-link search runs in coverage-sweep, bounded and budgeted; the old tick stops sending when switched', () => {
  const w = read('supabase/functions/coverage-sweep/index.ts')
  expect(w).toContain('if (mode === "link_search") {')
  expect(w).toContain('await rpc("svc_course_link_search_next", { p_limit: Math.min(Number(body.limit || 40), 120) })')
  expect(w).toContain('await pool(items, Math.min(Number(body.concurrency || 6), 10), async (it) => {')
  expect(w).toContain('if (!(await useFc("course_link_search", it.provider_id, it.query)))')
  expect(w).toContain('const units = /search$/.test(purpose) ? 2 : /^fcx_/.test(purpose) ? 5 : 1;') // v0.13.0 counts a JSON-format scrape at 5 credits
  const m = read('supabase/migrations/20261001175000_cf247_link_search_in_worker.sql')
  expect(m).toContain("if p_error in ('time budget', 'credit budget') then")
  expect(m).toContain("'ab94cc87e67ecf30cb35fac0c977161f'")
  expect(m).toContain("grant execute on function public.svc_course_link_search_next(int) to service_role;")
})
