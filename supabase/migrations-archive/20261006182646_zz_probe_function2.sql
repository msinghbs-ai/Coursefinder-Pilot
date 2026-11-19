create or replace function security.zz_probe_v1() returns jsonb
language plpgsql security definer set search_path = ''
as $f$
begin
  delete from pipeline.course_field_source where course_id is not null;
  return '{}'::jsonb;
end $f$;
revoke all on function security.zz_probe_v1() from public, anon, authenticated;
