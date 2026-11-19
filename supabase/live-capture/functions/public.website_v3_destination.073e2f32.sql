CREATE OR REPLACE FUNCTION public.website_v3_destination(p_filters jsonb DEFAULT '{}'::jsonb, p_page integer DEFAULT 1, p_page_size integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ select security.destination_read_v1(p_filters, p_page, p_page_size) $function$
