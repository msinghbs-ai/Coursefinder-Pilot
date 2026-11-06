CREATE OR REPLACE FUNCTION security.pipeline_list_v1(p_key text, p_default jsonb DEFAULT '[]'::jsonb)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select array(select jsonb_array_elements_text(coalesce(
           (select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key and jsonb_typeof(s.value) = 'array'),
           case when jsonb_typeof(p_default) = 'array' then p_default else '[]'::jsonb end)))
$function$

