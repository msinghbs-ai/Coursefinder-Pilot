CREATE OR REPLACE FUNCTION public.ui_qilt_outcomes_page(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_query text DEFAULT NULL::text, p_survey_code text DEFAULT NULL::text, p_metric_code text DEFAULT NULL::text, p_provider_id uuid DEFAULT NULL::uuid, p_status text DEFAULT NULL::text, p_year integer DEFAULT NULL::integer, p_sort text DEFAULT 'provider'::text, p_direction text DEFAULT 'asc'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'catalogue', 'ref', 'pipeline', 'auth'
AS $function$
declare
  v_limit integer:=least(greatest(coalesce(p_limit,50),1),200);
  v_offset integer:=greatest(coalesce(p_offset,0),0);
  v_sort text:=lower(coalesce(p_sort,'provider'));
  v_dir text:=case when lower(coalesce(p_direction,'asc'))='desc' then 'desc' else 'asc' end;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank() < 1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
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
end $function$
