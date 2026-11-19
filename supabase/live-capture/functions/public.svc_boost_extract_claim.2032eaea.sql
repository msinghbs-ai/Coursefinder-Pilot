CREATE OR REPLACE FUNCTION public.svc_boost_extract_claim(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return security.boost_extract_claim_v1(p_limit);
end $function$
