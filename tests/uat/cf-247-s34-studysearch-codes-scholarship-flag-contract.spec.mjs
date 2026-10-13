// CF-247 v2.15.271 (S34): Platform Admin, 14 Oct 2026 08:33.
// Course codes: "fill the real program code and if missing generate the studysearch code, create something not too long and meaningful
// with uni/campus/Degree based, it will be applicable to upcoming countries as well".
// Scholarship search: "skip scholarship search for any provider whose website is a directory site ... I need visible flag in provider for
// such rows. Which we can toggle to enable." (Auto off, operator can enable; queued directory reads closed and the retry loop stopped.)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const read = f => fs.readFileSync(f, 'utf8')
const mig = read('supabase/migrations/20261014013200_cf247_studysearch_codes_and_scholarship_search_flag.sql')
const fix = read('supabase/migrations/20261014013300_cf247_printed_code_wins.sql')

test('StudySearch codes: printed codes kept, a short code for the rest, never written into course_code', () => {
  expect(mig).toContain('create table if not exists ref.course_code_schemes (')
  expect(mig).toContain("('cricos', true, 'CRICOS course code'")
  expect(mig).toContain("('bc_epbc_program_guid', false, 'EducationPlannerBC ID'")
  expect(mig).toContain("pc.identifier || '-' || n.lvl || '-' || lpad(")
  expect(mig).toContain("'studysearch', ")
  expect(mig).not.toMatch(/update catalogue\.courses set course_code/i)
  expect(mig).toContain("select cron.schedule('studysearch-codes', '41 * * * *', 'select security.studysearch_code_assign_v1(security.pipeline_num_v1(''batch.studysearch_codes'', 2000)::int)');")
  expect(mig).toContain("values ('studysearch-codes', 'Platform upkeep'") // G1: catalogued
  expect(mig).toContain("('pipeline', 'batch.studysearch_codes', 'StudySearch codes'") // G2: a setting
  // a printed code always wins, so a type marked printed takes effect at once
  expect(fix).toContain("update ref.course_code_schemes set printed = true, label = 'Ontario college program code'")
  expect(fix.split('and not exists (select 1 from catalogue.course_identifiers j join ref.course_code_schemes s on s.scheme=j.scheme and s.printed where j.course_id=pg.id)').length).toBe(3)
  // only the function's own scratch table (_ss_need, a temporary table dropped at commit) is emptied; no data is dropped or deleted
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b(?!\s+_ss_need)/im)
})

test('scholarship search flag: off for directory-only providers, switched with a reason, respected by every reader', () => {
  expect(mig).toContain('create table if not exists pipeline.provider_scholarship_search (')
  expect(mig).toContain("if v_rank < 4 then raise exception 'Pipeline Operator role or above required'")
  expect(mig).toContain("raise exception 'that address is a directory site; enter the provider''s own website'")
  for (const f of ['svc_scholarship_candidate_next', 'svc_scholarship_discover_next'])
    expect(mig.slice(mig.indexOf(`FUNCTION public.${f}(`))).toContain('security.provider_sch_search_off_v1(')
  expect(mig).toContain("skip_reason = case when security.third_party_host_v1(q.url) then 'directory site' else 'scholarship search off for this provider' end")
  // a refused read counts toward its 3 tries (it looped every 30 minutes uncounted)
  expect(mig).not.toContain('attempts = greatest(attempts - 1, 0)')
  expect(mig).toContain("skip_reason = case when attempts >= 3 then 'no scraper credit after 3 tries' end")
  expect(mig).toContain("raise exception 'v2.15.271 post-check: queued reads of directory pages remain'")
})

test('screens: course code column, StudySearch marker, course summary label, provider flag', () => {
  const main = read('src/mature-main.jsx')
  expect(main).not.toContain("label:'CRICOS / Course code'")
  expect(main).toContain('data-code-kind="studysearch"')
  expect(main).toContain("key:'_sch_search',label:'Scholarship search'")
  expect(read('src/DetailSummary.jsx')).toContain("label={`${codeLabel} ${code}`}")
  expect(read('src/ScholarshipActions.jsx')).toContain('export function ProviderScholarshipSearch(')
})

test.describe('mocked browser', () => {
  test('Providers: Off flag on the row; the provider panel turns it on with a website and a reason', async ({ page }) => {
    await mockAdmin(page)
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
      let b = {}
      try { b = route.request().postDataJSON() || {} } catch {}
      const json = d => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(d) })
      if (b.p_operation === 'providers_page') return json({ items: [{ id: 'p1', canonical_name: 'Green Valley College', country_code: 'AU', course_count: 3, lifecycle_status: 'active', publication_status: 'published' }], total: 1, limit: 50, offset: 0 })
      if (b.p_operation === 'provider_detail') return json({ id: 'p1', canonical_name: 'Green Valley College', country_code: 'AU' })
      return route.fallback()
    })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_provider_sch_search', async route => {
      const b = route.request().postDataJSON() || {}
      calls.push(b)
      const off = { on: false, auto: true, directory_only: true, reason: 'Only website known is a directory site', set_at: '2026-10-14T08:48:00Z', own_site: null, can_manage: true }
      const on = { ...off, on: true, auto: false, directory_only: false, reason: b.p_args?.reason, own_site: b.p_args?.website }
      return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ p1: b.p_action === 'set' ? on : off }) })
    })
    await page.goto('/#providers')
    await expect(page.locator('[data-sch-flag="off"]').first()).toContainText('Off · directory site')
    await page.getByText('Green Valley College').first().click()
    const flag = page.locator('[data-sch-search]')
    await expect(flag).toHaveAttribute('data-sch-search', 'off')
    await flag.getByRole('button', { name: 'Turn on' }).click()
    await flag.getByPlaceholder('https://www.example.edu.au').fill('https://www.greenvalley.edu.au')
    await flag.getByRole('textbox').nth(1).fill('Own website confirmed by phone')
    await flag.getByRole('button', { name: 'Turn on and search' }).click()
    await expect.poll(() => calls.find(c => c.p_action === 'set')?.p_args).toEqual({ provider_id: 'p1', on: true, reason: 'Own website confirmed by phone', website: 'https://www.greenvalley.edu.au' })
    await expect(flag).toHaveAttribute('data-sch-search', 'on')
  })
})
