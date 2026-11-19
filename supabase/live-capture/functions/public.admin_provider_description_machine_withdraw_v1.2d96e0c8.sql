CREATE OR REPLACE FUNCTION public.admin_provider_description_machine_withdraw_v1(p_provider uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) is needed to withdraw a machine description' using errcode = '42501'; end if; -- fixed: rank 6 is the Platform Admin role
  return security.provider_description_machine_withdraw_v1(p_provider, p_reason, auth.uid());
end $function$
