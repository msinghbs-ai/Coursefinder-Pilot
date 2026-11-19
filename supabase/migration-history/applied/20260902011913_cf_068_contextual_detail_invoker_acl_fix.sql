-- CF-CHG-20260902-068
-- Restore authenticated execution through the SECURITY INVOKER public.admin_read boundary
-- for CF-061 contextual detail/compare helpers. Helpers retain their own auth + role-rank checks.
begin;

revoke all on function security.admin_contextual_insights_v2(text,uuid) from public,anon;
grant execute on function security.admin_contextual_insights_v2(text,uuid) to authenticated,service_role;

revoke all on function security.admin_contextual_compare(jsonb) from public,anon;
grant execute on function security.admin_contextual_compare(jsonb) to authenticated,service_role;

commit;
