-- CF-247 v2.15.240 follow-up (S4): the first hourly automatic publish (15:29 UTC, 11 Oct 2026 Melbourne) stopped at the database's
-- statement time limit while it took the before-and-after snapshot of the consumer APIs that every publication batch records
-- (zoho_course_search_v2 inside security.consumer_api_snapshot_v1). The automatic publish now runs with a 5-minute limit, as a
-- Platform Admin's publish from the screen effectively does. Nothing else changes; nothing is dropped or deleted.
do $guard$
begin
  if to_regprocedure('security.scholarship_auto_publish_v1()') is null then raise exception 'security.scholarship_auto_publish_v1() not found'; end if;
end $guard$;
alter function security.scholarship_auto_publish_v1() set statement_timeout to '300s';
do $post$
begin
  if not exists (select 1 from pg_proc where oid = 'security.scholarship_auto_publish_v1()'::regprocedure and 'statement_timeout=300s' = any(proconfig)) then
    raise exception 'CF-247 post-check: statement_timeout not set on security.scholarship_auto_publish_v1()';
  end if;
end $post$;
