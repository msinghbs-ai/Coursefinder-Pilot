CREATE OR REPLACE FUNCTION public.svc_worker_settings_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return (select coalesce(jsonb_object_agg(s.key, s.value), '{}'::jsonb) from pipeline.platform_toolset_settings s
           where s.toolset_key = 'firecrawl' and s.key in ('read_proxy', 'map_limit_course_site', 'map_limit_central', 'map_limit_central_search', 'map_limit_scholarships',
                                                          'search_results_website', 'search_results_register', 'search_results_cricos',
                                                          'search_results_scholarship_search', 'search_results_scholarship_discover'));
end $function$
