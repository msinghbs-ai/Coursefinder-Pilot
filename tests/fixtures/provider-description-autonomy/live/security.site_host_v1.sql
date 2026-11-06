CREATE OR REPLACE FUNCTION security.site_host_v1(p_url text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select nullif(lower(regexp_replace(substring(btrim(coalesce(p_url, '')) from '^(?:https?://)?([^/:?#\s]+)'), '^www\.', '')), '')
$function$

