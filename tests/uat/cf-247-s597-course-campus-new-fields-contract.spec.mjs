// Guards: Platform Admin 18 Nov 2026 07:03 (UI audit of the new API v3 fields, slices A and B): Catalogue › Courses shows Study load and Empty reason as columns and filters; Catalogue › Providers › Campuses shows Primary and the Locality of the campus postcode as columns and filters; the shared read path is edited in place under md5 guards, catalogue.courses and catalogue.campuses are read and never altered, and the ILEP draft is marked for its move to TrustEd Ireland.
// Behaviour and speed are proven on isolated PostgreSQL by tests/fixtures/course-campus-new-fields/run.sh (production-parity volume; workflow course-catalogue-columns-test); these checks keep the rules in the migration and the screen.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { COURSE_COLUMNS, STUDY_LOAD_LABELS, EMPTY_REASON_LABELS, defaultLayout } from '../../src/catalogue-columns.js'

const read = (p) => fs.readFileSync(p, 'utf8')
const M = read('supabase/migrations-archive/20261118073000_cf247_course_study_load_empty_reason_campus_primary_locality.sql')
const C = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const UI = read('src/mature-main.jsx')

test('the migration edits four live bodies under md5 guards, adds the Campuses read beside the old one, and drops nothing', () => {
  expect(M).toMatch(/^-- Replaces: the four bodies above, in place \(md5-guarded edits\); security\.admin_campus_page_fast\(jsonb\) as the Campuses list read$/m)
  expect(M).toMatch(/^-- Retires: security\.admin_campus_page_fast\(jsonb\) \(marked retiring;/m)
  for (const l of M.split('\n')) expect(l).not.toMatch(/^(drop|delete|truncate)\b|^alter table/i)
  const edits = [...C.matchAll(/select pg_temp\.edit_all\('([^']+)', '([0-9a-f]{32})', '([0-9a-f]{32})',/g)].map((m) => m.slice(1))
  expect(edits.map((e) => e[0])).toEqual(['security.admin_course_page_fast(jsonb)', 'security.admin_course_page_fast_base(jsonb)', 'security.course_list_with_extras_v1(jsonb)', 'public.admin_read(text,jsonb)'])
  for (const [sig, before, after] of edits) { expect(before).not.toBe(after); expect(M).toContain(`--   ${sig}  ${before} -> ${after}`) }
  expect(C).toContain("if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change replaces (body md5 %)', p_sig, md5(v_src); end if;")
  // one new function; the old Campuses read is left and marked retiring with the hygiene setting's period
  expect(C.match(/create or replace function (?!pg_temp\.)/g).length).toBe(1)
  expect(C).toContain("create or replace function security.admin_campuses_page_v2(p_args jsonb default '{}'::jsonb) returns jsonb\nlanguage plpgsql stable security definer set search_path = ''")
  expect(C).toContain("current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int")
  expect(C).toContain('revoke all on function security.admin_campuses_page_v2(jsonb) from public, anon;')
  // the held forward recovery reverses exactly the four edits
  const held = read('supabase/held/course_campus_new_fields_forward_recovery.sql')
  for (const [sig, before, after] of edits) expect(held).toContain(`select pg_temp.edit_all('${sig}', '${after}', '${before}',`)
})

test('G3: the catalogue tables are read, with two indexes beside them; no consumer API object is named', () => {
  expect(C.match(/create index if not exists /g).length).toBe(2)
  expect(C).toContain('create index if not exists courses_study_load_idx on catalogue.courses (study_load) where study_load is not null;')
  expect(C).toContain('create index if not exists courses_empty_reason_code_idx on catalogue.courses (empty_reason_code) where empty_reason_code is not null;')
  expect(C).not.toMatch(/\b(website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1)|\bapi\.[a-z]/)
  // the only table writes: the column registry, the component register and the one ILEP draft
  expect([...C.matchAll(/^(?:insert into|update) ([a-z0-9_.]+)/gm)].map((m) => m[1]).filter((t) => !t.startsWith('pg_temp'))).toEqual(['pipeline.admin_table_columns', 'pipeline.component_register', 'pipeline.layer1_source_inductions'])
})

test('the filters are applied on the course row, before any derived value, and only in the bounded path', () => {
  expect(C).toContain("        or (p_args->>'study_load'='none' and c.study_load is null)\n        or c.study_load=p_args->>'study_load')")
  expect(C).toContain("        or (p_args->>'empty_reason'='any' and c.empty_reason_code is not null)\n        or (p_args->>'empty_reason'='none' and c.empty_reason_code is null)\n        or c.empty_reason_code=p_args->>'empty_reason')")
  expect(C).toContain("if v_sort in ('fee','completeness') and nullif(p_args->>'description','') is null and nullif(p_args->>'study_load','') is null and nullif(p_args->>'empty_reason','') is null then")
  expect(C).toContain("jsonb_build_object('study_load', c.study_load, 'empty_reason_code', c.empty_reason_code, 'description_text', c.description,")
  // Campuses: the course count for the page's rows only; the locality is the primary postcode match and is searched as typed text
  expect(C).toContain("'course_count', (select count(*)::int from catalogue.course_campuses cc where cc.campus_id = o.id),")
  expect(C).toContain("where lp.country_code = o.country_code::character(2) and lp.postcode = o.postcode and lp.is_primary_match\n                          order by lp.boundary_vintage desc limit 1) loc on true);")
  expect(C).toContain("v_loc_like := '%' || replace(replace(replace(v_loc, '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%';")
})

test('the screen: two registered course columns (off by default) and their filters; two campus columns and their filters', () => {
  const keys = COURSE_COLUMNS.map((c) => c.key)
  expect(keys.indexOf('study_load')).toBe(keys.indexOf('delivery_mode') + 1); expect(keys.indexOf('empty_reason_code')).toBe(keys.indexOf('official_url') + 1)
  expect(defaultLayout().columns).not.toContain('study_load'); expect(defaultLayout().columns).not.toContain('empty_reason_code')
  expect(Object.keys(STUDY_LOAD_LABELS)).toEqual(['full_time', 'part_time', 'both'])
  expect(Object.keys(EMPTY_REASON_LABELS)).toEqual(['not_published_by_provider', 'not_listed_on_register', 'online_only_no_campus', 'pending_extraction', 'source_unavailable'])
  expect(UI).toContain("if(filters.studyLoad)a.study_load=filters.studyLoad;if(filters.emptyReason)a.empty_reason=filters.emptyReason}if(type==='campus'){if(filters.campusPrimary)a.primary=filters.campusPrimary;if(filters.campusLocality)a.locality=filters.campusLocality}return a}")
  expect(UI).toContain("{key:'locality_name',label:'Locality',width:200},{key:'is_primary',label:'Primary',width:110},")
  expect(read('src/catalogue-columns.css')).not.toContain('m-filter-text')
  // the integration test's database registers the same two rows the migration does
  const rowsOf = (t) => [...t.matchAll(/^ \('courses', '(?:study_load|empty_reason_code)', .*\),?$/gm)].map((x) => x[0].replace(/,$/, ''))
  expect(rowsOf(read('tests/fixtures/course-campus-new-fields/registry.sql'))).toEqual(rowsOf(M)); expect(rowsOf(M)).toHaveLength(2)
})

test('the ILEP draft is kept and marked for its move to TrustEd Ireland', () => {
  const note = C.match(/jsonb_build_object\('notes', '((?:[^']|'')+)'\)/)[1]
  expect(note).toMatch(/^Wave 2 draft, pre-staged 17 Nov 2026\. DEPRECATING SOURCE \(Platform Admin 18 Nov 2026\):/); expect(note).toContain('TrustEd Ireland'); expect(note).toContain('ie_ilep')
  expect(note.length).toBeLessThanOrEqual(600)
  expect(C).toContain("where i.country_code = 'IE' and i.status = 'draft' and i.payload->>'source_label' = 'Interim List of Eligible Programmes (ILEP)'")
})

test.describe('mocked browser', () => {
  async function reads(page, op, respond) {
    const calls = []
    await mockAdmin(page)
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async (route) => {
      const b = route.request().postDataJSON()
      if (b.p_operation !== op) return route.fallback()
      calls.push(b.p_args)
      return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(respond(b.p_args)) })
    })
    return calls
  }
  test('Courses: the two columns show the study load and the empty reason badge; the two filters are sent to courses_page', async ({ page }) => {
    const rows = [{ id: '00000000-0000-4000-8000-000000000001', canonical_title: 'Bachelor of Design', provider_name: 'University', study_load: 'both', empty_reason_code: 'not_published_by_provider', field_states: {} },
      { id: '00000000-0000-4000-8000-000000000002', canonical_title: 'Diploma of Business', provider_name: 'University', study_load: null, empty_reason_code: null, field_states: {} }]
    const calls = await reads(page, 'courses_page', () => ({ items: rows, total: rows.length, limit: 50, offset: 0 }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_table_layout', (route) => route.fulfill({ status: 200, contentType: 'application/json',
      body: JSON.stringify({ screen: 'courses', layout: { version: 1, columns: ['canonical_title', 'study_load', 'empty_reason_code'], widths: {}, sort: 'course', direction: 'asc' }, has_previous: false, limits: { max_columns: 60, width_min_px: 64, width_max_px: 1200, max_bytes: 16000 } }) }))
    await page.goto('/#courses')
    await expect(page.getByRole('heading', { name: 'Course catalogue' })).toBeVisible()
    await expect(page.locator('[data-study-load="both"]')).toHaveText('Full-time or part-time'); await expect(page.locator('[data-study-load=""]')).toHaveText('Not held')
    await expect(page.locator('[data-empty-reason="not_published_by_provider"]')).toHaveText('Not published by the provider'); await expect(page.locator('[data-empty-reason=""]')).toHaveText('No reason recorded')
    if (await page.locator('.m-filter-button', { hasText: 'Study load' }).count() === 0) await page.getByRole('button', { name: 'Filters', exact: true }).click()
    await page.locator('.m-filter-button', { hasText: 'Study load' }).click(); await page.getByRole('button', { name: 'Part-time', exact: true }).click()
    await expect.poll(() => calls.at(-1)?.study_load).toBe('part_time')
    await page.locator('.m-filter-button', { hasText: 'Empty reason' }).click(); await page.getByRole('button', { name: 'Any reason recorded', exact: true }).click()
    await expect.poll(() => calls.at(-1)?.empty_reason).toBe('any'); expect(calls.at(-1).study_load).toBe('part_time')
  })
  test('Campuses: Primary badge and Locality (with its draft status) are shown; the Primary filter and the Locality search are sent to campuses_page', async ({ page }) => {
    const rows = [{ id: 'cp1', name: 'City campus', provider_name: 'RMIT University', country_code: 'AU', city: 'Melbourne', course_count: 12, status: 'active', is_primary: true, primary_basis: 'register_head_office', postcode: '3000', locality_name: 'Melbourne', locality_status: 'draft' },
      { id: 'cp2', name: 'Brunswick campus', provider_name: 'RMIT University', country_code: 'AU', city: 'Brunswick', course_count: 3, status: 'active', is_primary: false, primary_basis: null, postcode: null, locality_name: null, locality_status: null }]
    const calls = await reads(page, 'campuses_page', () => ({ items: rows, total: rows.length, limit: 50, offset: 0 }))
    await page.goto('/#campuses')
    await expect(page.locator('[data-campus-primary="1"]')).toHaveText('Primary'); await expect(page.locator('[data-campus-primary="0"]')).toHaveCount(1)
    await expect(page.locator('[data-campus-locality="draft"]')).toContainText('Melbourne'); await expect(page.locator('[data-campus-locality="draft"]')).toContainText('Draft')
    await expect(page.locator('[data-campus-locality="none"]')).toHaveText('No postcode')
    await page.locator('.m-filter-button', { hasText: 'Primary' }).first().click(); await page.getByRole('button', { name: 'Primary campus', exact: true }).click()
    await expect.poll(() => calls.at(-1)?.primary).toBe('true')
    const box = page.locator('[data-campus-locality-filter] input'); await box.fill('Melb'); await box.press('Enter')
    await expect.poll(() => calls.at(-1)?.locality).toBe('Melb'); expect(calls.at(-1).primary).toBe('true')
  })
})
