CREATE OR REPLACE FUNCTION security.url_on_provider_site(p_url text, p_site text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'security'
AS $function$
  select coalesce(security.url_base_host(p_url) = security.url_base_host(p_site)
      or lower(substring(p_url from '^[a-zA-Z]+://([^/:?#]+)')) like '%.' || security.url_base_host(p_site), false)
$function$
