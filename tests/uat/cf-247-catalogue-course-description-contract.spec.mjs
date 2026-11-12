// Guards: Platform Admin 12 Nov 2026 20:50 (Course catalogue: "add ui Filter to see the updated course description and instead of populated it should fill in the value as wrapped text").
// Source contract and the screen in a mocked browser. The database behaviour (the text on every page path, the filter, its totals and its speed at production volume) runs on
// the isolated fixture tests/fixtures/catalogue-course-description/run.sh (workflow course-catalogue-columns-test.yml).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const MIG = fs.readFileSync('supabase/migrations/20261112210000_cf247_catalogue_course_description.sql', 'utf8')
const code = MIG.split('\n').filter(l => !/^\s*--/.test(l)).join('\n')
const HELD = fs.readFileSync('supabase/held/catalogue_course_description_forward_recovery.sql', 'utf8')
const UI = fs.readFileSync('src/mature-main.jsx', 'utf8')
const COLS = fs.readFileSync('src/CatalogueColumns.jsx', 'utf8')
const CSS = fs.readFileSync('src/catalogue-columns.css', 'utf8')
const WF = fs.readFileSync('.github/workflows/course-catalogue-columns-test.yml', 'utf8')

test('migration 20261112210000: three md5-guarded edits, housekeeping lines, nothing dropped, no consumer API, held recovery the other way', () => {
  for (const [sig, b, a] of [['security.admin_course_page_fast(jsonb)', 'c4d2eb53d5ffb893217f3e408dd01fd0', '19d7dde7292e5707a7e1bc110c6106d8'],
                             ['security.admin_course_page_fast_base(jsonb)', '56bcf191ba8dd6da8f84c170c7c3c5f9', '94b2f188b20a1a222c8016491e0e9d8c'],
                             ['security.course_list_with_extras_v1(jsonb)', '91e88067d293f13cf99a95fa2faa8f93', '9f187a3c1d9d43a9e8df84b8a309e443']]) {
    expect(MIG).toContain(`--   ${sig}  ${b} -> ${a}`)
    expect(code).toContain(`select pg_temp.edit_all('${sig}', '${b}', '${a}',`)
    expect(HELD).toContain(`select pg_temp.edit_all('${sig}', '${a}', '${b}',`)
  }
  expect(MIG).toMatch(/^-- Replaces: the three bodies above/m); expect(MIG).toMatch(/^-- Retires: nothing/m)
  expect(code).not.toMatch(/\bdrop\s|\bdelete\s+from|\btruncate\b/i)
  expect(code).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./)
  // the filter's four values and the text on every page
  for (const v of ['populated', 'missing', 'updated_24h', 'updated_7d']) expect(code).toContain(`'${v}'`)
  expect(code).toContain("jsonb_build_object('description_text', c.description,")
  expect(code).toContain("'description_updated_at', (select max(e.updated_at) from pipeline.field_enrich_items e where e.course_id = c.id and e.field = 'description' and e.state = 'filled')")
  expect(code).toContain("and nullif(p_args->>'description','') is null\n")
  expect(WF).toContain('bash tests/fixtures/catalogue-course-description/run.sh')
})

test('the screen: a Course description filter sends description; the column shows the text (wrapped, Show all) or the field state', () => {
  expect(UI).toContain("const COURSE_DESCRIPTION_OPTIONS=[{value:'updated_24h',label:'Updated in the last 24 hours'},{value:'updated_7d',label:'Updated in the last 7 days'},{value:'populated',label:'Has a description'},{value:'missing',label:'No description'}]")
  expect(UI).toContain("<FilterSelect label=\"Course description\" value={filters.courseDescription||''} onChange={(v,l)=>patch('courseDescription',v,l)} options={COURSE_DESCRIPTION_OPTIONS}/>")
  expect(UI).toContain('if(filters.courseDescription)a.description=filters.courseDescription}return a}')
  expect(COLS).toContain("case 'description': return <DescriptionText row={row} />")
  expect(COLS).toContain("if (!t) return <FieldState fs={(row.field_states || {}).description} />")
  expect(CSS).toMatch(/\.ccol-desc-text \{[^}]*-webkit-line-clamp: 5;[^}]*white-space: normal;/)
})

test.describe('mocked browser', () => {
  const long = 'The Bachelor of Laws develops legal research, writing and advocacy across core areas of Australian law. Students complete foundation units in contracts, torts and criminal law, then public law and equity. Later years add electives and a supervised practice placement in a community legal centre.'
  async function mount(page, rows, calls) {
    await mockAdmin(page)
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_table_layout', route => route.fulfill({ status: 200, contentType: 'application/json',
      body: JSON.stringify({ screen: 'courses', layout: { version: 1, columns: ['canonical_title', 'provider_name', 'description'], widths: { description: 320 }, sort: 'course', direction: 'asc' }, has_previous: false, limits: { max_columns: 60, width_min_px: 64, width_max_px: 1200, max_bytes: 16000 } }) }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
      const b = route.request().postDataJSON()
      if (b.p_operation !== 'courses_page') return route.fallback()
      calls.push(b.p_args)
      return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ items: rows, total: rows.length, limit: 50, offset: 0 }) })
    })
    await page.goto('/#courses')
    await expect(page.getByRole('heading', { name: 'Course catalogue' })).toBeVisible()
  }
  const row = (id, extra) => ({ id, canonical_title: `Course ${id}`, provider_name: 'University', field_states: { description: { state: 'missing' } }, ...extra })
  test('the description is shown as wrapped text with when the reader wrote it; Show all opens it; no description shows its field state', async ({ page }) => {
    const calls = []
    await mount(page, [row('00000000-0000-4000-8000-000000000001', { description_text: long, description_updated_at: '2026-11-12T08:30:00Z', field_states: { description: { state: 'populated' } } }),
                       row('00000000-0000-4000-8000-000000000002', {})], calls)
    const cell = page.locator('[data-description-text]').first()
    await expect(cell).toContainText('The Bachelor of Laws develops legal research')
    await expect(cell.locator('.ccol-desc-meta')).toContainText('Updated')
    await expect(page.locator('[data-field-state="populated"]')).toHaveCount(0)
    await expect(page.locator('[data-field-state="missing"]')).toHaveCount(1)
    await cell.getByRole('button', { name: 'Show all' }).click()
    await expect(cell.getByRole('button', { name: 'Show less' })).toHaveAttribute('aria-expanded', 'true')
    expect(await cell.locator('.ccol-desc-text').evaluate(e => getComputedStyle(e).whiteSpace)).toBe('normal')
  })
  test('the Course description filter asks the server for the updated descriptions', async ({ page }) => {
    const calls = []
    await mount(page, [row('00000000-0000-4000-8000-000000000003', { description_text: 'A short description.', description_updated_at: null })], calls)
    await expect(page.locator('[data-description-text]')).toContainText('Reader time not recorded')
    const pick = page.locator('.m-filter-button', { hasText: 'Course description' })
    if (!(await pick.isVisible())) await page.getByRole('button', { name: /^Filters/ }).first().click()
    await pick.click()
    await page.locator('.m-filter-popover').getByRole('button', { name: 'Updated in the last 24 hours' }).click()
    await expect(pick).toContainText('Updated in the last 24 hours')
    await expect.poll(() => calls.some(a => a.description === 'updated_24h')).toBe(true)
  })
})
