CREATE OR REPLACE FUNCTION public.ui_prisms_student_flow_page(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_query text DEFAULT NULL::text, p_subdivision_code text DEFAULT NULL::text, p_study_area_code text DEFAULT NULL::text, p_sector_code text DEFAULT NULL::text, p_remoteness_area text DEFAULT NULL::text, p_suppressed boolean DEFAULT NULL::boolean, p_sort text DEFAULT 'geography'::text, p_direction text DEFAULT 'asc'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'catalogue', 'ref', 'pipeline', 'auth'
AS $function$
declare
  v_limit integer:=least(greatest(coalesce(p_limit,50),1),200);
  v_offset integer:=greatest(coalesce(p_offset,0),0);
  v_sort text:=lower(coalesce(p_sort,'geography'));
  v_dir text:=case when lower(coalesce(p_direction,'asc'))='desc' then 'desc' else 'asc' end;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank() < 1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  return (
    with raw as (
      select sfo.*,om.code metric_code,sub.code subdivision_code,sub.name subdivision_name,
        src.label source_label,src.url source_url,e.source_url evidence_url,e.captured_at evidence_captured_at,
        nullif(sfo.metadata->>'source_row','')::integer source_row
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
      select md5(concat_ws('|',coalesce(source_row::text,''),coalesce(source_geography_key,''),coalesce(source_study_area_code,''),coalesce(source_sector_code,''),coalesce(source_remoteness_area,''),coalesce(period_start::text,''),coalesce(period_end::text,''))) id,
        source_row,subdivision_code,subdivision_name,source_geography_key,source_geography_name,source_geography_type,
        source_study_area_code,source_study_area_name,source_sector_code,source_remoteness_area,period_start,period_end,period_type,audience,
        max(metric_value) filter(where metric_code='enrolments') enrolments,
        max(metric_value) filter(where metric_code='commencements') commencements,
        bool_or(is_suppressed) suppressed,
        string_agg(distinct suppression_code,', ' order by suppression_code) filter(where suppression_code is not null) suppression_codes,
        count(distinct evidence_id)::bigint evidence_count,
        max(evidence_captured_at) evidence_captured_at,max(evidence_url) evidence_url,max(source_label) source_label,max(source_url) source_url,
        max(updated_at) updated_at
      from raw
      group by source_row,subdivision_code,subdivision_name,source_geography_key,source_geography_name,source_geography_type,source_study_area_code,source_study_area_name,source_sector_code,source_remoteness_area,period_start,period_end,period_type,audience,source_nationality_code,source_provider_type
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
        lower(source_geography_name),lower(source_study_area_name),source_sector_code,source_row,id
      limit v_limit offset v_offset
    )
    select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir) from ordered o
  );
end $function$
