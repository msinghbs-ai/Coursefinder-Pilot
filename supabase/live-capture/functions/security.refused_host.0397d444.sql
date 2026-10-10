CREATE OR REPLACE FUNCTION security.refused_host(p_url text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(substring(coalesce(p_url, '') from '^https?://([^/?#]+)') ~* nullif(btrim(coalesce(security.firecrawl_setting('refused_host_pattern') #>> '{}', '')), ''), false)
$function$
