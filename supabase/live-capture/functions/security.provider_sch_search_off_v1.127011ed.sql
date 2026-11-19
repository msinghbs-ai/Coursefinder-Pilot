CREATE OR REPLACE FUNCTION security.provider_sch_search_off_v1(p_provider uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (select 1 from pipeline.provider_scholarship_search f where f.provider_id = p_provider and not f.enabled)
$function$
