CREATE OR REPLACE FUNCTION security.admin_course_page_fast(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'public', 'auth'
AS $function$
declare
  v_q text:=nullif(trim(coalesce(p_args->>'query','')),'');
  v_provider_id uuid;
  v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'course'));
  v_dir text:=lower(coalesce(nullif(p_args->>'direction',''),'asc'));
  v_simple boolean;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank()<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  v_simple :=
    v_q is null
    and nullif(p_args->>'country_code','') is null
    and nullif(p_args->>'subdivision_code','') is null
    and nullif(p_args->>'provider_id','') is null
    and nullif(p_args->>'level_code','') is null
    and nullif(p_args->>'field_code','') is null
    and nullif(p_args->>'delivery_mode','') is null
    and nullif(p_args->>'lifecycle_status','') is null
    and nullif(p_args->>'publication_status','') is null
    and nullif(p_args->>'has_fee','') is null
    and nullif(p_args->>'has_intake','') is null
    and nullif(p_args->>'has_english','') is null
    and nullif(p_args->>'has_scholarship','') is null
    and nullif(p_args->>'has_state','') is null
    and nullif(p_args->>'has_link','') is null
    and nullif(p_args->>'min_completeness','') is null
    and nullif(p_args->>'freshness','') is null
    and nullif(p_args->>'university_group','') is null
    and nullif(p_args->>'applicant','') is null
    and v_sort='course' and v_dir='asc';

  if v_simple then
    return security.admin_course_page_unfiltered_fast(p_args);
  end if;

  if v_q is not null and v_q ~* '^course:' then
    select c.provider_id into v_provider_id
    from catalogue.courses c where c.stable_key=v_q limit 1;
  elsif v_q is not null and v_q ~ '^[0-9]{6}[A-Za-z]$' then
    select c.provider_id into v_provider_id
    from catalogue.courses c where upper(c.course_code)=upper(v_q) limit 1;
  end if;

  if v_provider_id is not null and nullif(p_args->>'provider_id','') is null then
    return security.admin_course_page_fast_base(p_args||jsonb_build_object('provider_id',v_provider_id::text));
  end if;

  return security.admin_course_page_fast_base(p_args);
end $function$
