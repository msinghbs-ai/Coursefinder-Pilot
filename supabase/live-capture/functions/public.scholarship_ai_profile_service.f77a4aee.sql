CREATE OR REPLACE FUNCTION public.scholarship_ai_profile_service(p_profile_id uuid, p_allow_benchmark_pending boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
declare p pipeline.layer3_model_profiles%rowtype;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select * into p from pipeline.layer3_model_profiles where id=p_profile_id;
 if not found then raise exception 'profile not found'; end if;
 if not p.enabled then raise exception 'profile disabled'; end if;
 if not p_allow_benchmark_pending and (p.paused or coalesce((p.quality_benchmark->>'pass')::boolean,false) is not true) then raise exception 'profile not qualified'; end if;
 return jsonb_build_object('id',p.id,'code',p.code,'aggregator_provider',p.aggregator_provider,'base_url',p.base_url,'model_identifier',p.model_identifier,'secret_env_key',p.secret_env_key,'prompt_profile_version',p.prompt_profile_version,'prompt_system',p.prompt_system,'validators',p.deterministic_validators,'max_input_tokens',p.max_input_tokens,'max_output_tokens',p.max_output_tokens,'retry_ceiling',p.retry_ceiling,'timeout_ms',p.timeout_ms,'cost_ceiling_usd',p.cost_ceiling_usd,'benchmark_pass',coalesce((p.quality_benchmark->>'pass')::boolean,false),'paused',p.paused);
end $function$
