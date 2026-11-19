CREATE OR REPLACE FUNCTION security.ranking_country_id(p text)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select c.id from ref.countries c
   where lower(c.name) = lower(btrim(p)) or lower(c.iso_alpha2::text) = lower(btrim(p)) or lower(c.iso_alpha3::text) = lower(btrim(p))
   order by (lower(c.name) = lower(btrim(p))) desc limit 1
$function$
