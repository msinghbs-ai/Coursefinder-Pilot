CREATE OR REPLACE FUNCTION security.admin_operational_page(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'workflow', 'ref', 'auth'
AS $function$
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
$function$
