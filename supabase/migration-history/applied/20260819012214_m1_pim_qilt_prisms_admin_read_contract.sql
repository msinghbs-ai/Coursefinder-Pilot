create or replace function public.ui_qilt_outcomes_page(
  p_limit integer default 50,
  p_offset integer default 0,
  p_query text default null,
  p_survey_code text default null,
  p_metric_code text default null,
  p_provider_id uuid default null,
  p_status text default null,
  p_year integer default null,
  p_sort text default 'provider',
  p_direction text default 'asc'
) returns jsonb
language plpgsql stable security definer
set search_path to 'public','catalogue','ref','pipeline','auth'
as $$
declare
  v_limit integer:=least(greatest(coalesce(p_limit,50),1),200);
  v_offset integer:=greatest(coalesce(p_offset,0),0);
  v_sort text:=lower(coalesce(p_sort,'provider'));
  v_dir text:=case when lower(coalesce(p_direction,'asc'))='desc' then 'desc' else 'asc' end;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  return (
    with base as (
      select po.id,po.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,
        c.iso_alpha2::text country_code,c.name country_name,
        os.code survey_code,os.name survey_name,om.code metric_code,om.name metric_name,om.unit metric_unit,om.category metric_category,
        po.metric_value,po.national_benchmark,po.response_count,po.audience,po.collection_year_from,po.collection_year_to,
        po.observed_at,po.status,po.source_institution_key,po.source_cohort_code,po.updated_at,
        po.evidence_id,e.source_url evidence_url,e.captured_at evidence_captured_at,
        po.source_id,s.label source_label,s.url source_url
      from catalogue.provider_outcomes po
      join catalogue.providers p on p.id=po.provider_id
      join ref.countries c on c.id=p.country_id
      join ref.outcome_surveys os on os.id=po.survey_id and os.code like 'qilt_%'
      join ref.outcome_metrics om on om.id=po.metric_id
      left join pipeline.evidence_artifacts e on e.id=po.evidence_id
      left join pipeline.sources s on s.id=po.source_id
      where (nullif(trim(coalesce(p_query,'')),'') is null
          or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_query)||'%'
          or os.name ilike '%'||trim(p_query)||'%'
          or om.name ilike '%'||trim(p_query)||'%'
          or coalesce(po.source_institution_key,'') ilike '%'||trim(p_query)||'%')
        and (nullif(trim(coalesce(p_survey_code,'')),'') is null or os.code=trim(p_survey_code))
        and (nullif(trim(coalesce(p_metric_code,'')),'') is null or om.code=trim(p_metric_code))
        and (p_provider_id is null or po.provider_id=p_provider_id)
        and (nullif(trim(coalesce(p_status,'')),'') is null or po.status=trim(p_status))
        and (p_year is null or p_year between coalesce(po.collection_year_from,p_year) and coalesce(po.collection_year_to,p_year))
    ), numbered as (select *,count(*) over()::bigint total_count from base), ordered as (
      select * from numbered order by
        case when v_sort='provider' and v_dir='asc' then lower(provider_name) end asc,
        case when v_sort='provider' and v_dir='desc' then lower(provider_name) end desc,
        case when v_sort='survey' and v_dir='asc' then survey_code end asc,
        case when v_sort='survey' and v_dir='desc' then survey_code end desc,
        case when v_sort='metric' and v_dir='asc' then metric_code end asc,
        case when v_sort='metric' and v_dir='desc' then metric_code end desc,
        case when v_sort='value' and v_dir='asc' then metric_value end asc nulls first,
        case when v_sort='value' and v_dir='desc' then metric_value end desc nulls last,
        case when v_sort='benchmark' and v_dir='asc' then national_benchmark end asc nulls first,
        case when v_sort='benchmark' and v_dir='desc' then national_benchmark end desc nulls last,
        case when v_sort='responses' and v_dir='asc' then response_count end asc nulls first,
        case when v_sort='responses' and v_dir='desc' then response_count end desc nulls last,
        case when v_sort='year' and v_dir='asc' then collection_year_to end asc nulls first,
        case when v_sort='year' and v_dir='desc' then collection_year_to end desc nulls last,
        lower(provider_name),survey_code,metric_code,id
      limit v_limit offset v_offset
    )
    select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir) from ordered o
  );
end $$;

create or replace function public.ui_qilt_filter_options(p_survey_code text default null) returns jsonb
language sql stable security definer
set search_path to 'public','catalogue','ref','auth'
as $$
  select case when auth.uid() is null then null else jsonb_build_object(
    'surveys',coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'count',x.cnt) order by x.name) from (select os.code,os.name,count(*)::bigint cnt from catalogue.provider_outcomes po join ref.outcome_surveys os on os.id=po.survey_id where os.code like 'qilt_%' group by os.code,os.name)x),'[]'::jsonb),
    'metrics',coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'unit',x.unit,'count',x.cnt) order by x.name) from (select om.code,om.name,om.unit,count(*)::bigint cnt from catalogue.provider_outcomes po join ref.outcome_surveys os on os.id=po.survey_id join ref.outcome_metrics om on om.id=po.metric_id where os.code like 'qilt_%' and (nullif(trim(coalesce(p_survey_code,'')),'') is null or os.code=trim(p_survey_code)) group by om.code,om.name,om.unit)x),'[]'::jsonb),
    'providers',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'count',x.cnt) order by x.name) from (select p.id,coalesce(p.display_name,p.canonical_name) name,count(*)::bigint cnt from catalogue.provider_outcomes po join catalogue.providers p on p.id=po.provider_id join ref.outcome_surveys os on os.id=po.survey_id where os.code like 'qilt_%' group by p.id,p.display_name,p.canonical_name)x),'[]'::jsonb),
    'statuses',coalesce((select jsonb_agg(jsonb_build_object('code',x.status,'name',initcap(replace(x.status,'_',' ')),'count',x.cnt) order by x.status) from (select po.status,count(*)::bigint cnt from catalogue.provider_outcomes po join ref.outcome_surveys os on os.id=po.survey_id where os.code like 'qilt_%' group by po.status)x),'[]'::jsonb),
    'years',coalesce((select jsonb_agg(jsonb_build_object('value',x.y,'label',x.y::text,'count',x.cnt) order by x.y desc) from (select collection_year_to y,count(*)::bigint cnt from catalogue.provider_outcomes po join ref.outcome_surveys os on os.id=po.survey_id where os.code like 'qilt_%' and collection_year_to is not null group by collection_year_to)x),'[]'::jsonb)
  ) end
$$;

create or replace function public.ui_prisms_student_flow_page(
  p_limit integer default 50,
  p_offset integer default 0,
  p_query text default null,
  p_subdivision_code text default null,
  p_study_area_code text default null,
  p_sector_code text default null,
  p_remoteness_area text default null,
  p_suppressed boolean default null,
  p_sort text default 'geography',
  p_direction text default 'asc'
) returns jsonb
language plpgsql stable security definer
set search_path to 'public','catalogue','ref','pipeline','auth'
as $$
declare
  v_limit integer:=least(greatest(coalesce(p_limit,50),1),200);
  v_offset integer:=greatest(coalesce(p_offset,0),0);
  v_sort text:=lower(coalesce(p_sort,'geography'));
  v_dir text:=case when lower(coalesce(p_direction,'asc'))='desc' then 'desc' else 'asc' end;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  return (
    with raw as (
      select sfo.*,om.code metric_code,sub.code subdivision_code,sub.name subdivision_name,
        src.label source_label,src.url source_url,e.source_url evidence_url,e.captured_at evidence_captured_at
      from catalogue.student_flow_observations sfo
      join ref.outcome_surveys os on os.id=sfo.survey_id and os.code='prisms_international_students'
      join ref.outcome_metrics om on om.id=sfo.metric_id
      left join ref.subdivisions sub on sub.id=sfo.subdivision_id
      left join pipeline.sources src on src.id=sfo.source_id
      left join pipeline.evidence_artifacts e on e.id=sfo.evidence_id
      where (nullif(trim(coalesce(p_query,'')),'') is null
        or coalesce(sfo.source_geography_name,'') ilike '%'||trim(p_query)||'%'
        or coalesce(sfo.source_study_area_name,'') ilike '%'||trim(p_query)||'%'
        or coalesce(sfo.source_sector_code,'') ilike '%'||trim(p_query)||'%'
        or coalesce(sfo.source_remoteness_area,'') ilike '%'||trim(p_query)||'%')
        and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or sub.code=upper(trim(p_subdivision_code)))
        and (nullif(trim(coalesce(p_study_area_code,'')),'') is null or sfo.source_study_area_code=trim(p_study_area_code))
        and (nullif(trim(coalesce(p_sector_code,'')),'') is null or sfo.source_sector_code=trim(p_sector_code))
        and (nullif(trim(coalesce(p_remoteness_area,'')),'') is null or sfo.source_remoteness_area=trim(p_remoteness_area))
        and (p_suppressed is null or sfo.is_suppressed=p_suppressed)
    ), paired as (
      select md5(concat_ws('|',coalesce(source_geography_key,''),coalesce(source_study_area_code,''),coalesce(source_sector_code,''),coalesce(source_remoteness_area,''),coalesce(period_start::text,''),coalesce(period_end::text,''),coalesce(audience,''),coalesce(source_nationality_code,''),coalesce(source_provider_type,''))) id,
        subdivision_code,subdivision_name,source_geography_key,source_geography_name,source_geography_type,
        source_study_area_code,source_study_area_name,source_sector_code,source_remoteness_area,period_start,period_end,period_type,audience,
        max(metric_value) filter(where metric_code='enrolments') enrolments,
        max(metric_value) filter(where metric_code='commencements') commencements,
        bool_or(is_suppressed) suppressed,
        string_agg(distinct suppression_code,', ' order by suppression_code) filter(where suppression_code is not null) suppression_codes,
        count(distinct evidence_id)::bigint evidence_count,
        max(evidence_captured_at) evidence_captured_at,max(evidence_url) evidence_url,max(source_label) source_label,max(source_url) source_url,
        max(updated_at) updated_at
      from raw
      group by subdivision_code,subdivision_name,source_geography_key,source_geography_name,source_geography_type,source_study_area_code,source_study_area_name,source_sector_code,source_remoteness_area,period_start,period_end,period_type,audience,source_nationality_code,source_provider_type
    ), numbered as (select *,count(*) over()::bigint total_count from paired), ordered as (
      select * from numbered order by
        case when v_sort='geography' and v_dir='asc' then lower(source_geography_name) end asc,
        case when v_sort='geography' and v_dir='desc' then lower(source_geography_name) end desc,
        case when v_sort='state' and v_dir='asc' then subdivision_code end asc,
        case when v_sort='state' and v_dir='desc' then subdivision_code end desc,
        case when v_sort='study_area' and v_dir='asc' then lower(source_study_area_name) end asc,
        case when v_sort='study_area' and v_dir='desc' then lower(source_study_area_name) end desc,
        case when v_sort='enrolments' and v_dir='asc' then enrolments end asc nulls first,
        case when v_sort='enrolments' and v_dir='desc' then enrolments end desc nulls last,
        case when v_sort='commencements' and v_dir='asc' then commencements end asc nulls first,
        case when v_sort='commencements' and v_dir='desc' then commencements end desc nulls last,
        case when v_sort='period' and v_dir='asc' then period_end end asc,
        case when v_sort='period' and v_dir='desc' then period_end end desc,
        lower(source_geography_name),lower(source_study_area_name),source_sector_code,id
      limit v_limit offset v_offset
    )
    select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir) from ordered o
  );
end $$;

create or replace function public.ui_prisms_filter_options() returns jsonb
language sql stable security definer
set search_path to 'public','catalogue','ref','auth'
as $$
  select case when auth.uid() is null then null else jsonb_build_object(
    'subdivisions',coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'count',x.cnt) order by x.name) from (select sub.code,sub.name,count(*)::bigint cnt from catalogue.student_flow_observations sfo join ref.outcome_surveys os on os.id=sfo.survey_id left join ref.subdivisions sub on sub.id=sfo.subdivision_id where os.code='prisms_international_students' and sub.id is not null group by sub.code,sub.name)x),'[]'::jsonb),
    'study_areas',coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'count',x.cnt) order by x.name) from (select source_study_area_code code,source_study_area_name name,count(*)::bigint cnt from catalogue.student_flow_observations sfo join ref.outcome_surveys os on os.id=sfo.survey_id where os.code='prisms_international_students' and source_study_area_code is not null group by source_study_area_code,source_study_area_name)x),'[]'::jsonb),
    'sectors',coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',initcap(replace(x.code,'_',' ')),'count',x.cnt) order by x.code) from (select source_sector_code code,count(*)::bigint cnt from catalogue.student_flow_observations sfo join ref.outcome_surveys os on os.id=sfo.survey_id where os.code='prisms_international_students' and source_sector_code is not null group by source_sector_code)x),'[]'::jsonb),
    'remoteness',coalesce((select jsonb_agg(jsonb_build_object('code',x.name,'name',x.name,'count',x.cnt) order by x.name) from (select source_remoteness_area name,count(*)::bigint cnt from catalogue.student_flow_observations sfo join ref.outcome_surveys os on os.id=sfo.survey_id where os.code='prisms_international_students' and source_remoteness_area is not null group by source_remoteness_area)x),'[]'::jsonb)
  ) end
$$;

revoke all on function public.ui_qilt_outcomes_page(integer,integer,text,text,text,uuid,text,integer,text,text) from public,anon;
revoke all on function public.ui_qilt_filter_options(text) from public,anon;
revoke all on function public.ui_prisms_student_flow_page(integer,integer,text,text,text,text,text,boolean,text,text) from public,anon;
revoke all on function public.ui_prisms_filter_options() from public,anon;
grant execute on function public.ui_qilt_outcomes_page(integer,integer,text,text,text,uuid,text,integer,text,text) to authenticated,service_role;
grant execute on function public.ui_qilt_filter_options(text) to authenticated,service_role;
grant execute on function public.ui_prisms_student_flow_page(integer,integer,text,text,text,text,text,boolean,text,text) to authenticated,service_role;
grant execute on function public.ui_prisms_filter_options() to authenticated,service_role;
