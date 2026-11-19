// Guards: Platform Admin 19 Nov 2026 23:12 and 23:21 AEDT (chat S1-Build, s790, IQ-00313 F-INT PAGE-01): Course intake Run & Validate pages through every active course of any Australian, New Zealand or Canadian provider and takes hand-picked courses, through the same intake plan and guards; the approved top-10 scope stays as it was.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261120002000_cf247_s790_s791_intake_run_validate.sql', 'utf8')
const body = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('the page size is a setting and the new scopes go through the existing selection and plan', () => {
  expect(body).toContain("('pipeline', 'run_now.university_page_courses', 'Intake Run & Validate: courses a page'")
  expect(body).toContain("security.pipeline_num_v1('run_now.university_page_courses', 200)")
  expect(body).toContain("if p_scope like 'university:%' or p_scope like 'courses:%' then return security.intake_ui_selection_wide_v1(p_scope, p_size); end if;")
  expect(body).toContain("'09b38c698f349b885bc0f3ddfeedb010'")
  expect(body).toContain('security.intake_dates_plan_v3(ids, rows_lim)')
  expect(body).toContain("order by md5(id::text), id offset (v_page - 1) * psz limit psz")
  expect(body).toContain("k.iso_alpha2 in ('AU', 'NZ', 'CA')")
  expect(body).toContain("if cardinality(v_pick) > cap then raise exception 'pick at most % courses', cap; end if;")
  expect(body).toContain("raise exception 'page % is outside 1 to %', v_page, v_pages;")
})

test('the read bridge lists every provider page by page and finds single courses; nothing reaches the consumer API', () => {
  expect(body).toContain("elsif p_view='universities' then")
  expect(body).toContain("elsif p_view='course_search' then")
  expect(body).toContain("'scope_forms',jsonb_build_array('top-au','<provider id>','university:<provider id>:page:<n>','courses:<course id>,<course id>')")
  expect(body).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|schema api|create (or replace )?function api\./i)
  expect(body).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
})

async function mount(page) {
  await page.goto('/')
  await page.evaluate(async () => {
    const React = await import('/node_modules/.vite/deps/react.js')
    const { default: ReactDOM } = await import('/node_modules/.vite/deps/react-dom_client.js')
    const { default: Intake } = await import('/src/IntakeRunValidate.jsx')
    const caps = { contract: 'intake-run-validate-v1', can_run: true, control_rank: 6, min_size: 1, max_size: 20, default_size: 20, page_courses: 200,
      scopes: [{ id: 'top-au', label: 'Top Australian universities (approved scope)' }] }
    window.calls = []
    const client = {
      async read(view, args) {
        window.calls.push({ view, args })
        if (view === 'capabilities') return caps
        if (view === 'universities') return { total: 1886, items: [{ id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', name: 'UNSW Sydney', country: 'AU', active_courses: 667, pages: 4 }] }
        if (view === 'course_search') return { items: [
          { course_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', title: 'Master of Data Science', code: '012345A', provider: 'UNSW Sydney', country: 'AU', intakes: 2, intakes_without_date: 1 },
          { course_id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', title: 'Master of Nursing', code: '067890B', provider: 'UNSW Sydney', country: 'AU', intakes: 1, intakes_without_date: 1 }] }
        if (view === 'preview') return { token: 'p1', courses: [], eligible_courses: 0, rule: 'rule', as_at: '2026-11-20T00:00:00Z', expires_at: '2026-11-20T00:10:00Z' }
        return {}
      },
      async prepare() { return {} }, async run() { return {} },
    }
    document.body.innerHTML = '<div id="root"></div>'
    ReactDOM.createRoot(document.getElementById('root')).render(React.default.createElement(Intake, { client, rank: 6 }))
  })
  await expect(page.getByRole('heading', { name: 'Course intake Run & Validate' })).toBeVisible()
}

test('a provider is chosen from the full list and previewed page by page', async ({ page }) => {
  await mount(page)
  await page.getByLabel('Scope type').selectOption('provider')
  await expect(page.getByLabel('University scope')).toHaveCount(0)
  await page.getByRole('button', { name: 'Find providers' }).click()
  await expect(page.getByTestId('intake-provider-picker')).toContainText('1886 Australian, New Zealand and Canadian providers')
  await page.getByRole('button', { name: 'Choose' }).click()
  await page.getByLabel('Course page').selectOption('2')
  await page.getByRole('button', { name: 'Preview eligible courses' }).click()
  const preview = await page.evaluate(() => window.calls.find((c) => c.view === 'preview'))
  expect(preview.args.scope).toBe('university:aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa:page:2')
})

test('single courses are found and hand-picked into one scope', async ({ page }) => {
  await mount(page)
  await page.getByLabel('Scope type').selectOption('courses')
  await page.getByLabel('Find courses').fill('Master')
  await page.getByRole('button', { name: 'Find courses' }).click()
  await page.getByLabel('Pick Master of Data Science').check()
  await page.getByLabel('Pick Master of Nursing').check()
  await expect(page.getByTestId('intake-picked')).toContainText('2 of 20 courses picked')
  await expect(page.getByLabel('Cohort size')).toHaveValue('2')
  await page.getByRole('button', { name: 'Preview eligible courses' }).click()
  const preview = await page.evaluate(() => window.calls.find((c) => c.view === 'preview'))
  expect(preview.args.scope).toBe('courses:bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb,cccccccc-cccc-4ccc-8ccc-cccccccccccc')
  expect(preview.args.size).toBe(2)
})
