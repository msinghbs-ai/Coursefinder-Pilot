// Start months by hand (v2.15.161, Decision 228, rapid admission plan step 1): a Platform Admin enters the month each
// study period starts; the job answers the waiting reviews. Nothing is written without a confirmation; only the
// backed functions are called.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = p => fs.readFileSync(p, 'utf8')

test('calendar by hand: read and set through the Decision 228 functions, on the Attributes page', () => {
  const pp = read('src/ProviderPolicies.jsx')
  expect(pp).toContain("supabase.rpc('admin_semester_intakes_read')")
  expect(pp).toContain("supabase.rpc('admin_provider_calendar_set',{p_provider_id:p.provider_id,p_periods:periods,p_url:f.url,p_note:f.note||null})")
  expect(pp).toContain('if(!window.confirm(`Set ${p.provider}:')
  expect(pp).not.toMatch(/toLocale|Intl\./)
  const main = read('src/mature-main.jsx')
  expect(main).toContain('<ProviderPolicies country={country}/>\n    <CalendarByHand country={country}/>')
  const a1 = read('supabase/migrations/20261003001510_cf247_calendar_intakes_on_a1.sql')
  expect(a1).toContain("update pipeline.layer4_review_items set status = 'superseded', decided_at = now(), escalation_reason = v_reason where id = r.review_id and status = 'pending';")
  const a2 = read('supabase/migrations/20261003001500_cf247_calendar_intakes_on_a2.sql')
  expect(a2).toContain("if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required'")
  const b = read('supabase/migrations/20261003001520_cf247_calendar_intakes_on_b.sql')
  expect(b).toContain("select cron.schedule('provider-calendar-intakes', '7-59/10 * * * *'")
  for (const m of [a1, a2, b]) for (const word of ['drop', 'delete from', 'truncate', 'on delete cascade']) expect(m.toLowerCase()).not.toContain(word)
})

// v2.15.162 (Platform Admin, 3 Oct 2026 12:05): on the Academic calendars list each study period is its own column with
// the suggested month as an input; Approve applies the months as shown. Edited months are saved by hand and the parsed
// document is closed, so what the course pages get is always what the Platform Admin saw.
test('calendars list: period columns with the suggested month as an input; approve applies what is shown', () => {
  const pp = read('src/ProviderPolicies.jsx')
  expect(pp).toContain("<><th>Intake 1</th><th>Intake 2</th><th>Raw value captured</th></>") // v2.15.164: two intakes at most, the raw value beside them
  expect(pp).toContain('<option value="">Not an intake</option>')
  expect(pp).toContain("const periods=intakes.flatMap(q=>kinds.map(k=>({period:`${k} ${q.rank}`,month:q.month})))") // an intake's month goes to every period of that rank
  expect(pp).toContain("onClick={()=>english?decide(x,'approve'):approveCalendar(x)}")
  expect(pp).toContain("supabase.rpc('admin_provider_calendar_set',{p_provider_id:x.provider_id,p_periods:periods,p_url:x.url,")
  expect(pp).toContain("{p_id:x.id,p_action:'reject',p_note:'Replaced by the months entered on the Academic calendars list'}")
})
