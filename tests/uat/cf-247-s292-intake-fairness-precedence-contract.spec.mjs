// Guards: Platform Admin direction 5 Nov 2026 15:50 (UNSW blockage and cross-university fairness; P0 IQ-00313): §1 course-specific offering evidence and governed withdrawal, §2 obsolete editions and equivalent period labels, §3 provider-fair selection under G2, §6 pre-production regressions on the production-equivalent fixture in CI.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261105060000_cf247_intake_fairness_precedence.sql', 'utf8')

test('§3: rows are taken round by round per university under a setting; the batch size is unchanged and the job is not bypassed', () => {
  expect(m).toMatch(/'intake_dates\.provider_share'[\s\S]{0,700}'number', to_jsonb\(25\), 5, 200, 'rows'/)
  expect(m).toContain('order by ceil(row_number() over (partition by c.provider_id order by i.course_id, i.id)::numeric / v_share), sets.served nulls first, f.rank nulls last')
  expect(m).toContain("'security.intake_dates_plan_v3(uuid[],integer)', '0eb4f9fdec574d089f9e869aa7d443dd'")
  expect(m).not.toMatch(/batch\.intake_dates_apply'[^)]*to_jsonb/)            // the batch size is not raised
  expect(m).not.toMatch(/cron\.(schedule|alter_job)/)                         // no new or changed scheduler
})

test('§2: an obsolete edition never supplies a period; equivalent official labels are one period', () => {
  expect(m).toContain("'obsolete edition: its latest proved teaching start is in ' || y.latest")
  expect(m).toContain("md5(pg_get_functiondef('security.calendar_sources_v1(uuid)'::regprocedure)) <> '3064e2096d87ce93756d52bc99f5ab4b'")
  expect(m).toContain("array['  select d.proposal_id, security.calendar_period_canonical_v1(d.period), d.kind,']")
  expect(m).toContain("when b ~ '^(teaching period|study period|tp) ?t ?[1-6]$' then 'term ' ||")
})

test('§1: a general calendar alone never proves a course offers the intake; withdrawal is governed and held by the existing lock', () => {
  expect(m).toContain("reason := security.intake_course_applicability_v1(v_raw, v_m, v_year, v_cal, rule = 'calendar-v3-unique-month', case when rule <> 'calendar-v3-unique-month' then v_pers end, v_pq);")
  expect(m).toContain("f ~ '\\m(i|we|my|our)\\M (have |had )?(commenced|started|began|joined|enrolled|studied|completed)\\M'")   // never a personal account
  expect(m).toContain("another academic calendar applies")
  expect(m).toContain("if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin required'")
  expect(m).toContain("insert into pipeline.manual_locks(entity, entity_id, field, mode, set_by, set_at)")
  expect(m).toContain("if exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = d.course_id and k.field in ('intakes', 'intake')) then")
  expect(m).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('§6: the pre-production regressions run in CI on the production-equivalent fixture, including the earlier releases\' cases', () => {
  const wf = fs.readFileSync('.github/workflows/intake-run-validate-test.yml', 'utf8')
  expect(wf).toContain('bash tests/fixtures/intake-fairness/run.sh'); expect(wf).toContain('bash tests/fixtures/intake-fairness/browser.sh')
  const c = fs.readFileSync('tests/fixtures/intake-fairness/cases.sql', 'utf8').replace(/\s*\n--\s*/g, ' ')
  for (const k of ['Obsolete 2023 calendar losing to current 2027', 'Term 1 / T1 canonical matching', 'Different institution or pathway college', 'Testimonial falsely presented as intake evidence',
    'Course-specific exceptions', 'Provider starvation under heavily skewed course counts', 'Zero-eligible university', 'Duplicate or unchanged work suppression', 'Manual locks',
    'Real admission and consumer publication']) expect(c.toLowerCase()).toContain(k.toLowerCase())
  expect(fs.readFileSync('tests/fixtures/intake-fairness/run.sh', 'utf8')).toContain('Refusing a remote database')
})

test('P0 IQ-00313 provenance: a withdrawal takes the admission from its own event, so a re-decided row is still corrected', () => {
  const h = fs.readFileSync('supabase/migrations/20261105070000_cf247_intake_withdraw_provenance.sql', 'utf8')
  expect(h).toContain("'security.intake_date_withdraw_v1(uuid,text,text,boolean)', '746b5c1a4141d4b5d022c1bfa0fa25f3'")
  expect(h).toContain("where e.intake_id = p_intake and e.outcome = 'filled'")
  expect(h).toContain("and not exists (select 1 from pipeline.course_intake_date_events w where w.intake_id = p_intake and w.outcome = 'withdrawn' and w.id > e.id)")
  expect(fs.readFileSync('tests/fixtures/intake-fairness/cases.sql', 'utf8')).toContain('PASS provenance')
})

test('§3 focus priority within a round: focus universities first, longest waiting first among them (production finding 17:26)', () => {
  const f = fs.readFileSync('supabase/migrations/20261105080000_cf247_intake_focus_rounds.sql', 'utf8')
  expect(f).toContain("'security.intake_dates_plan_v3(uuid[],integer)', '67e930818ee190f9124af45093be2ff0'")
  expect(f).toContain('(f.rank is null), sets.served nulls first, f.rank nulls last, c.provider_id, i.course_id, i.id')
  expect(fs.readFileSync('tests/fixtures/intake-fairness/cases.sql', 'utf8')).toContain('PASS focus priority')
})

test('explicit pilot scope beside fairness and focus (Platform Admin 5 Nov 2026 18:00): a setting, the existing pilot definition, no hard-coded list', () => {
  const g = fs.readFileSync('supabase/migrations/20261105090000_cf247_intake_pilot_share.sql', 'utf8')
  expect(g).toMatch(/'intake_dates\.pilot_batch_share'[\s\S]{0,700}'number', to_jsonb\(60\), 0, 100, 'per cent'/)
  expect(g).toContain("'security.intake_dates_plan_v3(uuid[],integer)', '886876cde3afdd3e55fa04a9459c6f95'")
  expect(g).toContain('jsonb_array_elements(security.intake_ui_scopes_v1())')     // the pilot is the existing run_now.cohort_top_au_universities scope
  expect(g).toContain("order by case when q.pilot and q.pilot_seq <= v_pilot_rows then 0 when not q.pilot then 1 else 2 end")
  expect(g).not.toMatch(/'(UNSW|Monash|Melbourne)/)                                 // no university named in code
  expect(fs.readFileSync('tests/fixtures/intake-fairness/cases.sql', 'utf8')).toContain('PASS selection: pilot scope takes its share')
})
