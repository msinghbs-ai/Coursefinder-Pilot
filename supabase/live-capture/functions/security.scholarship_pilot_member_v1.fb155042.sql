CREATE OR REPLACE FUNCTION security.scholarship_pilot_member_v1(p_provider_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select p_provider_id is not null and exists (
    select 1 from pipeline.platform_toolset_settings s, jsonb_array_elements_text(case when jsonb_typeof(s.value) = 'array' then s.value else '[]'::jsonb end) x(id)
     where s.toolset_key = 'pipeline' and s.key = 'scholarship.pilot_provider_ids' and lower(btrim(x.id)) = p_provider_id::text)
$function$
