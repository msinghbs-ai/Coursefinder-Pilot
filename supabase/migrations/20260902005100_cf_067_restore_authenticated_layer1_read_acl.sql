begin;
revoke execute on function security.admin_layer1_operations_read(jsonb) from public,anon;
grant execute on function security.admin_layer1_operations_read(jsonb) to authenticated,service_role;
commit;