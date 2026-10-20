CREATE OR REPLACE FUNCTION public.layer3_holdout_results_service(p_gold_set text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
begin
  perform public.layer3_routing_service_guard();
  return coalesce((select jsonb_agg(jsonb_build_object('run_label',r.run_label,'case_id',r.case_id,'case_key',c.case_key,'profile_id',r.profile_id,'profile_code',p.code,
      'configured_model',r.configured_model,'returned_model',r.returned_model,'outcome',r.outcome,'admitted',r.admitted,'answer',r.answer,'errors',r.errors,
      'cost_usd',r.cost_usd,'external_calls',r.external_calls,'cascade_tier_no',r.cascade_tier_no,'escalation_reasons',r.escalation_reasons,'cascade_final',r.cascade_final)
      order by r.run_label, c.case_key)
    from pipeline.layer3_holdout_results r join pipeline.layer3_holdout_cases c on c.id=r.case_id join pipeline.layer3_model_profiles p on p.id=r.profile_id
   where c.gold_set=p_gold_set),'[]'::jsonb);
end $function$
