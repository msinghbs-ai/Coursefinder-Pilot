create or replace function security.course_field_source_prune_v1() returns integer
language plpgsql security definer set search_path = ''
as $f$
declare v_n integer;
begin
  delete from pipeline.course_field_source s where not exists (select 1 from catalogue.courses c where c.id = s.course_id and c.lifecycle_status = 'active');
  get diagnostics v_n = row_count;
  return v_n;
end $f$;
revoke all on function security.course_field_source_prune_v1() from public, anon, authenticated;
select cron.schedule('course-field-source-build', '55 * * * *', 'select security.course_field_source_build_v1(); select security.course_field_source_prune_v1()');