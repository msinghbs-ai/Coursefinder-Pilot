-- CF-CHG-20260820-015 — deployed Admin UX maturity remediation.
-- Additive browser-read operations only. Provider/Course identity, source authority,
-- Search admission and legacy public.ui_* ACLs are unchanged.

create or replace function security.admin_catalogue_filter_options(
  p_operation text,
  p_args jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, catalogue, ref, auth
as $$
declare
  v_rank integer := 0;
  v_country text := upper(nullif(trim(coalesce(p_args->>'country_code','')),''));
  v_subdivision text := upper(nullif(trim(coalesce(p_args->>'subdivision_code','')),''));
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  select security.current_role_rank() into v_rank;
  if v_rank < 1 then
    raise exception 'assigned CourseFinder role required' using errcode='42501';
  end if;

  if p_operation='provider_filters' then
    return jsonb_build_object(
      'countries',coalesce((
        select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.name)
        from (
          select distinct c.iso_alpha2::text code,c.name
          from ref.countries c
          where exists(select 1 from catalogue.providers p where p.country_id=c.id)
        ) x
      ),'[]'::jsonb),
      'subdivisions',coalesce((
        select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'type',x.subdivision_type) order by x.name)
        from (
          select distinct s.code,s.name,s.subdivision_type
          from ref.subdivisions s
          join ref.countries c on c.id=s.country_id
          where (v_country is null or c.iso_alpha2::text=v_country)
            and (
              exists(select 1 from catalogue.providers p where p.subdivision_id=s.id)
              or exists(select 1 from catalogue.campuses cp where cp.subdivision_id=s.id)
            )
        ) x
      ),'[]'::jsonb)
    );
  elsif p_operation='course_filters' then
    return jsonb_build_object(
      'countries',coalesce((
        select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.name)
        from (
          select distinct co.iso_alpha2::text code,co.name
          from catalogue.courses c
          join catalogue.providers p on p.id=c.provider_id
          join ref.countries co on co.id=p.country_id
        ) x
      ),'[]'::jsonb),
      'subdivisions',coalesce((
        select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'type',x.subdivision_type) order by x.name)
        from (
          select distinct s.code,s.name,s.subdivision_type
          from catalogue.courses c
          join catalogue.providers p on p.id=c.provider_id
          join ref.countries co on co.id=p.country_id
          join catalogue.course_campuses cc on cc.course_id=c.id
          join catalogue.campuses cp on cp.id=cc.campus_id
          join ref.subdivisions s on s.id=cp.subdivision_id
          where (v_country is null or co.iso_alpha2::text=v_country)
        ) x
      ),'[]'::jsonb),
      'providers',coalesce((
        select jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'stable_key',x.stable_key) order by x.name)
        from (
          select distinct p.id,coalesce(p.display_name,p.canonical_name) name,p.stable_key
          from catalogue.courses c
          join catalogue.providers p on p.id=c.provider_id
          join ref.countries co on co.id=p.country_id
          where (v_country is null or co.iso_alpha2::text=v_country)
            and (v_subdivision is null or exists(
              select 1
              from catalogue.course_campuses cc
              join catalogue.campuses cp on cp.id=cc.campus_id
              join ref.subdivisions s on s.id=cp.subdivision_id
              where cc.course_id=c.id and s.code=v_subdivision
            ))
        ) x
      ),'[]'::jsonb),
      'levels',coalesce((
        select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.sort_order,x.name)
        from (
          select distinct sl.code,sl.name,sl.sort_order
          from catalogue.courses c
          join ref.study_levels sl on sl.id=c.study_level_id
          join catalogue.providers p on p.id=c.provider_id
          join ref.countries co on co.id=p.country_id
          where (v_country is null or co.iso_alpha2::text=v_country)
            and (v_subdivision is null or exists(
              select 1 from catalogue.course_campuses cc
              join catalogue.campuses cp on cp.id=cc.campus_id
              join ref.subdivisions s on s.id=cp.subdivision_id
              where cc.course_id=c.id and s.code=v_subdivision
            ))
        ) x
      ),'[]'::jsonb),
      'fields',coalesce((
        select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.name)
        from (
          select distinct fos.code,fos.name
          from catalogue.courses c
          join ref.fields_of_study fos on fos.id=c.primary_field_id
          join catalogue.providers p on p.id=c.provider_id
          join ref.countries co on co.id=p.country_id
          where (v_country is null or co.iso_alpha2::text=v_country)
            and (v_subdivision is null or exists(
              select 1 from catalogue.course_campuses cc
              join catalogue.campuses cp on cp.id=cc.campus_id
              join ref.subdivisions s on s.id=cp.subdivision_id
              where cc.course_id=c.id and s.code=v_subdivision
            ))
        ) x
      ),'[]'::jsonb),
      'delivery_modes',coalesce((
        select jsonb_agg(jsonb_build_object('code',x.code,'name',x.code) order by x.code)
        from (
          select distinct cc.delivery_mode code
          from catalogue.course_campuses cc
          join catalogue.courses c on c.id=cc.course_id
          join catalogue.providers p on p.id=c.provider_id
          join ref.countries co on co.id=p.country_id
          where cc.delivery_mode is not null and btrim(cc.delivery_mode)<>''
            and (v_country is null or co.iso_alpha2::text=v_country)
            and (v_subdivision is null or exists(
              select 1 from catalogue.course_campuses cc2
              join catalogue.campuses cp2 on cp2.id=cc2.campus_id
              join ref.subdivisions s2 on s2.id=cp2.subdivision_id
              where cc2.course_id=c.id and s2.code=v_subdivision
            ))
        ) x
      ),'[]'::jsonb)
    );
  end if;

  raise exception 'unsupported catalogue filter operation: %',p_operation using errcode='22023';
end
$$;

revoke all on function security.admin_catalogue_filter_options(text,jsonb) from public,anon;
grant execute on function security.admin_catalogue_filter_options(text,jsonb) to authenticated,service_role;
comment on function security.admin_catalogue_filter_options(text,jsonb) is
  'CF-CHG-20260820-015 role-checked governed Provider/Course filter-option read for Admin browser UX.';

create or replace function security.admin_dashboard_maturity()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, catalogue, scholarship, pipeline, workflow, pim, search, auth
as $$
declare
  v_rank integer := 0;
  v_activity jsonb := '[]'::jsonb;
  v_search_generation bigint;
  v_search_rows bigint;
  v_search_rebuilt_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  select security.current_role_rank() into v_rank;
  if v_rank < 1 then
    raise exception 'assigned CourseFinder role required' using errcode='42501';
  end if;

  select generation,row_count,rebuilt_at
    into v_search_generation,v_search_rows,v_search_rebuilt_at
  from search.projection_state
  where projection_code='courses';

  with activity as (
    select
      'job'::text kind,
      j.id,
      initcap(replace(coalesce(j.job_type,'job'),'_',' ')) title,
      coalesce(j.domain,'Pipeline') detail,
      coalesce(j.status,'unknown') status,
      coalesce(j.completed_at,j.started_at,j.created_at) occurred_at
    from pipeline.jobs j
    union all
    select
      'review'::text kind,
      r.id,
      'Review · '||initcap(replace(coalesce(r.domain,'general'),'_',' ')) title,
      coalesce(r.field_code,'Human resolution') detail,
      coalesce(r.status,'unknown') status,
      coalesce(r.updated_at,r.created_at) occurred_at
    from workflow.review_queue r
    union all
    select
      'evidence'::text kind,
      e.id,
      initcap(replace(coalesce(e.evidence_type,'evidence'),'_',' ')) title,
      'Evidence captured'::text detail,
      'captured'::text status,
      coalesce(e.captured_at,e.created_at) occurred_at
    from pipeline.evidence_artifacts e
  ), recent as (
    select * from activity where occurred_at is not null order by occurred_at desc limit 10
  )
  select coalesce(jsonb_agg(to_jsonb(recent) order by occurred_at desc),'[]'::jsonb)
    into v_activity from recent;

  return jsonb_build_object(
    'providers',(select count(*) from catalogue.providers),
    'courses',(select count(*) from catalogue.courses),
    'campuses',(select count(*) from catalogue.campuses),
    'course_campus_links',(select count(*) from catalogue.course_campuses),
    'scholarships',(select count(*) from scholarship.scholarships),
    'jobs',(select count(*) from pipeline.jobs),
    'open_reviews',(select count(*) from workflow.review_queue where status in ('open','in_review')),
    'evidence',(select count(*) from pipeline.evidence_artifacts),
    'attributes',(select count(*) from pim.attribute_definitions),
    'search_documents',(select count(*) from search.course_documents),
    'search_generation',v_search_generation,
    'operational',jsonb_build_object(
      'running_jobs',(select count(*) from pipeline.jobs where status in ('queued','pending','running','processing')),
      'failed_jobs_24h',(select count(*) from pipeline.jobs where status in ('failed','error') and coalesce(completed_at,created_at)>=now()-interval '24 hours'),
      'completed_jobs_24h',(select count(*) from pipeline.jobs where status in ('completed','succeeded') and coalesce(completed_at,created_at)>=now()-interval '24 hours'),
      'evidence_24h',(select count(*) from pipeline.evidence_artifacts where coalesce(captured_at,created_at)>=now()-interval '24 hours'),
      'latest_job_at',(select max(coalesce(completed_at,started_at,created_at)) from pipeline.jobs),
      'latest_evidence_at',(select max(coalesce(captured_at,created_at)) from pipeline.evidence_artifacts),
      'search_rebuilt_at',v_search_rebuilt_at,
      'search_row_count',v_search_rows
    ),
    'recent_activity',v_activity
  );
end
$$;

revoke all on function security.admin_dashboard_maturity() from public,anon;
grant execute on function security.admin_dashboard_maturity() to authenticated,service_role;
comment on function security.admin_dashboard_maturity() is
  'CF-CHG-20260820-015 role-checked operational Dashboard summary and bounded recent activity for Admin browser UX.';

create or replace function public.admin_read(p_operation text, p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, security
as $$
declare
  v_result jsonb;
  v_id uuid;
begin
  if p_operation='dashboard' then
    return security.admin_dashboard_maturity();
  end if;
  if p_operation in ('provider_filters','course_filters') then
    return security.admin_catalogue_filter_options(p_operation,p_args);
  end if;
  if p_operation in ('evidence_page','evidence_filters','evidence_detail','evidence_observations','evidence_entities') then
    return security.admin_evidence_read(p_operation,p_args);
  end if;
  if p_operation='courses_page' then
    return security.admin_course_page_fast(p_args);
  end if;
  if p_operation in ('providers_page','campuses_page','scholarships_page') then
    return security.admin_catalogue_page(p_operation,p_args);
  end if;
  if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then
    return security.admin_insights_read(p_operation,p_args);
  end if;
  if p_operation='reviews_page' then
    return security.admin_operational_page(p_operation,p_args);
  end if;
  if p_operation in ('reviews','jobs','sources') then
    return security.admin_operations_read(p_operation,p_args);
  end if;
  if p_operation='attributes' then
    return security.admin_pim_governance_read(p_args);
  end if;
  if p_operation in ('pipeline_overview','pipeline_jobs_page','pipeline_job_detail','pipeline_sources_page','pipeline_filters') then
    return security.admin_pipeline_ops_read(p_operation,p_args);
  end if;
  if p_operation='publication_overview' then
    return security.admin_publication_overview();
  end if;
  if p_operation='provider_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    return security.admin_provider_detail(v_id);
  end if;
  if p_operation='campus_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    return security.admin_campus_detail(v_id);
  end if;

  v_result:=security.admin_read_impl(p_operation,p_args);
  if p_operation='course_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    return v_result
      || jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id))
      || jsonb_build_object('entry_summary',security.admin_course_entry_summary(v_id))
      || jsonb_build_object('taxonomy_summary',security.admin_course_taxonomy_summary(v_id))
      || jsonb_build_object('state_summary',security.admin_course_state_summary(v_id));
  end if;
  if p_operation='scholarship_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    return v_result || jsonb_build_object('semantic_summary',security.admin_scholarship_semantic_summary(v_id));
  end if;
  return v_result;
end;
$$;

revoke execute on function public.admin_read(text,jsonb) from public,anon;
grant execute on function public.admin_read(text,jsonb) to authenticated,service_role;
