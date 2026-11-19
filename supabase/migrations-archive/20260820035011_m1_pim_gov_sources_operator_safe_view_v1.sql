create or replace function security.admin_operations_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, public, workflow, pipeline, ref, auth
as $$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,1000),1),5000);
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;

  if p_operation='reviews' then
    if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.priority desc,x.created_at desc),'[]'::jsonb)
      into v_result from public.ui_review_queue(v_limit) x;
    return v_result;
  elsif p_operation='jobs' then
    if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
      into v_result from public.ui_jobs_list(v_limit) x;
    return v_result;
  elsif p_operation='sources' then
    if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
    select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'source_id',to_jsonb(s)->>'id',
      'source_label',to_jsonb(s)->>'label',
      'source_type',to_jsonb(s)->>'source_type',
      'country_code',co.iso_alpha2,
      'source_url',to_jsonb(s)->>'url',
      'official_source',to_jsonb(s)->'official_source',
      'ingestion_enabled',to_jsonb(s)->'ingestion_enabled',
      'validation_status',to_jsonb(s)->>'validation_status',
      'validation_message',to_jsonb(s)->>'validation_message',
      'lifecycle_status',coalesce(to_jsonb(s)->>'lifecycle_status',to_jsonb(s)->>'status'),
      'current_snapshot_at',to_jsonb(s)->'current_snapshot_at',
      'refresh_cadence',to_jsonb(s)->>'refresh_cadence',
      'priority',to_jsonb(s)->'priority',
      'automation_eligible',to_jsonb(s)->'automation_eligible',
      'auth_required',to_jsonb(s)->'auth_required',
      'expected_format',to_jsonb(s)->>'expected_format'
    )) order by co.iso_alpha2 nulls last,to_jsonb(s)->>'label'),'[]'::jsonb)
      into v_result
      from pipeline.sources s
      left join ref.countries co on co.id=nullif(to_jsonb(s)->>'country_id','')::uuid;
    return v_result;
  end if;

  raise exception 'unsupported operations read: %',p_operation using errcode='22023';
end
$$;
