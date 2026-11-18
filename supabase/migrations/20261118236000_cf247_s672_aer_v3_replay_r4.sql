-- CF-247 S672 AER v2 model qualification replay, round 4: the three pinned models on the frozen 50-case set 5 (session S1-AER, Platform Admin standing mandate of
--   18 Nov 2026 19:28 AEDT, step 3: "Run the offline replay qualification via the on-demand open/close GitHub Actions route using the exact pinned OpenRouter model
--   IDs configured in the repo (Qwen3 30B, Mistral Small 3.2, and the pinned MiMo model ID if present), keeping the strict qualification gate intact (no loosening)").
-- Guards: G1 (no job), G2 (no setting changed here), G3 (no consumer API object; no function or table created), Decision 276 (AER v1 untouched), lesson 8 of
--   docs/platform/layer4-clearance-and-model-benchmark-2026-11-16.md (only catalogue-allowed, individually pinned models, no fallback across models),
--   "a passing qualification never switches anything on by itself" (evidence is written to pipeline.ai_route_qualifications as pending at most).
-- Same as round 3 (migration 20261117020000) for the set, the prompt and the limits: frozen set 5 and its gold rows, prompt aer-v2-course-v3 (system sha-256 unchanged),
--   reading.aer_v2_page_chars 60000, reading.aer_v2_max_tokens 12000, long-page sections on for the run only. Models, as pinned in pipeline.ai_instruction_versions
--   (read live 18 Nov 2026 19:58 AEDT, run 44270160887): qwen/qwen3-30b-a3b-instruct-2507 (siliconflow/fp8, nebius/fp8), mistralai/mistral-small-3.2-24b-instruct
--   (parasail/bf16, deepinfra/fp8), xiaomi/mimo-v2.6-flash (xiaomi/fp8, gmicloud/bf16); allow_fallbacks false on each. Worker coverage-sweep v1.0.18.
-- The gate is the round-3 gate, unchanged: source integrity 100% (ai_eval.min_source_integrity_pct), error rate at most 10 points, no false positives,
--   recall ai_eval.aer_v3_min_recall_pct (100). Nothing here changes a threshold.
-- What this change does: three proposals aer-v2-course-v3-*-r4 and their candidate runs, queued. Nothing answers yet: ai_eval.offline_runs_on and
--   ai_eval.aer_v3_runs_on stay 0. The answers are asked by the GitHub Actions workflow aer-v3-replay.yml (scripts/aer-v3-replay.mjs), which opens the on-demand
--   window, turns the three run switches on for the run only (reason and control event each), asks worker mode aer_v3_eval until the runs are recorded, scores
--   them (security.ai_eval_score_v1) and, whatever happens, turns the switches back to 0 and closes the window.
-- Spend: the cap ai_eval.aer_v3_max_usd (2 US dollars over every AER v3 answer ever; 1.247 used) stops the lease; round 3 cost 0.041 (Mistral) and 0.058 (MiMo);
--   Qwen3 30B 0.021 in round 2.
-- Replaces: nothing. Retires: nothing.

set local lock_timeout = '5s'; -- fixed: lock wait guard for the inserts below

do $g$
begin
  if (select count(*) from pipeline.ai_instruction_versions v join pipeline.aer_prompt_versions a on a.version = v.version
       where v.code = 'aer-v2-course' and v.status = 'candidate' and coalesce((a.routing->>'allow_fallbacks')::boolean, true) = false
         and (v.version, v.model_identifier) in (('aer-v2-course-v3-qwen3-30b', 'qwen/qwen3-30b-a3b-instruct-2507'),
                                                 ('aer-v2-course-v3-mistral-small-3.2', 'mistralai/mistral-small-3.2-24b-instruct'),
                                                 ('aer-v2-course-v3-mimo-v2.6-flash', 'xiaomi/mimo-v2.6-flash'))) <> 3 then
    raise exception 'S672: the three pinned candidate versions (no fallback) are not as read on 18 Nov 2026; nothing done';
  end if;
  if exists (select 1 from pipeline.ai_eval_runs x join pipeline.ai_improvement_proposals p on p.id = x.proposal_id
              where p.code like 'aer-v2-course-v3-%' and x.state in ('queued', 'answering')) then
    raise exception 'S672: another AER v3 run is still open; nothing done';
  end if;
end $g$;

-- 1. three round-4 proposals on the same frozen set, one per pinned model
insert into pipeline.ai_improvement_proposals(code, family, change_class, authority, title, problem_observed, current_method, proposed_change, production_evidence,
       expected_benefit, risks, candidate_version_id, eval_set_id, acceptance_criteria, status, fingerprint, proposed_by)
select v.version || '-r4', 'entry_requirements', 'prompt', 'release', 'AER v2 course page reader, prompt aer-v2-course-v3 on ' || v.model_identifier || ' (round 4, S672 replay)',
       'Round 3 (ai_eval_runs 24 to 26, 17 Nov 2026): no model passed the gate (Mistral Small 3.2: source integrity 85.7%, 22 error points, 1 false positive). About 1,620 held AER course reads need a corrected read from a qualified model.',
       'AER v1 entry reading off (Platform Admin 16 Nov 2026 16:52); AER v2 shadow reader off; no entry reading model qualified.',
       'Prompt aer-v2-course-v3 unchanged; the same frozen 50-case set; one pinned model per proposal; worker coverage-sweep v1.0.18; long-page sections on for the run only.',
       jsonb_build_object('round_3', 'ai_eval_runs 24 (Gemini), 25 (MiMo), 26 (Mistral)', 'round_2', 'ai_eval_runs 17 to 20', 'limits', jsonb_build_object('reading.aer_v2_page_chars', 60000,
                          'reading.aer_v2_max_tokens', 12000, 'reading.aer_v2_long_page_sections_on', 1, 'worker', 'coverage-sweep v1.0.18')),
       'Whether a pinned model now meets the qualification gate (source integrity 100%, error rate at most 10 points, no false positives).',
       'A model that misses rows or reproduces a rejected row; spend beyond the plan (cap ai_eval.aer_v3_max_usd).',
       v.id, 5,
       jsonb_build_object('false_positives', 0, 'person_fp_rate_pts', 0, 'min_source_integrity_pct', 100, 'max_error_rate_pts', 10,
                          'min_recall_pct_setting', 'ai_eval.aer_v3_min_recall_pct', 'max_usd_setting', 'ai_eval.aer_v3_max_usd',
                          'calls', jsonb_build_object('proposed', 50, 'max', 100, 'retry', 'one retry of a call that returned no answer'),
                          'gate', 'Unchanged from round 3 (no loosening, Platform Admin standing mandate 18 Nov 2026 19:28)',
                          'note', 'Passing is evidence only: the Platform Admin qualifies a model; nothing switches on by itself'),
       'proposed', md5('aer-v2-course-v3-r4|' || v.version || '|' || coalesce(v.spec->>'system_sha256', '')), 'migration 20261118236000'
  from pipeline.ai_instruction_versions v
 where v.code = 'aer-v2-course' and v.status = 'candidate'
   and v.version in ('aer-v2-course-v3-qwen3-30b', 'aer-v2-course-v3-mistral-small-3.2', 'aer-v2-course-v3-mimo-v2.6-flash')
on conflict (code) do nothing;

-- 2. their candidate runs, queued (answered only while both run switches are 1, which only the workflow does, for the run)
do $r$
declare p record;
begin
  for p in select id from pipeline.ai_improvement_proposals where code like 'aer-v2-course-v3-%-r4' and eval_set_id = 5 order by id loop
    if not exists (select 1 from pipeline.ai_eval_runs where proposal_id = p.id and arm = 'candidate') then
      perform security.ai_eval_run_open_v1(p.id, 'candidate');
    end if;
  end loop;
end $r$;

-- 3. post-checks
do $k$
declare n int;
begin
  select count(*) into n from pipeline.ai_eval_runs x join pipeline.ai_improvement_proposals p on p.id = x.proposal_id
   where p.code like 'aer-v2-course-v3-%-r4' and x.set_id = 5 and x.arm = 'candidate' and x.state = 'queued';
  if n <> 3 then raise exception 'post-check: % queued round-4 runs (expected 3)', n; end if;
  select count(*) into n from pipeline.ai_improvement_proposals p join pipeline.ai_instruction_versions v on v.id = p.candidate_version_id
   join pipeline.aer_prompt_versions a on a.version = v.version
   where p.code like 'aer-v2-course-v3-%-r4' and a.system_sha256 = (select system_sha256 from pipeline.aer_prompt_versions where version = 'aer-v2-course-v3-qwen3-30b')
     and coalesce((a.routing->>'allow_fallbacks')::boolean, true) = false;
  if n <> 3 then raise exception 'post-check: % round-4 proposals on the round-3 prompt text, pinned without fallback (expected 3)', n; end if;
  if security.pipeline_num_v1('ai_eval.offline_runs_on', 1) <> 0 or security.pipeline_num_v1('ai_eval.aer_v3_runs_on', 1) <> 0 then
    raise exception 'post-check: the run switches stay 0 here (the workflow turns them on for the run only)';
  end if;
  if security.pipeline_num_v1('ai_eval.min_source_integrity_pct', 0) <> 100 or security.pipeline_num_v1('ai_eval.aer_v3_min_recall_pct', 0) <> 100 then
    raise exception 'post-check: the qualification gate is unchanged';
  end if;
  if security.pipeline_num_v1('aer.v2_shadow_on', 0) <> 0 then raise exception 'post-check: the AER v2 shadow reader stays off'; end if;
  if exists (select 1 from pipeline.ai_route_qualifications where service_code in ('entry_requirements_v2_shadow', 'course_entry_requirements', 'entry_matrices') and status = 'qualified') then
    raise exception 'post-check: no entry reading model is qualified';
  end if;
  if (select count(*) from security.consumer_api_functions_v1()) <> 75 or (select count(*) from security.consumer_api_relations_v1()) <> 48 then
    raise exception 'post-check: G3 must stay 75 functions and 48 relations';
  end if;
end $k$;
