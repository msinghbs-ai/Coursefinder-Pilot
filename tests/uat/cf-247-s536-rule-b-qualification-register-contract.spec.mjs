// Guards: CF-247 F-INT (Platform Admin 11 Nov 2026 20:40, option B): every university is qualified for Rule B by a rolled-back trial of the live planner and listed only by the Platform Admin's one approval of all qualified universities; a failing listed university is taken off (a stop, never a start).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const MIG = fs.readFileSync('supabase/migrations/20261112010000_cf247_rule_b_qualification_register.sql', 'utf8')
const UI = fs.readFileSync('src/RuleBRegister.jsx', 'utf8')
const fn = (name) => { const i = MIG.indexOf(`create or replace function ${name}(`); return MIG.slice(i, MIG.indexOf('$function$;', i)) }

test('the trial runs the live planner with the university listed and is always rolled back', () => {
  const one = fn('security.intake_rule_b_qualify_one_v1')
  expect(one).toContain("update pipeline.platform_toolset_settings set value = v_list || jsonb_build_array(p_provider::text)")
  expect(one).toContain('from security.intake_dates_plan_v3((select array_agg(c2.id) from catalogue.courses c2 where c2.provider_id = p_provider')
  expect(one).toContain("raise exception using errcode = 'CF001', message = 'cf247 rule b trial rolled back';")
  expect(one).toContain("exception when sqlstate 'CF001' then")
  // the checks: the planner's own offering check, held levels, calendar evidence, one date per month, a minimum worth adding
  expect(one).toContain("security.intake_course_applicability_v1(rb.page_quote, rb.mon, extract(year from rb.new_start)::int, '[]'::jsonb, false) is not null")
  expect(one).toContain("'intake_dates.nearest_start_hold_levels'")
  expect(one).toContain("'calendar_missing', (select count(*) from rb where rb.calendar_url is null)")
  expect(one).toContain("'months_with_two_dates'")
  expect(one).toContain("security.pipeline_num_v1('intake_dates.rule_b_qualify_min_rows', 5)")
  expect(one).not.toMatch(/insert into|delete from/i)
})

test('the job never adds a university; only the approval does, with a reason, by the Platform Admin', () => {
  const job = fn('security.intake_rule_b_qualify_v1')
  expect(job).toContain("security.pipeline_num_v1('batch.intake_rule_b_qualify', 1)")
  expect(job).toContain("v_after := coalesce((select jsonb_agg(x) from jsonb_array_elements(v_list) x where x #>> '{}' <> r.provider_id::text), '[]'::jsonb);")
  expect(job).not.toMatch(/v_list \|\||jsonb_build_array\(r\.provider_id/)
  expect(job).toContain("perform security.flag_raise_v1('provider', r.provider_id::text, r.provider_id, 'intakes', 'rule_b_paused'")
  const ok = fn('public.admin_intake_rule_b_approve_v1')
  expect(ok).toContain("if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required'")
  expect(ok).toContain("where q.status = 'qualified' and q.checked_at >= now() - make_interval(hours => v_hours)")
  expect(ok).toContain("insert into pipeline.admin_control_events(area, action, target, detail, actor)")
  expect(MIG).toContain("perform cron.schedule('intake-rule-b-qualify', '7-59/10 * * * *', $j$select security.intake_rule_b_qualify_v1()$j$);")
  expect(MIG).toMatch(/^-- Replaces: /m)
  expect(MIG).toMatch(/^-- Retires: nothing/m)
  expect(MIG).toContain("comment on table pipeline.intake_rule_b_qualifications is '")
  expect(MIG).toContain('alter table pipeline.intake_rule_b_qualifications enable row level security;')
  expect(UI).toContain("rpc('admin_intake_rule_b_approve_v1',{p_reason:reason.trim(),p_exclude:[]})")
})

test.describe('mocked browser', () => {
  test('Process results: the register shows qualified and held universities; one approval with a reason switches on all qualified', async ({ page }) => {
    await mockAdmin(page)
    const read = { can_request: true, can_approve: true, requalify_hours: 24, approvable: 1, approvable_rows: 101, counts: { qualified: 1, listed: 2, held: 1 },
      rows: [
        { provider_id: 'c5c5d225-3d4c-4e41-8275-78eddd261073', name: 'Deakin University (Deakin)', country: 'AU', status: 'qualified', rule_b_rows: 101, other_rows: 156, reasons: [], dates: { July: { '2027-07-05': 58 }, November: { '2027-11-01': 43 } }, sample: [], checked_at: '2026-11-11T10:00:00Z', fresh: true },
        { provider_id: '551383f9-7732-4588-a843-dd2b97c13f6f', name: 'University of Southern Queensland', country: 'AU', status: 'held', rule_b_rows: 1, other_rows: 50, reasons: ['nothing worth adding: 1 dates (fewest to qualify: 5)'], dates: {}, sample: [], checked_at: '2026-11-11T10:10:00Z', fresh: true }] }
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_intake_rule_b_read_v1', (route) => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(read) }))
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_intake_rule_b_approve_v1', (route) => { calls.push(route.request().postDataJSON()); return route.fulfill({ status: 200, contentType: 'application/json', body: '{"ok":true,"approved":1}' }) })
    page.on('dialog', (d) => d.accept())
    await page.goto('/')
    await page.evaluate(async () => {
      const React = await import('/node_modules/.vite/deps/react.js')
      const { default: ReactDOM } = await import('/node_modules/.vite/deps/react-dom_client.js')
      const { default: RuleBRegister } = await import('/src/RuleBRegister.jsx')
      document.body.innerHTML = '<div id="rb-root"></div>'
      ReactDOM.createRoot(document.getElementById('rb-root')).render(React.default.createElement(RuleBRegister))
    })
    const reg = page.getByTestId('rule-b-register')
    await expect(reg).toContainText('Deakin University (Deakin)')
    await expect(reg).toContainText('nothing worth adding: 1 dates')
    const approve = reg.getByRole('button', { name: /Approve all qualified \(1 universities, about 101 dates\)/ })
    await expect(approve).toBeDisabled()
    await reg.getByLabel('Reason for approving all qualified universities').fill('Rule B for every qualified university, checked by the register')
    await approve.click()
    await expect.poll(() => calls[0]).toEqual({ p_reason: 'Rule B for every qualified university, checked by the register', p_exclude: [] })
  })
})
