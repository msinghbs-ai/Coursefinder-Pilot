-- CF-247 / Decision 160 (approved 28 Sep 2026, option 1): Layer 3 tuition qualification accepts safe abstention.
-- Before: a model qualified only if every provider case resolved exactly (10 of 10).
-- Now: a model qualifies when
--   * every required safety control passes (unchanged);
--   * no provider case is UNSAFE: an answer that is wrong but would pass the deterministic validators
--     (semantic result false with no validator error) — a wrong answer caught by a validator, a low-confidence
--     answer or a null answer is routed to Layer 4 in production and is SAFE;
--   * no provider case failed for an infrastructure reason (provider HTTP error, unreadable response), so the run
--     is conclusive;
--   * at least half of the provider cases (and at least 3) resolve correctly, so the model is useful.
-- The model and cost checks are unchanged. A passing benchmark still leaves the profile paused: activation stays
-- a separate, deliberate step. Checksum-guarded.
do $patch$
declare d text; n text;
begin
  d:=pg_get_functiondef('public.layer3_cf245_tuition_benchmark_record_service(jsonb,jsonb,text[],integer,integer,integer,numeric,integer,uuid[],text,text,uuid)'::regprocedure);
  if md5(d)<>'33ed315e5208a6b09ba4d195971947bb' then raise exception 'benchmark record service changed since review (%); not patched', md5(d); end if;
  n:=replace(d,
$old$  select coalesce(jsonb_array_length(coalesce(p_provider_cases,'[]'::jsonb))>=3,false)
     and not exists(select 1 from jsonb_array_elements(coalesce(p_provider_cases,'[]'::jsonb)) c where coalesce((c->>'valid')::boolean,false)=false)
    into v_provider_ok;$old$,
$new$  -- Decision 160: safe abstention. Unsafe = wrong but uncaught; infrastructure errors make the run inconclusive.
  select count(*),
         count(*) filter (where coalesce((c->>'valid')::boolean,false) and coalesce((c->>'semantic_result')::boolean,true)),
         count(*) filter (where coalesce((c->>'semantic_result')::boolean,true)=false and jsonb_array_length(coalesce(c->'errors','[]'::jsonb))=0),
         count(*) filter (where exists(select 1 from jsonb_array_elements_text(coalesce(c->'errors','[]'::jsonb)) e
                                        where e ~ '^provider_[0-9]+$' or e ilike '%JSON%' or e='at_least_one_semantic_provider_result_required'))
    into v_cases, v_resolved, v_unsafe, v_infra
    from jsonb_array_elements(coalesce(p_provider_cases,'[]'::jsonb)) c;
  v_provider_ok:=v_cases>=3 and v_unsafe=0 and v_infra=0 and v_resolved>=3 and v_resolved*2>=v_cases;$new$);
  n:=replace(n,'v_cost_ok boolean;v_pass boolean;','v_cost_ok boolean;v_pass boolean;v_cases int:=0;v_resolved int:=0;v_unsafe int:=0;v_infra int:=0;');
  n:=replace(n,$o$'provider_cases_pass',v_provider_ok,'controls_pass',v_controls_ok,'model_exact',v_model_ok,'cost_pass',v_cost_ok,'summary'$o$,
               $o$'provider_cases_pass',v_provider_ok,'provider_cases',v_cases,'resolved',v_resolved,'safe_abstained',v_cases-v_resolved-v_unsafe-v_infra,'unsafe',v_unsafe,'infrastructure_errors',v_infra,'qualification_rule','decision_160_safe_abstention','controls_pass',v_controls_ok,'model_exact',v_model_ok,'cost_pass',v_cost_ok,'summary'$o$);
  n:=replace(n,$o$return jsonb_build_object('ok',true,'pass',v_pass,'run_id',v_run,'profile_paused',true,'provider_cases_pass',v_provider_ok,$o$,
               $o$return jsonb_build_object('ok',true,'pass',v_pass,'run_id',v_run,'profile_paused',true,'provider_cases_pass',v_provider_ok,'resolved',v_resolved,'unsafe',v_unsafe,'infrastructure_errors',v_infra,'provider_cases',v_cases,$o$);
  if (select count(*) from regexp_matches(n,'decision_160_safe_abstention|v_unsafe=0|''unsafe'',v_unsafe','g'))<>4 then raise exception 'patch points not found as expected'; end if;
  execute n;
end $patch$;
