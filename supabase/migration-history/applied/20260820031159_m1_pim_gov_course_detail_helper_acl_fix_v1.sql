revoke execute on function security.admin_course_entry_summary(uuid) from public, anon;
revoke execute on function security.admin_course_taxonomy_summary(uuid) from public, anon;
grant execute on function security.admin_course_entry_summary(uuid) to authenticated, service_role;
grant execute on function security.admin_course_taxonomy_summary(uuid) to authenticated, service_role;
