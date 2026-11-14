CREATE OR REPLACE FUNCTION security.adapter_builder_models_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('code', m.code, 'model', m.model_identifier, 'max_output_tokens', m.max_output_tokens) order by m.model_identifier), '[]'::jsonb)
    from pipeline.layer3_model_profiles m
   where m.enabled and not m.paused and m.retired_at is null and m.aggregator_provider = 'openrouter'
     and 'provider_intake_validation' = any(m.allowed_task_classes)
$function$
