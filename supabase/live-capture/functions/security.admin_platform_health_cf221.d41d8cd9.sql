CREATE OR REPLACE FUNCTION security.admin_platform_health_cf221()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security', 'scholarship'
AS $function$
declare v_rank int:=security.scholarship_ai_role_rank(); v_failed int; v_running int; v_completed int; v_ev24 bigint; v_attempts bigint; v_calls bigint; v_cost numeric; v_sch bigint; v_active_ai bigint;
begin
 if v_rank<1 then raise exception 'authenticated role required' using errcode='42501'; end if;
 select count(*) filter(where status='failed' and created_at>=now()-interval '24 hours'),count(*) filter(where status in ('queued','running')),count(*) filter(where status in ('completed','succeeded') and created_at>=now()-interval '24 hours') into v_failed,v_running,v_completed from pipeline.jobs;
 select count(*) into v_ev24 from pipeline.evidence_artifacts where created_at>=now()-interval '24 hours';
 select count(*) into v_attempts from pipeline.layer2_provider_attempts where created_at>=now()-interval '24 hours';
 select coalesce(sum(external_call_count),0),coalesce(sum(estimated_cost_usd),0) into v_calls,v_cost from pipeline.layer3_interpretations where created_at>=now()-interval '24 hours';
 select count(*) into v_sch from scholarship.scholarships;
 select count(*) into v_active_ai from pipeline.scholarship_ai_runs where status in ('queued','running');
 return jsonb_strip_nulls(jsonb_build_object(
   'overall_status',case when v_failed>0 then 'attention' when v_running>0 then 'active' else 'healthy' end,
   'jobs',jsonb_build_object('running',v_running,'failed_24h',v_failed,'completed_24h',v_completed),
   'data',jsonb_build_object('evidence_fetched_24h',v_ev24,'scholarships',v_sch),
   'edge_runtime',jsonb_build_object('status',case when v_failed>0 then 'attention' else 'healthy' end,'active_workloads',v_running,'completed_24h',v_completed),
   'api_activity',case when v_rank>=4 then jsonb_build_object('layer2_provider_requests_24h',v_attempts,'layer3_external_calls_24h',v_calls,'layer3_cost_24h_usd',v_cost) else null end,
   'scholarship_ai',case when v_rank>=3 then jsonb_build_object('active_runs',v_active_ai,'profiles_staged',(select count(*) from pipeline.layer3_model_profiles where code like 'openrouter-scholarship-%'),'profiles_qualified',(select count(*) from pipeline.layer3_model_profiles where code like 'openrouter-scholarship-%' and coalesce((quality_benchmark->>'pass')::boolean,false))) else null end,
   'security',case when v_rank>=6 then jsonb_build_object('status','reviewed_with_existing_findings','note','Security Advisor remains the authority; no CF-221 finding is asserted by this runtime snapshot.') else null end,
   'observed_at',now()
 ));
end $function$
