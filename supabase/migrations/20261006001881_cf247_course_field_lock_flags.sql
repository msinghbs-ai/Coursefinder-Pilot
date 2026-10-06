create or replace function security.course_field_lock_flags_v1() returns table (entity_id uuid, li boolean, le boolean, lf boolean)
language sql stable security definer set search_path = ''
as $f$
  select l.entity_id, bool_or(l.field in ('intakes','intake')), bool_or(l.field in ('english','english_requirements')), bool_or(l.field in ('tuition','fee','fees'))
    from pipeline.manual_locks l where l.entity = 'course' group by l.entity_id
$f$;
revoke all on function security.course_field_lock_flags_v1() from public, anon, authenticated;