// Start months by hand (v2.15.161, Decision 228, rapid admission plan step 1): a Platform Admin enters the month each
// study period starts; the job answers the waiting reviews. Nothing is written without a confirmation; only the
// backed functions are called.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = p => fs.readFileSync(p, 'utf8')

// v2.15.166 (Platform Admin, 3 Oct 2026 13:50): the by-hand panel is folded into the Academic calendars list — a
// university with no months found is a row of the same shape (Intake 1, Intake 2, periods on its pages) with the
// calendar page address to fill in; "Save months" writes them by hand and nothing is rejected.
test('calendar by hand: folded into the calendars list, set through the Decision 228 functions', () => {
  const pp = read('src/ProviderPolicies.jsx')
  expect(pp).toContain("supabase.rpc('admin_semester_intakes_read')")
  expect(pp).toContain("if(x.byhand){const{error:e0}=await supabase.rpc('admin_provider_calendar_set',{p_provider_id:x.provider_id,p_periods:periods,p_url:url,")
  expect(pp).toContain("if(x.byhand&&!/^https?:\\/\\//.test(url||'')){setErr('Give the calendar page address.');return}")
  expect(pp).toContain("{x.byhand?'Save months':!english&&edited(x)?'Approve as edited':'Approve'}")
  expect(pp).toContain("{!x.byhand&&<Button compact onClick={()=>decide(x,'reject')}>")
  expect(pp).not.toContain('CalendarByHand')
  expect(pp).not.toMatch(/toLocale|Intl\./)
  const main = read('src/mature-main.jsx')
  expect(main).toContain('<ProviderPolicies country={country}/>')
  expect(main).not.toContain('CalendarByHand')
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

// v2.15.165 (Platform Admin, 3 Oct 2026 12:51): calendar rows carry an internal link (the university in CourseFinder) and
// the external calendar page, for navigation and checking.
test('calendar rows: internal and external links', () => {
  const pp = read('src/ProviderPolicies.jsx')
  expect(pp).toContain('href={`#providers?id=${x.provider_id}`} className="cf-link" data-provider-link')
  expect(pp).toContain('className="cf-link">Calendar page ↗</a>')
  const m = read('supabase/migrations/20261003001700_cf247_calendar_byhand_wins.sql')
  expect(m).toContain("order by e->>'period', (x.style = 'by_hand') desc nulls last, x.decided_at desc nulls last")
  expect(m).toContain("when q.missing > 0 and not (q.byhand and q.mon is not null) then 'period_unknown'")
})

test.describe('browser: calendars list with a by-hand row', () => {
  test('v2.15.166: a university with no months found is a row; Save months writes every period of that rank by hand', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page)
    const calls = page.l3calls
    page.on('dialog', (d) => d.accept())
    await page.goto('/#layer-4-review?tab=attributes')
    const pp = page.locator('[data-provider-policies]')
    await pp.getByRole('button', { name: 'Academic calendars' }).click()
    const row = pp.locator('tr[data-policy="byhand:pv-byhand"]')
    await expect(row.locator('[data-byhand]')).toContainText('45 intake reviews waiting')
    await expect(row.locator('[data-raw]')).toContainText('Semester 1, Semester 2, Trimester 3')
    await expect(row.getByRole('button', { name: 'Reject' })).toHaveCount(0)
    await row.locator('[data-intake="1"] select').selectOption('2')
    await row.locator('[data-intake="2"] select').selectOption('7')
    await row.getByRole('button', { name: 'Save months' }).click()
    await expect.poll(() => calls.find(c => c.calendarSet)?.calendarSet.p_periods.map(x => `${x.period}=${x.month}`).sort()).toEqual(['semester 1=2', 'semester 2=7', 'trimester 1=2', 'trimester 2=7'])
    expect(calls.find(c => c.calendarSet).calendarSet.p_url).toBe('https://byhand.edu.au/calendar')
    expect(calls.find(c => c.policyDecide)).toBeUndefined()
  })
})

// v2.15.166 (Platform Admin, 3 Oct 2026 14:12 and 14:21): provider drawer edited inline in priority order; Scholarships
// list gets an Audience filter (backed by migration 001900) and a clipped Award cell; the course editor says what its
// tuition field is beside the registered CRICOS cost.
test('provider drawer inline, scholarship audience filter, tuition field named', () => {
  const re = read('src/RecordEditor.jsx')
  expect(re).toContain('export function ProviderEditor({providerId,onChanged,onError,inline=false,facts=null})')
  expect(re).toContain('<strong>Provider values</strong>')
  expect(re).toContain('<h4 className="re-group">Contact details</h4>')
  expect(re).toContain('label="Tuition from the course page (international)"')
  expect(re).toContain('data-tuition-note')
  const main = read('src/mature-main.jsx')
  expect(main).toContain('<ProviderEditor inline providerId={data.id} onChanged={onChanged} onError={onError} facts={grid}/>')
  expect(main.indexOf('facts={grid}/>')).toBeLessThan(main.indexOf('<InternationalContacts data={data} navigate={navigate}/>{data.id&&<ProviderRankings'))
  expect(main).toContain(`<FilterSelect label="Audience" value={filters.audience||''}`)
  expect(main).toContain("if(type==='scholarship'&&filters.audience)a.audience=filters.audience;")
  expect(main).toContain('className="m-cell-clip"')
  const m = read('supabase/migrations/20261003001900_cf247_scholarships_page_audience.sql')
  expect(m).toContain("and (nullif(p_args->>'audience','') is null or s.audience::text=p_args->>'audience')")
  for (const word of ['drop', 'delete from', 'truncate', 'on delete cascade']) expect(m.toLowerCase()).not.toContain(word)
})

// v2.15.167 (Decision 244): scholarship audience read from each scholarship's wording; labels for the two new values.
test('scholarship audience from wording: labels and migration shape', () => {
  const main = read('src/mature-main.jsx')
  expect(main).toContain("international_and_domestic:'International and domestic',not_stated:'Not stated on the page'")
  const m = read('supabase/migrations/20261003002000_cf247_scholarship_audience_from_wording.sql')
  expect(m).toContain("check (audience in ('international','domestic','international_and_domestic','not_stated'))")
  expect(m).toContain("and not exists (select 1 from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id and k.field = 'audience');")
  expect(m).toContain("select cron.schedule('scholarship-audience', '41 * * * *'")
  for (const word of ['drop', 'delete from', 'truncate', 'on delete cascade']) expect(m.toLowerCase()).not.toContain(word)
})

// Decision 245: several values stated on a page become award tiers with the page as evidence; the value text is the range.
test('scholarship award tiers from the page: migration shape', () => {
  const m = read('supabase/migrations/20261003002100_cf247_scholarship_award_tiers_from_page.sql')
  expect(m).toContain("and not exists (select 1 from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id and k.field in ('award', 'award_value')))")
  expect(m).toContain("or exists (select 1 from scholarship.award_tiers t where t.scholarship_id=s.id and t.tier_code like 'page_tier_%')")
  for (const word of ['drop', 'delete from', 'truncate', 'on delete cascade']) expect(m.toLowerCase()).not.toContain(word)
})

// v2.15.168 (Decisions 245, 246): nationalities on the list and the record; Zoho scholarships action; migrations shaped.
test('scholarship nationality and Zoho scholarships action', () => {
  const main = read('src/mature-main.jsx')
  expect(main).toContain("{key:'sch_who',label:'Who it is for',width:200,sortKey:'audience'}") // v2.15.171: nationalities shown with who it is for (v2.15.223 width)
  const el = read('src/ScholarshipEligibility.jsx')
  expect(el).toContain('data-audience')
  const z = read('supabase/functions/zoho-course-api/index.ts')
  expect(z).toContain('action === "scholarships"')
  expect(z).toContain('svc.rpc("zoho_edge_scholarships_v1", { p_course: course })')
  for (const f of ['20261003002200_cf247_scholarship_nationality_from_wording', '20261003002300_cf247_scholarship_selection_fields_and_zoho', '20261003002400_cf247_scholarship_reads_nationalities']) {
    const m = read(`supabase/migrations/${f}.sql`)
    for (const word of ['drop', 'delete from', 'truncate', 'on delete cascade']) expect(m.toLowerCase()).not.toContain(word)
  }
  const n = read('supabase/migrations/20261003002200_cf247_scholarship_nationality_from_wording.sql')
  expect(n).toContain("where x.code <> 'AU' and not (x.code = 'NZ' and t.study_country = 'AU')")
})

// v2.15.169 (Decisions 247–249): saving estimate, course attribute sync, clean value label, Publishing in Layer 4, course search.
test('scholarship operations: Layer 4 publishing, course search, migrations shaped', async () => {
  const { PAGES, resolveTarget } = await import('../../src/nav-map.js')
  expect(PAGES.layer4.tabs.map(t => t.key)).toContain('publishing')
  expect(PAGES.scholarships.tabs.map(t => t.key)).not.toContain('publishing')
  expect(resolveTarget('scholarships', new URLSearchParams('tab=publishing'))).toMatchObject({ page: 'layer4', tab: 'publishing' })
  const main = read('src/mature-main.jsx')
  expect(main).toContain("if(type==='scholarship'&&filters.course)a.course=filters.course;")
  expect(main).toContain('data-course-filter')
  for (const f of ['20261003002500_cf247_scholarship_saving_estimate_and_course_attribute', '20261003002600_cf247_scholarship_course_attribute_sync', '20261003002700_cf247_scholarship_value_label', '20261003002800_cf247_scholarships_page_course_search']) {
    const m = read(`supabase/migrations/${f}.sql`)
    for (const word of ['drop', 'delete from', 'truncate', 'on delete cascade']) expect(m.toLowerCase()).not.toContain(word)
  }
  expect(read('supabase/migrations/20261003002600_cf247_scholarship_course_attribute_sync.sql')).toContain("select cron.schedule('scholarship-course-attribute', '*/15 * * * *'")
})
