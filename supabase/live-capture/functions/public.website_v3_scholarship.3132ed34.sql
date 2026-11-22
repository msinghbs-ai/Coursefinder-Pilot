CREATE OR REPLACE FUNCTION public.website_v3_scholarship(p_scholarship_id text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select public.website_v3_scholarship(p_scholarship_id, null::jsonb)
$function$
