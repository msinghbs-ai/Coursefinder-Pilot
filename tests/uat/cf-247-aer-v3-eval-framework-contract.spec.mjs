// Guards: Platform Admin 14 Nov 2026 option 1 (twice) "build the AER v2 evaluation runner on the #1128 platform framework (ai_eval_sets, ai_eval_runs, ai_eval_answers, security.ai_eval_score_v1, and ai_route_qualifications)" and "re-draw the 50-case ai_eval_sets benchmark strictly from trusted labels ... Keep the ground-truth-only database trigger intact. Measure the gate_incomplete and unlabelled negative probe pages separately via the existing paused shadow reader ... Hold all paid AI calls": one evaluation path, trusted labels only, frozen gold rows, multi-record scoring, qualification evidence at most pending, the #1137 tables retiring, probes on the paused shadow reader, and nothing that runs or spends
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261114081500_cf247_aer_v3_eval_framework.sql', 'utf8')
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const AER = fs.readFileSync('supabase/functions/coverage-sweep/aer-v2.ts', 'utf8')
const mode = IX.slice(IX.indexOf('    if (mode === AER_V3_EVAL_MODE) {'), IX.indexOf('    if (mode === AER_V2_MODE) {'))
const fn = (name) => { const i = M.indexOf(`create or replace function ${name}`); return M.slice(i, M.indexOf('$f$;', M.indexOf('$f$', i) + 3) + 4) }

test('the set is 50 trusted examples, stratified by page shape and size; the ground-truth trigger is untouched', () => {
  expect(M).toContain("where x.family = 'entry_requirements' and x.active and x.tier = 'person'")
  expect(M).toContain("strata(stratum, want, per_provider) as (values ('T1', 8, 2), ('T2', 6, 2), ('T3', 10, 2), ('T4', 12, 2), ('T5', 8, 4), ('T6', 6, 2))")
  expect(M).toContain("when p.label = 'reject' and p.scope = 'row' then 'T5'")
  expect(M).toContain("when p.scope = 'matrix' and p.label in ('accept', 'correct') and g.acc between 1 and 40 then 'T1'")
  expect(M).toContain("if s <> '{\"T1\": 8, \"T2\": 6, \"T3\": 10, \"T4\": 12, \"T5\": 8, \"T6\": 6}'::jsonb then raise exception")
  expect(M).toContain("(x.tier <> 'person' or not x.active)) then")
  // only existing examples become members: no example is written, and the trigger is never replaced or disabled
  expect(M).not.toMatch(/insert into pipeline\.ai_eval_examples|update pipeline\.ai_eval_examples|function security\.ai_eval_example_trusted_trg|disable trigger|drop trigger/i)
})

test('gold rows are frozen with the set and scoring reads only them', () => {
  expect(M).toMatch(/create table if not exists pipeline\.aer_v3_eval_gold \(/)
  expect(M).toMatch(/comment on table pipeline\.aer_v3_eval_gold is '/)
  expect(M).toContain('insert into pipeline.aer_v3_eval_gold(set_id, example_id, label, source_kind, row_id, min_grade, quote, country)')
  expect(fn('security.aer_v3_eval_gold_v1')).toContain('from pipeline.aer_v3_eval_gold g where g.set_id = p_set and g.example_id = p_example')
  expect(fn('security.aer_v3_eval_gold_v1')).not.toContain('aer_labelled_rows_v1')
})

test('multi-record scoring in the framework: found rows, no reproduced rejected row, source integrity from the v3 verifier', () => {
  const pair = fn('security.aer_v3_eval_pair_v1')
  expect(pair).toContain("security.pipeline_num_v1('ai_eval.aer_v3_min_recall_pct', 100)")
  expect(pair).toContain("where coalesce((p_value->'checks'->(e.i::int - 1)->>'pass')::boolean, false)) r;")
  expect(pair).toContain("when v_repro > 0 then case when p_base->>'label' = 'reject' then p_base->'rejected' else jsonb_build_object('aer', 'reproduced a rejected row') end")
  expect(pair).toContain("'quote_on_page', v_ok and v_failed = 0 and jsonb_array_length(v_passed) > 0")
  expect(fn('security.aer_v3_flat_v1')).toContain("regexp_replace(normalize(lower(coalesce(p, '')), NFKD), '[^a-z0-9]+', '', 'g')")
  expect(AER).toContain('export const aerFlat = (s: unknown) => String(s ?? "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "");')
  // the framework's own scorer is edited (md5-guarded), its metrics function is not
  expect(M).toContain("select pg_temp.edit_n('security.ai_eval_score_v1(bigint)', 'bfdc98c50f115949498e6d95c5e43e2b'")
  expect(M).toContain("(case when v_aer then security.aer_v3_eval_pair_v1(jsonb_build_object(")
  expect(M).not.toMatch(/create or replace function security\.ai_eval_metrics_v1/)
})

test('qualification evidence is written as pending at most; a model is never qualified by the benchmark', () => {
  const ev = fn('security.aer_v3_qualification_evidence_v1')
  expect(ev).toContain("values ('entry_requirements_v2_shadow', v_model, 'aer-v2-course-v3', 'pending', false,")
  expect(ev).toContain("status = case when q.status = 'qualified' then q.status else 'pending' end")
  expect(ev).not.toMatch(/'qualified'\s*,|qualified_at\s*=|qualified_by\s*=/)
  expect(M).toContain("raise exception 'post-check: no model qualified'")
})

test('one lease per answer contract: AER v3 runs only through svc_aer_v3_eval_next_v1, behind both switches and the spend cap; no run is opened', () => {
  const lease = fn('public.svc_aer_v3_eval_next_v1')
  expect(lease).toContain("security.pipeline_num_v1('ai_eval.offline_runs_on', 0) <> 1")
  expect(lease).toContain("security.pipeline_num_v1('ai_eval.aer_v3_runs_on', 0) <> 1")
  expect(lease).toContain("if v_spent >= v_cap then return")
  expect(M).toContain("select pg_temp.edit_n('public.svc_ai_eval_run_next_v1()', 'd4537de869c5c12752e6d1aeec7265a8'")
  expect(M).toContain('and not security.aer_v3_eval_version_v1(version_id)')
  expect(M).toContain("'number', to_jsonb(0), 0, 1, 'switch', 1418, 'AI evaluation'")
  expect(M).toContain("'number', to_jsonb(2), 0, 20, 'US$', 1419, 'AI evaluation'")
  expect(M).not.toMatch(/ai_eval_run_open_v1\(/)
  expect(M).not.toMatch(/cron\.schedule|svc_pilot_submit_nonce|net\.http_post|on_demand_open_v1/)
  expect(M).toContain("raise exception 'post-check: no AER v3 run is opened'")
})

test('three candidates of prompt aer-v2-course-v3, one pinned model each, no GPT-4.1 mini; proposals stay proposed', () => {
  expect(M).toContain("and p.version in ('aer-v2-course-v3-qwen3-30b', 'aer-v2-course-v3-mistral-small-3.2', 'aer-v2-course-v3-mimo-v2.6-flash')")
  expect(M).toContain("'entry_requirements', 'prompt', 'release', 'AER v2 course page reader, prompt aer-v2-course-v3 on '")
  expect(M).toContain("if exists (select 1 from pipeline.ai_instruction_versions v where v.code = 'aer-v2-course' and v.model_identifier ilike '%gpt-4.1-mini%') then raise exception")
  expect(M).toContain("v.body_md5 = md5(p.system_text) and v.model_identifier = p.model")
})

test('the worker answers through the framework with the unchanged [B#] blocks, pinned providers, require_parameters and one retry', () => {
  expect(AER).toContain('export const AER_V3_EVAL_MODE = "aer_v3_eval";')
  expect(mode).toContain('const w: any = await rpc("svc_aer_v3_eval_next_v1", {});')
  expect(mode).toContain('blocks = aerV3Blocks(leanText(raw), pageDataItems(raw))')
  expect(mode).toContain('aerV3Request(model, system, user, maxTokens, routing, params)')
  expect(mode).toContain('const v = aerV3Verify(a.a, blocks, refs, quoteMax, gapMax);')
  expect(mode).toContain('for (let attempt = 1; attempt <= 2; attempt++) {  // fixed: the plan\'s one retry of a call that returned no answer')
  expect(mode).toContain('if (spent >= cap) {')
  expect(mode).toContain('await rpc("svc_ai_eval_answer_record_v1", { p_run: w.run, p_answers: { answers, worker: WORKER } })')
  expect(mode).toContain('a cut page is never read')
  expect(mode).not.toMatch(/svc_aer_v2_shadow_record|course_entry_review_apply|svc_pilot_submit_nonce/)
  // the [B#] contract Lean AI consumes is unchanged (Platform Admin 14 Nov 2026 14:34)
  expect(AER).toContain('const show = (b: AerBlock) => `[B${b.n} @${b.source_at === null ? "data" : b.source_at}] ${b.kind === "heading" ? "## " : b.kind === "item" ? "- " : ""}${b.text}`;')
  expect(IX).toMatch(/const WORKER = "coverage-sweep-worker-v0\.94\.0";/)
})

test('one evaluation path: the #1137 tables retire, the probes move to the paused shadow reader; nothing is dropped and the queue is untouched', () => {
  expect(M).toContain("update pipeline.component_register set status = 'retiring'")
  expect(M).toContain("where name in ('pipeline.aer_v2_eval_cases', 'pipeline.aer_v2_eval_plans') and status = 'active';")
  expect(M).toContain("update pipeline.aer_v2_eval_plans set status = 'closed'")
  expect(M).toContain("c.stratum in ('S1', 'S3', 'S6')")
  expect(M).toContain("select pg_temp.edit_n('security.aer_v2_sample_refresh_v1()', '4c1ea14da4064c05f2dcd4b49387dd86'")
  expect(M).toContain("or s.course_id::text in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'aer.v2_shadow_probe_courses'), '[]'::jsonb)))")
  expect(M).not.toMatch(/select security\.aer_v2_sample_refresh_v1\(\)/)
  expect(M).not.toMatch(/^\s*(delete|drop table|drop function|truncate)\b/im)
  expect(M).not.toMatch(/key\s*=\s*'aer\.v2_shadow_on'|aer_v2_shadow_results\s+(set|where)|insert into catalogue\.|course_entry_review_apply_v1/i)
  expect(M).toContain("if security.pipeline_num_v1('aer.v2_shadow_on', 0) <> 0 or security.pipeline_num_v1('ai_eval.offline_runs_on', 0) <> 0 or security.pipeline_num_v1('ai_eval.aer_v3_runs_on', 0) <> 0 then")
  expect(M).toMatch(/^-- Replaces: .+\. Retires: pipeline\.aer_v2_eval_cases, pipeline\.aer_v2_eval_plans\.$/m)
})
