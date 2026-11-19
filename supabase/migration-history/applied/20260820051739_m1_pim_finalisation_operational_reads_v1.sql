-- M1-PIM-FINALISATION operational read contract v1
-- Add bounded/paged browser reads, repair current PIM governance table mappings,
-- repair Provider/Campus decision-detail payloads, and expose a safe Search/Publication overview.
-- No canonical entity identity or field semantics are changed.

create or replace function security.admin_operational_page(
  p_operation text,
  p_args jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, pipeline, workflow, ref, auth
as $$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_query text:=nullif(trim(coalesce(p_args->>'query','')),'');
  v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'created'));
  v_dir text:=case when lower(coalesce(nullif(p_args->>'direction',''),'desc'))='asc' then 'asc' else 'desc' end;
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;

  if p_operation='evidence_page' then
    if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
    with base as (
      select e.id,e.entity_id,e.source_id,e.job_id,e.evidence_type,
             s.label source_label,s.source_type,e.source_url,e.storage_path,e.content_hash,
             e.mime_type,e.captured_at,e.valid_from,e.valid_to,e.supersedes_evidence_id,e.metadata
      from pipeline.evidence_artifacts e
      left join pipeline.sources s on s.id=e.source_id
      where (v_query is null
        or e.id::text=v_query
        or coalesce(e.entity_id::text,'')=v_query
        or coalesce(e.source_id::text,'')=v_query
        or coalesce(e.job_id::text,'')=v_query
        or coalesce(e.content_hash,'')=v_query
        or coalesce(e.evidence_type,'') ilike '%'||v_query||'%'
        or coalesce(s.label,'') ilike '%'||v_query||'%'
        or coalesce(e.source_url,'') ilike '%'||v_query||'%'
        or coalesce(e.storage_path,'') ilike '%'||v_query||'%')
        and (nullif(p_args->>'source_id','') is null or e.source_id::text=p_args->>'source_id')
        and (nullif(p_args->>'evidence_type','') is null or e.evidence_type=p_args->>'evidence_type')
    ), numbered as (
      select *,count(*) over() total_count from base
    ), ordered as (
      select * from numbered order by
        case when v_sort in ('created','captured') and v_dir='asc' then captured_at end asc nulls last,
        case when v_sort in ('created','captured') and v_dir='desc' then captured_at end desc nulls last,
        case when v_sort='source' and v_dir='asc' then lower(coalesce(source_label,'')) end asc,
        case when v_sort='source' and v_dir='desc' then lower(coalesce(source_label,'')) end desc,
        case when v_sort='type' and v_dir='asc' then lower(coalesce(evidence_type,'')) end asc,
        case when v_sort='type' and v_dir='desc' then lower(coalesce(evidence_type,'')) end desc,
        captured_at desc nulls last,id
      limit v_limit offset v_offset
    )
    select jsonb_build_object(
      'items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),
      'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir,
      'filters',jsonb_build_object(
        'sources',coalesce((select jsonb_agg(jsonb_build_object('id',x.source_id,'name',x.source_label,'count',x.n) order by x.source_label) from (select e2.source_id,coalesce(s2.label,'Unknown source') source_label,count(*) n from pipeline.evidence_artifacts e2 left join pipeline.sources s2 on s2.id=e2.source_id group by e2.source_id,s2.label) x),'[]'::jsonb),
        'evidence_types',coalesce((select jsonb_agg(jsonb_build_object('code',x.evidence_type,'name',initcap(replace(x.evidence_type,'_',' ')),'count',x.n) order by x.evidence_type) from (select evidence_type,count(*) n from pipeline.evidence_artifacts where evidence_type is not null group by evidence_type) x),'[]'::jsonb)
      )
    ) into v_result from ordered o;
    return v_result;

  elsif p_operation='reviews_page' then
    if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
    with base as (
      select r.id,r.entity_id,r.domain,r.field_code,r.candidate_claim_id,r.previous_review_id,
             r.reopen_reason,r.priority,r.status,r.assigned_to,r.created_at,r.updated_at,r.closed_at
      from workflow.review_queue r
      where (v_query is null
        or r.id::text=v_query
        or coalesce(r.entity_id::text,'')=v_query
        or coalesce(r.candidate_claim_id::text,'')=v_query
        or coalesce(r.domain,'') ilike '%'||v_query||'%'
        or coalesce(r.field_code,'') ilike '%'||v_query||'%'
        or coalesce(r.reopen_reason,'') ilike '%'||v_query||'%')
        and (nullif(p_args->>'status','') is null or r.status=p_args->>'status')
        and (nullif(p_args->>'domain','') is null or r.domain=p_args->>'domain')
    ), numbered as (select *,count(*) over() total_count from base), ordered as (
      select * from numbered order by
        case when v_sort='priority' and v_dir='asc' then priority end asc,
        case when v_sort='priority' and v_dir='desc' then priority end desc,
        case when v_sort='status' and v_dir='asc' then lower(coalesce(status,'')) end asc,
        case when v_sort='status' and v_dir='desc' then lower(coalesce(status,'')) end desc,
        case when v_sort in ('created','updated') and v_dir='asc' then (case when v_sort='updated' then updated_at else created_at end) end asc,
        case when v_sort in ('created','updated') and v_dir='desc' then (case when v_sort='updated' then updated_at else created_at end) end desc,
        priority desc nulls last,created_at desc,id
      limit v_limit offset v_offset
    )
    select jsonb_build_object(
      'items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),
      'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir,
      'filters',jsonb_build_object(
        'statuses',coalesce((select jsonb_agg(jsonb_build_object('code',x.status,'name',initcap(replace(x.status,'_',' ')),'count',x.n) order by x.status) from (select status,count(*) n from workflow.review_queue where status is not null group by status) x),'[]'::jsonb),
        'domains',coalesce((select jsonb_agg(jsonb_build_object('code',x.domain,'name',initcap(replace(x.domain,'_',' ')),'count',x.n) order by x.domain) from (select domain,count(*) n from workflow.review_queue where domain is not null group by domain) x),'[]'::jsonb)
      )
    ) into v_result from ordered o;
    return v_result;

  elsif p_operation='jobs_page' then
    if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
    with base as (
      select j.id,j.job_type,j.domain,j.source_id,j.provider_id,j.entity_id,j.status,
             j.attempt_count,j.created_at,j.started_at,j.completed_at,j.error_text
      from pipeline.jobs j
      where (v_query is null
        or j.id::text=v_query
        or coalesce(j.source_id::text,'')=v_query
        or coalesce(j.provider_id::text,'')=v_query
        or coalesce(j.entity_id::text,'')=v_query
        or coalesce(j.job_type,'') ilike '%'||v_query||'%'
        or coalesce(j.domain,'') ilike '%'||v_query||'%'
        or coalesce(j.status,'') ilike '%'||v_query||'%'
        or coalesce(j.error_text,'') ilike '%'||v_query||'%')
        and (nullif(p_args->>'status','') is null or j.status=p_args->>'status')
        and (nullif(p_args->>'domain','') is null or j.domain=p_args->>'domain')
        and (nullif(p_args->>'job_type','') is null or j.job_type=p_args->>'job_type')
    ), numbered as (select *,count(*) over() total_count from base), ordered as (
      select * from numbered order by
        case when v_sort='created' and v_dir='asc' then created_at end asc,
        case when v_sort='created' and v_dir='desc' then created_at end desc,
        case when v_sort='status' and v_dir='asc' then lower(coalesce(status,'')) end asc,
        case when v_sort='status' and v_dir='desc' then lower(coalesce(status,'')) end desc,
        case when v_sort='type' and v_dir='asc' then lower(coalesce(job_type,'')) end asc,
        case when v_sort='type' and v_dir='desc' then lower(coalesce(job_type,'')) end desc,
        case when v_sort='domain' and v_dir='asc' then lower(coalesce(domain,'')) end asc,
        case when v_sort='domain' and v_dir='desc' then lower(coalesce(domain,'')) end desc,
        created_at desc,id
      limit v_limit offset v_offset
    )
    select jsonb_build_object(
      'items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),
      'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir,
      'filters',jsonb_build_object(
        'statuses',coalesce((select jsonb_agg(jsonb_build_object('code',x.status,'name',initcap(replace(x.status,'_',' ')),'count',x.n) order by x.status) from (select status,count(*) n from pipeline.jobs where status is not null group by status) x),'[]'::jsonb),
        'domains',coalesce((select jsonb_agg(jsonb_build_object('code',x.domain,'name',initcap(replace(x.domain,'_',' ')),'count',x.n) order by x.domain) from (select domain,count(*) n from pipeline.jobs where domain is not null group by domain) x),'[]'::jsonb),
        'job_types',coalesce((select jsonb_agg(jsonb_build_object('code',x.job_type,'name',initcap(replace(x.job_type,'_',' ')),'count',x.n) order by x.job_type) from (select job_type,count(*) n from pipeline.jobs where job_type is not null group by job_type) x),'[]'::jsonb)
      )
    ) into v_result from ordered o;
    return v_result;

  elsif p_operation='sources_page' then
    if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
    with base as (
      select s.id source_id,s.label source_label,s.source_type,co.iso_alpha2::text country_code,
             s.url source_url,
             coalesce(to_jsonb(s)->'official_source','false'::jsonb) official_source,
             to_jsonb(s)->'ingestion_enabled' ingestion_enabled,
             to_jsonb(s)->>'validation_status' validation_status,
             to_jsonb(s)->>'validation_message' validation_message,
             coalesce(to_jsonb(s)->>'lifecycle_status',s.status) lifecycle_status,
             to_jsonb(s)->'current_snapshot_at' current_snapshot_at,
             to_jsonb(s)->>'refresh_cadence' refresh_cadence,
             to_jsonb(s)->'priority' priority,
             to_jsonb(s)->'automation_eligible' automation_eligible,
             to_jsonb(s)->'auth_required' auth_required,
             to_jsonb(s)->>'expected_format' expected_format,
             s.last_checked_at,s.last_success_at,s.last_failure_at,s.last_error
      from pipeline.sources s left join ref.countries co on co.id=s.country_id
      where (v_query is null
        or s.id::text=v_query
        or coalesce(s.label,'') ilike '%'||v_query||'%'
        or coalesce(s.source_type,'') ilike '%'||v_query||'%'
        or coalesce(s.url,'') ilike '%'||v_query||'%'
        or coalesce(co.iso_alpha2::text,'') ilike '%'||v_query||'%')
        and (nullif(p_args->>'source_type','') is null or s.source_type=p_args->>'source_type')
        and (nullif(p_args->>'status','') is null or s.status=p_args->>'status')
        and (nullif(p_args->>'country_code','') is null or co.iso_alpha2::text=upper(p_args->>'country_code'))
    ), numbered as (select *,count(*) over() total_count from base), ordered as (
      select * from numbered order by
        case when v_sort in ('source','name') and v_dir='asc' then lower(coalesce(source_label,'')) end asc,
        case when v_sort in ('source','name') and v_dir='desc' then lower(coalesce(source_label,'')) end desc,
        case when v_sort='country' and v_dir='asc' then coalesce(country_code,'') end asc,
        case when v_sort='country' and v_dir='desc' then coalesce(country_code,'') end desc,
        case when v_sort='type' and v_dir='asc' then lower(coalesce(source_type,'')) end asc,
        case when v_sort='type' and v_dir='desc' then lower(coalesce(source_type,'')) end desc,
        case when v_sort='checked' and v_dir='asc' then last_checked_at end asc nulls last,
        case when v_sort='checked' and v_dir='desc' then last_checked_at end desc nulls last,
        lower(coalesce(source_label,'')),source_id
      limit v_limit offset v_offset
    )
    select jsonb_build_object(
      'items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),
      'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir,
      'filters',jsonb_build_object(
        'source_types',coalesce((select jsonb_agg(jsonb_build_object('code',x.source_type,'name',initcap(replace(x.source_type,'_',' ')),'count',x.n) order by x.source_type) from (select source_type,count(*) n from pipeline.sources where source_type is not null group by source_type) x),'[]'::jsonb),
        'statuses',coalesce((select jsonb_agg(jsonb_build_object('code',x.status,'name',initcap(replace(x.status,'_',' ')),'count',x.n) order by x.status) from (select status,count(*) n from pipeline.sources where status is not null group by status) x),'[]'::jsonb),
        'countries',coalesce((select jsonb_agg(jsonb_build_object('code',x.country_code,'name',x.country_code,'count',x.n) order by x.country_code) from (select co2.iso_alpha2::text country_code,count(*) n from pipeline.sources s2 join ref.countries co2 on co2.id=s2.country_id group by co2.iso_alpha2) x),'[]'::jsonb)
      )
    ) into v_result from ordered o;
    return v_result;
  end if;

  raise exception 'unsupported operational page: %',p_operation using errcode='22023';
end
$$;

revoke execute on function security.admin_operational_page(text,jsonb) from public, anon;
grant execute on function security.admin_operational_page(text,jsonb) to authenticated, service_role;

create or replace function security.admin_pim_governance_read(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, pim, auth
as $$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,200),1),500);
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<5 then raise exception 'pim_admin role required' using errcode='42501'; end if;

  select jsonb_build_object(
    'families',coalesce((select jsonb_agg(to_jsonb(x) order by x.code) from (select * from pim.attribute_families order by code limit v_limit) x),'[]'::jsonb),
    'groups',coalesce((select jsonb_agg(to_jsonb(x) order by x.display_order nulls last,x.code) from (select * from pim.attribute_groups order by display_order nulls last,code limit v_limit) x),'[]'::jsonb),
    'attributes',coalesce((select jsonb_agg(to_jsonb(x) order by x.display_order nulls last,x.code) from (select * from pim.attribute_definitions order by display_order nulls last,code limit v_limit) x),'[]'::jsonb),
    'options',coalesce((select jsonb_agg(to_jsonb(x) order by x.attribute_id,x.display_order nulls last,x.code) from (select * from pim.attribute_options order by attribute_id,display_order nulls last,code limit v_limit) x),'[]'::jsonb),
    'completeness_profiles',coalesce((select jsonb_agg(to_jsonb(x) order by x.code) from (select * from pim.completeness_profiles order by code limit v_limit) x),'[]'::jsonb),
    'completeness_profile_rules',coalesce((select jsonb_agg(to_jsonb(x) order by x.profile_id,x.requirement_code,x.attribute_code) from (
      select cr.id,cr.profile_id,cr.attribute_id,cr.requirement_code,cr.weight,cr.is_mandatory,cr.rule,cr.created_at,
             ad.code attribute_code,ad.name attribute_name
      from pim.completeness_requirements cr
      left join pim.attribute_definitions ad on ad.id=cr.attribute_id
      order by cr.profile_id,cr.requirement_code,ad.code
      limit v_limit
    ) x),'[]'::jsonb),
    'family_groups',coalesce((select jsonb_agg(to_jsonb(x) order by x.family_id,x.display_order nulls last) from (select * from pim.family_groups order by family_id,display_order nulls last limit v_limit) x),'[]'::jsonb),
    'family_attributes',coalesce((select jsonb_agg(to_jsonb(x) order by x.family_id,x.display_order nulls last) from (select * from pim.family_attributes order by family_id,display_order nulls last limit v_limit) x),'[]'::jsonb),
    'counts',jsonb_build_object(
      'families',(select count(*) from pim.attribute_families),
      'groups',(select count(*) from pim.attribute_groups),
      'attributes',(select count(*) from pim.attribute_definitions),
      'options',(select count(*) from pim.attribute_options),
      'completeness_profiles',(select count(*) from pim.completeness_profiles),
      'completeness_profile_rules',(select count(*) from pim.completeness_requirements)
    ),
    'limit',v_limit
  ) into v_result;
  return v_result;
end
$$;

revoke execute on function security.admin_pim_governance_read(jsonb) from public, anon;
grant execute on function security.admin_pim_governance_read(jsonb) to authenticated, service_role;

create or replace function security.admin_provider_detail(p_provider_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, public, catalogue, pipeline, ref, search, scholarship, auth
as $$
declare
  v_rank integer:=0;
  v_base jsonb;
  v_courses jsonb;
  v_evidence jsonb;
  v_campuses jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  v_base:=public.ui_provider_detail(p_provider_id);
  if v_base is null then return '{}'::jsonb; end if;
  v_courses:=public.ui_provider_related_courses(p_provider_id,25,0,null,null,null);
  v_evidence:=public.ui_provider_related_evidence(p_provider_id,25,0,null,null);

  with base as (
    select ca.id,ca.stable_key,ca.name,ca.campus_code,ca.city,ca.postcode,ca.status,ca.publication_status,
           sd.code subdivision_code,sd.name subdivision_name,
           (select count(*)::int from catalogue.course_campuses cc where cc.campus_id=ca.id) course_count
    from catalogue.campuses ca left join ref.subdivisions sd on sd.id=ca.subdivision_id
    where ca.provider_id=p_provider_id
  ), numbered as (select *,count(*) over() total_count from base), ordered as (
    select * from numbered order by lower(name),id limit 25
  )
  select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',25,'offset',0)
    into v_campuses from ordered o;

  return v_base || jsonb_build_object(
    'courses_page',coalesce(v_courses,jsonb_build_object('items','[]'::jsonb,'total',0,'limit',25,'offset',0)),
    'evidence_page',coalesce(v_evidence,jsonb_build_object('items','[]'::jsonb,'total',0,'limit',25,'offset',0)),
    'campuses_page',coalesce(v_campuses,jsonb_build_object('items','[]'::jsonb,'total',0,'limit',25,'offset',0)),
    'courses',coalesce(v_courses->'items','[]'::jsonb),
    'evidence',coalesce(v_evidence->'items','[]'::jsonb),
    'scholarship_count',(select count(*) from scholarship.scholarships s where s.provider_id=p_provider_id),
    'history',jsonb_build_object('created_at',v_base->'created_at','updated_at',v_base->'updated_at','last_verified_at',v_base->'last_verified_at')
  );
end
$$;

revoke execute on function security.admin_provider_detail(uuid) from public, anon;
grant execute on function security.admin_provider_detail(uuid) to authenticated, service_role;

create or replace function security.admin_campus_detail(p_campus_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, catalogue, pipeline, ref, scholarship, auth
as $$
declare
  v_rank integer:=0;
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  select jsonb_build_object(
    'id',ca.id,'stable_key',ca.stable_key,'name',ca.name,'campus_code',ca.campus_code,
    'provider_id',ca.provider_id,'provider_name',coalesce(p.display_name,p.canonical_name),
    'country_code',co.iso_alpha2,'country_name',co.name,'subdivision_code',sd.code,'subdivision_name',sd.name,
    'city',ca.city,'address_line1',ca.address_line1,'address_line2',ca.address_line2,'postcode',ca.postcode,
    'latitude',ca.latitude,'longitude',ca.longitude,'phone',ca.phone,'website',ca.website,
    'status',ca.status,'publication_status',ca.publication_status,'valid_from',ca.valid_from,'valid_to',ca.valid_to,
    'last_verified_at',ca.last_verified_at,'created_at',ca.created_at,'updated_at',ca.updated_at,
    'source',jsonb_build_object('source_id',ca.source_id,'source_label',s.label,'source_type',s.source_type,'source_url',s.url),
    'evidence',case when e.id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('id',e.id,'type',e.evidence_type,'source_url',e.source_url,'storage_path',e.storage_path,'content_hash',e.content_hash,'captured_at',e.captured_at)) end,
    'courses_page',coalesce((
      with base as (
        select c.id,c.stable_key,c.canonical_title,c.course_code,c.lifecycle_status,c.publication_status,cc.delivery_mode,cc.is_primary
        from catalogue.course_campuses cc join catalogue.courses c on c.id=cc.course_id
        where cc.campus_id=ca.id
      ), numbered as (select *,count(*) over() total_count from base), ordered as (
        select * from numbered order by lower(canonical_title),id limit 25
      )
      select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',25,'offset',0) from ordered o
    ),jsonb_build_object('items','[]'::jsonb,'total',0,'limit',25,'offset',0)),
    'scholarship_count',(select count(distinct ss.scholarship_id) from scholarship.scopes ss where ss.campus_id=ca.id and coalesce(ss.include_exclude,'include')='include')
  ) into v_result
  from catalogue.campuses ca
  join catalogue.providers p on p.id=ca.provider_id
  join ref.countries co on co.id=ca.country_id
  left join ref.subdivisions sd on sd.id=ca.subdivision_id
  left join pipeline.sources s on s.id=ca.source_id
  left join pipeline.evidence_artifacts e on e.id=ca.evidence_id
  where ca.id=p_campus_id;

  return coalesce(v_result,'{}'::jsonb);
end
$$;

revoke execute on function security.admin_campus_detail(uuid) from public, anon;
grant execute on function security.admin_campus_detail(uuid) to authenticated, service_role;

create or replace function security.admin_publication_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, search, publishing, auth
as $$
declare
  v_rank integer:=0;
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  select jsonb_build_object(
    'course_documents',jsonb_build_object(
      'total',count(*),
      'published',count(*) filter(where publication_status='published'),
      'unpublished',count(*) filter(where publication_status='unpublished'),
      'has_fee',count(*) filter(where has_fee),
      'has_intake',count(*) filter(where has_intake),
      'has_english',count(*) filter(where has_english),
      'has_scholarship',count(*) filter(where has_scholarship),
      'latest_generated_at',max(generated_at)
    ),
    'projection',coalesce((select jsonb_build_object(
      'projection_code',ps.projection_code,'generation',ps.generation,'rebuilt_at',ps.rebuilt_at,'row_count',ps.row_count,
      'content_hash',ps.content_hash,'projection_version',ps.metadata->>'projection_version','enrichment_gate',ps.metadata->>'enrichment_gate'
    ) from search.projection_state ps where ps.projection_code='courses'),'{}'::jsonb),
    'channels',coalesce((select jsonb_agg(jsonb_build_object(
      'code',ch.code,'name',ch.name,'audience',ch.audience,'status',ch.status,
      'entity_state_count',(select count(*) from publishing.entity_states es where es.channel_code=ch.code),
      'published_count',(select count(*) from publishing.entity_states es where es.channel_code=ch.code and es.publication_status='published')
    ) order by ch.code) from publishing.channels ch),'[]'::jsonb)
  ) into v_result
  from search.course_documents;
  return v_result;
end
$$;

revoke execute on function security.admin_publication_overview() from public, anon;
grant execute on function security.admin_publication_overview() to authenticated, service_role;

create or replace function public.admin_read(p_operation text, p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog, public, security
as $$
declare
  v_result jsonb;
  v_id uuid;
begin
  if p_operation='courses_page' then
    return security.admin_course_page_search_state(security.admin_catalogue_page(p_operation,p_args));
  end if;
  if p_operation in ('providers_page','campuses_page','scholarships_page') then
    return security.admin_catalogue_page(p_operation,p_args);
  end if;
  if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then
    return security.admin_insights_read(p_operation,p_args);
  end if;
  if p_operation in ('evidence_page','reviews_page','jobs_page','sources_page') then
    return security.admin_operational_page(p_operation,p_args);
  end if;
  if p_operation in ('reviews','jobs','sources') then
    return security.admin_operations_read(p_operation,p_args);
  end if;
  if p_operation='attributes' then
    return security.admin_pim_governance_read(p_args);
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

revoke execute on function public.admin_read(text,jsonb) from public, anon;
grant execute on function public.admin_read(text,jsonb) to authenticated, service_role;
