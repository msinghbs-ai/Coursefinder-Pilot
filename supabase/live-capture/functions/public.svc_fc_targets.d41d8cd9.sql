CREATE OR REPLACE FUNCTION public.svc_fc_targets()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if not exists (select 1 from pipeline.firecrawl_target_cache c where c.refreshed_at > now() - interval '5 minutes') then perform security.firecrawl_targets_refresh_v1(); end if;
  return jsonb_build_object('target_only', coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true),
                            'ids', coalesce((select jsonb_agg(c.provider_id) from pipeline.firecrawl_target_cache c where c.included), '[]'::jsonb));
end $function$
