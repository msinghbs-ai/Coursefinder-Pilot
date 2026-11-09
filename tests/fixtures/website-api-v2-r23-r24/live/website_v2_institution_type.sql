CREATE OR REPLACE FUNCTION api.website_v2_institution_type(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object('code', t.code, 'name', t.name, 'basis', p.provider_type_basis)
  from catalogue.providers p join ref.provider_types t on t.id = p.provider_type_id where p.id = p_provider_id
$function$
