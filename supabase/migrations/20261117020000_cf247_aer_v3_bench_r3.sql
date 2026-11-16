-- CF-247 AER v3 benchmark, round 3: three pinned models on the frozen 50-case set with the long-page entry sections on (Platform Admin 16 Nov 2026
-- 16:52 "Stop Qwen, shadow Mistral", step 3; the A/B gate pre-authorised 16 Nov 2026 20:14; scheduled Tue 17 Nov 07:30 AEDT).
-- Replaces: nothing
-- Retires: nothing
--
-- Same as round 2 (migration 20261116100000) except the long-page switch: the frozen set 5 and gold, prompt aer-v2-course-v3 (same text and sha-256),
-- reading.aer_v2_page_chars 60000 and reading.aer_v2_max_tokens 12000 unchanged, each model pinned individually with its own provider pins and no
-- fallback across models. Models: Mistral Small 3.2, MiMo v2.6 Flash, Gemini 2.5 Flash (Qwen3 30B is retired from the AER path, 16 Nov 16:52).
-- New in round 3: worker coverage-sweep v1.0.6 (Pilot #1179) sends a page over reading.aer_v2_page_chars as its entry requirement sections only
-- (lean-sections-v3, the page's own block numbers) when reading.aer_v2_long_page_sections_on = 1; the answer is still verified against the whole page.
--
-- What this does: three proposals aer-v2-course-v3-*-r3 on set 5 with their candidate runs queued; reading.aer_v2_long_page_sections_on,
-- ai_eval.offline_runs_on and ai_eval.aer_v3_runs_on set to 1 for this run, each with its reason and a control event; an on-demand window for the
-- OpenRouter answers (estimate below; no Firecrawl). Spend stays under ai_eval.aer_v3_max_usd (2 US dollars over every AER v3 answer ever; 0.634 used).
-- The runs are scored by the ai-eval job (security.ai_eval_score_v1) and their evidence is written to pipeline.ai_route_qualifications as pending at
-- most: nothing is qualified or switched on by a result. A following change restores the three switches to 0 when the runs are recorded.
-- Unchanged: every route, cascade, qualification and production reader; aer.v2_shadow_on stays 0; AER v1 stays off and frozen (Decision 276).
-- G1: no job. G2: no new setting (existing settings changed with a reason). G3: no consumer API object is read or changed.

set local lock_timeout = '5s'; -- fixed: lock wait guard for the inserts and updates below

-- 1. three round-3 proposals on the same frozen set, one per model
insert into pipeline.ai_improvement_proposals(code, family, change_class, authority, title, problem_observed, current_method, proposed_change, production_evidence,
       expected_benefit, risks, candidate_version_id, eval_set_id, acceptance_criteria, status, fingerprint, proposed_by)
select v.version || '-r3', 'entry_requirements', 'prompt', 'release', 'AER v2 course page reader, prompt aer-v2-course-v3 on ' || v.model_identifier || ' (round 3, long-page sections on)',
       'Round 2 (ai_eval_runs 17 to 20, 16 Nov 2026) lost the same 10 long-page cases on every model at reading.aer_v2_page_chars 60000; no model passed the gate.',
       'AER v1 readers switched off (Platform Admin 16 Nov 2026 16:52); AER v2 shadow reader off.',
       'Prompt aer-v2-course-v3 unchanged; worker v1.0.6 sends the entry requirement sections of a page over the limit (reading.aer_v2_long_page_sections_on = 1); the same frozen 50-case set, one pinned model per proposal.',
       jsonb_build_object('round_2', 'ai_eval_runs 17 (Gemini), 18 (MiMo), 19 (Mistral), 20 (Qwen)', 'limits', jsonb_build_object('reading.aer_v2_page_chars', 60000,
                          'reading.aer_v2_max_tokens', 12000, 'reading.aer_v2_long_page_sections_on', 1, 'worker', 'coverage-sweep v1.0.6')),
       'Whether reading the entry sections of long pages lifts a pinned model to the qualification gate (source integrity 100%, error rate at most 10 points, no false positives).',
       'A model that misses rows or reproduces a rejected row; spend beyond the plan (cap ai_eval.aer_v3_max_usd).',
       v.id, 5,
       jsonb_build_object('false_positives', 0, 'person_fp_rate_pts', 0, 'min_source_integrity_pct', 100, 'max_error_rate_pts', 10,
                          'min_recall_pct_setting', 'ai_eval.aer_v3_min_recall_pct', 'max_usd_setting', 'ai_eval.aer_v3_max_usd',
                          'calls', jsonb_build_object('proposed', 50, 'max', 100, 'retry', 'one retry of a call that returned no answer'),
                          'gate', 'Platform Admin 16 Nov 2026 20:14: Path A if Mistral Small 3.2 passes (qualify, shadow on, re-read the held items); Path B otherwise (stay off, log the failure buckets)',
                          'note', 'Passing is evidence only: the Platform Admin qualifies a model; nothing switches on by itself'),
       'proposed', md5('aer-v2-course-v3-r3|' || v.version || '|' || coalesce(v.spec->>'system_sha256', '')), 'migration 20261117020000'
  from pipeline.ai_instruction_versions v
 where v.code = 'aer-v2-course' and v.status = 'candidate'
   and v.version in ('aer-v2-course-v3-mistral-small-3.2', 'aer-v2-course-v3-mimo-v2.6-flash', 'aer-v2-course-v3-gemini-2.5-flash')
on conflict (code) do nothing;

-- 2. their candidate runs, queued (answered only while both switches are 1)
do $r$
declare p record;
begin
  for p in select id from pipeline.ai_improvement_proposals where code like 'aer-v2-course-v3-%-r3' and eval_set_id = 5 order by id loop
    if not exists (select 1 from pipeline.ai_eval_runs where proposal_id = p.id and arm = 'candidate') then
      perform security.ai_eval_run_open_v1(p.id, 'candidate');
    end if;
  end loop;
end $r$;

-- 3. the three switches for this run, each with its reason and a control event
with u as (
  update pipeline.platform_toolset_settings
     set value = '1'::jsonb, updated_at = now(),
         reason = 'Migration 20261117020000: AER v3 benchmark round 3 (Platform Admin 16 Nov 2026 16:52 step 3, gate pre-authorised 20:14); restored to 0 by the following change once the three runs are recorded'
   where toolset_key = 'pipeline' and key in ('reading.aer_v2_long_page_sections_on', 'ai_eval.offline_runs_on', 'ai_eval.aer_v3_runs_on')
  returning key)
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'settings', 'migration', u.key, jsonb_build_object('migration', '20261117020000', 'after', 1, 'why', 'AER v3 benchmark round 3, for the run only'), null from u;

-- 4. the on-demand window for the answers (OpenRouter only; no Firecrawl; the providers of the frozen set's courses, as round 2's window ca8dee01): estimate from round 2 (Gemini 0.35, MiMo 0.06, Mistral 0.03) plus room for
--    the longer section prompts
select security.on_demand_open_v1('claude_session',
  'AER v3 benchmark round 3 (Platform Admin 16 Nov 2026 16:52 step 3; migration 20261117020000): 3 pinned models x 50 frozen cases, long-page sections on',
  (select provider_ids from pipeline.on_demand_requests where id = 'ca8dee01-5203-4152-a04c-f39b11091421'),  -- the frozen set's 31 providers, as round 2
  jsonb_build_object('calls', 150, 'openrouter_usd', 0.60, 'firecrawl_credits', 0,
                           'detail', 'Gemini 2.5 Flash ~0.40, MiMo v2.6 Flash ~0.10, Mistral Small 3.2 ~0.06; cap ai_eval.aer_v3_max_usd 2 (0.634 used)'),
  null, array['openrouter']);

-- 5. post-checks
do $k$
declare n int;
begin
  select count(*) into n from pipeline.ai_eval_runs x join pipeline.ai_improvement_proposals p on p.id = x.proposal_id
   where p.code like 'aer-v2-course-v3-%-r3' and x.set_id = 5 and x.arm = 'candidate' and x.state = 'queued';
  if n <> 3 then raise exception 'post-check: % queued round-3 runs (expected 3)', n; end if;
  select count(*) into n from pipeline.ai_improvement_proposals p join pipeline.ai_instruction_versions v on v.id = p.candidate_version_id
   join pipeline.aer_prompt_versions a on a.version = v.version
   where p.code like 'aer-v2-course-v3-%-r3' and a.system_sha256 = (select system_sha256 from pipeline.aer_prompt_versions where version = 'aer-v2-course-v3-qwen3-30b')
     and coalesce((a.routing->>'allow_fallbacks')::boolean, false) = false;
  if n <> 3 then raise exception 'post-check: % round-3 proposals on the round-2 prompt text, pinned without fallback (expected 3)', n; end if;
  if security.pipeline_num_v1('reading.aer_v2_page_chars', 0) <> 60000 or security.pipeline_num_v1('reading.aer_v2_max_tokens', 0) <> 12000 then
    raise exception 'post-check: the round-2 page limit and answer limit are unchanged';
  end if;
  if security.pipeline_num_v1('reading.aer_v2_long_page_sections_on', 0) <> 1 or security.pipeline_num_v1('ai_eval.offline_runs_on', 0) <> 1
     or security.pipeline_num_v1('ai_eval.aer_v3_runs_on', 0) <> 1 then
    raise exception 'post-check: the three run switches are on';
  end if;
  if security.pipeline_num_v1('aer.v2_shadow_on', 0) <> 0 then raise exception 'post-check: the AER v2 shadow reader stays off'; end if;
  if exists (select 1 from pipeline.ai_route_qualifications where service_code in ('entry_requirements_v2_shadow', 'course_entry_requirements', 'entry_matrices') and status = 'qualified') then
    raise exception 'post-check: no entry reading model is qualified';
  end if;
  if exists (select 1 from pipeline.ai_service_routes where service_code in ('entry_requirements_v2_shadow', 'course_entry_requirements', 'entry_matrices') and enabled) then
    raise exception 'post-check: the entry reading routes stay off';
  end if;
end $k$;
