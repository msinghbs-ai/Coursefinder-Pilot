CREATE OR REPLACE FUNCTION public.admin_api_usage_refresh()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.current_role_rank() < 4 then raise exception 'pipeline_operator role required' using errcode = '42501'; end if;
  return security.api_usage_refresh_v1('on_demand');
end $function$
