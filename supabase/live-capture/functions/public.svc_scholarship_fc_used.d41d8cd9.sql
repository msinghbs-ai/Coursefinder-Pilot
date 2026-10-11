CREATE OR REPLACE FUNCTION public.svc_scholarship_fc_used()
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
  select coalesce(sum(units),0) from pipeline.coverage_vendor_usage where purpose in ('sch_map','sch_search','sch_scrape')
$function$
