CREATE OR REPLACE FUNCTION public.svc_coverage_firecrawl()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'security'
AS $function$
declare v_id uuid;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  select id into v_id from pipeline.layer2_acquisition_providers where provider_key='firecrawl' and enabled;
  if v_id is null then return jsonb_build_object('enabled',false); end if;
  return public.layer2_provider_runtime_config(v_id);
end $function$
