CREATE OR REPLACE FUNCTION public.admin_scholarship_publishing_read()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$ select security.admin_scholarship_publishing_read_v1() $function$
