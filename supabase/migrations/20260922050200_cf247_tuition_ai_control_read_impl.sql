-- CF-CHG-20260915-247
-- Read-only model-profile comparison view for the tuition validation
-- task class, following the exact pattern of
-- security.scholarship_ai_control_read_impl. Reuses
-- security.scholarship_ai_role_rank() (a generic role-rank lookup
-- despite its name, no scholarship-specific logic) rather than
-- duplicating an identical check.
--
-- Governance note: applied directly to the live Pilot Supabase project
-- before being committed here; this file brings the checked-in migration
-- history back in sync with what is actually live.
CREATE OR REPLACE FUNCTION security.tuition_ai_control_read_impl()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v_rank int := security.scholarship_ai_role_rank(); v_result jsonb;
begin
  if v_rank < 3 then raise exception 'curator role required' using errcode='42501'; end if;
  select jsonb_build_object(
    'role_rank', v_rank,
    'profiles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'code', p.code,
        'model_identifier', p.model_identifier,
        'enabled', p.enabled,
        'paused', p.paused,
        'benchmark_pass', coalesce((p.quality_benchmark->>'pass')::boolean, false),
        'benchmark_summary', p.quality_benchmark->>'summary',
        'binding_hash', p.quality_benchmark->>'binding_hash',
        'external_call_count', nullif(p.quality_benchmark->>'external_call_count','')::int,
        'estimated_cost_usd', nullif(p.quality_benchmark->>'estimated_cost_usd','')::numeric,
        'completed_at', p.quality_benchmark->>'completed_at',
        'provider_cases_pass', (p.quality_benchmark->>'provider_cases_pass')::boolean,
        'controls_pass', (p.quality_benchmark->>'controls_pass')::boolean,
        'cost_ceiling_usd', p.cost_ceiling_usd
      ) order by p.code)
      from pipeline.layer3_model_profiles p
      where p.code like 'openrouter-provider-tuition-validation%'
    ), '[]'::jsonb)
  ) into v_result;
  return v_result;
end $function$;
