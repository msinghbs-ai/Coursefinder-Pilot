CREATE OR REPLACE FUNCTION public.website_v3_reference()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ select public.website_v2_reference() $function$
