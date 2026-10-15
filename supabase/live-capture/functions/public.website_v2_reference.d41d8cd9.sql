CREATE OR REPLACE FUNCTION public.website_v2_reference()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'search', 'ref', 'catalogue', 'scholarship', 'security', 'api'
AS $function$
  select coalesce((select c.payload - 'generated_at' || jsonb_build_object('generated_at', c.built_at) from pipeline.website_reference_cache c where c.id = 1),
                  api.website_v2_reference_build())  -- 15 Oct 2026: the copy built every 15 minutes (job website-reference-cache); live only when none
$function$
