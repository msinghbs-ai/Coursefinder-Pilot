CREATE OR REPLACE FUNCTION security.scholarship_ai_control_read_impl(p_country_code text DEFAULT 'AU'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'scholarship', 'security'
AS $function$
declare v_rank int:=security.scholarship_ai_role_rank(); v_country text:=upper(coalesce(nullif(p_country_code,''),'AU')); v_result jsonb;
begin
 if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
 select jsonb_build_object(
   'country_code',v_country,
   'role_rank',v_rank,
   'settings',(select to_jsonb(s)-'schedule_actor'-'updated_by' from pipeline.scholarship_ai_settings s where s.country_code=v_country),
   'profiles',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.code,'model_identifier',p.model_identifier,'enabled',p.enabled,'paused',p.paused,'benchmark_pass',coalesce((p.quality_benchmark->>'pass')::boolean,false),'benchmark_state',coalesce(p.quality_benchmark->>'state',p.last_validation_result->>'state'),'cost_ceiling_usd',p.cost_ceiling_usd,'requests_per_minute',p.requests_per_minute,'requests_per_day',p.requests_per_day) order by p.code) from pipeline.layer3_model_profiles p where p.code like 'openrouter-scholarship-%'), '[]'::jsonb),
   'queue',jsonb_build_object(
      'unclassified',(select count(*) from pipeline.layer2_scholarship_discovery_candidates c where c.evidence_id is not null and c.classification is null),
      'needs_review',(select count(*) from pipeline.layer2_scholarship_discovery_candidates c where c.evidence_id is not null and c.classification='needs_review'),
      'detail_ready',(select count(*) from pipeline.layer2_scholarship_discovery_candidates c where c.evidence_id is not null and c.classification='detail_ready')
   ),
   'telemetry',jsonb_build_object(
      'runs_total',(select count(*) from pipeline.scholarship_ai_runs r where r.country_code=v_country),
      'runs_active',(select count(*) from pipeline.scholarship_ai_runs r where r.country_code=v_country and r.status in ('queued','running')),
      'processed',(select coalesce(sum(r.processed_items),0) from pipeline.scholarship_ai_runs r where r.country_code=v_country),
      'api_calls',(select coalesce(sum(r.api_calls),0) from pipeline.scholarship_ai_runs r where r.country_code=v_country),
      'input_tokens',(select coalesce(sum(r.input_tokens),0) from pipeline.scholarship_ai_runs r where r.country_code=v_country),
      'output_tokens',(select coalesce(sum(r.output_tokens),0) from pipeline.scholarship_ai_runs r where r.country_code=v_country),
      'cost_usd',(select coalesce(sum(r.cost_usd),0) from pipeline.scholarship_ai_runs r where r.country_code=v_country),
      'today_cost_usd',(select coalesce(sum(r.cost_usd),0) from pipeline.scholarship_ai_runs r where r.country_code=v_country and r.created_at>=date_trunc('day',now()))
   ),
   'recent_runs',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,country_code,task_class,profile_id,trigger_mode,changes_only,status,total_items,processed_items,validated_items,review_items,no_candidate_items,failed_items,api_calls,input_tokens,output_tokens,cost_usd,started_at,completed_at,created_at from pipeline.scholarship_ai_runs where country_code=v_country order by created_at desc limit 12) x),'[]'::jsonb)
 ) into v_result;
 return v_result;
end $function$
