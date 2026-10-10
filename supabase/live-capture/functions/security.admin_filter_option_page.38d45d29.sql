CREATE OR REPLACE FUNCTION security.admin_filter_option_page(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'catalogue', 'ref', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_kind text:=lower(nullif(trim(coalesce(p_args->>'kind','')),''));
  v_query text:=lower(nullif(trim(coalesce(p_args->>'query','')),''));
  v_country text:=upper(nullif(trim(coalesce(p_args->>'country_code','')),''));
  v_survey text:=nullif(trim(coalesce(p_args->>'survey_code','')),'');
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,10),1),10);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_items jsonb:='[]'::jsonb;
  v_total integer:=0;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;

  if v_kind='evidence_source' then
    if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
    with q as (
      select s.id::text value,s.label label,
             concat_ws(' · ',nullif(s.source_type,''),co.iso_alpha2::text) meta,
             count(*)::bigint cnt
      from pipeline.evidence_artifacts e
      join pipeline.sources s on s.id=e.source_id
      left join ref.countries co on co.id=s.country_id
      where (v_country is null or upper(co.iso_alpha2::text)=v_country)
        and (v_query is null or lower(s.label||' '||coalesce(s.source_type,'')||' '||coalesce(co.iso_alpha2::text,'')) like '%'||v_query||'%')
      group by s.id,s.label,s.source_type,co.iso_alpha2
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta,'count',cnt) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='qilt_provider' then
    if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
    with q as (
      select p.id::text value,coalesce(p.display_name,p.canonical_name) label,p.stable_key meta,count(*)::bigint cnt
      from catalogue.provider_outcomes po
      join catalogue.providers p on p.id=po.provider_id
      join ref.outcome_surveys os on os.id=po.survey_id
      where os.code like 'qilt_%'
        and (v_survey is null or os.code=v_survey)
        and (v_query is null or lower(coalesce(p.display_name,p.canonical_name)||' '||coalesce(p.stable_key,'')) like '%'||v_query||'%')
      group by p.id,p.display_name,p.canonical_name,p.stable_key
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta,'count',cnt) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='qilt_metric' then
    if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
    with q as (
      select om.code value,om.name label,concat_ws(' · ',om.unit,om.code) meta,count(*)::bigint cnt
      from catalogue.provider_outcomes po
      join ref.outcome_surveys os on os.id=po.survey_id
      join ref.outcome_metrics om on om.id=po.metric_id
      where os.code like 'qilt_%'
        and (v_survey is null or os.code=v_survey)
        and (v_query is null or lower(om.name||' '||om.code||' '||coalesce(om.unit,'')) like '%'||v_query||'%')
      group by om.code,om.name,om.unit
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta,'count',cnt) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='prisms_study_area' then
    if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
    with q as (
      select sfo.source_study_area_code value,sfo.source_study_area_name label,sfo.source_study_area_code meta,count(*)::bigint cnt
      from catalogue.student_flow_observations sfo
      join ref.outcome_surveys os on os.id=sfo.survey_id
      where os.code='prisms_international_students'
        and sfo.source_study_area_code is not null
        and (v_query is null or lower(coalesce(sfo.source_study_area_name,'')||' '||sfo.source_study_area_code) like '%'||v_query||'%')
      group by sfo.source_study_area_code,sfo.source_study_area_name
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta,'count',cnt) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;
  else
    raise exception 'unsupported filter option kind: %',coalesce(v_kind,'') using errcode='22023';
  end if;

  return jsonb_build_object(
    'items',v_items,'total',v_total,'limit',v_limit,'offset',v_offset,
    'has_more',(v_offset+jsonb_array_length(v_items))<v_total
  );
end $function$
