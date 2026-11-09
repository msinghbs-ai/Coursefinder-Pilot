CREATE OR REPLACE FUNCTION api.website_v2_institution_type_code(p_provider_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select t.code from catalogue.providers p join ref.provider_types t on t.id = p.provider_type_id where p.id = p_provider_id
$function$
