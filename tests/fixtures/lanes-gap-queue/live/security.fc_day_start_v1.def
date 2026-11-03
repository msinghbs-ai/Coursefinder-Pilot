CREATE OR REPLACE FUNCTION security.fc_day_start_v1()
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select date_trunc('day', now() at time zone 'Australia/Melbourne') at time zone 'Australia/Melbourne'
$function$
