CREATE OR REPLACE FUNCTION public.svc_website_settings_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return jsonb_build_object('logo_link_days', security.pipeline_num_v1('website.logo_link_days', 365),
                            'logo_renew_before_days', security.pipeline_num_v1('website.logo_renew_before_days', 30),
                            'sync_page_max', security.pipeline_num_v1('website.sync_page_max', 50));
end $function$
