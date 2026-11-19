CREATE OR REPLACE FUNCTION public.website_v3_rankings(p_filters jsonb, p_page integer, p_page_size integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ select public.website_v2_rankings(p_filters, p_page, p_page_size) $function$
