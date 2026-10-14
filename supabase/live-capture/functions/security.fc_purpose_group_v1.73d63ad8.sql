CREATE OR REPLACE FUNCTION security.fc_purpose_group_v1(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case when p = 'course_link_search' then 'course_search'
              when p like 'sch\_%' then 'scholarships'
              when p in ('central_map', 'central_scrape') or p like 'provider\_facts%' then 'central'
              when p in ('scrape', 'fc_read', 'fc_probe', 'site_hint', 'adapter_builder') or p like 'fcx\_%' then 'reads'
              else 'other' end
$function$
