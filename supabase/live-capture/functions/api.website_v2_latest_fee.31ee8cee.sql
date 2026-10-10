CREATE OR REPLACE FUNCTION api.website_v2_latest_fee(p_opts jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select o from jsonb_array_elements(coalesce(p_opts,'[]'::jsonb)) o
  where (o->>'amount') ~ '^[0-9]+(\.[0-9]+)?$' and (o->>'amount')::numeric >= 1000
  order by nullif(o->>'fee_year','')::int desc nulls last limit 1
$function$
