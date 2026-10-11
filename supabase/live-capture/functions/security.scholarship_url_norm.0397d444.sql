CREATE OR REPLACE FUNCTION security.scholarship_url_norm(p_url text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select regexp_replace(regexp_replace(lower(split_part(btrim(coalesce(p_url,'')),'#',1)),'^http://','https://'),'/+$','')
$function$
