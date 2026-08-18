alter table catalogue.student_flow_observations
  alter column metric_value drop not null;

alter table catalogue.student_flow_observations
  add column if not exists is_suppressed boolean not null default false,
  add column if not exists suppression_code text;

alter table catalogue.student_flow_observations
  drop constraint if exists student_flow_observations_metric_value_check;

alter table catalogue.student_flow_observations
  add constraint student_flow_observations_value_or_suppression_check
  check (
    (is_suppressed = false and metric_value is not null and metric_value >= 0 and suppression_code is null)
    or
    (is_suppressed = true and metric_value is null and suppression_code is not null)
  );

create or replace function pipeline.svc_prisms_apply_observations(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pipeline','catalogue','ref','public','extensions'
as $function$
declare
  r jsonb;
  v_changed integer:=0;
  v_seen integer:=0;
  v_rc integer;
  v_country uuid;
  v_survey uuid;
  v_source pipeline.sources%rowtype;
  v_provider uuid;
  v_course uuid;
  v_area uuid;
  v_field uuid;
  v_suppressed boolean;
  v_value bigint;
  v_suppression_code text;
begin
  if p_rows is null or jsonb_typeof(p_rows)<>'array' then
    raise exception 'p_rows must be a JSON array';
  end if;
  if jsonb_array_length(p_rows)>5000 then
    raise exception 'bounded apply limit exceeded';
  end if;

  select id into v_country from ref.countries where iso_alpha2='AU';
  select id into v_survey from ref.outcome_surveys
  where code='prisms_international_students' and source_family='PRISMS' and status='active';

  for r in select value from jsonb_array_elements(p_rows)
  loop
    v_seen:=v_seen+1;
    v_provider:=nullif(r->>'provider_id','')::uuid;
    v_course:=nullif(r->>'course_id','')::uuid;
    v_area:=nullif(r->>'external_study_area_id','')::uuid;
    v_field:=nullif(r->>'field_of_study_id','')::uuid;
    v_suppressed:=coalesce((r->>'is_suppressed')::boolean,false);
    v_value:=nullif(r->>'metric_value','')::bigint;
    v_suppression_code:=nullif(r->>'suppression_code','');

    if (r->>'host_country_id')::uuid is distinct from v_country then
      raise exception 'PRISMS observation host country must be AU';
    end if;
    if (r->>'survey_id')::uuid is distinct from v_survey then
      raise exception 'PRISMS observation survey is invalid';
    end if;
    if not exists(
      select 1 from ref.outcome_metrics m
      where m.id=(r->>'metric_id')::uuid and m.survey_id=v_survey and m.status='active'
    ) then
      raise exception 'PRISMS observation metric is invalid';
    end if;
    if coalesce(nullif(r->>'audience',''),'international') <> 'international' then
      raise exception 'PRISMS observation audience must be international';
    end if;
    if nullif(r->>'source_observation_key','') is null then
      raise exception 'PRISMS source observation key is required';
    end if;
    if (not v_suppressed and (v_value is null or v_value < 0 or v_suppression_code is not null))
       or (v_suppressed and (v_value is not null or v_suppression_code is null)) then
      raise exception 'PRISMS observation must contain either an exact non-negative count or an explicit suppression marker';
    end if;

    select * into v_source from pipeline.sources where id=(r->>'source_id')::uuid;
    if v_source.id is null
       or v_source.country_id is distinct from v_country
       or coalesce(v_source.metadata->>'source_system','') <> 'PRISMS'
       or coalesce(v_source.metadata->>'identity_authority','true') <> 'false' then
      raise exception 'PRISMS observation source is invalid';
    end if;
    if not exists(
      select 1 from pipeline.evidence_artifacts e
      where e.id=(r->>'evidence_id')::uuid
        and e.source_id=v_source.id
        and e.evidence_type='prisms_published_workbook'
    ) then
      raise exception 'PRISMS observation evidence is invalid';
    end if;

    if v_provider is not null then
      if coalesce(v_source.metadata->>'published_provider_dimension','false') <> 'true' then
        raise exception 'source does not publish a Provider dimension';
      end if;
      if not exists(
        select 1 from catalogue.providers p
        join ref.countries c on c.id=p.country_id
        where p.id=v_provider and c.iso_alpha2='AU'
      ) then
        raise exception 'PRISMS Provider target must be an existing AU CRICOS Provider';
      end if;
    end if;

    if v_course is not null then
      if coalesce(v_source.metadata->>'published_course_dimension','false') <> 'true' then
        raise exception 'source does not publish a Course dimension';
      end if;
      if v_provider is null or not exists(
        select 1 from catalogue.courses co
        join catalogue.providers p on p.id=co.provider_id
        join ref.countries c on c.id=p.country_id
        where co.id=v_course and co.provider_id=v_provider and c.iso_alpha2='AU'
      ) then
        raise exception 'PRISMS Course target must be an existing AU CRICOS Course under the mapped Provider';
      end if;
    end if;

    if nullif(r->>'subdivision_id','') is not null and not exists(
      select 1 from ref.subdivisions s
      where s.id=(r->>'subdivision_id')::uuid
        and s.country_id=v_country
        and s.status='active'
    ) then
      raise exception 'PRISMS subdivision must be an active AU subdivision';
    end if;

    if v_area is not null and not exists(
      select 1 from ref.external_study_areas esa
      where esa.id=v_area and esa.source_system='PRISMS' and esa.status='active'
    ) then
      raise exception 'PRISMS external study area is invalid';
    end if;

    if v_field is not null and not exists(
      select 1 from ref.external_study_area_mappings eam
      where eam.external_study_area_id=v_area
        and eam.field_of_study_id=v_field
        and eam.status='active'
    ) then
      raise exception 'canonical field requires an active governed PRISMS study-area mapping';
    end if;

    if nullif(r->>'study_level_id','') is not null and not exists(
      select 1 from ref.study_levels sl
      where sl.id=(r->>'study_level_id')::uuid and sl.status='active'
    ) then
      raise exception 'PRISMS study level is invalid';
    end if;

    insert into catalogue.student_flow_observations(
      host_country_id,provider_id,course_id,subdivision_id,
      external_study_area_id,field_of_study_id,study_level_id,
      survey_id,metric_id,audience,period_start,period_end,period_type,
      source_geography_type,source_geography_key,source_geography_name,
      source_remoteness_area,source_sector_code,source_provider_type,
      source_nationality_code,source_nationality_name,
      source_study_area_code,source_study_area_name,source_observation_key,
      metric_value,is_suppressed,suppression_code,
      source_id,evidence_id,observed_at,status,metadata
    )
    values(
      v_country,v_provider,v_course,nullif(r->>'subdivision_id','')::uuid,
      v_area,v_field,nullif(r->>'study_level_id','')::uuid,
      v_survey,(r->>'metric_id')::uuid,'international',
      (r->>'period_start')::date,(r->>'period_end')::date,
      coalesce(nullif(r->>'period_type',''),'ytd'),
      nullif(r->>'source_geography_type',''),
      nullif(r->>'source_geography_key',''),
      nullif(r->>'source_geography_name',''),
      nullif(r->>'source_remoteness_area',''),
      nullif(r->>'source_sector_code',''),
      nullif(r->>'source_provider_type',''),
      nullif(r->>'source_nationality_code',''),
      nullif(r->>'source_nationality_name',''),
      nullif(r->>'source_study_area_code',''),
      nullif(r->>'source_study_area_name',''),
      r->>'source_observation_key',
      v_value,v_suppressed,v_suppression_code,
      v_source.id,(r->>'evidence_id')::uuid,
      coalesce(nullif(r->>'observed_at','')::timestamptz,now()),
      coalesce(nullif(r->>'status',''),'current'),
      coalesce(r->'metadata','{}'::jsonb)
    )
    on conflict(source_id,source_observation_key)
    do update set
      provider_id=excluded.provider_id,
      course_id=excluded.course_id,
      subdivision_id=excluded.subdivision_id,
      external_study_area_id=excluded.external_study_area_id,
      field_of_study_id=excluded.field_of_study_id,
      study_level_id=excluded.study_level_id,
      audience=excluded.audience,
      period_start=excluded.period_start,
      period_end=excluded.period_end,
      period_type=excluded.period_type,
      source_geography_type=excluded.source_geography_type,
      source_geography_key=excluded.source_geography_key,
      source_geography_name=excluded.source_geography_name,
      source_remoteness_area=excluded.source_remoteness_area,
      source_sector_code=excluded.source_sector_code,
      source_provider_type=excluded.source_provider_type,
      source_nationality_code=excluded.source_nationality_code,
      source_nationality_name=excluded.source_nationality_name,
      source_study_area_code=excluded.source_study_area_code,
      source_study_area_name=excluded.source_study_area_name,
      metric_value=excluded.metric_value,
      is_suppressed=excluded.is_suppressed,
      suppression_code=excluded.suppression_code,
      evidence_id=excluded.evidence_id,
      observed_at=excluded.observed_at,
      status=excluded.status,
      metadata=excluded.metadata,
      updated_at=now()
    where (
      catalogue.student_flow_observations.provider_id,
      catalogue.student_flow_observations.course_id,
      catalogue.student_flow_observations.subdivision_id,
      catalogue.student_flow_observations.external_study_area_id,
      catalogue.student_flow_observations.field_of_study_id,
      catalogue.student_flow_observations.study_level_id,
      catalogue.student_flow_observations.audience,
      catalogue.student_flow_observations.period_start,
      catalogue.student_flow_observations.period_end,
      catalogue.student_flow_observations.period_type,
      catalogue.student_flow_observations.source_geography_type,
      catalogue.student_flow_observations.source_geography_key,
      catalogue.student_flow_observations.source_geography_name,
      catalogue.student_flow_observations.source_remoteness_area,
      catalogue.student_flow_observations.source_sector_code,
      catalogue.student_flow_observations.source_provider_type,
      catalogue.student_flow_observations.source_nationality_code,
      catalogue.student_flow_observations.source_nationality_name,
      catalogue.student_flow_observations.source_study_area_code,
      catalogue.student_flow_observations.source_study_area_name,
      catalogue.student_flow_observations.metric_value,
      catalogue.student_flow_observations.is_suppressed,
      catalogue.student_flow_observations.suppression_code,
      catalogue.student_flow_observations.evidence_id,
      catalogue.student_flow_observations.status,
      catalogue.student_flow_observations.metadata
    ) is distinct from (
      excluded.provider_id,
      excluded.course_id,
      excluded.subdivision_id,
      excluded.external_study_area_id,
      excluded.field_of_study_id,
      excluded.study_level_id,
      excluded.audience,
      excluded.period_start,
      excluded.period_end,
      excluded.period_type,
      excluded.source_geography_type,
      excluded.source_geography_key,
      excluded.source_geography_name,
      excluded.source_remoteness_area,
      excluded.source_sector_code,
      excluded.source_provider_type,
      excluded.source_nationality_code,
      excluded.source_nationality_name,
      excluded.source_study_area_code,
      excluded.source_study_area_name,
      excluded.metric_value,
      excluded.is_suppressed,
      excluded.suppression_code,
      excluded.evidence_id,
      excluded.status,
      excluded.metadata
    );

    get diagnostics v_rc=row_count;
    v_changed:=v_changed+v_rc;
  end loop;

  return jsonb_build_object('seen',v_seen,'changed',v_changed);
end
$function$;

revoke all on function pipeline.svc_prisms_apply_observations(jsonb) from public,anon,authenticated;
grant execute on function pipeline.svc_prisms_apply_observations(jsonb) to service_role;

create or replace function public.svc_prisms_apply_observations(p_rows jsonb)
returns jsonb
language sql
security definer
set search_path to 'pipeline','public'
as $function$
  select pipeline.svc_prisms_apply_observations(p_rows);
$function$;

revoke all on function public.svc_prisms_apply_observations(jsonb) from public,anon,authenticated;
grant execute on function public.svc_prisms_apply_observations(jsonb) to service_role;

drop function if exists public.ui_international_student_observations(date,text,text,integer);

create function public.ui_international_student_observations(
  p_period_end date default null,
  p_subdivision_code text default null,
  p_sector text default null,
  p_limit integer default 1000
)
returns table(
  observation_id uuid,
  host_country_code text,
  subdivision_code text,
  subdivision_name text,
  survey_code text,
  metric_code text,
  metric_name text,
  unit text,
  audience text,
  period_start date,
  period_end date,
  period_type text,
  source_geography_type text,
  source_geography_key text,
  source_geography_name text,
  source_remoteness_area text,
  source_sector_code text,
  source_study_area_code text,
  source_study_area_name text,
  canonical_field_code text,
  canonical_field_name text,
  metric_value bigint,
  is_suppressed boolean,
  suppression_code text,
  source_label text,
  source_url text,
  collection_version text,
  evidence_hash text,
  evidence_storage_path text,
  provider_id uuid,
  course_id uuid,
  status text,
  metadata jsonb
)
language sql
stable
security definer
set search_path to 'public','catalogue','ref','pipeline','auth'
as $function$
select
  o.id,
  trim(c.iso_alpha2)::text,
  s.code,
  s.name,
  os.code,
  m.code,
  m.name,
  m.unit,
  o.audience,
  o.period_start,
  o.period_end,
  o.period_type,
  o.source_geography_type,
  o.source_geography_key,
  o.source_geography_name,
  o.source_remoteness_area,
  o.source_sector_code,
  o.source_study_area_code,
  o.source_study_area_name,
  f.code,
  f.name,
  o.metric_value,
  o.is_suppressed,
  o.suppression_code,
  ps.label,
  ps.url,
  ps.metadata->>'collection_version',
  ea.content_hash,
  ea.storage_path,
  o.provider_id,
  o.course_id,
  o.status,
  o.metadata
from catalogue.student_flow_observations o
join ref.countries c on c.id=o.host_country_id
join ref.outcome_surveys os on os.id=o.survey_id
join ref.outcome_metrics m on m.id=o.metric_id
join pipeline.sources ps on ps.id=o.source_id
join pipeline.evidence_artifacts ea on ea.id=o.evidence_id
left join ref.subdivisions s on s.id=o.subdivision_id
left join ref.fields_of_study f on f.id=o.field_of_study_id
where auth.uid() is not null
  and os.source_family='PRISMS'
  and (p_period_end is null or o.period_end=p_period_end)
  and (p_subdivision_code is null or s.code=p_subdivision_code)
  and (p_sector is null or o.source_sector_code=p_sector)
order by o.period_end desc,s.code,o.source_geography_name,o.source_sector_code,o.source_study_area_code,m.code
limit least(greatest(coalesce(p_limit,1000),1),5000);
$function$;

revoke all on function public.ui_international_student_observations(date,text,text,integer) from public,anon;
grant execute on function public.ui_international_student_observations(date,text,text,integer) to authenticated,service_role;
