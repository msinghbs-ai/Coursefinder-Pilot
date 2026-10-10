-- CF-CHG-20260825-034
-- Direct browser execution of this privileged SECURITY DEFINER mutation is removed.
-- Authenticated policy changes now traverse the JWT-enforced layer2-config-control Edge Function.

revoke execute on function public.layer2_ops_policy_update(uuid, uuid, jsonb) from authenticated;
revoke execute on function public.layer2_ops_policy_update(uuid, uuid, jsonb) from anon;
grant execute on function public.layer2_ops_policy_update(uuid, uuid, jsonb) to service_role;
