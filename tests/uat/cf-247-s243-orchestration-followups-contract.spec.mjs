// Guards: Integration issues IQ-00066 (a plan step is proposed only when its scope has eligible work; a task or step with none ends not needed,
// never done; a plan of not-needed steps is not counted as moving data), IQ-00053 residual (svc_enrich_ai_record answers within the statement
// time-out: the course description duplicate check does less per call) and IQ-00063 (onboarding refuses a website that is not a site address
// and stops with needs_source_discovery instead of looping). The behaviour runs on isolated fixtures by tests/fixtures/orchestration-followups/
// run.sh (scratch PostgreSQL; the live v2.15.424 definitions loaded from their live text and checked against the live md5s; the three defects
// reproduced on them; the migration checked with the switches off and applied again; every case asserted). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261103230000_cf247_orchestration_followups.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/orchestration-followups'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const before = fs.readFileSync(`${FX}/fixtures-before.sql`, 'utf8')
const off = fs.readFileSync(`${FX}/fixtures-off.sql`, 'utf8')
const plan = fs.readFileSync('src/EnrichPlan.jsx', 'utf8')
const iq = fs.readFileSync('src/IntegrationQueue.jsx', 'utf8')
const edit = (sig) => { const a = m.indexOf(`select pg_temp.edit_once('${sig}'`); expect(a, sig).toBeGreaterThan(-1); return m.slice(a, m.indexOf('\n]::text[][], array[', a)) }
const after = (block) => block.split('$n$').filter((_, i) => i % 2 === 1).join('\n')

const MD5 = {
  'security.enrich_plan_v1(uuid)': '818ef130484e567c35a7a2cf5a99d7c8',
  'security.enrich_plan_tick_v1(uuid)': 'cab734df6715e25014935bd22058343b',
  'security.admin_job_watch_v1(uuid)': '34a1cfd57b367d0e60ccb4a85f56e228',
  'security.admin_jobs_tick_v1(integer)': 'fc698f9912cffd90a7b8ae32e33dd09e',
  'public.admin_pipeline_yield(jsonb)': '34617ad96ea43189509c3f4dd536d50e',
  'security.course_description_check_v1(uuid,jsonb)': '4822f66ee262cdfa1c4cd798cfc3dd26',
  'security.provider_onboarding_tick_v1()': '01c5659bb4c364e80b0544fa60bca0ee',
}

test('seven live definitions are edited only from their live md5 and checked after; Release B functions are not edited; the fixture loads the same', () => {
  for (const [sig, b] of Object.entries(MD5)) {
    const a = m.match(new RegExp(`^--   ${sig.replace(/[.()]/g, '\\$&')} +${b} -> ([0-9a-f]{32})$`, 'm'))
    expect(a, sig).not.toBeNull()
    expect(edit(sig)).toContain(`'${b}', '${a[1]}'`)
    expect(run).toContain(`["${sig}"]=${b}`)
  }
  expect(m).toContain("if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;")
  expect(m).toContain("raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;")
  for (const f of ['svc_enrich_ai_record', 'svc_enrich_ai_next', 'enrich_fields_slice_v1', 'field_enrich_items_flag_v1', 'course_coverage_build_v1', 'source_proof_feed_v1'])
    expect(m).not.toMatch(new RegExp(`edit_once\\('[a-z]+\\.${f}\\(`))
  expect(run).toContain("grep -c ': applied$')\" = 7 ]")
  expect(run).toContain("grep -c ': already applied$')\" = 7 ]")
})

test('the switches ship on (the items state the behaviour); the report window is a setting; the adapter step waits for a corrected website', () => {
  expect(m).toMatch(/\('pipeline', 'plans\.step_needs_work_on', [\s\S]*?'number', '1'::jsonb, '0', '1', 'on \(1\) or off \(0\)'/)
  expect(m).toMatch(/\('pipeline', 'onboarding\.website_check_on', [\s\S]*?'number', '1'::jsonb, '0', '1', 'on \(1\) or off \(0\)'/)
  expect(m).toMatch(/'plans\.outcome_window_hours'[\s\S]*?'number', '24'::jsonb, '1', '168', 'hours'/)
  expect(m).toContain(`set value = value || '["needs_source_discovery"]'::jsonb`)
  expect(off).toContain("set value = '0' where toolset_key = 'pipeline' and key in ('plans.step_needs_work_on', 'onboarding.website_check_on')")
  for (const k of ['off: the scholarships step is proposed as before', 'off: the scan ends done "0 of 0" as before', 'off: a no_website row with an email-address website goes back to the website stage as before'])
    expect(off).toContain(k)
})

test('IQ-00066: a scholarships step is proposed and started only with eligible work, by the reader\'s own gates', () => {
  expect(m).toContain('create or replace function security.scholarship_scan_work_v1(p_providers uuid[]) returns jsonb')
  expect(m).toContain("when security.fc_sch_held_v1(r.id, true) then case when not security.fc_sch_eligible_v1(r.id) then 'not_eligible' else 'credit_cap' end end;")
  expect(m).toContain('if not r.has_row or r.next_discover_at is null or r.next_discover_at <= now() then v_map := v_map + 1;')
  const p = after(edit('security.enrich_plan_v1(uuid)'))
  expect(p).toContain("security.plan_step_work_v1(p_provider, 'scholarships')")
  expect(p).toContain("'steps', v_steps, 'not_proposed', v_held,")
  const t = after(edit('security.enrich_plan_tick_v1(uuid)'))
  expect(t).toContain("v_state := 'not_needed'; v_note := left('Not needed: ' || coalesce(v_work->>'reason', 'no eligible work'), 300);")
  expect(t).toContain("when j.state = 'cancelled' and j.result->>'end_state' = 'not_needed' then 'not_needed'")
  expect(before).toContain("'before IQ-00066: the plan builder proposes Find and read scholarships for a provider the scholarship reader refuses'")
  for (const k of ['P1 the 12:41 case', 'P2 an eligible provider whose site was mapped and whose next mapping is not due', 'P3 never mapped: proposed', 'P5 not due, but a candidate page waits',
    'P7 its scholarship credit cap is used', 'P8 scholarship search switched off', 'T1 a pending step with no eligible work ends not_needed with the reason; no task is started', 'T3 a step with eligible work starts as before'])
    expect(fixtures).toContain(k)
})

test('IQ-00066: a scan with no eligible work ends not needed at once, never done; an eligible mapping or screening is held', () => {
  const w = after(edit('security.admin_job_watch_v1(uuid)'))
  expect(w).toContain("v_n_map := least(v_n_map, coalesce((v_work->>'map_due')::int, v_n_map));")
  expect(w).toContain("and not exists (select 1 from pipeline.scholarship_discovery_providers d where d.provider_id = any (v_ids) and (d.attempts > 0 or d.discovered_at >= v_since))")
  expect(w).toContain("v_extra := v_extra || jsonb_build_object('end_state', 'not_needed', 'not_needed', v_work);")
  expect(w).toContain("v_j.kind = 'scholarship_provider_scan' and v_n_map + v_n_cand > 0 and security.pipeline_num_v1('plans.step_needs_work_on', 0) >= 1")
  expect(after(edit('security.admin_jobs_tick_v1(integer)'))).toContain("when result->>'end_state' = 'not_needed' then 'cancelled' else 'done' end")
  expect(before).toContain('before IQ-00066: the scan ends done "0 of 0 done, nothing more for 30 minutes"')
  for (const k of ['W1 the 12:41 case: the scan with no eligible work ends not needed at once', 'W2 the plan ends with outcome not_needed', 'W3 an eligible site mapping that waits 40 minutes is held',
    'W4 once its site is mapped the scan finishes done', 'W5 mapping not due, a candidate waits', 'W6 a scan with its page read finishes done as before']) expect(fixtures).toContain(k)
})

test('IQ-00066: a plan of not-needed steps is reported apart from plans that moved data (Pipeline yield)', () => {
  expect(after(edit('security.enrich_plan_tick_v1(uuid)'))).toContain("'outcome', security.plan_run_outcome_v1(r.steps),")
  expect(after(edit('public.admin_pipeline_yield(jsonb)'))).toContain("|| jsonb_build_object('plan_outcomes', security.plan_outcomes_v1());")
  expect(m).toContain("make_interval(hours => security.pipeline_num_v1('plans.outcome_window_hours', 24)::int)")
  for (const k of ['T2 the plan finishes with outcome not_needed', 'T4 outcomes', 'Y1 plan_outcomes_v1', 'Y2 admin_pipeline_yield returns plan_outcomes']) expect(fixtures).toContain(k)
  expect(iq).toContain('{y.plan_outcomes&&<PlanOutcomes o={y.plan_outcomes}/>}')
  expect(iq).toContain('data-plan-outcomes')
  expect(plan).toContain("not_needed:['Not needed','neutral']")
  expect(plan).toContain('data-plan-not-proposed')
})

test('IQ-00053 residual: the description duplicate check splits the new text once, with the same answers', () => {
  const d = after(edit('security.course_description_check_v1(uuid,jsonb)'))
  expect(d).toContain('v_words := security.pdesc_words_v1(v_text);')
  expect(d).toContain("array(select distinct w from regexp_split_to_table(lower(coalesce(x0.d, '')), '[^a-z0-9]+') w where length(w) >= 3) wb")
  expect(d).toContain('round(k.n::numeric / (cardinality(v_words) + cardinality(x.wb) - k.n), 4)')
  expect(d).not.toContain('pdesc_similarity_v1(v_text')
  expect(m).toContain("('security.pdesc_words_v1(text)', '1a18bd60d2978c1885a25085b688afc7')")
  expect(before).toContain('before IQ-00053: 6 description answers recorded')
  expect(fixtures).toContain("'D1 the six answers (four duplicates, one new text, one too short) are the same as on the live definition'")
})

test('IQ-00063: onboarding refuses a website that is not a site address and stops with needs_source_discovery; no data is corrected here', () => {
  expect(m).toContain("when substring(btrim(p_url) from '^[A-Za-z]+://([^/?#]*)') like '%@%' then 'it has a user part")
  const o = after(edit('security.provider_onboarding_tick_v1()'))
  expect(o).toContain("set status = 'stopped', stop_reason = 'needs_source_discovery', job_id = null")
  expect(o).toContain("ob.stop_reason in ('no_website', 'needs_source_discovery')")
  expect(o).toContain("security.website_refusal_v1(pv.website) is null);")
  expect(m).not.toMatch(/d5dfc2ea-6012-45e9-a8c5-e0c4c77d5d79|2db6cb5e-eb25-4722-bac9-69c49166bdd7/)
  expect(m).not.toMatch(/^\s*update catalogue\.providers/im)
  expect(before).toContain('before IQ-00063: a stopped no_website row with an email-address website is sent back to the website stage and stepped')
  for (const k of ['O1 the d5dfc2ea case', 'O3 it stays stopped: no loop', 'O4 a stopped no_website row with a refused website is not sent back', 'O5 once the website is corrected it carries on by itself', 'O6 website_refusal_v1'])
    expect(fixtures).toContain(k)
})
