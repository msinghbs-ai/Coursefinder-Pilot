CREATE OR REPLACE FUNCTION security.admin_insights_read(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'security', 'auth'
AS $function$
declare
  v_rank integer := 0;
  v_limit integer := least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer := greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_provider_id uuid;
  v_year integer;
  v_suppressed boolean;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  select security.current_role_rank() into v_rank;
  if v_rank < 1 then
    raise exception 'assigned CourseFinder role required' using errcode='42501';
  end if;

  v_provider_id := nullif(p_args->>'provider_id','')::uuid;
  v_year := nullif(p_args->>'year','')::integer;
  v_suppressed := case
    when nullif(p_args->>'suppressed','') is null then null
    else (p_args->>'suppressed')::boolean
  end;

  if p_operation='qilt_outcomes' then
    return public.ui_qilt_outcomes_page(
      v_limit,
      v_offset,
      nullif(p_args->>'query',''),
      nullif(p_args->>'survey_code',''),
      nullif(p_args->>'metric_code',''),
      v_provider_id,
      nullif(p_args->>'status',''),
      v_year,
      coalesce(nullif(p_args->>'sort',''),'provider'),
      coalesce(nullif(p_args->>'direction',''),'asc')
    );
  elsif p_operation='qilt_filters' then
    return public.ui_qilt_filter_options(nullif(p_args->>'survey_code',''));
  elsif p_operation='prisms_student_flow' then
    return public.ui_prisms_student_flow_page(
      v_limit,
      v_offset,
      nullif(p_args->>'query',''),
      nullif(p_args->>'subdivision_code',''),
      nullif(p_args->>'study_area_code',''),
      nullif(p_args->>'sector_code',''),
      nullif(p_args->>'remoteness_area',''),
      v_suppressed,
      coalesce(nullif(p_args->>'sort',''),'geography'),
      coalesce(nullif(p_args->>'direction',''),'asc')
    );
  elsif p_operation='prisms_filters' then
    return public.ui_prisms_filter_options();
  else
    raise exception 'unsupported insights read operation: %',p_operation using errcode='22023';
  end if;
end
$function$
