CREATE OR REPLACE FUNCTION public.layer3_holdout_finalise_service(p_run_label text, p_binding_hash text, p_summary jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
declare p pipeline.layer3_model_profiles%rowtype; v_set text; v_task text; v_frozen text; v_digest text; v_all int; v_n int; v_stated int; v_exact int; v_ns int; v_ns_exact int;
        v_wrong int; v_withheld int; v_incomplete int; v_nsos int; v_cost numeric; v_in int; v_out int; v_calls int; v_lat int; v_text_ok boolean; v_models text[];
        v_model_ok boolean; v_rate numeric; v_pass boolean; v_run uuid; v_q jsonb;
begin
  perform public.layer3_routing_service_guard();
  if p_binding_hash is null or p_binding_hash !~ '^[0-9a-f]{64}$' then raise exception 'binding hash required'; end if;
  if (select count(distinct profile_id) from pipeline.layer3_holdout_results where run_label=p_run_label)<>1 then raise exception 'run must have exactly one profile'; end if;
  if (select count(distinct c.gold_set) from pipeline.layer3_holdout_results r join pipeline.layer3_holdout_cases c on c.id=r.case_id where r.run_label=p_run_label)<>1 then raise exception 'run must cover exactly one gold set'; end if;
  select * into p from pipeline.layer3_model_profiles where id=(select profile_id from pipeline.layer3_holdout_results where run_label=p_run_label limit 1) for update;
  select c.gold_set, c.task_class into v_set, v_task from pipeline.layer3_holdout_results r join pipeline.layer3_holdout_cases c on c.id=r.case_id where r.run_label=p_run_label limit 1;
  select digest into v_frozen from pipeline.layer3_holdout_sets where gold_set=v_set;
  v_digest:=pipeline.layer3_holdout_digest(v_set);
  select count(*) into v_all from pipeline.layer3_holdout_cases where gold_set=v_set;
  select count(*),
         count(*) filter (where c.gold->>'status' in ('months','stated','admit')),
         count(*) filter (where c.gold->>'status' in ('months','stated','admit') and r.outcome='exact'),
         count(*) filter (where c.gold->>'status' not in ('months','stated','admit')),
         count(*) filter (where c.gold->>'status' not in ('months','stated','admit') and r.outcome='exact_not_stated'),
         count(*) filter (where r.outcome='wrong_admitted'), count(*) filter (where r.outcome='withheld'),
         count(*) filter (where r.outcome='incomplete'), count(*) filter (where r.outcome='not_stated_on_stated'),
         coalesce(sum(r.cost_usd),0), coalesce(sum(r.input_tokens),0), coalesce(sum(r.output_tokens),0), coalesce(sum(r.external_calls),0), coalesce(max(r.latency_ms),0),
         bool_and(coalesce(r.text_matches_gold,false) and coalesce(r.excerpt_in_text,true))
    into v_n, v_stated, v_exact, v_ns, v_ns_exact, v_wrong, v_withheld, v_incomplete, v_nsos, v_cost, v_in, v_out, v_calls, v_lat, v_text_ok
    from pipeline.layer3_holdout_results r join pipeline.layer3_holdout_cases c on c.id=r.case_id where r.run_label=p_run_label;
  v_models:=array(select distinct coalesce(returned_model,'<none>') from pipeline.layer3_holdout_results where run_label=p_run_label and external_calls>0 order by 1);
  v_model_ok:=coalesce(array_length(v_models,1),0)>0 and not exists (select 1 from unnest(v_models) m where m<>p.model_identifier);
  v_rate:=case when v_stated>0 then round(v_exact::numeric/v_stated,4) end;
  v_pass:=v_frozen is not null and v_frozen=v_digest and v_n=v_all and v_stated>0 and coalesce(v_rate,0)>=0.95 and v_wrong=0 and v_model_ok and coalesce(v_text_ok,false);
  v_q:=jsonb_build_object('run_label',p_run_label,'pass',v_pass,'task_class',v_task,'gold_set',v_set,'gold_digest',v_frozen,'gold_unchanged',v_frozen=v_digest,
      'binding_hash',p_binding_hash,'configured_model',p.model_identifier,'returned_models',v_models,'model_exact',v_model_ok,'text_pinned',coalesce(v_text_ok,false),
      'cases',v_n,'gold_cases',v_all,'stated_cases',v_stated,'stated_exact',v_exact,'stated_exact_rate',v_rate,'not_stated_cases',v_ns,'not_stated_exact',v_ns_exact,
      'wrong_admitted',v_wrong,'withheld',v_withheld,'incomplete',v_incomplete,'not_stated_on_stated',v_nsos,
      'cost_usd',v_cost,'cost_per_call_usd',case when v_calls>0 then round(v_cost/v_calls,6) end,'input_tokens',v_in,'output_tokens',v_out,'external_calls',v_calls,'max_latency_ms',v_lat,
      'summary',coalesce(p_summary,'{}'::jsonb),'completed_at',now(),
      'qualification_rule','>=95% exact on stated cases AND zero wrong-admitted values (fresh holdout, pinned model)','change_control_ref','CF-CHG-20260915-247');
  insert into pipeline.layer3_quality_benchmark_runs(profile_id,actor_id,status,provider_case_results,control_case_results,configured_model,returned_models,external_call_count,input_tokens,output_tokens,
    estimated_cost_usd,max_latency_ms,evidence_ids,binding_hash,prompt_profile_version,validator_profile,summary,change_control_ref,uat_ref,completed_at)
  select p.id,'00000000-0000-0000-0000-000000000000'::uuid,case when v_pass then 'pass' else 'fail' end,
    coalesce((select jsonb_agg(jsonb_build_object('case_key',c.case_key,'gold',c.gold,'outcome',r.outcome,'admitted',r.admitted,'errors',r.errors) order by c.case_key)
      from pipeline.layer3_holdout_results r join pipeline.layer3_holdout_cases c on c.id=r.case_id where r.run_label=p_run_label and c.gold->>'status' in ('months','stated','admit')),'[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object('case_key',c.case_key,'gold',c.gold,'outcome',r.outcome,'admitted',r.admitted,'errors',r.errors) order by c.case_key)
      from pipeline.layer3_holdout_results r join pipeline.layer3_holdout_cases c on c.id=r.case_id where r.run_label=p_run_label and c.gold->>'status' not in ('months','stated','admit')),'[]'::jsonb),
    p.model_identifier,v_models,v_calls,v_in,v_out,v_cost,v_lat,
    coalesce((select array_agg(distinct c.evidence_id) from pipeline.layer3_holdout_results r join pipeline.layer3_holdout_cases c on c.id=r.case_id where r.run_label=p_run_label),'{}'),
    p_binding_hash,p.prompt_profile_version,coalesce(p.deterministic_validators,'{}'::jsonb),
    left(format('CF-247 model routing holdout %s on %s (%s): stated exact %s/%s (%s); wrong-admitted %s; withheld %s; cost_usd=%s; %s',
      p_run_label,v_set,v_task,v_exact,v_stated,v_rate,v_wrong,v_withheld,round(v_cost,6),case when v_pass then 'PASS' else 'FAIL' end),1000),
    'CF-CHG-20260915-247','CF-247-layer3-model-routing',now()
  returning id into v_run;
  update pipeline.layer3_model_profiles set holdout_qualification=v_q||jsonb_build_object('run_id',v_run), updated_at=now() where id=p.id;
  return v_q||jsonb_build_object('run_id',v_run,'profile_code',p.code);
end $function$
