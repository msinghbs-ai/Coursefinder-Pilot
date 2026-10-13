CREATE OR REPLACE FUNCTION security.automation_batch(p_command text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select coalesce((substring(p_command from '"limit"\s*:\s*(\d+)'))::int, (substring(p_command from '\(\s*(\d+)\s*\)'))::int)
$function$
