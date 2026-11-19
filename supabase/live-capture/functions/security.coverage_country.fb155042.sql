CREATE OR REPLACE FUNCTION security.coverage_country(p_provider_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select k.iso_alpha2::text from catalogue.providers p join ref.countries k on k.id = p.country_id where p.id = p_provider_id
$function$
