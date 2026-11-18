-- CF-247 S674 AER v2 reader prompt aer-v2-course-v3.1 (every row of a requirement table or list) on the three pinned models, round-5 runs, and the
--   validation renewal setting (session S1-AER, Platform Admin 18 Nov 2026 20:53 AEDT: "Combine (a) Prompt v3 + (b) 180s Per-Call Eval Timeout ... Dispatch Round 5
--   via aer-v3-replay.yml ... keeping the strict qualification gate unchanged" and "a standing operational rule ... authorising automatic 7-day validation renewal on
--   unchanged thresholds").
-- Guards: G1 (no job), G2 (the renewal age is a setting), G3 (no consumer API object; no function or table created: 75 functions and 48 relations stay),
--   Decision 276 (AER v1 untouched), lesson 8 of the 16 Nov benchmark report (only individually pinned models, no fallback across models),
--   "a passing qualification never switches anything on by itself" (round-5 evidence is pending at most; no route, shadow or qualification changes).
-- Why: round 4 (runs 36 to 38, 18 Nov 2026 20:13 to 20:37) failed the gate on time-outs at the 90 s per-call limit (Qwen3 30B 27, Mistral 11, MiMo 11) and on missed
--   rows (false negatives 20 to 26). Worker v1.0.19 (same PR) answers the evaluation in a background task with a 180 s per-call limit; this change adds the prompt.
-- What:
--   1. Prompt aer-v2-course-v3.1: the text of aer-v2-course-v3 with its first line renamed and one section added, "Tables and lists (read every row)", asking for one
--      record per printed requirement row or item, in page order, first to last, never sampled or merged, completion-only rows kept with min_grade null, and a final
--      check that every row is a record or in seen_not_mapped. Everything else (answer contract aer-v2-answer-v3, input lean-blocks-v1, quote rules, quote limit 300)
--      is unchanged. Held as three evaluation versions, the exact pins of v3: qwen/qwen3-30b-a3b-instruct-2507, mistralai/mistral-small-3.2-24b-instruct,
--      xiaomi/mimo-v2.6-flash (routing and params copied from the v3 rows, allow_fallbacks false).
--   2. Their instruction versions (candidate) and round-5 proposals aer-v2-course-v3.1-*-r5 on the frozen set 5 with queued candidate runs. The run switches stay 0:
--      workflow aer-v3-replay.yml (round r5) opens the on-demand window, turns them on for the run only and back to 0.
--   3. Setting aer.validation_renew_after_days (5): the age of the last passing validation at which workflow aer-validation-renew.yml renews it under the Platform
--      Admin's standing rule of 18 Nov 2026 20:53 (thresholds unchanged, 0 regressions); a validation still lapses after 7 days.
-- Spend: cap ai_eval.aer_v3_max_usd (2 US dollars over every AER v3 answer; 1.372 used). Round 4 cost 0.125; longer answers may cost more.
-- Replaces: nothing. Retires: nothing.

set local lock_timeout = '5s'; -- fixed: lock wait guard for the inserts below

do $g$
begin
  if (select count(*) from pipeline.aer_prompt_versions where version in ('aer-v2-course-v3-qwen3-30b', 'aer-v2-course-v3-mistral-small-3.2', 'aer-v2-course-v3-mimo-v2.6-flash')
        and answer_contract = 'aer-v2-answer-v3' and coalesce((routing->>'allow_fallbacks')::boolean, true) = false) <> 3 then
    raise exception 'S674: the three v3 evaluation rows are not as read on 18 Nov 2026; nothing done';
  end if;
  if exists (select 1 from pipeline.ai_eval_runs x join pipeline.ai_improvement_proposals p on p.id = x.proposal_id
              where p.code like 'aer-v2-course-v3%' and x.state in ('queued', 'answering')) then
    raise exception 'S674: another AER v3 run is still open; nothing done';
  end if;
end $g$;

-- 1. prompt v3.1, one row per pinned model (text from v3, renamed first line, one section added before the Rules)
insert into pipeline.aer_prompt_versions(version, purpose, system_text, system_sha256, model, quote_max_chars, status, reason, created_by, answer_contract, input_format, routing, params)
select replace(p.version, 'aer-v2-course-v3-', 'aer-v2-course-v3.1-'), p.purpose, t.t, encode(sha256(convert_to(t.t, 'UTF8')), 'hex'), p.model, p.quote_max_chars, 'evaluation',
       'Platform Admin 18 Nov 2026 20:53 (S1-AER s674): prompt v3 with exhaustive row-by-row extraction of requirement tables and lists; round-5 benchmark',
       'migration 20261118243000', p.answer_contract, p.input_format, p.routing, p.params
  from pipeline.aer_prompt_versions p
  cross join lateral (select replace(replace(p.system_text, 'AER course page reader, prompt aer-v2-course-v3.', 'AER course page reader, prompt aer-v2-course-v3.1.'),
    E'\nRules:\n', $s$
Tables and lists (read every row):
- When the page prints requirements as a table or a list (one row or item for each country, qualification, level, course or route), give one record for EVERY row or item that prints an academic entry requirement, in page order, from the first to the last. Never stop early, never sample, never give one record for several rows.
- A row that prints a requirement with no minimum (for example "Successful completion of the High School Certificate") is still a record, with min_grade null.
- Take each record's quote from its own row's block. Repeat the table's column or heading words in support, not in the quote.
- Keep records short so every row fits: fill only what the row prints.
- Before you answer, check that every requirement row of every table and list on the page is a record or is in seen_not_mapped.
Rules:
$s$) t) t
 where p.version in ('aer-v2-course-v3-qwen3-30b', 'aer-v2-course-v3-mistral-small-3.2', 'aer-v2-course-v3-mimo-v2.6-flash')
on conflict (version) do nothing;

-- 2. their instruction versions, round-5 proposals and queued runs
insert into pipeline.ai_instruction_versions(family, code, kind, version, home, body, spec, model_identifier, status, note)
select 'entry_requirements', 'aer-v2-course', 'prompt', p.version, 'pipeline.aer_prompt_versions ' || p.version, p.system_text,
       jsonb_build_object('prompt_version', 'aer-v2-course-v3.1', 'answer_contract', p.answer_contract, 'input_format', p.input_format, 'routing', p.routing, 'params', p.params,
                          'quote_max_chars', p.quote_max_chars, 'system_sha256', p.system_sha256),
       p.model, 'candidate', 'AER v2 prompt v3.1 benchmark candidate, round 5 (Platform Admin 18 Nov 2026 20:53); provider pins and require_parameters set by the worker'
  from pipeline.aer_prompt_versions p
 where p.version like 'aer-v2-course-v3.1-%'
on conflict (code, version) do nothing;

insert into pipeline.ai_improvement_proposals(code, family, change_class, authority, title, problem_observed, current_method, proposed_change, production_evidence,
       expected_benefit, risks, candidate_version_id, eval_set_id, acceptance_criteria, status, fingerprint, proposed_by)
select v.version || '-r5', 'entry_requirements', 'prompt', 'release', 'AER v2 course page reader, prompt aer-v2-course-v3.1 on ' || v.model_identifier || ' (round 5)',
       'Round 4 (ai_eval_runs 36 to 38, 18 Nov 2026): no model passed; time-outs at the 90 s per-call limit (Qwen3 30B 27 of 50) and missed rows (false negatives 20 to 26).',
       'AER v1 entry reading off; AER v2 shadow off; no entry reading model qualified; about 1,620 incomplete course reads held.',
       'Prompt aer-v2-course-v3.1 (every row of a table or list); worker coverage-sweep v1.0.19 answers in a background task with a 180 s per-call limit; the same frozen 50-case set and limits.',
       jsonb_build_object('round_4', 'ai_eval_runs 36 (MiMo), 37 (Mistral), 38 (Qwen3 30B)', 'limits', jsonb_build_object('reading.aer_v2_page_chars', 60000,
                          'reading.aer_v2_max_tokens', 12000, 'reading.aer_v2_long_page_sections_on', 1, 'call_seconds', 180, 'worker', 'coverage-sweep v1.0.19')),
       'Whether exhaustive row reading and a 180 s call limit bring a pinned model to the gate (source integrity 100%, error rate at most 10 points, no false positives).',
       'Longer answers cost more; a model that reproduces a rejected row; spend beyond the plan (cap ai_eval.aer_v3_max_usd).',
       v.id, 5,
       jsonb_build_object('false_positives', 0, 'person_fp_rate_pts', 0, 'min_source_integrity_pct', 100, 'max_error_rate_pts', 10,
                          'min_recall_pct_setting', 'ai_eval.aer_v3_min_recall_pct', 'max_usd_setting', 'ai_eval.aer_v3_max_usd',
                          'calls', jsonb_build_object('proposed', 50, 'max', 100, 'retry', 'one retry of a call that returned no answer'),
                          'gate', 'Unchanged from rounds 3 and 4 (no loosening, Platform Admin 18 Nov 2026 20:53)',
                          'note', 'Passing is evidence only: the Platform Admin qualifies a model; nothing switches on by itself'),
       'proposed', md5('aer-v2-course-v3.1-r5|' || v.version || '|' || coalesce(v.spec->>'system_sha256', '')), 'migration 20261118243000'
  from pipeline.ai_instruction_versions v
 where v.code = 'aer-v2-course' and v.status = 'candidate' and v.version like 'aer-v2-course-v3.1-%'
on conflict (code) do nothing;

do $r$
declare p record;
begin
  for p in select id from pipeline.ai_improvement_proposals where code like 'aer-v2-course-v3.1-%-r5' and eval_set_id = 5 order by id loop
    if not exists (select 1 from pipeline.ai_eval_runs where proposal_id = p.id and arm = 'candidate') then
      perform security.ai_eval_run_open_v1(p.id, 'candidate');
    end if;
  end loop;
end $r$;

-- 3. the renewal age (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.validation_renew_after_days', 'Entry requirements: renew the automatic admission validations after',
  'Age of the last passing validation of rules aer-machine-v1 and aer-matrix-machine-v1 at which the daily workflow aer-validation-renew.yml runs the validation again (thresholds unchanged, no regressions). A validation lapses after 7 days, when admission runs as shadow.',
  'number', '5'::jsonb, 1, 6, 'days', 1499, 'Entry requirements', 'workflow aer-validation-renew.yml (scripts/aer-validation-renew.mjs)',
  'CF-247 S674 (Platform Admin 18 Nov 2026 20:53): standing rule, automatic 7-day validation renewal on unchanged thresholds')
on conflict (toolset_key, key) do nothing;

-- 4. post-checks
do $k$
declare n int;
begin
  select count(*) into n from pipeline.ai_eval_runs x join pipeline.ai_improvement_proposals p on p.id = x.proposal_id
   where p.code like 'aer-v2-course-v3.1-%-r5' and x.set_id = 5 and x.arm = 'candidate' and x.state = 'queued';
  if n <> 3 then raise exception 'post-check: % queued round-5 runs (expected 3)', n; end if;
  select count(*) into n from pipeline.aer_prompt_versions a join pipeline.ai_instruction_versions v on v.version = a.version and v.code = 'aer-v2-course'
   where a.version like 'aer-v2-course-v3.1-%' and a.system_text like 'AER course page reader, prompt aer-v2-course-v3.1.%' and a.system_text like '%Tables and lists (read every row):%'
     and a.system_sha256 = encode(sha256(convert_to(a.system_text, 'UTF8')), 'hex') and v.spec->>'system_sha256' = a.system_sha256
     and coalesce((a.routing->>'allow_fallbacks')::boolean, true) = false;
  if n <> 3 then raise exception 'post-check: % v3.1 versions with the new section, a matching sha-256 and no fallback (expected 3)', n; end if;
  if (select count(distinct model) from pipeline.aer_prompt_versions where version like 'aer-v2-course-v3.1-%'
        and model in ('qwen/qwen3-30b-a3b-instruct-2507', 'mistralai/mistral-small-3.2-24b-instruct', 'xiaomi/mimo-v2.6-flash')) <> 3 then
    raise exception 'post-check: the three exact pinned models';
  end if;
  if security.pipeline_num_v1('ai_eval.offline_runs_on', 1) <> 0 or security.pipeline_num_v1('ai_eval.aer_v3_runs_on', 1) <> 0 then
    raise exception 'post-check: the run switches stay 0 here';
  end if;
  if security.pipeline_num_v1('ai_eval.min_source_integrity_pct', 0) <> 100 or security.pipeline_num_v1('ai_eval.aer_v3_min_recall_pct', 0) <> 100
     or security.pipeline_num_v1('aer.machine_min_confidence', -1) <> 0.8 or security.pipeline_num_v1('aer.machine_min_quote_chars', -1) <> 8 then
    raise exception 'post-check: the qualification gate and AER v1 thresholds are unchanged';
  end if;
  if security.pipeline_num_v1('aer.v2_shadow_on', 0) <> 0 then raise exception 'post-check: the AER v2 shadow reader stays off'; end if;
  if exists (select 1 from pipeline.ai_route_qualifications where service_code in ('entry_requirements_v2_shadow', 'course_entry_requirements', 'entry_matrices') and status = 'qualified') then
    raise exception 'post-check: no entry reading model is qualified';
  end if;
  if (select count(*) from security.consumer_api_functions_v1()) <> 75 or (select count(*) from security.consumer_api_relations_v1()) <> 48 then
    raise exception 'post-check: G3 must stay 75 functions and 48 relations';
  end if;
end $k$;
