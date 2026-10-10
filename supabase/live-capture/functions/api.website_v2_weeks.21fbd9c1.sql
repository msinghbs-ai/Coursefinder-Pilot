CREATE OR REPLACE FUNCTION api.website_v2_weeks(p_value numeric, p_unit text)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select case lower(coalesce(p_unit,'')) when 'weeks' then p_value when 'months' then p_value*52/12.0 when 'years' then p_value*52 end
$function$
