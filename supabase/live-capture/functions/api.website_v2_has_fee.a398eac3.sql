CREATE OR REPLACE FUNCTION api.website_v2_has_fee(p_opts jsonb, p_reg numeric)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'api'
AS $function$
  select api.website_v2_latest_fee(p_opts) is not null or coalesce(p_reg,0) >= 1000
$function$
