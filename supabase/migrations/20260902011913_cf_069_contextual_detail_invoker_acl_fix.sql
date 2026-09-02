-- CF-CHG-20260902-069
-- Course/Provider detail and contextual comparison ACL correction.
-- Restores authenticated execution required by SECURITY INVOKER public.admin_read.
-- The helpers remain read-only SECURITY DEFINER functions with their own auth.uid()
-- and role-rank checks. anon/public remain denied.
begin;

revoke all on function security.admin_contextual_insights_v2(text,uuid) from public,anon;
grant execute on function security.admin_contextual_insights_v2(text,uuid) to authenticated,service_role;

revoke all on function security.admin_contextual_compare(jsonb) from public,anon;
grant execute on function security.admin_contextual_compare(jsonb) to authenticated,service_role;

commit;
