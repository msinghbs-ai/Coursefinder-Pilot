CREATE OR REPLACE FUNCTION public.svc_scholarship_fc_budget()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return jsonb_build_object(
    'used', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose in ('sch_map', 'sch_search', 'sch_scrape')),
    'cap', (select s.value from pipeline.scholarship_layer_settings s where s.key = 'firecrawl_cap'),
    'reserve', (select s.value from pipeline.scholarship_layer_settings s where s.key = 'firecrawl_reserve'),
    -- 11 Oct 2026: read scholarship pages through the scraper first (1 = on, 0 = off)
    'scraper', coalesce((select s.value from pipeline.scholarship_layer_settings s where s.key = 'read_via_scraper'), 1));
end $function$
