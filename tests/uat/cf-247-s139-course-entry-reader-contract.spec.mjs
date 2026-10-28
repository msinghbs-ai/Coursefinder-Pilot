// Guards: CF-247 Track C Step B decision 28 Oct 2026 (Platform Admin mandate 20:36; admin docs/platform/ENTRY-REQUIREMENTS-STEP-B-DECISION-2026-10-28.md section 4; B1 spec field-admission section 5): course entry requirements ride the existing Enrich fields lane from the stored course page only, admitted as proposed under the B1 rules (quote on page, score with printed basis, band only when printed, no English duplicate, audience from the quote) and only through Layer 4; settings not constants; one bounded slice read
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261028001000_cf247_entry_step_b_course_read_resolver.sql', 'utf8')
const code = m.split('\n').filter(l => !/^\s*--/.test(l)).join('\n')
const rec = code.slice(code.indexOf('create or replace function security.enrich_entry_record_v1'), code.indexOf('revoke all on function security.enrich_entry_record_v1'))
const apply = code.slice(code.indexOf('create or replace function security.course_entry_review_apply_v1'), code.indexOf('revoke all on function security.course_entry_review_apply_v1'))
const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const entry = w.slice(w.indexOf('const entryRead = async'), w.indexOf('tally.entry = (tally.entry || 0) + items.length;'))

test('the existing lane, a new field outside the registry, stored page only, strong AU proofs', () => {
  expect(m).not.toMatch(/enrich_fields_v1\(\)\s+returns/)  // the field registry is not changed: no automatic plan asks for it
  expect(m).toContain("values ('AU', 'entry_requirements', array['ai_stored'],")
  expect(m).toContain("jsonb_build_object('entry_requirements', jsonb_build_array('cricos_code', 'adapter_code', 'manual'))")
  expect(rec).toContain("security.coverage_identity_allowed(g.provider_id, g.identity_basis, 'entry_requirements')")
  expect(code).toContain("values ('enrich_fields', 'enrich', 'queued', left('Entry requirements · ' || c.canonical_title, 200),")
  expect(code).toContain("'fields', jsonb_build_array('entry_requirements'), 'ai', true, 'scraper', false)")
  expect(code).not.toMatch(/insert into pipeline\.(automation_catalogue|admin_job_kinds)/)  // no new job or kind
  expect(code).not.toMatch(/cron\.schedule/)
})

test('worker: own call with the pinned entry model; every row quoted on the page; no band from a score; no English tests', () => {
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v0\.49\.[1-9]\d*";/)
  expect(entry).toContain('htmlToText(raw.replace(/<(nav|header|footer)\\b[\\s\\S]*?<\\/\\1>/gi, " "))')  // v0.49.1: the whole page, not only <main>
  expect(entry).toContain('const em = String(w?.entry?.model || ""), chars = Number(w?.entry?.page_chars || 0);')
  expect(entry).toContain('if (!on(text, q)) { dropped.push({ reason: "quote_not_on_page"')
  expect(entry).toContain('never derive a band from an ATAR, rank or score')
  expect(entry).toContain('Do not list English language tests or English proficiency requirements.')
  expect(code).toContain("'entry', jsonb_build_object('model', coalesce(security.toolset_setting('pipeline', 'entry.matrix_model') #>> '{}', 'openai/gpt-4.1-mini'),")
})

test('database B1 rules: score with its printed basis, band only when printed, English duplicate dropped, audience from the quote', () => {
  expect(rec).toContain("v_drop := v_drop || jsonb_build_object('reason', 'score_without_basis'")
  expect(rec).toContain("not exists (select 1 from regexp_matches(v_q, '([0-9]+(\\.[0-9]+)?)', 'g') m where m[1]::numeric = v_score)")
  expect(rec).toContain("v_notes := v_notes || jsonb_build_object('note', 'band_not_printed'")
  expect(rec).toContain("jsonb_build_object('reason', 'english_duplicate'")
  expect(rec).toContain("v_aud := case when v_q ~* '\\m(international|overseas)\\M' then 'international'")
  expect(rec).toContain("security.pipeline_num_v1('entry.max_rows_per_course', 6)")
  expect(rec).toContain("security.pipeline_num_v1('entry.min_confidence', 0.8)")
})

test('rows land proposed and go to a person; Layer 4 admits the whole read or makes it inactive; nothing auto-approves', () => {
  expect(rec).toContain("v_c, coalesce(g.captured_at::date, current_date), 'proposed',")
  expect(rec).toContain("values ('course', i.course_id, 'course_entry_first_read',")
  expect(rec).toContain("update pipeline.field_enrich_items set state = 'review'")
  expect(rec).not.toMatch(/'active'\s*,\s*jsonb_build_object\('reader'/)
  expect(apply).toContain("if p_action = 'approve' then")
  expect(apply).toContain("set status = 'inactive', status_reason = 'quarantined (' || p_action")
  expect(code).toContain("for each row when (old.status = 'pending' and new.status <> 'pending' and new.field_code = 'course_entry_first_read')")
  expect(code).toContain("elsif v_item.entity_type='course' and v_item.field_code='course_entry_first_read' then")
  expect(code).not.toMatch(/provider_entry_matrix\s+(m\s+)?set/)  // the matrix (and its 37 proposed rows) is never changed here
})

test('edited functions are md5-guarded; one bounded, count-guarded slice read', () => {
  expect(m).toContain("select pg_temp.edit_n('public.svc_enrich_ai_record(jsonb)', 'c3685d7aa7306365fa33f6f09834ea90'")
  expect(m).toContain("select pg_temp.edit_n('public.svc_enrich_ai_next(integer)', '0ad1ad53db595992ecb4b892c07ec184'")
  expect(m).toContain("select pg_temp.edit_n('security.layer4_review_decide_impl(uuid,text,text,jsonb)', 'a438f594dea0fc905323b640ea909b30'")
  expect(m).toContain("declare v_course uuid := '09431698-3cfd-4c2b-8669-e924bc65c329';")
  expect(m).toContain("if (select count(*) from pipeline.field_enrich_items where field = 'entry_requirements') = 0")
  expect(m).toContain("raise exception 'slice guard: more than one entry_requirements item would exist';")
  for (const k of ['entry.course_read_countries', 'entry.max_rows_per_course', 'entry.min_confidence', 'entry.course_page_chars']) expect(m).toContain(`('pipeline', '${k}',`)
  expect(m).toContain('-- Replaces:'); expect(m).toContain('-- Retires: nothing')
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('v0.49.1 follow-up: a read releases the field\'s earlier no-value hold and is refused loudly by the item gate otherwise', () => {
  const f = fs.readFileSync('supabase/migrations/20261028003000_cf247_entry_step_b_course_read_full_page.sql', 'utf8')
  expect(f).toContain("if md5(pg_get_functiondef('security.course_entry_read_enqueue_v1(uuid,uuid,text)'::regprocedure)) <> '77053f34121c28c633f10d2318cc9f4b' then")
  expect(f).toContain("and f.reason_code = 'enrich_no_value' and f.state in ('raised', 'counting') and f.field = 'entry_requirements';")
  expect(f).toContain("raise exception 'the entry requirements item was refused by the item gate'")
  expect(f).not.toMatch(/^\s*perform security\.course_entry_read_enqueue_v1/m)  // no read enqueued here: it waits for the v0.49.1 worker
  expect(f).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('the slice read once more, after v0.49.1 is live: count-guarded, at most two items ever', () => {
  const f = fs.readFileSync('supabase/migrations/20261028004000_cf247_entry_step_b_slice_reread.sql', 'utf8')
  expect(f).toContain("if (select count(*) from pipeline.field_enrich_items where field = 'entry_requirements') = 1")
  expect(f).toContain("and state = 'skipped' and reason = 'the page does not state it') then")
  expect(f).toContain("raise exception 'slice guard: more than two entry_requirements items would exist';")
  expect(f).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})
