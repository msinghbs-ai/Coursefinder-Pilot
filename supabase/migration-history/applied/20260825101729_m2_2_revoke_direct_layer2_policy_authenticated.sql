revoke execute on function public.layer2_ops_policy_update(uuid, uuid, jsonb) from authenticated;
revoke execute on function public.layer2_ops_policy_update(uuid, uuid, jsonb) from anon;
grant execute on function public.layer2_ops_policy_update(uuid, uuid, jsonb) to service_role;
