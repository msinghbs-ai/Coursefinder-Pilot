CREATE OR REPLACE FUNCTION security.ops_remedy_guard_active_v1()
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce(current_setting('cf247.ops_remedy', true), '') = 'on'
$function$

