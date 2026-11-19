CREATE OR REPLACE FUNCTION security.url_on_provider_sites(p_url text, p_provider_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
  select coalesce((select security.url_on_provider_site(p_url, coalesce(d.site_origin,d.website)) or security.url_on_provider_site(p_url, d.website)
                          or exists (select 1 from unnest(d.allowed_hosts) h where security.url_on_provider_site(p_url, h))
                     from pipeline.scholarship_discovery_providers d where d.provider_id=p_provider_id), false)
$function$
