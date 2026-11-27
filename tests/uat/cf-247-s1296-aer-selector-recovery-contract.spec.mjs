// Guards: SS-Programme-Control 27 Nov 2026 11:27 AEDT (complete autonomous AER reader selection and admission: the selector uses the recovery signature, never repeats an unchanged unsuccessful read, stays inside the paid cap; E13 counts reads made; domestic cut-off statistics do not make a read incomplete)
// s1296: worker v1.0.55 entryDomesticStatistic and the migration settings use the same words; the selector, tick and E13 changes are read-only on what is stored, add no job, and keep G1, G2 and G3.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { entryDomesticStatistic, courseEntrySliceRows, ENTRY_DOMESTIC_STATISTIC, ENTRY_DOMESTIC_STATISTIC_EXCLUDE } from '../../supabase/functions/coverage-sweep/course-entry.ts'

const MIG = fs.readFileSync('supabase/migrations/20261130123000_cf247_s1296_aer_selector_recovery_signature.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')
const words = (re) => re.source.replace(/^\\b\(/, '').replace(/\)\\b$/, '').split('|')

test('s1296: a quote that fails the page proof and is a domestic cut-off statistic is dropped as domestic_route_statistic, which does not hold the read', () => {
  for (const q of ['Median 99.65', 'Lowest 84.8 With adjustments', 'Entry score range... Lowest 80.45 With adjustments', 'Highest 98.85 for Semester 1, 2026 intake.', '2026 Lowest ATAR 70.6']) {
    expect(entryDomesticStatistic(q)).toBe(true)
  }
  const page = 'Applicants must have a relevant bachelor degree or equivalent qualification. Median rank is shown in the table.'
  const a = { rows: [
    { kind: 'minimum_grade', audience: 'domestic', description: 'Median 99.65', quote: 'Median 99.65' },
    { kind: 'prior_qualification', audience: 'all', description: 'bachelor', quote: 'Applicants must have a relevant bachelor degree or equivalent qualification.' },
  ] }
  const { rows, dropped } = courseEntrySliceRows(a, page)
  expect(rows.length).toBe(1)
  expect(dropped).toEqual([{ reason: 'domestic_route_statistic', kind: 'minimum_grade', quote: 'Median 99.65' }])
})

test('s1296: an international word, an English test, a visa or an "or equivalent" route is never a domestic statistic; a quote that is on the page is kept as before', () => {
  for (const q of ['International applicants need an ATAR equivalent of 80', 'IELTS 6.5 with ATAR 70 for local applicants', 'Year 12 (VCE or equivalent) with a median of 70', 'A visa is needed; median 80', 'Applicants must have a minimum selection rank of 80', 'VCE study score of at least 25']) expect(entryDomesticStatistic(q)).toBe(false)
  expect(entryDomesticStatistic('Applicants must have a relevant bachelor degree')).toBe(false)
  const { dropped } = courseEntrySliceRows({ rows: [{ kind: 'prior_qualification', audience: 'all', description: 'x', quote: 'Year 12 (VCE or equivalent) is required for entry' }] }, 'a page that does not say it')
  expect(dropped.map((d) => d.reason)).toEqual(['quote_not_on_page'])
  const page = 'Minimum ATAR 70 for local applicants.'
  const kept = courseEntrySliceRows({ rows: [{ kind: 'minimum_grade', audience: 'domestic', description: 'ATAR 70', quote: 'Minimum ATAR 70 for local applicants.' }] }, page)
  expect(kept.rows.length).toBe(1)
  expect(kept.dropped).toEqual([])
})

test('s1296: the migration settings use the same words as the worker (statistic and exclusion), and domestic_route_statistic is not a gate hold reason', () => {
  const settingWords = (key) => { const m = code.match(new RegExp(`'${key}'[\\s\\S]*?to_jsonb\\('([^']*)'::text\\)`)); return m && m[1] }
  const dom = settingWords('aer.domestic_statistic_pattern'), exc = settingWords('aer.domestic_statistic_exclude')
  expect(dom).toBeTruthy(); expect(exc).toBeTruthy()
  const pg = (re) => re.source.replace(/\\b/g, '\\\\b')
  for (const w of words(ENTRY_DOMESTIC_STATISTIC)) expect(dom).toContain(w)
  for (const w of ['international', 'overseas', 'ielts', 'toefl', 'pte', 'visa', 'must', 'minimum', 'at least']) { expect(exc).toContain(w); expect(ENTRY_DOMESTIC_STATISTIC_EXCLUDE.source).toContain(w) }
  expect(exc).toContain('or (an |any )?equivalent'); expect(ENTRY_DOMESTIC_STATISTIC_EXCLUDE.source).toContain('or (an |any )?equivalent')
  expect(pg(ENTRY_DOMESTIC_STATISTIC)).toBeTruthy()
  expect(code).not.toContain("entry.gate_hold_reasons")
})

test('s1296: the selector is one read-only rule; an outcome that was not a read, an unchanged copy, the deterministic outcome, the row limit and recorded failures decide eligibility', () => {
  expect(code).toContain('create or replace function security.aer_first_read_state_v1(p_provider uuid default null)')
  expect(code).toMatch(/aer_first_read_state_v1[\s\S]*?language sql stable security definer set search_path = ''/)
  for (const c of ['never_read', 'not_a_read', 'incomplete_read', 'read_no_result', 'read_no_row', 'page_limit', 'row_limit', 'in_progress']) expect(code).toContain(`'${c}'`)
  expect(code).toContain('d.copy_changed')
  expect(code).toContain("d.detok ? d.det")
  expect(code).toContain("security.ops_learning_retry_check_v1('aer_first_read:unchanged_copy_no_result', d.course_id::text, d.sig)")
  expect(code).toContain("security.course_entry_max_rows_v1(d.provider_id)")
  expect(code).toContain("from security.aer_first_read_state_v1(p_provider) x where x.eligible")
  expect(code).toContain("not exists (select 1 from catalogue.course_entry_requirements x where x.course_id = p.course_id and x.status in ('active', 'proposed'))")
  expect(code).toContain("r.status = 'pending'")
  // the old flat timer is not the rule for classified outcomes any more: it remains only for the unclassified 'other'
  expect(code).toContain('else d.last_at < now() - d.retry end')
  expect(code).not.toMatch(/f\.updated_at > now\(\) - s\.retry/)
})

test('s1296: G2 settings carry a label, range, unit and used_by; constants are marked fixed; nothing is hard-coded about money or a day', () => {
  for (const k of ['aer.not_a_read_pattern', 'aer.no_result_pattern', 'aer.no_result_reader_pattern', 'aer.page_limit_pattern', 'aer.read_again_change_keys', 'aer.ai_after_det_outcomes', 'aer.domestic_statistic_pattern', 'aer.domestic_statistic_exclude', 'aer.schedule_technical_retry_hours', 'aer.schedule_paid_share', 'aer.e13_not_read_pattern']) expect(code).toContain(`'${k}'`)
  expect(code).toContain("'number', '24'::jsonb, 1, 720, 'hours'")
  expect(code).toContain("'number', '0.6'::jsonb, 0, 1, 'share of the cap'")
  expect(code).toContain('security.pipeline_num_v1(\'budgets.paid_daily_cap_usd\', 5)')
  expect(code).toContain("security.pipeline_num_v1('aer.schedule_paid_share', 0.6)")
  expect(MIG).toContain("interval '3 hours'  -- fixed:")
  expect(MIG).toContain('limit 500  -- fixed:')
  expect(code).not.toMatch(/\b(5\.00|US\$5)\b/)
})

test('s1296: the tick is clamped to the paid cap, records what it spent and what it learned, and keeps its other behaviour', () => {
  expect(code).toContain('security.ai_spend_today_v1()')
  expect(code).toContain("x.use = 'enrich_fields'")
  expect(code).toContain('least(v_paid * v_share - v_spent_lane, v_paid - v_spent_all) / v_cost')
  expect(code).toContain('v_room := least(v_room, v_paid_room); v_croom := least(v_croom, v_paid_room);')
  expect(code).toContain('the paid cap for today is used')
  expect(code).toContain("'paid', jsonb_build_object('cap_usd', v_paid")
  expect(code).toContain('v_learn := security.aer_first_read_learn_v1();')
  for (const s of ['pg_try_advisory_xact_lock(hashtext(\'cf247:aer-scheduled-read\'))', 'security.aer_schedule_held_v1(v_croom)', 'security.course_entry_read_enqueue_v1(r.course_id, v_owner', 'security.aer_technical_recovery_v1()', "aer.schedule_layer4_max"]) expect(code).toContain(s)
})

test('s1296: E13 counts reads made, not asks that never reached a read; the pilot limits are unchanged', () => {
  expect(code).toContain("coalesce(security.toolset_setting('pipeline', 'aer.e13_not_read_pattern') #>> '{}', '')")
  expect(code.match(/not \(\(v_notread <> '' and coalesce\(s\.outcome, ''\) ~\* v_notread\)/g).length).toBe(2)
  expect(code).toContain("s.state = 'requested' and exists (select 1 from pipeline.field_enrich_items f where f.id = s.enrich_item_id and f.state in ('skipped', 'failed')")
  expect(code).toContain("v_room := greatest(0, least(v_batch, v_day - v_used, v_total - v_all));")
  expect(code).not.toMatch(/update pipeline\.platform_toolset_settings/i)
  expect(code).toContain("'AI route is switched off|no longer waits|another read of this course waits|Layer 4 item is no lo|no proven course page'")
})

test('s1296: the recovery knowledge is the existing table; outcomes are recorded once per copy and reader; authorities are valid', () => {
  expect(code).toContain('insert into pipeline.ops_remedy_knowledge')
  expect(code).toContain("'aer_first_read:unchanged_copy_no_result'")
  expect(code).toContain("'aer_first_read:incomplete_structure_needs_reader'")
  expect(code).toContain("'auto', 'platform',")
  expect(code).toContain("'release', 'claude_engineering',")
  expect(code).toContain('security.ops_learning_record_v1(jsonb_build_object(')
  expect(code).toContain("o.evidence_signature = r.sig")
  expect(code).not.toMatch(/create table|create index/i)
})

test('s1296: nothing deleted or dropped; no consumer object, job, lock or setting value changed; pre- and post-checks guard G3, locks and cron', () => {
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l))).toEqual([])
  expect(code).not.toMatch(/\bdelete from\b|truncate |cron\.schedule|cron\.alter_job|cron\.unschedule|website_v2_|website_edge_|zoho_edge_/i)
  for (const s of ['guard: consumer API baseline is not 75/48', 'post-check: consumer API drift', 'post-check: manual locks changed', 'post-check: a cron job was added', 'above 140', 'post-check: the rule classifies', 'hold a row, a lock or a waiting decision']) expect(MIG).toContain(s)
  expect(MIG).toContain('-- Replaces:')
  expect(MIG).toContain('Retires: nothing.')
})
