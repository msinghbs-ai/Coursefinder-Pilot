CREATE OR REPLACE FUNCTION public.admin_automations_read()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$ select security.admin_automations_read_v1() $function$
