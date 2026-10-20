// CF-247 (S72) v2.15.292: counsellor reports from Zoho. Platform Admin, 19 Oct 2026 14:51: "Can I add some control for counsellor in zohoncreator
// or crm to flag or comment to pass on to studsearch platform admin for specific record"; choice "Approve all (Recommended)" (consumer API change
// approved, additive only).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const mig = fs.readFileSync('supabase/migrations/20261019040000_cf247_zoho_counsellor_reports.sql', 'utf8')
const fn = fs.readFileSync('supabase/functions/zoho-api-v2/index.ts', 'utf8')
const nav = fs.readFileSync('src/nav-map.js', 'utf8')
// v2.15.300 (Platform Admin, 20 Oct 2026, "Counsellor reports tab"): the tab retired; reports are closed in Layer 4 › Inbox
const ui = fs.readFileSync('src/Layer4Inbox.jsx', 'utf8')
const l23 = fs.readFileSync('supabase/migrations/20261020060000_cf247_layer23_operations.sql', 'utf8')

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
  expect(nav).not.toContain("{ key: 'reports', label: 'Counsellor reports', min: 3 },")
  expect(nav).toContain("if (hit.page === 'coverage' && tab === 'reports') return inboxOf('counsellor_report', p)")
  expect(l23).toContain("v_r := public.admin_counsellor_reports('close', jsonb_build_object('ids', jsonb_build_array(v_ref), 'outcome', case v_choice when 'report_fixed' then 'fixed' else 'not_changed' end, 'reason', v_reason));")
  expect(ui).toContain("it.kind==='counsellor_report'&&<dl className=\"l4i-dl\" data-l4-report>")
})

test.describe('mocked browser', () => {
  test('Counsellor reports: the old address opens the Inbox on reports; what was reported shows and Fixed closes it with a reason', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank: 6 })
    const calls = []
    const kinds = { counsellor_report: { label: 'Counsellor report', order: 12, choices: [{ key: 'report_fixed', label: 'Fixed', returns: 'Closed as fixed with your note; Zoho shows the outcome to the counsellor' }, { key: 'report_not_changed', label: 'Not changed', returns: 'Closed as not changed' }] } }
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async route => {
      const b = route.request().postDataJSON(); calls.push(b)
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds, target_days: 7, rank: 6, total: 1, universities: 1, late: 0, by_kind: { counsellor_report: { n: 1 } } } })
      if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [{ provider_id: 'uq', name: 'The University of Queensland', country: 'AU', courses: 900, n: 1, by_kind: { counsellor_report: 1 } }] } })
      if (b.p_action === 'items') return route.fulfill({ json: { total: 1, items: [{ kind: 'counsellor_report', ref: 'f1', provider_id: 'uq', provider: 'The University of Queensland', subject: 'Bachelor of Nursing (Honours)', why: 'Fee on the page is 45,000 for 2027', created_at: '2026-10-19T04:00:00Z',
        detail: { issue: 'wrong', suggested_value: '45000', source_url: 'https://study.uq.edu.au/x', reporter: { name: 'Asha', email: 'asha@example.com' } } }] } })
      if (b.p_action === 'decide') return route.fulfill({ json: { ok: true, returns: 'Closed as fixed with your note; Zoho shows the outcome to the counsellor' } })
      return route.fulfill({ json: {} })
    })
    await page.goto('/#coverage?tab=reports')
    await expect(page).toHaveURL(/kind=counsellor_report/)
    const item = page.locator('[data-l4-item="counsellor_report"]')
    await expect(item).toContainText('Bachelor of Nursing (Honours)')
    await expect(item.locator('[data-l4-report]')).toContainText('45000')
    await expect(item.locator('[data-l4-report]')).toContainText('Asha')
    await item.locator('[data-l4-choice="report_fixed"]').click()
    await item.getByLabel('Reason').fill('Fee corrected from the 2027 fee page')
    await item.locator('[data-l4-confirm]').click()
    await expect(page.getByRole('status')).toContainText('Done.')
    expect(calls.find(c => c.p_action === 'decide').p_args).toMatchObject({ kind: 'counsellor_report', ref: 'f1', choice: 'report_fixed', reason: 'Fee corrected from the 2027 fee page' })
  })
})
