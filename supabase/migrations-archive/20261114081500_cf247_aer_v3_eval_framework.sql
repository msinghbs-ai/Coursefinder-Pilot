-- CF-247 S1-AER: the AER v2 prompt v3 benchmark on the platform's AI evaluation framework (Platform Admin 14 Nov 2026, option 1 twice:
--   "build the AER v2 evaluation runner on the #1128 platform framework (ai_eval_sets, ai_eval_runs, ai_eval_answers, security.ai_eval_score_v1, and
--   ai_route_qualifications)" and "re-draw the 50-case ai_eval_sets benchmark strictly from trusted labels ... Keep the ground-truth-only database trigger
--   intact. Measure the gate_incomplete and unlabelled negative probe pages separately via the existing paused shadow reader").
-- What:
--   1. Set: a frozen ai_eval_sets set of family entry_requirements with 50 trusted examples (every one a person's Layer 4 decision or correction), stratified
--      by page shape and size (pipeline.ai_eval_set_members gains a stratum column): T1 country tables (provider matrix pages, at most 40 rows), T2 band tables,
--      T3 multi-row pages (four or more rows, the list-shaped proxy), T4 course-specific pages (one to three rows), T5 person rejections (E14 rows a person
--      took back: true negatives), T6 long stored pages; at most 2 examples of a provider in a stratum (4 in T5), one example a stored page. The
--      ground-truth trigger security.ai_eval_example_trusted_trg is not touched: only existing examples are members.
--   2. Instruction versions: the three evaluation versions of prompt aer-v2-course-v3 (#1137) as ai_instruction_versions (kind prompt, one pinned model each;
--      text, sha-256, answer contract, input format, provider pins and params in spec): Qwen3 30B A3B Instruct 2507, Mistral Small 3.2 24B, MiMo-V2.6-Flash.
--      No GPT-4.1 mini. One proposal each (change class prompt, authority release), status proposed, with the acceptance criteria; NO run is opened.
--   3. Runs, answers and scores stay the framework's (pipeline.ai_eval_runs, svc_ai_eval_answer_record_v1, security.ai_eval_score_v1, ai_eval_metrics_v1):
--      - public.svc_aer_v3_eval_next_v1 leases an AER v3 run for worker mode aer_v3_eval (worker v0.92.0), only when ai_eval.offline_runs_on and
--        ai_eval.aer_v3_runs_on are 1 and the AER v3 spend is under ai_eval.aer_v3_max_usd; it hands over the unanswered examples with their frozen stored page;
--      - public.svc_ai_eval_run_next_v1 (md5-guarded edit) never leases an AER v3 run, so no generic answerer reads them;
--      - security.ai_eval_score_v1 (md5-guarded edit) scores an AER v3 run with security.aer_v3_eval_pair_v1: an accepted example is right when the passed
--        records (v3 verifier: exact_quote inside its cited [B#] block, lead_in_quote by the ordered proximity rule) find at least
--        ai_eval.aer_v3_min_recall_pct of its accepted gold rows and reproduce none of its rejected rows; a person rejection is right when the rejected row is
--        not reproduced; reproducing a rejected row is a false positive. The framework's metrics function is unchanged;
--      - the score is written as evidence to pipeline.ai_route_qualifications (service entry_requirements_v2_shadow, prompt aer-v2-course-v3) with status
--        pending at most: a qualification is the Platform Admin's decision and never switches anything on (security.ai_route_v1 hands out only qualified).
--   4. Probes: setting aer.v2_shadow_probe_courses lists the 28 unlabelled probe courses (gate_incomplete, v2 trial and candidate negatives from the #1137
--      set); security.aer_v2_sample_refresh_v1 (md5-guarded edit) keeps them in the shadow sample at their own rank (after the sample), so the paused shadow
--      reader measures them by verifier pass rate only. The sample is not rebuilt here; the 1,912-page order is unchanged.
--   5. Retired: pipeline.aer_v2_eval_cases and pipeline.aer_v2_eval_plans (#1137) are marked retiring in pipeline.component_register (one evaluation path,
--      Decision 260); the plan row is closed. Nothing is dropped or deleted.
-- Nothing runs, calls or spends: aer.v2_shadow_on stays 0, ai_eval.offline_runs_on stays 0, ai_eval.aer_v3_runs_on ships 0, no run is opened, no qualification
--   changes to qualified, the shadow queue and its tries are unchanged. The benchmark runs only after Lean AI's shadow check and the Platform Admin's sign-off.
-- Live definitions this change edits (md5 of pg_get_functiondef, read 14 Nov 2026): public.svc_ai_eval_run_next_v1 d4537de869c5c12752e6d1aeec7265a8,
--   security.ai_eval_score_v1 bfdc98c50f115949498e6d95c5e43e2b, security.aer_v2_sample_refresh_v1 4c1ea14da4064c05f2dcd4b49387dd86.
-- Replaces: the #1137 AER evaluation tables pipeline.aer_v2_eval_cases and pipeline.aer_v2_eval_plans. Retires: pipeline.aer_v2_eval_cases, pipeline.aer_v2_eval_plans.

-- 1. settings -------------------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'ai_eval.aer_v3_runs_on', 'Entry requirements v3 benchmark runs',
  'Lets worker mode aer_v3_eval answer an opened AER v2 prompt v3 benchmark run (with ai_eval.offline_runs_on). Off until the Platform Admin signs the benchmark off.',
  'number', to_jsonb(0), 0, 1, 'switch', 1418, 'AI evaluation', 'public.svc_aer_v3_eval_next_v1 (worker mode aer_v3_eval)',
  'Platform Admin 14 Nov 2026: zero paid AI calls until Lean AI''s shadow check completes and explicit evaluation sign-off'),
 ('pipeline', 'ai_eval.aer_v3_max_usd', 'Entry requirements v3 benchmark: spend cap',
  'The most the AER v2 prompt v3 benchmark runs may spend together (the answers'' recorded cost). A run is not leased once it is reached.',
  'number', to_jsonb(2), 0, 20, 'US$', 1419, 'AI evaluation', 'public.svc_aer_v3_eval_next_v1 (worker mode aer_v3_eval)',
  'Plan recorded 14 Nov 2026 (#1137): at most US$2.00 for the three-model benchmark'),
 ('pipeline', 'ai_eval.aer_v3_min_recall_pct', 'Entry requirements v3 benchmark: rows to find on an accepted example',
  'An accepted example is answered right when the passed records find at least this share of its accepted gold rows and reproduce none of its rejected rows.',
  'number', to_jsonb(100), 50, 100, 'percent', 1420, 'AI evaluation', 'security.aer_v3_eval_pair_v1 (security.ai_eval_score_v1)',
  'Platform Admin 14 Nov 2026: score multi-record AER answers in the framework')
on conflict (toolset_key, key) do nothing;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
select 'pipeline', 'aer.v2_shadow_probe_courses', 'Entry requirements v2: unlabelled probe courses kept in the shadow sample',
       'Courses with no trusted label (gate_incomplete reads, the v2 trial''s courses, candidate negatives) that the paused shadow reader measures by verifier pass rate only, unscored. Kept in the sample at their own rank.',
       'list', coalesce(jsonb_agg(c.course_id::text order by c.case_no), '[]'::jsonb), null, null, 'courses', 1549, 'Entry requirements',
       'security.aer_v2_sample_refresh_v1 (job aer-v2-shadow)', 'Platform Admin 14 Nov 2026: probes measured on the existing paused shadow reader'
  from pipeline.aer_v2_eval_cases c where c.eval_set = 'aer-v2-eval-50-v1' and c.stratum in ('S1', 'S3', 'S6')
on conflict (toolset_key, key) do nothing;

-- 2. the strata column (new, beside the existing ones) ----------------------------------------------------------------------------------------------------
alter table pipeline.ai_eval_set_members add column if not exists stratum text;
comment on column pipeline.ai_eval_set_members.stratum is 'The stratum an example was drawn for, when its set is stratified (AER v3 benchmark: T1 to T6); null for sets frozen whole.';

-- 3. helpers --------------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.aer_v3_eval_version_v1(p_version bigint) returns boolean
language sql stable security definer set search_path to '' as $f$
  select coalesce((select v.spec->>'answer_contract' = 'aer-v2-answer-v3' from pipeline.ai_instruction_versions v where v.id = p_version), false)
$f$;
comment on function security.aer_v3_eval_version_v1(bigint) is 'AER v3 benchmark: whether an instruction version answers with the AER v2 answer contract v3 (multi-record, [B#] quotes); such runs are leased only by worker mode aer_v3_eval.';

create or replace function security.aer_v3_flat_v1(p text) returns text
language sql immutable set search_path to '' as $f$
  -- the verifier's canonical form (aer-v2.ts aerFlat): lower case, NFKD, letters and digits only
  select regexp_replace(normalize(lower(coalesce(p, '')), NFKD), '[^a-z0-9]+', '', 'g')
$f$;

-- an example's subject and frozen stored page: scope course (a course page decision), row (a course row a person took back) or matrix (a provider page)
create or replace function security.aer_v3_eval_subject_v1(p_example bigint) returns jsonb
language sql stable security definer set search_path to '' as $f$
  with x as (select x.*, case when x.field like 'entry_matrix%' then 'matrix' when x.entity = 'course_entry' then 'row' else 'course' end scope,
                    case when x.entity = 'course_entry' then (select c.course_id from catalogue.course_entry_requirements c where c.id = x.entity_id)
                         when x.entity = 'course' then x.entity_id end course_id,
                    coalesce(x.evidence_id, case when x.entity = 'course_entry' then (select c.evidence_id from catalogue.course_entry_requirements c where c.id = x.entity_id) end) ev
               from pipeline.ai_eval_examples x where x.id = p_example)
  select jsonb_build_object('example_id', x.id, 'scope', x.scope, 'label', x.label, 'course_id', x.course_id,
           'provider_id', coalesce(co.provider_id, case when x.entity = 'provider' then x.entity_id end),
           'evidence_id', x.ev, 'storage_path', a.storage_path, 'content_hash', a.content_hash,
           'review_item_id', substring(x.input_ref from '[0-9a-f-]{36}$'), 'row_id', case when x.scope = 'row' then x.entity_id end,
           'title', coalesce(co.canonical_title, 'Entry requirements (institution page)'),
           'provider', coalesce(p.display_name, p.canonical_name), 'provider_country', security.coverage_country(coalesce(co.provider_id, case when x.entity = 'provider' then x.entity_id end)),
           'level', (select sl.name from ref.study_levels sl where sl.id = co.study_level_id), 'url', a.source_url)
    from x left join catalogue.courses co on co.id = x.course_id
    left join catalogue.providers p on p.id = coalesce(co.provider_id, case when x.entity = 'provider' then x.entity_id end)
    left join pipeline.evidence_artifacts a on a.id = x.ev
$f$;
comment on function security.aer_v3_eval_subject_v1(bigint) is 'AER v3 benchmark: an example''s subject (course, course row or provider page), its frozen stored page and the course record the reader is given.';

-- an example's gold rows, frozen with the set (pipeline.aer_v3_eval_gold): accepted rows to find, rejected rows never to reproduce
create table if not exists pipeline.aer_v3_eval_gold (
  set_id bigint not null references pipeline.ai_eval_sets(id),
  example_id bigint not null references pipeline.ai_eval_examples(id),
  label text not null check (label in ('accepted', 'rejected')),
  source_kind text not null,
  row_id uuid,
  min_grade text,
  quote text,
  country text,
  frozen_at timestamptz not null default now()
);
comment on table pipeline.aer_v3_eval_gold is 'AER v3 benchmark: the gold rows of each example of a frozen entry_requirements set, copied once from pipeline.aer_labelled_rows_v1 when the set is frozen (the accepted rows of the same stored page or decided read, the rejected rows, or the one row a person took back), so later changes to live rows never move the benchmark. Read by security.aer_v3_eval_gold_v1; never by the consumer API.';
create index if not exists aer_v3_eval_gold_example on pipeline.aer_v3_eval_gold(set_id, example_id);

create or replace function security.aer_v3_eval_gold_v1(p_set bigint, p_example bigint) returns jsonb
language sql stable security definer set search_path to '' as $f$
  select jsonb_build_object(
    'accepted', coalesce(jsonb_agg(jsonb_build_object('min_grade', g.min_grade, 'quote', g.quote, 'country', g.country)) filter (where g.label = 'accepted'), '[]'::jsonb),
    'rejected', coalesce(jsonb_agg(jsonb_build_object('min_grade', g.min_grade, 'quote', g.quote, 'country', g.country)) filter (where g.label = 'rejected'), '[]'::jsonb))
    from pipeline.aer_v3_eval_gold g where g.set_id = p_set and g.example_id = p_example
$f$;
comment on function security.aer_v3_eval_gold_v1(bigint, bigint) is 'AER v3 benchmark: the frozen gold rows of an example in a set (accepted rows to find, rejected rows never to reproduce).';

-- a passed record finds a gold row when it prints the same minimum (or both print none) and one quote holds the other; a named country must agree
create or replace function security.aer_v3_row_found_v1(p_gold jsonb, p_rec jsonb) returns boolean
language sql immutable set search_path to '' as $f$
  select security.aer_v3_flat_v1(p_gold->>'min_grade') = security.aer_v3_flat_v1(p_rec->>'min_grade')
     and length(security.aer_v3_flat_v1(p_rec->>'exact_quote')) >= 4 and length(security.aer_v3_flat_v1(p_gold->>'quote')) >= 4  -- fixed: the verifier's quote floor
     and (position(security.aer_v3_flat_v1(p_rec->>'exact_quote') in security.aer_v3_flat_v1(p_gold->>'quote')) > 0
          or position(security.aer_v3_flat_v1(p_gold->>'quote') in security.aer_v3_flat_v1(p_rec->>'exact_quote')) > 0)
     and (p_gold->>'country' is null or upper(coalesce(p_rec->>'applicant_country', '')) = upper(p_gold->>'country'))
$f$;

-- one scoring pair for the framework's metrics (security.ai_eval_metrics_v1): the base pair with verdict, value and quote_on_page from the AER comparison
create or replace function security.aer_v3_eval_pair_v1(p_base jsonb, p_set bigint, p_example bigint, p_value jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $f$
declare v_gold jsonb := security.aer_v3_eval_gold_v1(p_set, p_example); v_min numeric := security.pipeline_num_v1('ai_eval.aer_v3_min_recall_pct', 100);
        v_passed jsonb; v_acc int; v_found int; v_repro int; v_recall numeric; v_failed int; v_ok boolean;
begin
  v_ok := coalesce((p_base->>'answered')::boolean, false) and p_base->>'error' is null and jsonb_typeof(p_value->'records') = 'array';
  -- checks are in record order (aer-v2.ts aerV3Verify); a record without its check counts as failed
  select count(*) filter (where not coalesce((p_value->'checks'->(e.i::int - 1)->>'pass')::boolean, false)) into v_failed
    from jsonb_array_elements(coalesce(p_value->'records', '[]'::jsonb)) with ordinality e(rec, i);
  select coalesce(jsonb_agg(r.rec), '[]'::jsonb) into v_passed
    from (select e.rec from jsonb_array_elements(coalesce(p_value->'records', '[]'::jsonb)) with ordinality e(rec, i)
           where coalesce((p_value->'checks'->(e.i::int - 1)->>'pass')::boolean, false)) r;
  v_acc := jsonb_array_length(v_gold->'accepted');
  select count(*) into v_found from jsonb_array_elements(v_gold->'accepted') g where exists (select 1 from jsonb_array_elements(v_passed) r where security.aer_v3_row_found_v1(g, r));
  select count(*) into v_repro from jsonb_array_elements(v_gold->'rejected') g where exists (select 1 from jsonb_array_elements(v_passed) r where security.aer_v3_row_found_v1(g, r));
  v_recall := case when v_acc > 0 then round(100.0 * v_found / v_acc, 2) end;
  return p_base || jsonb_build_object(
    'verdict', case when not v_ok then null when v_repro > 0 then 'accept'
                    when p_base->>'label' in ('accept', 'correct') and v_acc > 0 and v_recall >= v_min then 'accept' else 'no_value' end,
    'value', case when not v_ok then null
                  when v_repro > 0 then case when p_base->>'label' = 'reject' then p_base->'rejected' else jsonb_build_object('aer', 'reproduced a rejected row') end
                  when p_base->>'label' in ('accept', 'correct') and v_acc > 0 and v_recall >= v_min then p_base->'expected' end,
    'quote_on_page', v_ok and v_failed = 0 and jsonb_array_length(v_passed) > 0,
    'aer', jsonb_build_object('gold_accepted', v_acc, 'found', v_found, 'recall_pct', v_recall, 'reproduced_rejected', v_repro,
                              'passed', jsonb_array_length(v_passed), 'failed', v_failed));
end $f$;
comment on function security.aer_v3_eval_pair_v1(jsonb, bigint, bigint, jsonb) is 'AER v3 benchmark: turns one multi-record AER answer into the framework''s scoring pair (right: enough accepted gold rows found by passed records and no rejected row reproduced; a reproduced rejected row is a false positive; source integrity: every record passed the v3 verifier).';

-- the score as qualification evidence: pending at most; the Platform Admin qualifies
create or replace function security.aer_v3_qualification_evidence_v1(p_run bigint, p_metrics jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare r record; v_model text; v_strata jsonb;
begin
  select x.*, v.version ver, p.code proposal, p.acceptance_criteria crit into r
    from pipeline.ai_eval_runs x join pipeline.ai_instruction_versions v on v.id = x.version_id left join pipeline.ai_improvement_proposals p on p.id = x.proposal_id where x.id = p_run;
  select m.code into v_model from pipeline.ai_model_catalogue m where m.model_identifier = r.model_identifier;
  if v_model is null then return jsonb_build_object('recorded', false, 'why', 'model not in the catalogue'); end if;
  select jsonb_object_agg(z.stratum, z.m) into v_strata from (
    select m.stratum, security.ai_eval_metrics_v1(jsonb_agg(security.aer_v3_eval_pair_v1(jsonb_build_object(
             'label', x.label, 'expected', x.expected, 'rejected', x.rejected, 'needs_quote', true, 'tier', x.tier, 'answered', a.example_id is not null,
             'verdict', a.verdict, 'value', a.value, 'quote_on_page', a.quote_on_page, 'error', a.error, 'cost_usd', a.cost_usd, 'tokens_in', a.tokens_in, 'tokens_out', a.tokens_out),
             m.set_id, x.id, a.value))) m
      from pipeline.ai_eval_set_members m join pipeline.ai_eval_examples x on x.id = m.example_id
      left join pipeline.ai_eval_answers a on a.run_id = p_run and a.example_id = x.id
     where m.set_id = r.set_id group by m.stratum) z;
  insert into pipeline.ai_route_qualifications as q(service_code, model_code, prompt_version, status, provisional, evidence, evidence_detail, note, changed_at)
  values ('entry_requirements_v2_shadow', v_model, 'aer-v2-course-v3', 'pending', false,
          format('ai_eval run %s (%s, set %s): accuracy %s%%, false positives %s of %s, source integrity %s%%', p_run, r.ver, r.set_id,
                 p_metrics->>'accuracy_pct', p_metrics->>'false_positives', p_metrics->>'examples', p_metrics->>'source_integrity_pct'),
          jsonb_build_object('run', p_run, 'proposal', r.proposal, 'version', r.ver, 'set', r.set_id, 'metrics', p_metrics, 'strata', v_strata, 'criteria', r.crit),
          'Benchmark evidence recorded; qualifying the model is the Platform Admin''s decision (a qualification never switches a service on).', now())
  on conflict (service_code, model_code) do update
     set prompt_version = excluded.prompt_version, evidence = excluded.evidence, evidence_detail = excluded.evidence_detail, note = excluded.note, changed_at = now(),
         status = case when q.status = 'qualified' then q.status else 'pending' end;
  return jsonb_build_object('recorded', true, 'model', v_model, 'strata', v_strata);
end $f$;
comment on function security.aer_v3_qualification_evidence_v1(bigint, jsonb) is 'AER v3 benchmark: writes a scored run as evidence on pipeline.ai_route_qualifications (entry_requirements_v2_shadow, prompt aer-v2-course-v3), status pending at most; never qualifies a model.';
revoke all on function security.aer_v3_qualification_evidence_v1(bigint, jsonb) from public, anon, authenticated;

-- the lease for worker mode aer_v3_eval: AER v3 runs only, behind both switches and the spend cap; unanswered examples with their frozen page
create or replace function public.svc_aer_v3_eval_next_v1() returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare r record; v_spent numeric; v_cap numeric := security.pipeline_num_v1('ai_eval.aer_v3_max_usd', 2);
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  perform set_config('cf247.ai_eval_path', 'on', true);
  if security.pipeline_num_v1('ai_eval.offline_runs_on', 0) <> 1 then return jsonb_build_object('run', null, 'why', 'ai_eval.offline_runs_on is 0'); end if;
  if security.pipeline_num_v1('ai_eval.aer_v3_runs_on', 0) <> 1 then return jsonb_build_object('run', null, 'why', 'ai_eval.aer_v3_runs_on is 0'); end if;
  select coalesce(sum(a.cost_usd), 0) into v_spent from pipeline.ai_eval_answers a join pipeline.ai_eval_runs x on x.id = a.run_id where security.aer_v3_eval_version_v1(x.version_id);
  if v_spent >= v_cap then return jsonb_build_object('run', null, 'why', format('spend cap reached: US$%s of US$%s (ai_eval.aer_v3_max_usd)', round(v_spent, 4), v_cap)); end if;
  select * into r from pipeline.ai_eval_runs
   where (state = 'queued' or (state = 'answering' and leased_until < now())) and security.aer_v3_eval_version_v1(version_id)
   order by requested_at limit 1 for update skip locked;
  if not found then return jsonb_build_object('run', null); end if;
  update pipeline.ai_eval_runs set state = 'answering', leased_until = now() + interval '30 minutes' where id = r.id;  -- fixed: claim lease
  return jsonb_build_object('run', r.id, 'set_id', r.set_id, 'budget', jsonb_build_object('cap_usd', v_cap, 'spent_usd', v_spent),
    'version', (select jsonb_build_object('id', v.id, 'version', v.version, 'model', v.model_identifier, 'body', v.body, 'spec', v.spec) from pipeline.ai_instruction_versions v where v.id = r.version_id),
    'countries', (select coalesce(jsonb_agg(k.iso_alpha2 order by k.iso_alpha2), '[]'::jsonb) from ref.countries k where k.iso_alpha2 is not null),
    'qualifications', (select coalesce(jsonb_agg(jsonb_build_object('code', q.code, 'name', q.name) order by q.code), '[]'::jsonb) from ref.aer_qualifications q),
    'examples', (select coalesce(jsonb_agg(security.aer_v3_eval_subject_v1(m.example_id) order by m.example_id), '[]'::jsonb)
                   from pipeline.ai_eval_set_members m where m.set_id = r.set_id
                    and not exists (select 1 from pipeline.ai_eval_answers a where a.run_id = r.id and a.example_id = m.example_id)));
end $f$;
comment on function public.svc_aer_v3_eval_next_v1() is 'AER v3 benchmark: leases one opened AER v2 prompt v3 run for worker mode aer_v3_eval (both switches on and under the spend cap); answers go back through public.svc_ai_eval_answer_record_v1 and are scored by security.ai_eval_score_v1.';
revoke all on function public.svc_aer_v3_eval_next_v1() from public, anon, authenticated;
grant execute on function public.svc_aer_v3_eval_next_v1() to service_role;

-- 4. md5-guarded edits ----------------------------------------------------------------------------------------------------------------------------------
create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- the generic lease never hands out an AER v3 run (those have their own answerer and answer contract)
select pg_temp.edit_n('public.svc_ai_eval_run_next_v1()', 'd4537de869c5c12752e6d1aeec7265a8', array[
  array[$o$   where state = 'queued' or (state = 'answering' and leased_until < now())$o$,
        $n$   where (state = 'queued' or (state = 'answering' and leased_until < now()))
     and not security.aer_v3_eval_version_v1(version_id)  -- 14 Nov 2026: AER v3 runs are leased by public.svc_aer_v3_eval_next_v1 only$n$]
], array[1]);

-- AER v3 runs are scored on their multi-record answers, and the score is written as qualification evidence
select pg_temp.edit_n('security.ai_eval_score_v1(bigint)', 'bfdc98c50f115949498e6d95c5e43e2b', array[
  array[$o$declare v jsonb;$o$, $n$declare v jsonb; v_aer boolean := security.aer_v3_eval_version_v1((select r.version_id from pipeline.ai_eval_runs r where r.id = p_run));$n$],
  array[$o$  select security.ai_eval_metrics_v1(coalesce(jsonb_agg(jsonb_build_object($o$,
        $n$  select security.ai_eval_metrics_v1(coalesce(jsonb_agg((case when v_aer then security.aer_v3_eval_pair_v1(jsonb_build_object($n$],
  array[$o$'tokens_in', a.tokens_in, 'tokens_out', a.tokens_out)), '[]'))$o$,
        $n$'tokens_in', a.tokens_in, 'tokens_out', a.tokens_out), r.set_id, x.id, a.value) else jsonb_build_object(
           'label', x.label, 'expected', x.expected, 'rejected', x.rejected, 'needs_quote', f.needs_quote, 'tier', x.tier, 'answered', a.example_id is not null,
           'verdict', a.verdict, 'value', a.value, 'quote_on_page', a.quote_on_page, 'error', a.error, 'cost_usd', a.cost_usd, 'tokens_in', a.tokens_in, 'tokens_out', a.tokens_out) end)), '[]'))$n$],
  array[$o$  update pipeline.ai_eval_runs set metrics = v, state = 'scored', scored_at = now() where id = p_run and state in ('recorded', 'scored');$o$,
        $n$  update pipeline.ai_eval_runs set metrics = v, state = 'scored', scored_at = now() where id = p_run and state in ('recorded', 'scored');
  if v_aer then v := v || jsonb_build_object('qualification', security.aer_v3_qualification_evidence_v1(p_run, v)); end if;  -- 14 Nov 2026: evidence only$n$]
], array[1, 1, 1, 1]);

-- the unlabelled probes stay in the shadow sample (at their own rank, after the sample); the sample is not rebuilt here
select pg_temp.edit_n('security.aer_v2_sample_refresh_v1()', '4c1ea14da4064c05f2dcd4b49387dd86', array[
  array[$o$from sample s cross join cfg where s.sample_rank <= cfg.sample_size$o$,
        $n$from sample s cross join cfg where s.sample_rank <= cfg.sample_size
      -- 14 Nov 2026: the unlabelled probe courses (aer.v2_shadow_probe_courses), measured by verifier pass rate only
      or s.course_id::text in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'aer.v2_shadow_probe_courses'), '[]'::jsonb)))$n$]
], array[1]);

-- 5. the set (frozen once) ------------------------------------------------------------------------------------------------------------------------------
do $s$
declare v_set bigint; v_ver int;
begin
  if exists (select 1 from pipeline.ai_eval_sets where family = 'entry_requirements' and note like 'aer-v2-course-v3 benchmark%') then return; end if;
  select coalesce(max(version), 0) + 1 into v_ver from pipeline.ai_eval_sets where family = 'entry_requirements';
  insert into pipeline.ai_eval_sets(family, version, example_count, person_count, quote_count, frozen_at, note)
  values ('entry_requirements', v_ver, 0, 0, 0, now(),
          'aer-v2-course-v3 benchmark (Platform Admin 14 Nov 2026): 50 trusted examples stratified by page shape and size (T1 country table, T2 band table, T3 multi-row, T4 course-specific, T5 person rejection, T6 long page)')
  returning id into v_set;
  insert into pipeline.ai_eval_set_members(set_id, example_id, stratum)
  with lab as materialized (select l.source_kind, l.course_id, l.evidence_id, l.review_item_id, l.label, l.benchmark_band from pipeline.aer_labelled_rows_v1 l where l.source_kind in ('course_page', 'country_table')),
  x as materialized (
    select x.id, x.tier, x.label, x.field, x.entity, x.entity_id, x.input_ref,
           case when x.entity = 'course_entry' then c.course_id when x.entity = 'course' then x.entity_id end course_id,
           coalesce(x.evidence_id, c.evidence_id) evidence_id
      from pipeline.ai_eval_examples x left join catalogue.course_entry_requirements c on x.entity = 'course_entry' and c.id = x.entity_id
     where x.family = 'entry_requirements' and x.active and x.tier = 'person'
       and (x.field in ('entry_requirements', 'course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change') or (x.field = 'status' and x.entity = 'course_entry'))),
  pool as materialized (
    select x.*, (o.metadata->>'size')::bigint bytes, coalesce(co.provider_id, case when x.entity = 'provider' then x.entity_id end) provider_id,
           case when x.field like 'entry_matrix%' then 'matrix' when x.entity = 'course_entry' then 'row' else 'course' end scope
      from x join pipeline.evidence_artifacts a on a.id = x.evidence_id and a.storage_path is not null
      left join catalogue.courses co on co.id = x.course_id
      left join storage.objects o on o.bucket_id = 'evidence' and o.name = a.storage_path),
  gold as materialized (
    select p.id, count(*) filter (where l.label = 'accepted') acc, count(*) filter (where l.label = 'accepted' and l.benchmark_band is not null) band
      from pool p join lab l on l.source_kind = 'course_page' and l.course_id = p.course_id and l.evidence_id = p.evidence_id where p.scope = 'course' group by 1
    union all
    select p.id, count(*) filter (where l.label = 'accepted'), count(*) filter (where l.label = 'accepted' and l.benchmark_band is not null)
      from pool p join lab l on l.source_kind = 'country_table' and l.review_item_id::text = substring(p.input_ref from '[0-9a-f-]{36}$') where p.scope = 'matrix' group by 1),
  pct as materialized (select percentile_cont(0.90) within group (order by bytes) p90, percentile_cont(0.97) within group (order by bytes) p97 from pool where scope = 'course' and bytes is not null),
  tagged as (
    select p.*, case when p.label = 'reject' and p.scope = 'row' then 'T5'
                     when p.scope = 'matrix' and p.label in ('accept', 'correct') and g.acc between 1 and 40 then 'T1'
                     when p.scope = 'course' and g.acc > 0 and p.bytes between (select p90 from pct) and (select p97 from pct) then 'T6'
                     when p.scope = 'course' and g.band > 0 then 'T2'
                     when p.scope = 'course' and g.acc >= 4 then 'T3'
                     when p.scope = 'course' and g.acc between 1 and 3 then 'T4' end stratum
      from pool p left join gold g on g.id = p.id),
  strata(stratum, want, per_provider) as (values ('T1', 8, 2), ('T2', 6, 2), ('T3', 10, 2), ('T4', 12, 2), ('T5', 8, 4), ('T6', 6, 2)),
  -- one example a stored page (a page shared with a person rejection stays in T5: negatives are scarce), then at most per_provider of a provider
  dedup as (select t.*, row_number() over (partition by t.evidence_id order by (t.stratum = 'T5') desc, t.stratum, md5(t.id::text || 'aer-v3-eval-trusted-v1')) ev_rank
              from tagged t where t.stratum is not null),
  capped as (select d.*, row_number() over (partition by d.stratum, d.provider_id order by md5(d.id::text || 'aer-v3-eval-trusted-v1')) prov_rank from dedup d where d.ev_rank = 1),
  picked as (select c.*, s.want, row_number() over (partition by c.stratum order by md5(c.id::text || 'aer-v3-eval-trusted-v1')) st_rank
               from capped c join strata s on s.stratum = c.stratum where c.prov_rank <= s.per_provider)
  select v_set, p.id, p.stratum from picked p where p.st_rank <= p.want;
  -- the gold rows, frozen with the set
  insert into pipeline.aer_v3_eval_gold(set_id, example_id, label, source_kind, row_id, min_grade, quote, country)
  with lab as materialized (select l.source_kind, l.row_id, l.course_id, l.evidence_id, l.review_item_id, l.label, l.min_grade, l.quote, l.country_code
                              from pipeline.aer_labelled_rows_v1 l where l.source_kind in ('course_page', 'country_table') and l.label in ('accepted', 'rejected')),
  mem as materialized (select m.example_id, security.aer_v3_eval_subject_v1(m.example_id) j from pipeline.ai_eval_set_members m where m.set_id = v_set)
  select v_set, mem.example_id, case when mem.j->>'scope' = 'row' then 'rejected' else lab.label end, lab.source_kind, lab.row_id, lab.min_grade, lab.quote, lab.country_code
    from mem join lab
      on (mem.j->>'scope' = 'course' and lab.source_kind = 'course_page' and lab.course_id = (mem.j->>'course_id')::uuid and lab.evidence_id = (mem.j->>'evidence_id')::uuid)
      or (mem.j->>'scope' = 'matrix' and lab.source_kind = 'country_table' and lab.review_item_id::text = mem.j->>'review_item_id')
      or (mem.j->>'scope' = 'row' and lab.source_kind = 'course_page' and lab.row_id = (mem.j->>'row_id')::uuid);
  update pipeline.ai_eval_sets s set example_count = z.n, person_count = z.p, quote_count = z.q
    from (select count(*) n, count(*) filter (where x.tier = 'person') p, count(*) filter (where x.tier = 'verified_quote') q
            from pipeline.ai_eval_set_members m join pipeline.ai_eval_examples x on x.id = m.example_id where m.set_id = v_set) z where s.id = v_set;
end $s$;

-- 6. instruction versions and proposals (no run is opened) ----------------------------------------------------------------------------------------------
insert into pipeline.ai_instruction_versions(family, code, kind, version, home, body, spec, model_identifier, status, note)
select 'entry_requirements', 'aer-v2-course', 'prompt', p.version, 'pipeline.aer_prompt_versions ' || p.version, p.system_text,
       jsonb_build_object('prompt_version', 'aer-v2-course-v3', 'answer_contract', p.answer_contract, 'input_format', p.input_format, 'routing', p.routing, 'params', p.params,
                          'quote_max_chars', p.quote_max_chars, 'system_sha256', p.system_sha256),
       p.model, 'candidate', 'AER v2 prompt v3 benchmark candidate (Platform Admin 14 Nov 2026); provider pins and require_parameters set by the worker'
  from pipeline.aer_prompt_versions p
 where p.status = 'evaluation' and p.answer_contract = 'aer-v2-answer-v3'
   and p.version in ('aer-v2-course-v3-qwen3-30b', 'aer-v2-course-v3-mistral-small-3.2', 'aer-v2-course-v3-mimo-v2.6-flash')
on conflict (code, version) do nothing;

insert into pipeline.ai_improvement_proposals(code, family, change_class, authority, title, problem_observed, current_method, proposed_change, production_evidence,
       expected_benefit, risks, candidate_version_id, eval_set_id, acceptance_criteria, status, fingerprint, proposed_by)
select v.version, 'entry_requirements', 'prompt', 'release', 'AER v2 course page reader, prompt aer-v2-course-v3 on ' || v.model_identifier,
       'The v2 trial (13 Nov 2026, 14 reads) joined list lead-ins to list items, put non-grade text in min_grade and gave long quotes; 1,912 gate_incomplete reads wait in Layer 4.',
       'AER v1 readers (frozen, Decision 276) and the paused AER v2 shadow reader on prompt aer-v2-course-v2.',
       'Prompt aer-v2-course-v3: the whole stored page as numbered [B#] blocks; exact_quote and lead_in_quote apart under the ordered proximity rule; pinned model and providers.',
       jsonb_build_object('change', 'Pilot #1137 (prompt v3 and verifier, worker v0.88.0)', 'trial', 'pipeline.aer_v2_shadow_results, prompt aer-v2-course-v2, 13 Nov 2026',
                          'waiting', 'Layer 4 course_entry_first_read gate_incomplete'),
       'Source-backed AER records that pass the v3 verifier, measured against people''s decisions before any qualification.',
       'A model that misses rows or reproduces a rejected row; spend beyond the plan (cap ai_eval.aer_v3_max_usd).',
       v.id, (select s.id from pipeline.ai_eval_sets s where s.family = 'entry_requirements' and s.note like 'aer-v2-course-v3 benchmark%' order by s.id desc limit 1),
       jsonb_build_object('false_positives', 0, 'person_fp_rate_pts', 0, 'min_source_integrity_pct', 100, 'max_error_rate_pts', 10,
                          'min_recall_pct_setting', 'ai_eval.aer_v3_min_recall_pct', 'max_usd_setting', 'ai_eval.aer_v3_max_usd',
                          'calls', jsonb_build_object('proposed', 150, 'max', 300, 'retry', 'one retry of a call that returned no answer'),
                          'note', 'Passing is evidence only: the Platform Admin qualifies a model; nothing switches on by itself'),
       'proposed', md5('aer-v2-course-v3|' || v.version || '|' || coalesce(v.spec->>'system_sha256', '')), 'migration 20261114081500'
  from pipeline.ai_instruction_versions v
 where v.code = 'aer-v2-course' and v.version in ('aer-v2-course-v3-qwen3-30b', 'aer-v2-course-v3-mistral-small-3.2', 'aer-v2-course-v3-mimo-v2.6-flash')
on conflict (code) do nothing;

-- 7. one evaluation path: the #1137 tables retire (kept; dropped later by a paste file once unused) ---------------------------------------------------------
update pipeline.aer_v2_eval_plans set status = 'closed' where eval_set = 'aer-v2-eval-50-v1' and status = 'proposed';
update pipeline.component_register set status = 'retiring', updated_at = now(),
       replaced_by = 'pipeline.ai_eval_sets (entry_requirements, aer-v2-course-v3 benchmark) and pipeline.ai_improvement_proposals aer-v2-course-v3-*',
       retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int,
       note = 'Retired by migration 20261114081500: the AER benchmark runs on the platform AI evaluation framework (Platform Admin 14 Nov 2026).'
 where name in ('pipeline.aer_v2_eval_cases', 'pipeline.aer_v2_eval_plans') and status = 'active';
comment on table pipeline.aer_v2_eval_cases is 'RETIRING (migration 20261114081500): replaced by the aer-v2-course-v3 benchmark set in pipeline.ai_eval_sets (trusted labels only); the unlabelled probe courses moved to setting aer.v2_shadow_probe_courses. Kept until dropped by a paste file.';
comment on table pipeline.aer_v2_eval_plans is 'RETIRING (migration 20261114081500): replaced by pipeline.ai_improvement_proposals aer-v2-course-v3-* (acceptance criteria and call plan) and setting ai_eval.aer_v3_max_usd. Kept until dropped by a paste file.';

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'public.svc_aer_v3_eval_next_v1', 'Layer 2', 'Entry requirements', 'AER v3 benchmark: leases an opened run for worker mode aer_v3_eval (behind ai_eval.offline_runs_on, ai_eval.aer_v3_runs_on and the spend cap)', 'active', '{pipeline.aer_v2_eval_plans}', '20261114081500'),
 ('function', 'security.aer_v3_eval_pair_v1', 'Layer 2', 'Entry requirements', 'AER v3 benchmark: scores a multi-record answer in the framework''s metrics', 'active', '{pipeline.aer_v2_eval_cases}', '20261114081500'),
 ('table', 'pipeline.aer_v3_eval_gold', 'Layer 2', 'Entry requirements', 'AER v3 benchmark: gold rows frozen with the entry_requirements benchmark set', 'active', '{pipeline.aer_v2_eval_cases}', '20261114081500')
on conflict do nothing;

-- 8. post-checks ----------------------------------------------------------------------------------------------------------------------------------------
do $k$
declare v_set bigint; n int; s jsonb;
begin
  select id into v_set from pipeline.ai_eval_sets where family = 'entry_requirements' and note like 'aer-v2-course-v3 benchmark%' order by id desc limit 1;
  select count(*) into n from pipeline.ai_eval_set_members where set_id = v_set;
  if n <> 50 then raise exception 'post-check: % examples in the benchmark set (expected 50)', n; end if;
  select jsonb_object_agg(stratum, k) into s from (select stratum, count(*) k from pipeline.ai_eval_set_members where set_id = v_set group by 1) z;
  if s <> '{"T1": 8, "T2": 6, "T3": 10, "T4": 12, "T5": 8, "T6": 6}'::jsonb then raise exception 'post-check: strata %', s; end if;
  if exists (select 1 from pipeline.ai_eval_set_members m join pipeline.ai_eval_examples x on x.id = m.example_id where m.set_id = v_set and (x.tier <> 'person' or not x.active)) then
    raise exception 'post-check: every member is an active person decision';
  end if;
  if exists (select 1 from pipeline.ai_eval_set_members m where m.set_id = v_set and (security.aer_v3_eval_subject_v1(m.example_id)->>'storage_path') is null) then
    raise exception 'post-check: every member has its stored page';
  end if;
  if exists (select 1 from pipeline.ai_eval_set_members m where m.set_id = v_set and m.stratum <> 'T5' and jsonb_array_length(security.aer_v3_eval_gold_v1(v_set, m.example_id)->'accepted') = 0)
     or exists (select 1 from pipeline.ai_eval_set_members m where m.set_id = v_set and m.stratum = 'T5' and jsonb_array_length(security.aer_v3_eval_gold_v1(v_set, m.example_id)->'rejected') <> 1) then
    raise exception 'post-check: every accepted example has gold rows and every rejection its one rejected row';
  end if;
  select count(*) into n from pipeline.ai_instruction_versions v join pipeline.aer_prompt_versions p on p.version = v.version
   where v.code = 'aer-v2-course' and v.status = 'candidate' and v.body_md5 = md5(p.system_text) and v.model_identifier = p.model and security.aer_v3_eval_version_v1(v.id);
  if n <> 3 then raise exception 'post-check: % AER v3 instruction versions match their prompt rows (expected 3)', n; end if;
  if exists (select 1 from pipeline.ai_instruction_versions v where v.code = 'aer-v2-course' and v.model_identifier ilike '%gpt-4.1-mini%') then raise exception 'post-check: no GPT-4.1 mini'; end if;
  select count(*) into n from pipeline.ai_improvement_proposals where code like 'aer-v2-course-v3-%' and status = 'proposed' and eval_set_id = v_set;
  if n <> 3 then raise exception 'post-check: % proposals (expected 3, proposed)', n; end if;
  if exists (select 1 from pipeline.ai_eval_runs x where security.aer_v3_eval_version_v1(x.version_id)) then raise exception 'post-check: no AER v3 run is opened'; end if;
  if exists (select 1 from pipeline.ai_route_qualifications where service_code = 'entry_requirements_v2_shadow' and status = 'qualified') then raise exception 'post-check: no model qualified'; end if;
  if security.pipeline_num_v1('aer.v2_shadow_on', 0) <> 0 or security.pipeline_num_v1('ai_eval.offline_runs_on', 0) <> 0 or security.pipeline_num_v1('ai_eval.aer_v3_runs_on', 0) <> 0 then
    raise exception 'post-check: the shadow reader, offline runs and AER v3 runs stay off';
  end if;
  if public.svc_aer_v3_eval_next_v1()->>'run' is not null then raise exception 'post-check: nothing to lease'; end if;
  if jsonb_array_length(security.toolset_setting('pipeline', 'aer.v2_shadow_probe_courses')) <> 28 then raise exception 'post-check: 28 probe courses'; end if;
  if (select count(*) from pipeline.component_register where name in ('pipeline.aer_v2_eval_cases', 'pipeline.aer_v2_eval_plans') and status = 'retiring') <> 2 then
    raise exception 'post-check: the #1137 tables are retiring';
  end if;
end $k$;
