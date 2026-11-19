CREATE OR REPLACE FUNCTION security.provider_description_identity_snapshot_v1(p_provider uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select jsonb_strip_nulls(jsonb_build_object('canonical_name',p.canonical_name,'display_name',p.display_name,'provider_type_id',p.provider_type_id,'country_id',p.country_id,'website',p.website))
 from catalogue.providers p where p.id=p_provider
$function$
