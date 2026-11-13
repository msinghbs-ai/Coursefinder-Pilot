CREATE OR REPLACE FUNCTION security.ai_model_pinned_ok_v1(p_model text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(p_model, '') ~ '^[a-z0-9][a-z0-9._-]*/[a-zA-Z0-9][a-zA-Z0-9._:-]*$'
     and p_model !~* '(^openrouter/|(^|[/:._-])auto([/:._-]|$)|router)'
     and (exists (select 1 from pipeline.scholarship_ai_models m where m.model_identifier = p_model and m.status in ('active', 'candidate'))
       or exists (select 1 from pipeline.layer3_model_profiles l where l.model_identifier = p_model and l.retired_at is null)
       or exists (select 1 from pipeline.central_ai_settings c where c.model_identifier = p_model)
       or exists (select 1 from pipeline.platform_toolset_settings s where s.kind = 'text' and s.key ~ 'model$' and s.value #>> '{}' = p_model))
$function$
