// CF-247 (S72) v2.15.292: counsellor reports from Zoho. Platform Admin, 19 Oct 2026 14:51: "Can I add some control for counsellor in zohoncreator
// or crm to flag or comment to pass on to studsearch platform admin for specific record"; choice "Approve all (Recommended)" (consumer API change
// approved, additive only).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const mig = fs.readFileSync('supabase/migrations/20261019040000_cf247_zoho_counsellor_reports.sql', 'utf8')
const fn = fs.readFileSync('supabase/functions/zoho-api-v2/index.ts', 'utf8')
const nav = fs.readFileSync('src/nav-map.js', 'utf8')
const ui = fs.readFileSync('src/CounsellorReports.jsx', 'utf8')

test('the change is approved and additive: no consumer API function is replaced or the baseline re-taken', () => {
  expect(mig).toMatch(/^-- Consumer API change approved: Platform Admin, 19 Oct 2026 14:51/m)
  expect(mig).not.toMatch(/create\s+or\s+replace\s+function\s+(public\.)?(zoho_edge_|website_|api\.)/i)
  expect(mig).not.toContain('consumer_api_rebaseline_v1(')
  expect(mig).toContain("if jsonb_array_length(security.consumer_api_check_v1() -> 'drift') <> 0 then raise exception 'post-check: consumer API drift'; end if;")
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('report: course by id or CRICOS code; institutes, campuses and contacts; issue, suggested value, source link', () => {
  expect(mig).toContain("or (v_entity = 'course' and z.item->>'cricos_course_code' = upper(v_ident))")
  expect(mig).toContain("or (v_entity = 'provider' and z.item->>'cricos_provider_code' = upper(v_ident))")
  expect(mig).toContain("if v_entity not in ('course', 'provider', 'campus', 'contact') then")
  expect(mig).toContain("if v_issue not in ('missing', 'wrong', 'out_of_date') then v_issue := 'wrong'; end if;")
  expect(mig).toContain("'value_at_report', case when v_path is not null and v_item is not null then v_item->v_path end")
  // the first-issue answer keeps its keys
  expect(mig).toContain("|| case when v_entity = 'course' then jsonb_build_object('course_id', v_key) else '{}'::jsonb end;")
  expect(fn).toContain('fn = "zoho_v2_report"; args = { p_body: pick };')
  expect(fn).toContain('fn = "zoho_v2_report_status"; args = { p_flag_ids: ids.map((x) => (x as string).trim()) };')
  expect(fn).toContain('"report", "report_status"];')
  expect(fn).not.toMatch(/zoho_edge_/)
})

test('outcome back to Zoho; the screen closes with a reason; limits are settings', () => {
  expect(mig).toContain("'status', case f.status when 'open' then 'open' when 'corrected' then 'fixed' else 'not_changed' end,")
  expect(mig).toContain("security.pipeline_num_v1('reports.status_batch_max', 100)")
  expect(mig).toContain("v_can := v_rank >= security.pipeline_num_v1('reports.resolve_min_rank', 4)::int;")
  expect(mig).toContain("if length(v_reason) < 4 then raise exception 'give a reason (Zoho shows it to the counsellor)'; end if;")
  expect(nav).toContain("{ key: 'reports', label: 'Counsellor reports', min: 3 },")
  expect(ui).toContain("supabase.rpc('admin_counsellor_reports',{p_action:action,p_args:args})")
})

test.describe('mocked browser', () => {
  test('Counsellor reports: what was reported, the value held, and close as Fixed with a reason', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank: 6 })
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_counsellor_reports', async route => {
      const b = route.request().postDataJSON(); calls.push(b)
      if (b.p_action === 'list') return route.fulfill({ json: { can_change: true, total: 1, counts: { open: 1, fixed: 0, not_changed: 0, last_7_days: 1 }, items: [{
        id: 'f1', entity: 'course', key: 'course:cricos:00025b:082960f', label: 'Bachelor of Nursing (Honours)', provider_name: 'The University of Queensland',
        field: 'tuition', issue: 'wrong', note: 'Fee on the page is 45,000 for 2027', suggested_value: '45000', source_url: 'https://study.uq.edu.au/x',
        value_at_report: { year: 2026, annual_amount: 43000 }, reporter: { name: 'Asha', email: 'asha@example.com' }, reported_at: '2026-10-19T04:00:00Z', status: 'open' }] } })
      if (b.p_action === 'close') return route.fulfill({ json: { closed: 1, outcome: 'fixed' } })
      return route.fulfill({ json: {} })
    })
    page.on('dialog', d => d.accept('Fee corrected from the 2027 fee page'))
    await page.goto('/#coverage?tab=reports')
    await expect(page.getByText('Bachelor of Nursing (Honours)')).toBeVisible()
    await expect(page.getByText('Fee on the page is 45,000 for 2027')).toBeVisible()
    await expect(page.locator('.cf-report-value')).toContainText('43000')
    await page.getByRole('button', { name: 'Fixed', exact: true }).click()
    await expect(page.getByRole('status')).toHaveText('1 closed as fixed.')
    expect(calls.find(c => c.p_action === 'close').p_args).toEqual({ ids: ['f1'], outcome: 'fixed', reason: 'Fee corrected from the 2027 fee page' })
  })
})
