-- M1-L2-AU-PRISMS: structured international-student flow observations.
-- PRISMS is Layer 2A enrichment only. It must not create/redefine Provider or Course identity.

insert into ref.subdivisions(country_id, code, name, subdivision_type, status)
select c.id, v.code, v.name, v.kind, 'active'
from ref.countries c
cross join (values
  ('AU-ACT','Australian Capital Territory','territory'),
  ('AU-NSW','New South Wales','state'),
  ('AU-NT','Northern Territory','territory'),
  ('AU-QLD','Queensland','state'),
  ('AU-SA','South Australia','state'),
  ('AU-TAS','Tasmania','state'),
  ('AU-VIC','Victoria','state'),
  ('AU-WA','Western Australia','state')
) as v(code,name,kind)
where c.iso_alpha2='AU'
on conflict(code) do update
set country_id=excluded.country_id,
    name=excluded.name,
    subdivision_type=excluded.subdivision_type,
    status='active',
    updated_at=now();

insert into ref.outcome_surveys(code,name,source_family,description,status)
values (
  'prisms_international_students',
  'PRISMS International Student Enrolments and Commencements',
  'PRISMS',
  'Department of Education PRISMS-derived international student enrolment and commencement counts. Statistical enrichment only; never Provider/Course identity.',
  'active'
)
on conflict(code) do update
set name=excluded.name,
    source_family=excluded.source_family,
    description=excluded.description,
    status='active',
    updated_at=now();

with s as (
  select id from ref.outcome_surveys where code='prisms_international_students'
), defs(code,name,category,unit,description) as (
  values
    ('enrolments','International student enrolments','student_flow','count','Published cumulative international-student enrolment count.'),
    ('commencements','International student commencements','student_flow','count','Published cumulative international-student commencement count.')
)
insert into ref.outcome_metrics(survey_id,code,name,category,unit,higher_is_better,description,status)
select s.id,d.code,d.name,d.category,d.unit,null,d.description,'active'
from s cross join defs d
on conflict(survey_id,code) do update
set name=excluded.name,
    category=excluded.category,
    unit=excluded.unit,
    higher_is_better=null,
    description=excluded.description,
    status='active',
    updated_at=now();

with defs(external_code,name,description) as (
  values
    ('agriculture_environmental_related_studies','Agriculture, Environmental and Related Studies','PRISMS published broad field of education.'),
    ('architecture_building','Architecture and Building','PRISMS published broad field of education.'),
    ('creative_arts','Creative Arts','PRISMS published broad field of education.'),
    ('education','Education','PRISMS published broad field of education.'),
    ('engineering_related_technologies','Engineering and Related Technologies','PRISMS published broad field of education.'),
    ('food_hospitality_personal_services','Food, Hospitality and Personal Services','PRISMS published broad field of education.'),
    ('health','Health','PRISMS published broad field of education.'),
    ('information_technology','Information Technology','PRISMS published broad field of education.'),
    ('management_commerce','Management and Commerce','PRISMS published broad field of education.'),
    ('mixed_field_programmes','Mixed Field Programmes','PRISMS published broad field of education.'),
    ('natural_physical_sciences','Natural and Physical Sciences','PRISMS published broad field of education.'),
    ('society_culture','Society and Culture','PRISMS published broad field of education.'),
    ('dual_qualification','_Dual Qualification','PRISMS published dual-qualification grouping; no canonical field mapping implied.')
)
insert into ref.external_study_areas(source_system,external_code,name,description,status)
select 'PRISMS',d.external_code,d.name,d.description,'active'
from defs d
on conflict(source_system,external_code) do update
set name=excluded.name,
    description=excluded.description,
    status='active',
    updated_at=now();

-- Only exact, already-existing canonical field labels are mapped at this gate.
with pairs(external_code,field_code) as (
  values
    ('management_commerce','management-commerce'),
    ('natural_physical_sciences','natural-physical-sciences')
)
insert into ref.external_study_area_mappings(
  external_study_area_id,field_of_study_id,match_method,confidence,status,verified_at,notes
)
select esa.id,f.id,'exact_existing_canonical_label',1.0000,'active',now(),
       'M1-L2-AU-PRISMS deterministic exact-label mapping; PRISMS has no identity authority.'
from pairs p
join ref.external_study_areas esa
  on esa.source_system='PRISMS' and esa.external_code=p.external_code
join ref.fields_of_study f on f.code=p.field_code and f.status='active'
on conflict(external_study_area_id,field_of_study_id) do update
set match_method=excluded.match_method,
    confidence=excluded.confidence,
    status='active',
    verified_at=coalesce(ref.external_study_area_mappings.verified_at,excluded.verified_at),
    notes=excluded.notes,
    updated_at=now();

create table if not exists catalogue.student_flow_observations (
  id uuid primary key default gen_random_uuid(),
  host_country_id uuid not null references ref.countries(id) on delete restrict,
  provider_id uuid references catalogue.providers(id) on delete restrict,
  course_id uuid references catalogue.courses(id) on delete restrict,
  subdivision_id uuid references ref.subdivisions(id) on delete restrict,
  external_study_area_id uuid references ref.external_study_areas(id) on delete restrict,
  field_of_study_id uuid references ref.fields_of_study(id) on delete restrict,
  study_level_id uuid references ref.study_levels(id) on delete restrict,
  survey_id uuid not null references ref.outcome_surveys(id) on delete restrict,
  metric_id uuid not null references ref.outcome_metrics(id) on delete restrict,
  audience text not null default 'international'
    check(audience in ('all','domestic','international','mixed','unknown')),
  period_start date not null,
  period_end date not null,
  period_type text not null check(period_type in ('month','ytd','year','snapshot')),
  source_geography_type text,
  source_geography_key text,
  source_geography_name text,
  source_remoteness_area text,
  source_sector_code text,
  source_provider_type text,
  source_nationality_code text,
  source_nationality_name text,
  source_study_area_code text,
  source_study_area_name text,
  source_observation_key text not null,
  metric_value bigint not null check(metric_value >= 0),
  source_id uuid not null references pipeline.sources(id) on delete restrict,
  evidence_id uuid not null references pipeline.evidence_artifacts(id) on delete restrict,
  observed_at timestamptz not null default now(),
  status text not null default 'current'
    check(status in ('current','superseded','withdrawn','review')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(period_end >= period_start),
  check(course_id is null or provider_id is not null)
);

create unique index if not exists uq_student_flow_source_observation
  on catalogue.student_flow_observations(source_id,source_observation_key);
create index if not exists idx_student_flow_metric_period
  on catalogue.student_flow_observations(metric_id,period_end desc);
create index if not exists idx_student_flow_subdivision_period
  on catalogue.student_flow_observations(subdivision_id,period_end desc)
  where subdivision_id is not null;
create index if not exists idx_student_flow_external_area_period
  on catalogue.student_flow_observations(external_study_area_id,period_end desc)
  where external_study_area_id is not null;
create index if not exists idx_student_flow_canonical_field_period
  on catalogue.student_flow_observations(field_of_study_id,period_end desc)
  where field_of_study_id is not null;
create index if not exists idx_student_flow_provider_period
  on catalogue.student_flow_observations(provider_id,period_end desc)
  where provider_id is not null;
create index if not exists idx_student_flow_course
  on catalogue.student_flow_observations(course_id)
  where course_id is not null;
create index if not exists idx_student_flow_country
  on catalogue.student_flow_observations(host_country_id);
create index if not exists idx_student_flow_survey
  on catalogue.student_flow_observations(survey_id);
create index if not exists idx_student_flow_study_level
  on catalogue.student_flow_observations(study_level_id)
  where study_level_id is not null;
create index if not exists idx_student_flow_evidence
  on catalogue.student_flow_observations(evidence_id);

alter table catalogue.student_flow_observations enable row level security;
revoke all on catalogue.student_flow_observations from anon,authenticated;
grant all on catalogue.student_flow_observations to service_role;

create or replace function public.svc_prisms_context()
returns jsonb
language sql
security definer
set search_path to 'catalogue','ref','public','extensions'
as $function$
with au as (
  select id from ref.countries where iso_alpha2='AU'
), survey as (
  select id from ref.outcome_surveys
  where code='prisms_international_students'
    and source_family='PRISMS'
    and status='active'
), metrics as (
  select coalesce(jsonb_object_agg(m.code,m.id),'{}'::jsonb) j
  from ref.outcome_metrics m
  join survey s on s.id=m.survey_id
  where m.status='active'
), subdivisions as (
  select coalesce(jsonb_agg(
    jsonb_build_object('id',s.id,'code',s.code,'name',s.name)
    order by s.code
  ),'[]'::jsonb) j
  from ref.subdivisions s join au on au.id=s.country_id
  where s.status='active'
), areas as (
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',esa.id,
      'external_code',esa.external_code,
      'name',esa.name,
      'field_of_study_id',m.field_of_study_id,
      'canonical_field_code',f.code,
      'canonical_field_name',f.name
    ) order by esa.external_code
  ),'[]'::jsonb) j
  from ref.external_study_areas esa
  left join lateral (
    select eam.field_of_study_id
    from ref.external_study_area_mappings eam
    where eam.external_study_area_id=esa.id and eam.status='active'
    order by eam.confidence desc nulls last
    limit 1
  ) m on true
  left join ref.fields_of_study f on f.id=m.field_of_study_id
  where esa.source_system='PRISMS' and esa.status='active'
)
select jsonb_build_object(
  'country_id',(select id from au),
  'survey_id',(select id from survey),
  'metric_ids',(select j from metrics),
  'subdivisions',(select j from subdivisions),
  'external_study_areas',(select j from areas)
);
$function$;

create or replace function public.svc_prisms_prepare_source(
  p_label text,
  p_url text,
  p_collection_version text,
  p_period_start date,
  p_period_end date
)
returns uuid
language plpgsql
security definer
set search_path to 'pipeline','ref','public','extensions'
as $function$
declare v_id uuid; v_country uuid;
begin
  select id into v_country from ref.countries where iso_alpha2='AU';
  if v_country is null then raise exception 'AU country reference missing'; end if;

  select id into v_id
  from pipeline.sources
  where label=p_label and url=p_url
  order by created_at
  limit 1;

  if v_id is null then
    insert into pipeline.sources(
      source_type,country_id,url,label,trust_rank,status,metadata
    )
    values(
      'structured_outcomes',v_country,p_url,p_label,95,'active',
      jsonb_build_object(
        'layer','2A',
        'publisher','Department of Education',
        'source_system','PRISMS',
        'collection_version',p_collection_version,
        'period_start',p_period_start,
        'period_end',p_period_end,
        'published_grain','state+sa4+remoteness+sector+broad_field',
        'published_provider_dimension',false,
        'published_course_dimension',false,
        'identity_authority',false
      )
    )
    returning id into v_id;
  else
    update pipeline.sources
    set source_type='structured_outcomes',
        country_id=v_country,
        trust_rank=95,
        status='active',
        metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
          'layer','2A',
          'publisher','Department of Education',
          'source_system','PRISMS',
          'collection_version',p_collection_version,
          'period_start',p_period_start,
          'period_end',p_period_end,
          'published_grain','state+sa4+remoteness+sector+broad_field',
          'published_provider_dimension',false,
          'published_course_dimension',false,
          'identity_authority',false
        ),
        updated_at=now()
    where id=v_id;
  end if;
  return v_id;
end
$function$;

create or replace function public.svc_prisms_touch_source(
  p_source_id uuid,
  p_ok boolean,
  p_error text default null
)
returns void
language plpgsql
security definer
set search_path to 'pipeline','public'
as $function$
begin
  update pipeline.sources
  set last_checked_at=now(),
      last_success_at=case when p_ok then now() else last_success_at end,
      last_failure_at=case when not p_ok then now() else last_failure_at end,
      last_error=case when p_ok then null else p_error end,
      updated_at=now()
  where id=p_source_id;
end
$function$;

create or replace function public.svc_prisms_register_evidence(
  p_source_id uuid,
  p_source_url text,
  p_storage_path text,
  p_content_hash text,
  p_collection_version text,
  p_period_start date,
  p_period_end date,
  p_worker_version text
)
returns uuid
language plpgsql
security definer
set search_path to 'pipeline','public','extensions'
as $function$
declare v_id uuid;
begin
  select id into v_id
  from pipeline.evidence_artifacts
  where source_id=p_source_id
    and evidence_type='prisms_published_workbook'
    and content_hash=p_content_hash
  order by captured_at desc
  limit 1;

  if v_id is null then
    insert into pipeline.evidence_artifacts(
      source_id,evidence_type,source_url,storage_path,content_hash,mime_type,metadata
    )
    values(
      p_source_id,
      'prisms_published_workbook',
      p_source_url,
      p_storage_path,
      p_content_hash,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      jsonb_build_object(
        'layer','2A',
        'publisher','Department of Education',
        'source_system','PRISMS',
        'collection_version',p_collection_version,
        'period_start',p_period_start,
        'period_end',p_period_end,
        'worker_version',p_worker_version,
        'identity_authority',false
      )
    )
    returning id into v_id;
  end if;
  return v_id;
end
$function$;

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
    if nullif(r->>'metric_value','') is null or (r->>'metric_value')::bigint < 0 then
      raise exception 'PRISMS metric value must be a non-negative count';
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
      metric_value,source_id,evidence_id,observed_at,status,metadata
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
      (r->>'metric_value')::bigint,
      v_source.id,(r->>'evidence_id')::uuid,
      coalesce(nullif(r->>'observed_at','')::timestamptz,now()),
      coalesce(nullif(r->>'status',''),'current'),
      coalesce(r->'metadata','{}'::jsonb)
    )
    on conflict(source_id,source_observation_key)
    do update set
      subdivision_id=excluded.subdivision_id,
      external_study_area_id=excluded.external_study_area_id,
      field_of_study_id=excluded.field_of_study_id,
      study_level_id=excluded.study_level_id,
      metric_value=excluded.metric_value,
      evidence_id=excluded.evidence_id,
      observed_at=excluded.observed_at,
      status=excluded.status,
      metadata=excluded.metadata,
      updated_at=now()
    where (
      catalogue.student_flow_observations.subdivision_id,
      catalogue.student_flow_observations.external_study_area_id,
      catalogue.student_flow_observations.field_of_study_id,
      catalogue.student_flow_observations.study_level_id,
      catalogue.student_flow_observations.metric_value,
      catalogue.student_flow_observations.evidence_id,
      catalogue.student_flow_observations.status,
      catalogue.student_flow_observations.metadata
    ) is distinct from (
      excluded.subdivision_id,
      excluded.external_study_area_id,
      excluded.field_of_study_id,
      excluded.study_level_id,
      excluded.metric_value,
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

create or replace function public.svc_prisms_apply_observations(p_rows jsonb)
returns jsonb
language sql
security definer
set search_path to 'pipeline','public'
as $function$
  select pipeline.svc_prisms_apply_observations(p_rows);
$function$;

create or replace function public.ui_international_student_observations(
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

revoke all on function public.svc_prisms_context() from public,anon,authenticated;
revoke all on function public.svc_prisms_prepare_source(text,text,text,date,date) from public,anon,authenticated;
revoke all on function public.svc_prisms_touch_source(uuid,boolean,text) from public,anon,authenticated;
revoke all on function public.svc_prisms_register_evidence(uuid,text,text,text,text,date,date,text) from public,anon,authenticated;
revoke all on function pipeline.svc_prisms_apply_observations(jsonb) from public,anon,authenticated;
revoke all on function public.svc_prisms_apply_observations(jsonb) from public,anon,authenticated;
revoke all on function public.ui_international_student_observations(date,text,text,integer) from public,anon;

grant execute on function public.svc_prisms_context() to service_role;
grant execute on function public.svc_prisms_prepare_source(text,text,text,date,date) to service_role;
grant execute on function public.svc_prisms_touch_source(uuid,boolean,text) to service_role;
grant execute on function public.svc_prisms_register_evidence(uuid,text,text,text,text,date,date,text) to service_role;
grant execute on function pipeline.svc_prisms_apply_observations(jsonb) to service_role;
grant execute on function public.svc_prisms_apply_observations(jsonb) to service_role;
grant execute on function public.ui_international_student_observations(date,text,text,integer) to authenticated,service_role;

create or replace function pipeline.svc_pilot_submit_nonce(
  p_function text,
  p_body jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path to 'pipeline','net','public','extensions'
as $function$
declare v_nonce uuid:=extensions.gen_random_uuid(); v_id bigint;
begin
  if p_function not in ('layer1-ca-niagara-catalogue','qilt-au-etl','prisms-au-etl') then
    raise exception 'one-time Pilot Edge function is not allowlisted';
  end if;
  insert into pipeline.pilot_edge_nonces(id,function_name,expires_at)
  values(v_nonce,p_function,now()+interval '2 minutes');
  select net.http_post(
    url:='https://fxcwkweaxjtknorudmwp.supabase.co/functions/v1/'||p_function,
    headers:=jsonb_build_object(
      'content-type','application/json',
      'x-cf-run-nonce',v_nonce::text
    ),
    body:=coalesce(p_body,'{}'::jsonb),
    timeout_milliseconds:=120000
  ) into v_id;
  return v_id;
end
$function$;
