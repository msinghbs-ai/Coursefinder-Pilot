create index if not exists courses_course_code_upper_idx
  on catalogue.courses (upper(course_code))
  where course_code is not null;

alter function security.admin_course_page_fast(jsonb)
  rename to admin_course_page_fast_base;

revoke all on function security.admin_course_page_fast_base(jsonb)
  from public, anon, authenticated;
grant execute on function security.admin_course_page_fast_base(jsonb)
  to service_role;

create or replace function security.admin_course_page_fast(
  p_args jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','security','catalogue','public','auth'
as $function$
declare
  v_q text := nullif(trim(coalesce(p_args->>'query','')), '');
  v_provider_id uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  if security.current_role_rank() < 1 then
    raise exception 'assigned CourseFinder role required' using errcode='42501';
  end if;

  if v_q is not null and v_q ~* '^course:' then
    select c.provider_id
      into v_provider_id
    from catalogue.courses c
    where c.stable_key = v_q
    limit 1;
  elsif v_q is not null and v_q ~ '^[0-9]{6}[A-Za-z]$' then
    select c.provider_id
      into v_provider_id
    from catalogue.courses c
    where upper(c.course_code) = upper(v_q)
    limit 1;
  end if;

  if v_provider_id is not null
     and nullif(p_args->>'provider_id','') is null then
    return security.admin_course_page_fast_base(
      p_args || jsonb_build_object('provider_id', v_provider_id::text)
    );
  end if;

  return security.admin_course_page_fast_base(p_args);
end
$function$;

revoke all on function security.admin_course_page_fast(jsonb)
  from public, anon;
grant execute on function security.admin_course_page_fast(jsonb)
  to authenticated, service_role;
