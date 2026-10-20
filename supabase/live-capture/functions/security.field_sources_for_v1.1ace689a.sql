CREATE OR REPLACE FUNCTION security.field_sources_for_v1(p_country text, p_field text)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select r.sources from pipeline.field_source_rules r where r.country_code = upper(coalesce(p_country, '')) and r.field = p_field),
                  (select r.sources from pipeline.field_source_rules r where r.country_code = 'ALL' and r.field = p_field), '{}'::text[])
$function$
