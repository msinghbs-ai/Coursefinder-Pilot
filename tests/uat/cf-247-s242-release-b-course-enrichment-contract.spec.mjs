// Guards: Platform Admin mandate 3 Nov 2026 13:09 §4 Release B, D2, D3 and §6 (course enrichment from verified stored evidence; evidence-aware absence)
// Release B extends the existing Enrich fields engine (enrich_fields_slice_v1, svc_enrich_ai_next / svc_enrich_ai_record, worker mode enrich_ai):
// one read of a course's stored page for every missing field, an explicit and configurable absence catalogue recorded per course and field
// (evidence, content hash, reader version, confidence, reason, next eligibility), no re-read of an unchanged copy after a verified negative, and
// the standing gap queue checked hourly. The behaviour runs on isolated fixtures by tests/fixtures/course-enrichment/run.sh (scratch PostgreSQL;
// the five live functions the migration edits and the four it reads against are loaded from their live text and checked against the live md5s;
// the migration applied twice; every case asserted). This spec holds the contract of the change.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261103210000_cf247_release_b_course_enrichment.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/course-enrichment'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const before = fs.readFileSync(`${FX}/fixtures-before.sql`, 'utf8')
const edit = (sig) => { const a = m.indexOf(`select pg_temp.edit_once('${sig}'`); expect(a, sig).toBeGreaterThan(-1); return m.slice(a, m.indexOf(']], array[', a) + 20) }
const fn = (name) => { const a = m.indexOf(`create or replace function ${name}(`); expect(a, name).toBeGreaterThan(-1); return m.slice(a, m.indexOf(`comment on function ${name}(`, a)) }

// live md5 before (read 3 Nov 2026 13:11-13:30 AEDT) and after the edit
const EDITS = {
  'security.enrich_fields_slice_v1(uuid,integer)': ['4babdac64e58459fe38d79def27842ea', 'c385d9c3a9fd33614f189773e45683f3'],
  'public.svc_enrich_ai_next(integer)': ['dfaff31828c7d99d46f25719e5d985cf', 'e4bdf62857d011458e3293006a7e7426'],
  'public.svc_enrich_ai_record(jsonb)': ['ae1ced1c1f1fd092afe885cfc37be0b4', 'bcbfc91ce997b1516d90b1320264fa12'],
  'security.field_enrich_items_flag_v1()': ['d2180b8be792558f8c9f3fa1eb3daf98', 'a874a3b37e11a116f39742c80311a50b'],
  'security.course_coverage_build_v1()': ['f698bf7f6cc2130adf3c9a4e174c3810', '2f6a9a8314281004d9fa4253527a5488'],
}

test('five live definitions are edited only from their live md5 and checked after; the fixture loads the same live text', () => {
  for (const [sig, [b, a]] of Object.entries(EDITS)) {
    expect(edit(sig)).toContain(`'${b}', '${a}'`)
    expect(run).toContain(`["${sig}"]=${b}`)
  }
  for (const [sig, md5] of [['security.enrich_fields_v1()', '80ee183b324c196b4c9559cec6e3360f'], ['security.enrich_item_in_flight_v1(uuid,uuid,text)', '35caac7c2ae66aa43ea0ffc9a6d5f654'],
                            ['security.field_sources_for_v1(text,text)', 'd8c74083ed675fb2383fedd4b4a1ec49'], ['security.field_gap_queue_run_v1()', '429835d4d27375da95901104838a0cad']]) {
    expect(m).toContain(`('${sig}', '${md5}')`)
    expect(run).toContain(`["${sig}"]=${md5}`)
  }
  // functions owned by the Release A candidate are not touched here
  for (const owned of ['course_relink_', 'admin_pipeline_yield', 'field_backlog_v1', 'flag_jobs_v1', 'admin_job_watch_v1', 'admin_jobs_tick_v1', 'enrich_plan_tick_v1', 'field_gap_queue_tick_v1()'])
    expect(m).not.toContain(`edit_once('security.${owned}`)
})

test('multi-field: the reader takes one stored copy for every missing field of the course, inside the existing rules and guards', () => {
  expect(edit('security.enrich_fields_slice_v1(uuid,integer)')).toContain('perform security.enrich_siblings_v1(it.id);')
  const s = fn('security.enrich_siblings_v1')
  for (const rule of ["security.pipeline_num_v1('enrich.multi_field_on', 1) < 1", "'enrich.multi_field_fields'", "'enrich.multi_field_max_per_page'",
                      "security.field_sources_for_v1(v_cc, f)", 'security.enrich_course_field_missing_v1(i.course_id, f)', 'pipeline.manual_locks',
                      'security.enrich_item_in_flight_v1(i.provider_id, i.course_id, f)', 'security.field_absence_due_v1(i.course_id, f, i.evidence_id)',
                      'security.field_absence_unchanged_v1(i.course_id, f, i.evidence_id)', "'enrich.course_text_items_per_day'", "j.args->'fields'"])
    expect(s).toContain(rule)
  expect(s).toContain("values (i.job_id, i.provider_id, i.course_id, f, 'ai', 'ai_stored', array['ai_stored'], i.storage_path, i.evidence_id)")
  expect(s).not.toMatch(/firecrawl|scraper|next_read_at/i)  // D1: the stored copy only, nothing fetched
  const next = edit('public.svc_enrich_ai_next(integer)')
  expect(next).toContain("pick as (select p0.id from pick0 p0 union select p1.id from pick1 p1),")
  expect(next).toContain('for update skip locked),')
  expect(m).toMatch(/'enrich\.multi_field_fields', [^\n]*\n[^\n]*\n\s*'list', '\["campus", "duration", "delivery", "international", "english", "intakes", "description", "deadline"\]'/)
})

test('D2 + D3: an explicit, configurable absence catalogue recorded per course and field with evidence, reader, confidence and next eligibility', () => {
  for (const code of ['not_on_this_page', 'on_other_stored_page', 'needs_source_discovery', 'evidence_pending', 'explicitly_not_stated', 'not_applicable', 'identity_unresolved'])
    expect(m).toContain(`('${code}', `)
  expect(m).toContain('create table if not exists pipeline.field_absence_classes (')
  expect(m).toContain('create table if not exists pipeline.field_absence_rules (')
  expect(m).toMatch(/create table if not exists pipeline\.course_field_absence \(\n\s+course_id uuid not null, field text not null, absence_class text not null[^\n]*\n\s+evidence_id uuid, content_hash text, reader_version text, confidence numeric, reason text,\n\s+next_eligible_at timestamptz, reeval_trigger text/)
  const c = fn('security.field_absence_classify_v1')
  // D3: a negative only from a stored page that a reader read; an adapter or source with nothing is never "unavailable"
  expect(c).toContain("if k.verified_negative and (i.source is distinct from 'ai_stored' or i.evidence_id is null) then")
  expect(c).toContain("v_class := case when v_stored then 'evidence_pending' else 'needs_source_discovery' end")
  expect(m).toContain("(70, null, null, null, false, 'no allowed source had a value', 'needs_source_discovery'")
  expect(edit('security.field_enrich_items_flag_v1()')).toContain("$n$'(does not state|names no campus|quote is not on the page|site-wide line|not classified)'$n$")
  // never re-read an unchanged copy after a verified negative; re-evaluate on a changed copy or a new page
  expect(edit('security.enrich_fields_slice_v1(uuid,integer)')).toContain('security.field_absence_unchanged_v1(it.course_id, it.field, v_ev) or exists (')
  expect(fn('security.field_absence_unchanged_v1')).toContain("a.content_hash = (select e.content_hash from pipeline.evidence_artifacts e where e.id = p_ev)")
  expect(fn('security.field_absence_due_v1')).toContain("when 'page_change' then")
  expect(edit('public.svc_enrich_ai_record(jsonb)')).toContain("set_config('cf247.reader_version'")
  // the coverage cache: the class instead of the blanket "not on page" for delivery and duration
  const cov = edit('security.course_coverage_build_v1()')
  expect(cov).toContain("when g.reader='enrich' and ei.state in ('skipped','failed') and ab.by_class")
  expect(m).toContain(`'list', '["delivery", "duration"]'::jsonb`)
  expect(m).toContain('alter table pipeline.course_attribute_coverage add column if not exists absence_class text;')
})

test('throughput: the standing gap queue is checked hourly and advances when its next batch is due (settings, load-policy minute)', () => {
  expect(m).toContain("perform cron.alter_job(v_id, schedule := '23 * * * *', command := 'select security.field_gap_queue_run_v1() where security.field_gap_queue_due_v1()');")
  expect(m).toContain("if v_cmd <> 'select security.field_gap_queue_run_v1()' or v_sched <> '23 */6 * * *' then")
  const d = fn('security.field_gap_queue_due_v1')
  for (const k of ["'gaps.advance_minutes', 60", "'gaps.idle_rerun_minutes', 360", "j.state in ('queued', 'running', 'paused')", 'k.cursor_course_id', "l.outcome from l) = 'done'"])
    expect(d).toContain(k)
})

test('the fixture covers every case, before and after, applied twice', () => {
  expect(before).toContain("<> 'not_on_page'")
  expect(run).toContain('a second run changed jobs, settings, registers or absences')
  for (const n of ['ok 1 backfill', 'ok 2 multi-field', 'ok 3 lease', 'ok 4 record', 'ok 5 D2', 'ok 5b D2', 'ok 6 a person', 'ok 6b switched off', 'ok 7 D3', 'ok 7b', 'ok 8 coverage', 'ok 9 gap queue', 'ok 10 settings'])
    expect(fixtures).toContain(`raise notice '${n}`)
})
