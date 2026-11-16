-- CF-247 AER v3 benchmark, round 2: four pinned models on the frozen 50-case set (Platform Admin 16 Nov 2026 14:06, step 2 of the Layer 4 clearance
-- and model benchmark; route approved 16 Nov 2026: "run it via the AER eval", models Qwen3 30B, Mistral Small 3.2, MiMo v2.6 Flash, Gemini 2.5 Flash).
-- Replaces: nothing
-- Retires: nothing
--
-- Why a second round: the 14 Nov 2026 runs (6, 7, 8) of proposals aer-v2-course-v3-* answered on worker v0.94.0 to v0.96.0; the Qwen3 30B run lost 29 of
-- 50 answers to the platform wall-clock limit (fixed in v0.96.0), so the primary model was never measured. A run is opened once per proposal, arm and set
-- (security.ai_eval_run_open_v1), so the same versions are measured again under four new proposals on the same frozen set (ai_eval_sets 5, gold in
-- pipeline.aer_v3_eval_gold): one per model, Gemini 2.5 Flash added as a fourth candidate. Gemini 3 Flash is not in pipeline.ai_model_catalogue and is not
-- used (only allowed catalogue models).
--
-- What this adds: one prompt row (pipeline.aer_prompt_versions aer-v2-course-v3-gemini-2.5-flash, status evaluation: the same system text and sha-256 as
-- the three existing rows, pinned to google/gemini-2.5-flash with its own provider pins and reasoning off), its instruction version (candidate), four
-- proposals aer-v2-course-v3-*-r2 (eval set 5, status evaluating) and their four queued candidate runs. Nothing answers until the Platform Admin's
-- switches ai_eval.offline_runs_on and ai_eval.aer_v3_runs_on are 1; spend stays under ai_eval.aer_v3_max_usd (a cap on every AER v3 answer ever).
-- Unchanged: every route, cascade, qualification and production reader. A scored run is evidence only (security.aer_v3_qualification_evidence_v1 writes
-- status pending at most); nothing is qualified or switched on by a result. AER v1 stays frozen (Decision 276). G1: no job. G2: no new value (the cap is
-- the existing setting). G3: no consumer API object is read or changed.

set local lock_timeout = '5s'; -- fixed: lock wait guard for the inserts below

-- 1. the Gemini 2.5 Flash prompt row: the same prompt text as the three evaluation rows, its own pinned model and providers
insert into pipeline.aer_prompt_versions(version, purpose, system_text, system_sha256, model, quote_max_chars, status, reason, created_by, answer_contract, input_format, routing, params)
select 'aer-v2-course-v3-gemini-2.5-flash', p.purpose, p.system_text, p.system_sha256, 'google/gemini-2.5-flash', p.quote_max_chars, 'evaluation',
       'Platform Admin 16 Nov 2026 14:06: AER v3 benchmark round 2 (four pinned models on the frozen 50-case set)', 'migration 20261116100000',
       p.answer_contract, p.input_format, '{"order": ["google-vertex", "google-ai-studio"], "allow_fallbacks": false}'::jsonb, '{"reasoning": {"enabled": false}}'::jsonb
  from pipeline.aer_prompt_versions p
 where p.version = 'aer-v2-course-v3-qwen3-30b'
on conflict (version) do nothing;

-- 2. its instruction version (as migration 20261114081500 made the other three)
insert into pipeline.ai_instruction_versions(family, code, kind, version, home, body, spec, model_identifier, status, note)
select 'entry_requirements', 'aer-v2-course', 'prompt', p.version, 'pipeline.aer_prompt_versions ' || p.version, p.system_text,
       jsonb_build_object('prompt_version', 'aer-v2-course-v3', 'answer_contract', p.answer_contract, 'input_format', p.input_format, 'routing', p.routing, 'params', p.params,
                          'quote_max_chars', p.quote_max_chars, 'system_sha256', p.system_sha256),
       p.model, 'candidate', 'AER v2 prompt v3 benchmark candidate, round 2 (Platform Admin 16 Nov 2026); provider pins and require_parameters set by the worker'
  from pipeline.aer_prompt_versions p
 where p.version = 'aer-v2-course-v3-gemini-2.5-flash'
on conflict (code, version) do nothing;

-- 3. four round-2 proposals on the same frozen set, one per model
insert into pipeline.ai_improvement_proposals(code, family, change_class, authority, title, problem_observed, current_method, proposed_change, production_evidence,
       expected_benefit, risks, candidate_version_id, eval_set_id, acceptance_criteria, status, fingerprint, proposed_by)
select v.version || '-r2', 'entry_requirements', 'prompt', 'release', 'AER v2 course page reader, prompt aer-v2-course-v3 on ' || v.model_identifier || ' (round 2)',
       'Layer 4 holds 1,604 course_entry_first_read reads whose reader dropped printed requirements (quote_not_on_page, gate_incomplete); the 14 Nov 2026 benchmark never measured the primary model (29 of 50 Qwen3 30B answers lost to the wall-clock limit).',
       'AER v1 readers (frozen, Decision 276); AER v2 shadow reader paused.',
       'Prompt aer-v2-course-v3 unchanged; the same frozen 50-case set measured again on the current worker, one pinned model per proposal.',
       jsonb_build_object('round_1', 'ai_eval_runs 6, 7, 8 (14 Nov 2026)', 'waiting', 'Layer 4 course_entry_first_read gate_incomplete 1,883 (16 Nov 2026 14:20 AEDT)'),
       'Which pinned model gives the most source-backed rows that match people''s decisions per US dollar, before any qualification.',
       'A model that misses rows or reproduces a rejected row; spend beyond the plan (cap ai_eval.aer_v3_max_usd).',
       v.id, 5,
       jsonb_build_object('false_positives', 0, 'person_fp_rate_pts', 0, 'min_source_integrity_pct', 100, 'max_error_rate_pts', 10,
                          'min_recall_pct_setting', 'ai_eval.aer_v3_min_recall_pct', 'max_usd_setting', 'ai_eval.aer_v3_max_usd',
                          'calls', jsonb_build_object('proposed', 50, 'max', 100, 'retry', 'one retry of a call that returned no answer'),
                          'note', 'Passing is evidence only: the Platform Admin qualifies a model; nothing switches on by itself'),
       'proposed', md5('aer-v2-course-v3-r2|' || v.version || '|' || coalesce(v.spec->>'system_sha256', '')), 'migration 20261116100000'
  from pipeline.ai_instruction_versions v
 where v.code = 'aer-v2-course' and v.status = 'candidate'
   and v.version in ('aer-v2-course-v3-qwen3-30b', 'aer-v2-course-v3-mistral-small-3.2', 'aer-v2-course-v3-mimo-v2.6-flash', 'aer-v2-course-v3-gemini-2.5-flash')
on conflict (code) do nothing;

-- 4. their candidate runs, queued (answered only while both switches are 1)
do $r$
declare p record;
begin
  for p in select id from pipeline.ai_improvement_proposals where code like 'aer-v2-course-v3-%-r2' and eval_set_id = 5 order by id loop
    perform security.ai_eval_run_open_v1(p.id, 'candidate');
  end loop;
end $r$;

-- 5. post-checks
do $k$
declare n int;
begin
  if not exists (select 1 from pipeline.ai_model_catalogue where model_identifier = 'google/gemini-2.5-flash' and status = 'allowed') then
    raise exception 'post-check: google/gemini-2.5-flash is an allowed catalogue model';
  end if;
  select count(*) into n from pipeline.ai_instruction_versions v join pipeline.aer_prompt_versions p on p.version = v.version
   where v.code = 'aer-v2-course' and v.status = 'candidate' and v.body_md5 = md5(p.system_text) and v.model_identifier = p.model and security.aer_v3_eval_version_v1(v.id)
     and p.system_sha256 = (select system_sha256 from pipeline.aer_prompt_versions where version = 'aer-v2-course-v3-qwen3-30b');
  if n <> 4 then raise exception 'post-check: % AER v3 instruction versions share the prompt text (expected 4)', n; end if;
  select count(*) into n from pipeline.ai_eval_runs x join pipeline.ai_improvement_proposals p on p.id = x.proposal_id
   where p.code like 'aer-v2-course-v3-%-r2' and x.set_id = 5 and x.arm = 'candidate' and x.state = 'queued';
  if n <> 4 then raise exception 'post-check: % queued round-2 runs (expected 4)', n; end if;
  if security.pipeline_num_v1('ai_eval.offline_runs_on', 0) <> 0 or security.pipeline_num_v1('ai_eval.aer_v3_runs_on', 0) <> 0 or security.pipeline_num_v1('aer.v2_shadow_on', 0) <> 0 then
    raise exception 'post-check: offline runs, AER v3 runs and the shadow reader stay off';
  end if;
  if exists (select 1 from pipeline.ai_route_qualifications where service_code = 'entry_requirements_v2_shadow' and status = 'qualified') then raise exception 'post-check: no model qualified'; end if;
end $k$;
