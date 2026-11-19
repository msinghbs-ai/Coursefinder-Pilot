-- CF-CHG-20260915-247
-- Multi-model support foundation: accept an optional p_profile_code
-- parameter, defaulting to the original hardcoded value, so a different
-- candidate model profile can be benchmarked without touching the default
-- caller. No gating/authority logic changes; purely additive parameter.
CREATE OR REPLACE FUNCTION public.layer3_cf245_tuition_benchmark_profile_service(
  p_profile_code text default 'openrouter-provider-tuition-validation-v1'
)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
declare p pipeline.layer3_model_profiles%rowtype;
begin
  if current_user not in ('postgres','service_role') and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
  select * into p from pipeline.layer3_model_profiles where code=coalesce(nullif(trim(p_profile_code),''),'openrouter-provider-tuition-validation-v1');
  if not found then raise exception 'CF-245 tuition validation profile not found'; end if;
  return jsonb_build_object(
    'id',p.id,'code',p.code,'aggregator_provider',p.aggregator_provider,'base_url',p.base_url,'model_identifier',p.model_identifier,
    'secret_env_key',p.secret_env_key,'prompt_profile_version',p.prompt_profile_version,'prompt_system',p.prompt_system,
    'structured_output_schema',p.structured_output_schema,'deterministic_validators',p.deterministic_validators,
    'max_input_tokens',p.max_input_tokens,'max_output_tokens',p.max_output_tokens,'requests_per_minute',p.requests_per_minute,
    'requests_per_day',p.requests_per_day,'retry_ceiling',p.retry_ceiling,'timeout_ms',p.timeout_ms,'cost_ceiling_usd',p.cost_ceiling_usd,
    'enabled',p.enabled,'paused',p.paused,'quality_benchmark',p.quality_benchmark,'change_control_ref',p.change_control_ref
  );
end $function$;
