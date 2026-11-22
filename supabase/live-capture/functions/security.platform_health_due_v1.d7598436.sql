CREATE OR REPLACE FUNCTION security.platform_health_due_v1(p_key text, p_force boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
  select p_force or coalesce((select c.checked_at is null
                                  or c.checked_at <= now() - make_interval(mins=>c.cadence_minutes) + least(interval '3 minutes', make_interval(mins=>c.cadence_minutes)*0.3)
                               from pipeline.platform_health_checks c where c.key=p_key), true)
$function$
