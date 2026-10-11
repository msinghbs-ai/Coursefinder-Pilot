CREATE OR REPLACE FUNCTION security.scholarship_publishability_v1()
 RETURNS TABLE(scholarship_id uuid, publishable boolean, missing text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline'
AS $function$
  select * from security.scholarship_publishability_for_v1(null)
$function$
