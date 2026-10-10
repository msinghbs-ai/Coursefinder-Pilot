CREATE OR REPLACE FUNCTION public.svc_uni_adapters()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return coalesce((select jsonb_object_agg(a.provider_id::text, security.uni_adapter_json(a.provider_id)) from pipeline.uni_adapters a where a.enabled), '{}'::jsonb);
end $function$
