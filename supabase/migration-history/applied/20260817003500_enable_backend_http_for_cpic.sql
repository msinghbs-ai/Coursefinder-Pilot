create extension if not exists http with schema extensions;
revoke execute on function extensions.http_get(varchar) from public, anon, authenticated;
revoke execute on function extensions.http_post(varchar,varchar,varchar) from public, anon, authenticated;
grant execute on function extensions.http_get(varchar) to service_role;
grant execute on function extensions.http_post(varchar,varchar,varchar) to service_role;
