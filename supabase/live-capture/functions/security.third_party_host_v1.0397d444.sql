CREATE OR REPLACE FUNCTION security.third_party_host_v1(p_url text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select bool_or(case when l.domain like '%.%' then h = l.domain or h like '%.' || l.domain else h ~ ('(^|\.)' || l.domain) end)
                     from pipeline.important_links l, (select security.site_host_v1(p_url) h) x
                    where x.h is not null and l.enabled and l.retired_at is null and l.domain is not null and 'not_provider_site' = any(l.uses)
                      and l.authority_category in ('third_party_directory', 'general_web', 'ranking_publisher')), false)
$function$
