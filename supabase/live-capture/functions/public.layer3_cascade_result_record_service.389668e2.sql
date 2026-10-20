CREATE OR REPLACE FUNCTION public.layer3_cascade_result_record_service(p_run_label text, p_case_id uuid, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
begin
  perform public.layer3_routing_service_guard();
  if p_run_label !~ '^c-' then raise exception 'cascade run labels start with c-'; end if;
  insert into pipeline.layer3_holdout_results(run_label,case_id,profile_id,task_class,configured_model,returned_model,outcome,admitted,answer,errors,text_matches_gold,excerpt_in_text,
    cost_usd,input_tokens,output_tokens,latency_ms,external_calls,cascade_tier_no,escalation_reasons,cascade_final)
  values (p_run_label,p_case_id,(p_result->>'profile_id')::uuid,p_result->>'task_class',p_result->>'configured_model',p_result->>'returned_model',p_result->>'outcome',
    p_result->'admitted',p_result->'answer',coalesce((select array_agg(x) from jsonb_array_elements_text(p_result->'errors') x),'{}'),
    (p_result->>'text_matches_gold')::boolean,(p_result->>'excerpt_in_text')::boolean,greatest(coalesce((p_result->>'cost_usd')::numeric,0),0),
    coalesce((p_result->>'input_tokens')::int,0),coalesce((p_result->>'output_tokens')::int,0),(p_result->>'latency_ms')::int,coalesce((p_result->>'external_calls')::int,0),
    (p_result->>'cascade_tier_no')::int,coalesce((select array_agg(x) from jsonb_array_elements_text(p_result->'escalation_reasons') x),'{}'),(p_result->>'cascade_final')::boolean)
  on conflict (run_label,case_id) do nothing;
  return jsonb_build_object('ok',true,'cascade_test_spent_usd',pipeline.layer3_cascade_test_spent_usd());
end $function$
