CREATE OR REPLACE FUNCTION security.fc_on_demand_today_v1()
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(sum(x.units), 0) from pipeline.coverage_vendor_usage x where x.on_demand_run is not null and x.at >= security.fc_day_start_v1()
$function$
