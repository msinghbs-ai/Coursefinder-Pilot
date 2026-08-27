-- A10 — platform-wide server-paged growing filter option domains.

begin;

create or replace function security.admin_filter_option_page(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','security','pipeline','catalogue','ref','auth'
as $$
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
      select s.id::text value,s.label label,concat_ws(' · ',nullif(s.source_type,''),co.iso_alpha2::text) meta,count(*)::bigint cnt
      from pipeline.evidence_artifacts e join pipeline.sources s on s.id=e.source_id left join ref.countries co on co.id=s.country_id
      where (v_country is null or upper(co.iso_alpha2::text)=v_country)
        and (v_query is null or lower(s.label||' '||coalesce(s.source_type,'')||' '||coalesce(co.iso_alpha2::text,'')) like '%'||v_query||'%')
      group by s.id,s.label,s.source_type,co.iso_alpha2
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta,'count',cnt) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0) into v_items,v_total;

  elsif v_kind='qilt_provider' then
    if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
    with q as (
      select p.id::text value,coalesce(p.display_name,p.canonical_name) label,p.stable_key meta,count(*)::bigint cnt
      from catalogue.provider_outcomes po join catalogue.providers p on p.id=po.provider_id join ref.outcome_surveys os on os.id=po.survey_id
      where os.code like 'qilt_%' and (v_survey is null or os.code=v_survey)
        and (v_query is null or lower(coalesce(p.display_name,p.canonical_name)||' '||coalesce(p.stable_key,'')) like '%'||v_query||'%')
      group by p.id,p.display_name,p.canonical_name,p.stable_key
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta,'count',cnt) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0) into v_items,v_total;

  elsif v_kind='qilt_metric' then
    if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
    with q as (
      select om.code value,om.name label,concat_ws(' · ',om.unit,om.code) meta,count(*)::bigint cnt
      from catalogue.provider_outcomes po join ref.outcome_surveys os on os.id=po.survey_id join ref.outcome_metrics om on om.id=po.metric_id
      where os.code like 'qilt_%' and (v_survey is null or os.code=v_survey)
        and (v_query is null or lower(om.name||' '||om.code||' '||coalesce(om.unit,'')) like '%'||v_query||'%')
      group by om.code,om.name,om.unit
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta,'count',cnt) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0) into v_items,v_total;

  elsif v_kind='prisms_study_area' then
    if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
    with q as (
      select sfo.source_study_area_code value,sfo.source_study_area_name label,sfo.source_study_area_code meta,count(*)::bigint cnt
      from catalogue.student_flow_observations sfo join ref.outcome_surveys os on os.id=sfo.survey_id
      where os.code='prisms_international_students' and sfo.source_study_area_code is not null
        and (v_query is null or lower(coalesce(sfo.source_study_area_name,'')||' '||sfo.source_study_area_code) like '%'||v_query||'%')
      group by sfo.source_study_area_code,sfo.source_study_area_name
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta,'count',cnt) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0) into v_items,v_total;
  else
    raise exception 'unsupported filter option kind: %',coalesce(v_kind,'') using errcode='22023';
  end if;

  return jsonb_build_object('items',v_items,'total',v_total,'limit',v_limit,'offset',v_offset,'has_more',(v_offset+jsonb_array_length(v_items))<v_total);
end $$;

revoke all on function security.admin_filter_option_page(jsonb) from public,anon;
grant execute on function security.admin_filter_option_page(jsonb) to authenticated,service_role;

create or replace function public.ui_qilt_filter_options(p_survey_code text default null)
returns jsonb language sql stable security definer
set search_path to 'public','catalogue','ref','auth'
as $$
  select case when auth.uid() is null or security.current_role_rank() < 1 then null else jsonb_build_object(
    'surveys',coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'count',x.cnt) order by x.name) from (select os.code,os.name,count(*)::bigint cnt from catalogue.provider_outcomes po join ref.outcome_surveys os on os.id=po.survey_id where os.code like 'qilt_%' group by os.code,os.name)x),'[]'::jsonb),
    'metrics','[]'::jsonb,'providers','[]'::jsonb,
    'statuses',coalesce((select jsonb_agg(jsonb_build_object('code',x.status,'name',initcap(replace(x.status,'_',' ')),'count',x.cnt) order by x.status) from (select po.status,count(*)::bigint cnt from catalogue.provider_outcomes po join ref.outcome_surveys os on os.id=po.survey_id where os.code like 'qilt_%' group by po.status)x),'[]'::jsonb),
    'years',coalesce((select jsonb_agg(jsonb_build_object('value',x.y,'label',x.y::text,'count',x.cnt) order by x.y desc) from (select collection_year_to y,count(*)::bigint cnt from catalogue.provider_outcomes po join ref.outcome_surveys os on os.id=po.survey_id where os.code like 'qilt_%' and collection_year_to is not null group by collection_year_to)x),'[]'::jsonb)
  ) end
$$;

create or replace function public.ui_prisms_filter_options()
returns jsonb language sql stable security definer
set search_path to 'public','catalogue','ref','auth'
as $$
  select case when auth.uid() is null or security.current_role_rank() < 1 then null else jsonb_build_object(
    'subdivisions',coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'count',x.cnt) order by x.name) from (select sub.code,sub.name,count(*)::bigint cnt from catalogue.student_flow_observations sfo join ref.outcome_surveys os on os.id=sfo.survey_id left join ref.subdivisions sub on sub.id=sfo.subdivision_id where os.code='prisms_international_students' and sub.id is not null group by sub.code,sub.name)x),'[]'::jsonb),
    'study_areas','[]'::jsonb,
    'sectors',coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',initcap(replace(x.code,'_',' ')),'count',x.cnt) order by x.code) from (select source_sector_code code,count(*)::bigint cnt from catalogue.student_flow_observations sfo join ref.outcome_surveys os on os.id=sfo.survey_id where os.code='prisms_international_students' and source_sector_code is not null group by source_sector_code)x),'[]'::jsonb),
    'remoteness',coalesce((select jsonb_agg(jsonb_build_object('code',x.name,'name',x.name,'count',x.cnt) order by x.name) from (select source_remoteness_area name,count(*)::bigint cnt from catalogue.student_flow_observations sfo join ref.outcome_surveys os on os.id=sfo.survey_id where os.code='prisms_international_students' and source_remoteness_area is not null group by source_remoteness_area)x),'[]'::jsonb)
  ) end
$$;

create or replace function security.admin_evidence_filter_options()
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','security','pipeline','ref','auth'
as $$
declare v_rank integer:=0; v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
  select jsonb_build_object(
    'countries',coalesce((select jsonb_agg(x order by x->>'code') from (select jsonb_build_object('code',co.iso_alpha2,'name',co.name) x from pipeline.evidence_artifacts e join pipeline.sources s on s.id=e.source_id join ref.countries co on co.id=s.country_id group by co.iso_alpha2,co.name) q),'[]'::jsonb),
    'sources','[]'::jsonb,
    'layers',coalesce((select jsonb_agg(x order by x->>'code') from (select jsonb_build_object('code',security.admin_evidence_layer(e.storage_path,e.evidence_type,e.metadata,s.source_type),'name',security.admin_evidence_layer(e.storage_path,e.evidence_type,e.metadata,s.source_type)) x from pipeline.evidence_artifacts e left join pipeline.sources s on s.id=e.source_id group by 1) q),'[]'::jsonb),
    'entity_types',jsonb_build_array(jsonb_build_object('code','provider','name','Provider'),jsonb_build_object('code','course','name','Course'),jsonb_build_object('code','campus','name','Campus'),jsonb_build_object('code','scholarship','name','Scholarship')),
    'evidence_types',coalesce((select jsonb_agg(jsonb_build_object('code',evidence_type,'name',evidence_type) order by evidence_type) from (select distinct evidence_type from pipeline.evidence_artifacts where evidence_type is not null) q),'[]'::jsonb),
    'mimes',coalesce((select jsonb_agg(jsonb_build_object('code',mime_type,'name',mime_type) order by mime_type) from (select distinct mime_type from pipeline.evidence_artifacts where mime_type is not null) q),'[]'::jsonb),
    'job_statuses',coalesce((select jsonb_agg(jsonb_build_object('code',status,'name',status) order by status) from (select distinct j.status from pipeline.evidence_artifacts e join pipeline.jobs j on j.id=e.job_id where j.status is not null) q),'[]'::jsonb),
    'statuses',jsonb_build_array(jsonb_build_object('code','current','name','Current'),jsonb_build_object('code','missing_extraction','name','Missing extraction'),jsonb_build_object('code','source_null','name','Source-null value'),jsonb_build_object('code','stale','name','Stale'),jsonb_build_object('code','conflict','name','Unresolved conflict'),jsonb_build_object('code','rejected','name','Rejected'),jsonb_build_object('code','superseded','name','Superseded')),
    'extraction_states',jsonb_build_array(jsonb_build_object('code','extracted','name','Extracted / linked'),jsonb_build_object('code','missing_extraction','name','Missing extraction'),jsonb_build_object('code','rejected','name','Rejected')),
    'freshness_states',jsonb_build_array(jsonb_build_object('code','stale','name','Stale (policy-backed only)'),jsonb_build_object('code','expired','name','Expired validity'),jsonb_build_object('code','current','name','Within validity'),jsonb_build_object('code','no_policy','name','No freshness policy'))
  ) into v_result;
  return v_result;
end $$;

do $$
declare v_oid oid;v_def text;
begin
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='admin_read'
    and pg_get_function_identity_arguments(p.oid)='p_operation text, p_args jsonb' limit 1;
  select pg_get_functiondef(v_oid) into v_def;
  if position('admin_filter_option_page' in v_def)=0 then
    if position('if p_operation=''dashboard'' then' in v_def)=0 then raise exception 'admin_read marker not found'; end if;
    v_def:=replace(v_def,'if p_operation=''dashboard'' then','if p_operation=''admin_filter_option_page'' then return security.admin_filter_option_page(p_args); end if;'||chr(10)||' if p_operation=''dashboard'' then');
    execute v_def;
  end if;
end $$;

commit;
