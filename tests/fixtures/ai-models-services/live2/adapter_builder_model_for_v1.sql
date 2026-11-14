CREATE OR REPLACE FUNCTION security.adapter_builder_model_for_v1(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce(
    (select jsonb_build_object('code', m.code, 'model', m.model_identifier, 'chosen', true, 'set_at', a.set_at, 'reason', a.reason)
       from pipeline.uni_adapter_models a join pipeline.layer3_model_profiles m on m.code = a.profile_code
      where a.provider_id = p_provider_id and m.enabled and not m.paused and m.retired_at is null),
    jsonb_build_object('code', security.firecrawl_setting('builder_model_profile') #>> '{}', 'model', security.firecrawl_setting('builder_model') #>> '{}', 'chosen', false))
$function$
