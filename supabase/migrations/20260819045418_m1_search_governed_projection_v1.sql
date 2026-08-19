create table if not exists search.projection_country_gates (
  projection_code text not null,
  country_id uuid not null references ref.countries(id),
  gate_status text not null check (gate_status in ('approved','blocked')),
  approval_ref text not null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (projection_code,country_id)
);

create table if not exists search.enrichment_gates (
  projection_code text not null,
  domain_code text not null,
  gate_status text not null check (gate_status in ('approved','blocked')),
  approval_ref text not null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (projection_code,domain_code)
);

revoke all on search.projection_country_gates from public, anon, authenticated;
revoke all on search.enrichment_gates from public, anon, authenticated;

delete from search.projection_country_gates where projection_code='courses';
insert into search.projection_country_gates(projection_code,country_id,gate_status,approval_ref,approved_at)
select 'courses',id,'approved','M1-SEARCH accepted AU+NZ canonical substrate',now()
from ref.countries where iso_alpha2 in ('AU','NZ');

delete from search.enrichment_gates where projection_code='courses';
insert into search.enrichment_gates(projection_code,domain_code,gate_status,approval_ref,approved_at) values
('courses','scholarship','approved','M1-L2-SCHOLARSHIPS first-source accepted',now()),
('courses','course_link','blocked','Await M1-L2-AU-COURSE-FACTS UAT',null),
('courses','course_fee','blocked','Await M1-L2-AU-COURSE-FACTS UAT',null),
('courses','course_intake','blocked','Await M1-L2-AU-COURSE-FACTS UAT',null),
('courses','course_english','blocked','Await M1-L2-AU-COURSE-FACTS UAT',null);

alter table search.course_documents
  add column if not exists course_stable_key text,
  add column if not exists provider_stable_key text,
  add column if not exists course_code text,
  add column if not exists country_code text,
  add column if not exists study_level_code text,
  add column if not exists primary_field_code text,
  add column if not exists primary_field_name text,
  add column if not exists subdivision_codes text[] not null default '{}'::text[],
  add column if not exists delivery_modes text[] not null default '{}'::text[],
  add column if not exists has_state boolean not null default false,
  add column if not exists has_link boolean not null default false,
  add column if not exists projection_version text not null default 'course-v2',
  add column if not exists source_updated_at timestamptz,
  add column if not exists generated_at timestamptz not null default now(),
  add column if not exists semantic_content_hash text;

create index if not exists course_documents_country_code_idx on search.course_documents(country_code,publication_status);
create index if not exists course_documents_level_code_idx on search.course_documents(study_level_code,publication_status);
create index if not exists course_documents_field_code_idx on search.course_documents(primary_field_code,publication_status);
create index if not exists course_documents_subdivision_codes_idx on search.course_documents using gin(subdivision_codes);
create index if not exists course_documents_delivery_modes_idx on search.course_documents using gin(delivery_modes);
create index if not exists course_documents_readiness_idx on search.course_documents(has_state,has_link,has_fee,has_intake,has_english,has_scholarship);

create or replace function search.refresh_course_documents_v2(p_apply boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = search,catalogue,scholarship,publishing,ref,pipeline,extensions,pg_temp
as $function$
declare
  v_generation bigint;
  v_current_generation bigint;
  v_stage_count bigint;
  v_new bigint;
  v_changed bigint;
  v_unchanged bigint;
  v_removed bigint;
  v_applied bigint := 0;
  v_stage_hash text;
  v_country_counts jsonb;
  v_coverage jsonb;
begin
  drop table if exists pg_temp.cf_search_course_stage;

  create temp table cf_search_course_stage on commit drop as
  with gates as (
    select g.country_id
    from search.projection_country_gates g
    where g.projection_code='courses' and g.gate_status='approved'
  ),
  eg as (
    select
      bool_or(domain_code='scholarship' and gate_status='approved') as scholarship_ok,
      bool_or(domain_code='course_link' and gate_status='approved') as link_ok,
      bool_or(domain_code='course_fee' and gate_status='approved') as fee_ok,
      bool_or(domain_code='course_intake' and gate_status='approved') as intake_ok,
      bool_or(domain_code='course_english' and gate_status='approved') as english_ok
    from search.enrichment_gates
    where projection_code='courses'
  )
  select
    c.id as course_id,
    c.provider_id,
    p.country_id,
    c.study_level_id,
    c.primary_field_id,
    c.stable_key as course_stable_key,
    p.stable_key as provider_stable_key,
    c.course_code,
    trim(co.iso_alpha2::text) as country_code,
    sl.code as study_level_code,
    fos.code as primary_field_code,
    fos.name as primary_field_name,
    coalesce(p.display_name,p.canonical_name) as provider_name,
    c.canonical_title as course_title,
    coalesce(coll.collection_names,'{}'::text[]) as collection_names,
    coalesce(acad.academic_option_names,'{}'::text[]) as academic_option_names,
    c.description,
    coalesce(geo.subdivision_codes,'{}'::text[]) as subdivision_codes,
    coalesce(geo.delivery_modes,'{}'::text[]) as delivery_modes,
    cardinality(coalesce(geo.subdivision_codes,'{}'::text[])) > 0 as has_state,
    (select link_ok from eg) and exists(
      select 1 from catalogue.course_links l
      where l.course_id=c.id and l.status='active'
        and (l.valid_from is null or l.valid_from<=current_date)
        and (l.valid_to is null or l.valid_to>=current_date)
    ) as has_link,
    (select fee_ok from eg) and exists(
      select 1 from catalogue.course_fees f
      where f.course_id=c.id and f.status='active'
        and f.audience in ('international','all')
        and (f.valid_from is null or f.valid_from<=current_date)
        and (f.valid_to is null or f.valid_to>=current_date)
    ) as has_fee,
    (select intake_ok from eg) and exists(
      select 1 from catalogue.course_intakes i
      where i.course_id=c.id and i.status='active'
    ) as has_intake,
    (select english_ok from eg) and exists(
      select 1 from catalogue.course_english_requirements er
      where er.course_id=c.id
    ) as has_english,
    (select scholarship_ok from eg) and exists(
      select 1
      from scholarship.scopes ss
      join scholarship.scholarships s on s.id=ss.scholarship_id
      where s.lifecycle_status='active'
        and s.publication_status in ('published','internal')
        and ((ss.scope_type='course' and ss.course_id=c.id)
          or (ss.scope_type='provider' and ss.provider_id=c.provider_id))
    ) as has_scholarship,
    c.publication_status,
    (select max(es.completeness_score) from publishing.entity_states es where es.entity_id=c.id) as completeness_score,
    greatest(c.updated_at,p.updated_at,coalesce(geo.geo_updated_at,'epoch'::timestamptz),coalesce(fos.updated_at,'epoch'::timestamptz)) as source_updated_at,
    concat_ws(' ',c.canonical_title,coalesce(p.display_name,p.canonical_name),coalesce(c.course_code,''),coalesce(sl.name,''),coalesce(fos.name,''),coalesce(array_to_string(coll.collection_names,' '),''),coalesce(array_to_string(acad.academic_option_names,' '),''),coalesce(c.description,'')) as search_text,
    setweight(to_tsvector('english',coalesce(c.canonical_title,'')),'A') ||
    setweight(to_tsvector('english',coalesce(p.display_name,p.canonical_name,'')),'B') ||
    setweight(to_tsvector('english',concat_ws(' ',coalesce(c.course_code,''),coalesce(sl.name,''),coalesce(fos.name,''),coalesce(array_to_string(coll.collection_names,' '),''),coalesce(array_to_string(acad.academic_option_names,' '),''))),'B') ||
    setweight(to_tsvector('english',coalesce(c.description,'')),'C') as search_tsv
  from catalogue.courses c
  join catalogue.providers p on p.id=c.provider_id
  join gates g on g.country_id=p.country_id
  join ref.countries co on co.id=p.country_id
  left join ref.study_levels sl on sl.id=c.study_level_id
  left join ref.fields_of_study fos on fos.id=c.primary_field_id
  left join lateral (
    select
      coalesce(array_agg(distinct sd.code order by sd.code) filter (where sd.code is not null),'{}'::text[]) as subdivision_codes,
      coalesce(array_agg(distinct cc.delivery_mode order by cc.delivery_mode) filter (where nullif(trim(cc.delivery_mode),'') is not null),'{}'::text[]) as delivery_modes,
      max(cp.updated_at) as geo_updated_at
    from catalogue.course_campuses cc
    join catalogue.campuses cp on cp.id=cc.campus_id
    left join ref.subdivisions sd on sd.id=cp.subdivision_id
    where cc.course_id=c.id
  ) geo on true
  left join lateral (
    select array_agg(distinct cl.name order by cl.name) as collection_names
    from catalogue.course_collection_memberships cm
    join catalogue.course_collections cl on cl.id=cm.collection_id
    where cm.course_id=c.id
  ) coll on true
  left join lateral (
    select array_agg(distinct ao.name order by ao.name) as academic_option_names
    from catalogue.course_academic_options ao
    where ao.course_id=c.id and ao.status='active'
  ) acad on true
  where c.lifecycle_status='active';

  alter table cf_search_course_stage
    add column projection_version text not null default 'course-v2',
    add column generated_at timestamptz not null default now(),
    add column content_hash text,
    add column semantic_content_hash text;

  update cf_search_course_stage s
  set semantic_content_hash=encode(extensions.digest(jsonb_build_object(
      'course',s.course_stable_key,'provider',s.provider_name,'title',s.course_title,'code',s.course_code,'level',s.study_level_code,'field',s.primary_field_code,'collections',s.collection_names,'academic_options',s.academic_option_names,'description',s.description
    )::text,'sha256'),'hex'),
      content_hash=encode(extensions.digest(jsonb_build_object(
      'course',s.course_stable_key,'provider',s.provider_stable_key,'country',s.country_code,'level',s.study_level_code,'field',s.primary_field_code,'states',s.subdivision_codes,'delivery',s.delivery_modes,'has_state',s.has_state,'has_link',s.has_link,'has_fee',s.has_fee,'has_intake',s.has_intake,'has_english',s.has_english,'has_scholarship',s.has_scholarship,'publication',s.publication_status,
      'semantic',encode(extensions.digest(jsonb_build_object('course',s.course_stable_key,'provider',s.provider_name,'title',s.course_title,'code',s.course_code,'level',s.study_level_code,'field',s.primary_field_code,'collections',s.collection_names,'academic_options',s.academic_option_names,'description',s.description)::text,'sha256'),'hex')
    )::text,'sha256'),'hex');

  select count(*) into v_stage_count from cf_search_course_stage;
  select coalesce(jsonb_object_agg(country_code,cnt),'{}'::jsonb) into v_country_counts
  from (select country_code,count(*) cnt from cf_search_course_stage group by country_code order by country_code) x;

  select jsonb_build_object(
    'with_field',count(*) filter(where primary_field_id is not null),
    'with_state',count(*) filter(where has_state),
    'with_delivery',count(*) filter(where cardinality(delivery_modes)>0),
    'with_link',count(*) filter(where has_link),
    'with_fee',count(*) filter(where has_fee),
    'with_intake',count(*) filter(where has_intake),
    'with_english',count(*) filter(where has_english),
    'with_scholarship',count(*) filter(where has_scholarship)
  ) into v_coverage from cf_search_course_stage;

  select count(*) into v_new from cf_search_course_stage s left join search.course_documents d using(course_id) where d.course_id is null;
  select count(*) into v_changed from cf_search_course_stage s join search.course_documents d using(course_id) where d.content_hash is distinct from s.content_hash or d.projection_version is distinct from s.projection_version;
  select count(*) into v_unchanged from cf_search_course_stage s join search.course_documents d using(course_id) where d.content_hash is not distinct from s.content_hash and d.projection_version is not distinct from s.projection_version;
  select count(*) into v_removed from search.course_documents d left join cf_search_course_stage s using(course_id) where s.course_id is null;

  select generation into v_current_generation from search.projection_state where projection_code='courses' for update;
  if v_current_generation is null then
    insert into search.projection_state(projection_code,generation,row_count,metadata) values('courses',1,0,'{}'::jsonb)
    returning generation into v_current_generation;
  end if;

  select encode(extensions.digest(coalesce(string_agg(course_id::text||':'||content_hash,'|' order by course_id::text),''),'sha256'),'hex') into v_stage_hash from cf_search_course_stage;

  if p_apply then
    v_generation := v_current_generation + 1;

    insert into search.course_documents(
      course_id,provider_id,country_id,study_level_id,primary_field_id,course_stable_key,provider_stable_key,course_code,country_code,study_level_code,primary_field_code,primary_field_name,provider_name,course_title,collection_names,academic_option_names,description,search_text,search_tsv,subdivision_codes,delivery_modes,has_state,has_link,has_fee,has_intake,has_english,has_scholarship,publication_status,completeness_score,catalogue_generation,projection_version,source_updated_at,generated_at,content_hash,semantic_content_hash,updated_at
    )
    select
      course_id,provider_id,country_id,study_level_id,primary_field_id,course_stable_key,provider_stable_key,course_code,country_code,study_level_code,primary_field_code,primary_field_name,provider_name,course_title,collection_names,academic_option_names,description,search_text,search_tsv,subdivision_codes,delivery_modes,has_state,has_link,has_fee,has_intake,has_english,has_scholarship,publication_status,completeness_score,v_generation,projection_version,source_updated_at,generated_at,content_hash,semantic_content_hash,now()
    from cf_search_course_stage
    on conflict(course_id) do update set
      provider_id=excluded.provider_id,country_id=excluded.country_id,study_level_id=excluded.study_level_id,primary_field_id=excluded.primary_field_id,course_stable_key=excluded.course_stable_key,provider_stable_key=excluded.provider_stable_key,course_code=excluded.course_code,country_code=excluded.country_code,study_level_code=excluded.study_level_code,primary_field_code=excluded.primary_field_code,primary_field_name=excluded.primary_field_name,provider_name=excluded.provider_name,course_title=excluded.course_title,collection_names=excluded.collection_names,academic_option_names=excluded.academic_option_names,description=excluded.description,search_text=excluded.search_text,search_tsv=excluded.search_tsv,subdivision_codes=excluded.subdivision_codes,delivery_modes=excluded.delivery_modes,has_state=excluded.has_state,has_link=excluded.has_link,has_fee=excluded.has_fee,has_intake=excluded.has_intake,has_english=excluded.has_english,has_scholarship=excluded.has_scholarship,publication_status=excluded.publication_status,completeness_score=excluded.completeness_score,catalogue_generation=excluded.catalogue_generation,projection_version=excluded.projection_version,source_updated_at=excluded.source_updated_at,generated_at=excluded.generated_at,content_hash=excluded.content_hash,semantic_content_hash=excluded.semantic_content_hash,updated_at=now()
    where search.course_documents.content_hash is distinct from excluded.content_hash or search.course_documents.projection_version is distinct from excluded.projection_version;

    get diagnostics v_applied=row_count;
    delete from search.course_documents d where not exists(select 1 from cf_search_course_stage s where s.course_id=d.course_id);

    update search.projection_state
    set generation=v_generation,rebuilt_at=now(),row_count=v_stage_count,content_hash=v_stage_hash,
        metadata=jsonb_build_object('projection_version','course-v2','countries',v_country_counts,'coverage',v_coverage,'country_gate','explicit','enrichment_gate','explicit')
    where projection_code='courses';
  else
    v_generation := v_current_generation;
  end if;

  return jsonb_build_object('apply',p_apply,'projection','courses','projection_version','course-v2','generation',v_generation,'stage_count',v_stage_count,'new',v_new,'changed',v_changed,'unchanged',v_unchanged,'removed',v_removed,'applied_rows',v_applied,'countries',v_country_counts,'coverage',v_coverage,'content_hash',v_stage_hash);
end
$function$;

revoke all on function search.refresh_course_documents_v2(boolean) from public,anon,authenticated;
grant execute on function search.refresh_course_documents_v2(boolean) to service_role;

create or replace function search.rebuild_course_documents()
returns bigint
language plpgsql
security definer
set search_path=search
as $function$
declare v_result jsonb;
begin
  v_result := search.refresh_course_documents_v2(true);
  return (v_result->>'stage_count')::bigint;
end
$function$;

revoke all on function search.rebuild_course_documents() from public,anon,authenticated;
grant execute on function search.rebuild_course_documents() to service_role;
