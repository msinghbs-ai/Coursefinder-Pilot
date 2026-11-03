// Guards: Platform Admin design decision 4 Nov 2026 06:30 (mandatory human-assisted recovery across all admission layers, amending SS-018, SS-019
// and SS-021): one deduplicated intervention contract linked to work items; one server function for the eleven §2 actions with validation, ranks
// and audit; automatic resumption per lane with verification that closes or reopens; a targeted stronger-model step that ships off and never
// invents; AER first, then scholarship coverage; time bounds per failure class as settings; the §9 metrics in the operations report; and the
// Inbox functions left to their owner (Coordinator 4 Nov 2026 06:53). The six §8 lifecycles run end to end on isolated fixtures by
// tests/fixtures/human-assisted-recovery/run.sh (scratch PostgreSQL 16; the live Layer 4 build and ops_report_v1 checked against the live md5s;
// the migration applied, then applied again unchanged). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'

const MIG = 'supabase/migrations/20261104400000_cf247_human_assisted_recovery.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/human-assisted-recovery'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const md5 = (s) => crypto.createHash('md5').update(s).digest('hex')
const ACTIONS = ['provide_url', 'attach_document', 'enter_value', 'confirm_identity', 'select_source', 'confirm_scope', 'correct_value', 'search_again',
  'confirm_not_published', 'return_technical', 'reject_evidence']
const CLASSES = ['aer_source_missing', 'aer_document_unverified', 'aer_rendered_only', 'aer_empty_read', 'aer_read_held', 'aer_course_identity',
  'sch_source_missing', 'sch_international_unresolved', 'sch_ownership_conflict', 'fee_evidence_conflict', 'intake_incomplete', 'aer_read_evidence', 'aer_read_rows_missing']

test('one guarded edit (the operations report section) from the live text; the Inbox functions are not edited here', () => {
  expect(m).toContain("select pg_temp.edit_once('security.ops_report_v1(integer)', '5a1e21cc42f8f54cbf0d9f3f7fe81c71', '3ba694dc078995d88a983e8e92b2f425'")
  expect(md5(fs.readFileSync(`${FX}/live/security.ops_report_v1.def`, 'utf8').replace(/\n$/, ''))).toBe('5a1e21cc42f8f54cbf0d9f3f7fe81c71')
  expect(m).toContain("md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then")
  expect(m).toContain("('security.work_item_report_v1(text,text,text,text,jsonb)', '6a15318c0ecd6644b32f1883463c542e')")
  for (const f of ['admin_layer4_inbox', 'layer4_inbox_items_v1', 'layer4_inbox_kinds_v1']) expect(m).not.toMatch(new RegExp(`edit_once\\('[a-z]+\\.${f}`))
  expect(run).toContain('the migration changed $s, which it does not own')
})

test('the contract: one intervention per lane, entity and missing fact, linked to its work item, deduplicated by fingerprint', () => {
  expect(m).toContain('unique (lane, entity, missing_fact)')
  for (const col of ['required_input jsonb', 'evidence jsonb', 'ai_analysis jsonb', 'recommended jsonb', 'allowed_actions jsonb', 'resume_target jsonb', 'work_item_id bigint',
    'next_action_at', 'escalate_at', 'recover_by', 'assigned_to', 'verified_outcome']) expect(m).toContain(col)
  expect(m).toContain("update pipeline.layer4_interventions set repeat_count = repeat_count + 1, last_seen_at = now() where id = i.id;")
  expect(m).toContain("v_res := security.work_item_report_v1(v_wi->>'lane', v_wi->>'entity', v_wi->>'kind', 'review',")
  expect(m).toContain('if v_att < security.har_num_v1(c.code')  // AI-first: asked only after automatic attempts
  expect(m).toContain("security.pipeline_num_v1('har.open_max_per_lane', 150)")
})

test('the eleven actions of §2 through one server function, with ranks, validation, provenance and audit; never approval to publish', () => {
  for (const a of ACTIONS) expect(m).toContain(`'${a}'`)
  for (const c of CLASSES) expect(m).toMatch(new RegExp(`^ \\('${c}', '[a-z_]+', '`, 'm'))
  expect(m).toContain('create or replace function security.layer4_intervention_resolve_v1(p_id bigint, p_action text, p_payload jsonb) returns jsonb')
  expect(m).toContain("if v_rank < v_need then raise exception 'your role cannot take this action")
  expect(m).toContain("execute format('select %s($1, $2, $3)', (h.validate_fn::oid)::regproc) into v_valid using i.id, p_action, p_payload;")
  expect(m).toContain("perform security.har_event_v1(i.id, 'insufficient', p_payload, v_valid, i.status, i.status);")
  expect(m).toContain("'{\"confirm_identity\": 6, \"reject_evidence\": 6, \"return_technical\": 4}'")  // ownership is the Platform Admin's
  expect(m).toContain('security.url_on_provider_sites(v_url, p_provider)')
  expect(m).toContain('security.third_party_host_v1(v_url)')
  // nothing in the contract admits or publishes
  expect(m).not.toMatch(/insert into catalogue\.|update catalogue\.|publication_status\s*=\s*'published'|layer4_review_decide\(/i)
})

test('automatic resumption: a handler per lane; verification closes, or returns the same item with a specific request; issues close or reopen', () => {
  for (const lane of ['aer_source', 'aer_course', 'sch_coverage', 'fee', 'intake', 'aer_item']) expect(m).toMatch(new RegExp(`^ \\('${lane}', '`, 'm'))
  expect(m).toContain("insert into pipeline.entry_matrix_sources as s(provider_id, url, title, rank, found_via, status)")
  expect(m).toContain("'manual', true, 'waiting', now(), auth.uid(), now())")  // a person's listing source
  expect(m).toContain('update pipeline.scholarship_page_candidates set requested_at = now() where id = v_cand;')  // Read again
  expect(m).toContain("perform security.integration_issue_close_v1(r.integration_issue_id, 'layer4-interventions'")
  expect(m).toContain("v_issue := security.har_class_issue_v1(r.lane, r.missing_fact, 'resumed work failed verification")
  expect(m).toContain("required_input = required_input || jsonb_build_object('follow_up', left(v_req, 600)")
})

test('the stronger-model step: interpretative classes only, pinned model, existing lane and guards, ships off, proposals validated', () => {
  expect(m).toMatch(/\('pipeline', 'har\.ai_escalate_on',[\s\S]*?'number', to_jsonb\(0\), 0, 1, 'on \(1\) or off \(0\)'/)
  expect(m).toMatch(/\('pipeline', 'har\.ai_escalation_model',[\s\S]*?'text', to_jsonb\(''::text\)/)
  expect(m).toContain("security.ai_use_refusal_v1('ops_diagnose')")
  expect(m).toContain("security.pipeline_num_v1('ops.ai_diagnosis_on', 0) >= 1")
  expect(m).toContain('insert into pipeline.ops_ai_diagnosis_requests(issue_id, context, model, note)')
  expect(m).toContain('the address is not in any evidence the platform holds (an AI may not invent an address)')
  for (const k of ['har.on', 'har.generate_aer_on', 'har.generate_sch_on', 'har.resume_on'])
    expect(m).toMatch(new RegExp(`\\('pipeline', '${k.replace(/\./g, '\\.')}',[\\s\\S]*?'number', to_jsonb\\(1\\), 0, 1`))
})

test('AER first, then scholarships: bounded, fair, from what is held; the AER Layer 4 limit is not touched; time bounds per class are settings', () => {
  expect(m).toContain("i.outcome in ('blocked_site', 'unverified_link', 'verified_rendered_only')")
  expect(m).toContain("c.eligible and c.disposition in ('source_held', 'reader_failed')")
  expect(m).toContain("from pipeline.aer_schedule_runs a cross join lateral")
  expect(m).toContain("x.state in ('source_not_discovered', 'international_unresolved', 'ownership_conflict')")
  expect(m).toContain('coalesce(security.scholarship_admission_provider_ok_v1(x.provider_id), false)')
  expect(m).toContain("security.pipeline_num_v1('har.generate_per_provider_max', 2)")
  expect(m.split('\n').filter((l) => l.includes('aer.schedule_layer4_max') && !l.startsWith('--'))).toEqual([])  // only named in the header
  for (const k of ['max_attempts', 'escalate_after_hours', 'recheck_hours', 'deadline_hours', 'assigned_to']) expect(m).toContain(`(${['max_attempts', 'escalate_after_hours', 'recheck_hours', 'deadline_hours', 'assigned_to'].indexOf(k) + 1}, '${k}',`)
  expect(m).toContain("perform cron.schedule('layer4-interventions', '14,44 * * * *', $c$select security.layer4_interventions_tick_v1()$c$);")
})

test('the kind for the Inbox: counts, a compact page and lazy detail as this change\'s own functions; §9 metrics in the operations report', () => {
  for (const f of ['layer4_intervention_kind_v1()', 'layer4_intervention_inbox_counts_v1()', 'layer4_intervention_inbox_page_v1(p_args jsonb)',
    'layer4_intervention_inbox_detail_v1(p_ref text)', 'layer4_intervention_inbox_decide_v1(p_ref text, p_choice text, p_value text, p_reason text)'])
    expect(m).toContain(`create or replace function security.${f}`)
  expect(m).toContain("jsonb_build_object('key', 'resolution', 'title', 'Resolution', 'body'")  // paging contract: {sections:[{key, title, body}], actions:[{key, allowed, why}]}
  expect(m).toContain("'before', case when nullif(p_args->>'after_ref', '') is not null then")
  expect(m).toContain("v_out := v_out || jsonb_build_object('human_assisted_recovery', security.layer4_intervention_report_v1());")
  for (const k of ['automatically_resolved', 'human_input_needed', 'human_resolved', 'resumed', 'admitted', 'published', 'still_blocked', 'avg_minutes_to_resume', 'recovery_success_rate'])
    expect(m).toContain(`'${k}'`)
})

test('the fixture proves the six lifecycles of §8 and the rules around them', () => {
  for (const s of ['L1 ok:', 'L2 ok:', 'L3 ok:', 'L4 ok:', 'L5 ok:', 'L6 ok:', 'R1 ok:', 'M ok:', 'G0 ok:']) expect(fixtures).toContain(s)
  for (const s of ['an address is never approval to publish', 'an intervention is not a Layer 4 review item (the AER 600 limit is untouched)', 'unrelated work changed',
    'a changed failure reopens the same item', 'an unchanged failure came back', 'only the evidenced address is suggested', 'ownership decided below Platform Admin'])
    expect(fixtures).toContain(s)
  expect(run).toContain("[ \"$(grep -c ': already applied$' <<<\"$OUT\")\" = 1 ]")
})

test('AER reads held by E13 or D-R3: recovery choices, never approval; recorded once per unchanged problem; the corrected read restarts by itself', () => {
  for (const f of ['layer4_aer_recovery_kind_v1()', 'layer4_aer_recovery_detail_v1(p_ref text)', 'layer4_aer_recovery_decide_v1(p_ref text, p_choice text, p_value text, p_reason text)'])
    expect(m).toContain(`create or replace function security.${f}`)
  for (const k of ['reread_stored', 'request_evidence', 'ai_analyse', 'open_intervention']) expect(m).toContain(`{"key": "${k}"`)
  expect(m).toContain('unique (review_item_id, choice, problem_fingerprint)')
  expect(m).toContain('v_res := security.course_entry_correction_v1(p_ref::uuid, auth.uid(),')
  expect(m).toContain('found among the quotations of the requirements the reader dropped')
  const dec = m.slice(m.indexOf('create or replace function security.layer4_aer_recovery_decide_v1'), m.indexOf('revoke all on function security.layer4_aer_recovery_decide_v1'))
  expect(dec).not.toMatch(/layer4_review_decide|course_entry_review_apply|status = 'active'/)
  expect(fixtures).toContain('E13 ok: UNSW Actuarial pattern')
  for (const s of ['E13: recovery never approves', 'E13: one evidence request for the case', 'E13: dedupe', 'E13: the corrected read restarts by itself']) expect(fixtures).toContain(s)
})
