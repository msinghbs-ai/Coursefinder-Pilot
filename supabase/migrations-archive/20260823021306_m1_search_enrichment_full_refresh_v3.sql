-- M1-SEARCH-ENRICHMENT native course-v3 full refresh.
-- Live migration authority: 20260823021306 m1_search_enrichment_full_refresh_v3.

create or replace function search.refresh_course_base_v3(p_apply boolean default false)
returns jsonb
language plpgsql
security definer
set search_path=search,catalogue,publishing,ref,pipeline,extensions,pg_temp
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
  drop table if exists pg_temp.cf_search_course_base_v3_stage;

  create temp table cf_search_course_base_v3_stage on commit drop as
  with gates as (
    select g.country_id
    from search.projection_country_gates g
    where g.projection_code='courses' and g.gate_status='approved'
  )
  select
    c.id as course_id,c.provider_id,p.country_id,c.study_level_id,c.primary_field_id,
    c.stable_key as course_stable_key,p.stable_key as provider_stable_key,c.course_code,
    trim(co.iso_alpha2::text) as country_code,sl.code as study_level_code,
    fos.code as primary_field_code,fos.name as primary_field_name,
    coalesce(p.display_name,p.canonical_name) as provider_name,c.canonical_title as course_title,
    coalesce(coll.collection_names,'{}'::text[]) as collection_names,
    coalesce(acad.academic_option_names,'{}'::text[]) as academic_option_names,
    c.description,coalesce(geo.subdivision_codes,'{}'::text[]) as subdivision_codes,
    coalesce(geo.delivery_modes,'{}'::text[]) as delivery_modes,
    cardinality(coalesce(geo.subdivision_codes,'{}'::text[])) > 0 as has_state,
    c.publication_status,
    (select max(es.completeness_score) from publishing.entity_states es where es.entity_id=c.id) as completeness_score,
    greatest(c.updated_at,p.updated_at,coalesce(geo.geo_updated_at,'epoch'::timestamptz),coalesce(fos.updated_at,'epoch'::timestamptz)) as source_updated_at,
    concat_ws(' ',c.canonical_title,coalesce(p.display_name,p.canonical_name),coalesce(c.course_code,''),coalesce(sl.name,''),coalesce(fos.name,''),coalesce(array_to_string(coll.collection_names,' '),''),coalesce(array_to_string(acad.academic_option_names,' '),''),coalesce(c.description,'')) as base_search_text,
    setweight(to_tsvector('english',coalesce(c.canonical_title,'')),'A') ||
    setweight(to_tsvector('english',coalesce(p.display_name,p.canonical_name,'')),'B') ||
    setweight(to_tsvector('english',concat_ws(' ',coalesce(c.course_code,''),coalesce(sl.name,''),coalesce(fos.name,''),coalesce(array_to_string(coll.collection_names,' '),''),coalesce(array_to_string(acad.academic_option_names,' '),''))),'B') ||
    setweight(to_tsvector('english',coalesce(c.description,'')),'C') as base_search_tsv
  from catalogue.courses c
  join catalogue.providers p on p.id=c.provider_id
  join gates g on g.country_id=p.country_id
  join ref.countries co on co.id=p.country_id
  left join ref.study_levels sl on sl.id=c.study_level_id
  left join ref.fields_of_study fos on fos.id=c.primary_field_id
  left join lateral (
    select coalesce(array_agg(distinct sd.code order by sd.code) filter (where sd.code is not null),'{}'::text[]) as subdivision_codes,
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

  alter table cf_search_course_base_v3_stage
    add column projection_version text not null default 'course-v3',
    add column generated_at timestamptz not null default now(),
    add column content_hash text,
    add column semantic_content_hash text;

  update cf_search_course_base_v3_stage s
  set semantic_content_hash=encode(extensions.digest(jsonb_build_object(
      'course',s.course_stable_key,'provider',s.provider_name,'title',s.course_title,'code',s.course_code,
      'level',s.study_level_code,'field',s.primary_field_code,'collections',s.collection_names,
      'academic_options',s.academic_option_names,'description',s.description
    )::text,'sha256'),'hex'),
      content_hash=encode(extensions.digest(jsonb_build_object(
      'course',s.course_stable_key,'provider',s.provider_stable_key,'country',s.country_code,
      'level',s.study_level_code,'field',s.primary_field_code,'states',s.subdivision_codes,
      'delivery',s.delivery_modes,'has_state',s.has_state,'publication',s.publication_status,
      'semantic',encode(extensions.digest(jsonb_build_object(
        'course',s.course_stable_key,'provider',s.provider_name,'title',s.course_title,'code',s.course_code,
        'level',s.study_level_code,'field',s.primary_field_code,'collections',s.collection_names,
        'academic_options',s.academic_option_names,'description',s.description
      )::text,'sha256'),'hex')
    )::text,'sha256'),'hex');

  select count(*) into v_stage_count from cf_search_course_base_v3_stage;
  select coalesce(jsonb_object_agg(country_code,cnt),'{}'::jsonb) into v_country_counts
  from (select country_code,count(*) cnt from cf_search_course_base_v3_stage group by country_code order by country_code) x;
  select jsonb_build_object(
    'with_field',count(*) filter(where primary_field_id is not null),
    'with_state',count(*) filter(where has_state),
    'with_delivery',count(*) filter(where cardinality(delivery_modes)>0)
  ) into v_coverage from cf_search_course_base_v3_stage;

  select count(*) into v_new from cf_search_course_base_v3_stage s left join search.course_documents d using(course_id) where d.course_id is null;
  select count(*) into v_changed from cf_search_course_base_v3_stage s join search.course_documents d using(course_id)
   where d.content_hash is distinct from s.content_hash or d.projection_version is distinct from 'course-v3';
  select count(*) into v_unchanged from cf_search_course_base_v3_stage s join search.course_documents d using(course_id)
   where d.content_hash is not distinct from s.content_hash and d.projection_version='course-v3';
  select count(*) into v_removed from search.course_documents d left join cf_search_course_base_v3_stage s using(course_id) where s.course_id is null;

  select generation into v_current_generation from search.projection_state where projection_code='courses' for update;
  if v_current_generation is null then
    insert into search.projection_state(projection_code,generation,row_count,metadata) values('courses',1,0,'{}'::jsonb)
    returning generation into v_current_generation;
  end if;

  select encode(extensions.digest(coalesce(string_agg(course_id::text||':'||content_hash,'|' order by course_id::text),''),'sha256'),'hex') into v_stage_hash from cf_search_course_base_v3_stage;

  if p_apply then
    v_generation:=v_current_generation+1;
    insert into search.course_documents(
      course_id,provider_id,country_id,study_level_id,primary_field_id,course_stable_key,provider_stable_key,course_code,country_code,study_level_code,primary_field_code,primary_field_name,
      provider_name,course_title,collection_names,academic_option_names,description,search_text,search_tsv,subdivision_codes,delivery_modes,has_state,
      publication_status,completeness_score,catalogue_generation,projection_version,source_updated_at,generated_at,content_hash,semantic_content_hash,updated_at
    )
    select course_id,provider_id,country_id,study_level_id,primary_field_id,course_stable_key,provider_stable_key,course_code,country_code,study_level_code,primary_field_code,primary_field_name,
      provider_name,course_title,collection_names,academic_option_names,description,base_search_text,base_search_tsv,subdivision_codes,delivery_modes,has_state,
      publication_status,completeness_score,v_generation,'course-v3',source_updated_at,generated_at,content_hash,semantic_content_hash,now()
    from cf_search_course_base_v3_stage
    on conflict(course_id) do update set
      provider_id=excluded.provider_id,country_id=excluded.country_id,study_level_id=excluded.study_level_id,primary_field_id=excluded.primary_field_id,
      course_stable_key=excluded.course_stable_key,provider_stable_key=excluded.provider_stable_key,course_code=excluded.course_code,country_code=excluded.country_code,
      study_level_code=excluded.study_level_code,primary_field_code=excluded.primary_field_code,primary_field_name=excluded.primary_field_name,provider_name=excluded.provider_name,
      course_title=excluded.course_title,collection_names=excluded.collection_names,academic_option_names=excluded.academic_option_names,description=excluded.description,
      subdivision_codes=excluded.subdivision_codes,delivery_modes=excluded.delivery_modes,has_state=excluded.has_state,publication_status=excluded.publication_status,
      completeness_score=excluded.completeness_score,catalogue_generation=excluded.catalogue_generation,projection_version='course-v3',source_updated_at=excluded.source_updated_at,
      generated_at=excluded.generated_at,content_hash=excluded.content_hash,
      semantic_content_hash=case when nullif(trim(search.course_documents.enrichment_semantic_text),'') is null then excluded.semantic_content_hash else encode(extensions.digest(jsonb_build_object('base',excluded.course_stable_key,'provider',excluded.provider_name,'title',excluded.course_title,'code',excluded.course_code,'level',excluded.study_level_code,'field',excluded.primary_field_code,'collections',excluded.collection_names,'academic_options',excluded.academic_option_names,'description',excluded.description,'enrichment',nullif(trim(search.course_documents.enrichment_semantic_text),''))::text,'sha256'),'hex') end,
      updated_at=now()
    where search.course_documents.content_hash is distinct from excluded.content_hash
       or search.course_documents.projection_version is distinct from 'course-v3';
    get diagnostics v_applied=row_count;
    delete from search.course_documents d where not exists(select 1 from cf_search_course_base_v3_stage s where s.course_id=d.course_id);
  else
    v_generation:=v_current_generation;
  end if;

  return jsonb_build_object('apply',p_apply,'projection','courses','projection_version','course-v3','generation',v_generation,
    'stage_count',v_stage_count,'new',v_new,'changed',v_changed,'unchanged',v_unchanged,'removed',v_removed,'applied_rows',v_applied,
    'countries',v_country_counts,'coverage',v_coverage,'base_content_hash',v_stage_hash);
end
$function$;

revoke all on function search.refresh_course_base_v3(boolean) from public,anon,authenticated;
grant execute on function search.refresh_course_base_v3(boolean) to service_role;

create or replace function search.refresh_course_documents_v3(p_apply boolean default false)
returns jsonb
language plpgsql
security definer
set search_path=search,extensions,pg_temp
as $function$
declare
  v_base jsonb;
  v_enrichment jsonb;
  v_full_hash text;
  v_coverage jsonb;
  v_generation bigint;
begin
  v_base:=search.refresh_course_base_v3(p_apply);
  v_enrichment:=search.refresh_course_enrichment_v1(p_apply);
  if p_apply then
    select encode(extensions.digest(coalesce(string_agg(course_id::text||':'||coalesce(content_hash,'')||':'||coalesce(enrichment_content_hash,''),'|' order by course_id::text),''),'sha256'),'hex') into v_full_hash from search.course_documents;
    select jsonb_build_object(
      'with_field',count(*) filter(where primary_field_id is not null),'with_state',count(*) filter(where has_state),'with_delivery',count(*) filter(where cardinality(delivery_modes)>0),
      'with_regulatory_tuition',count(*) filter(where has_regulatory_tuition),'with_provider_current_tuition',count(*) filter(where has_provider_current_tuition),
      'with_official_url',count(*) filter(where official_course_url is not null),'with_intake',count(*) filter(where has_intake),'with_english',count(*) filter(where has_english),'with_scholarship',count(*) filter(where has_scholarship)
    ) into v_coverage from search.course_documents;
    update search.projection_state
      set generation=generation+1,rebuilt_at=now(),row_count=(select count(*) from search.course_documents),content_hash=v_full_hash,
          metadata=jsonb_build_object('projection_version','course-v3','countries',v_base->'countries','coverage',v_coverage,'country_gate','explicit','enrichment_gate','domain_and_source_explicit','base_content_hash',v_base->>'base_content_hash','enrichment_stage_hash',v_enrichment->>'stage_hash','refresh_function','search.refresh_course_documents_v3')
      where projection_code='courses' returning generation into v_generation;
  else
    select generation into v_generation from search.projection_state where projection_code='courses';
  end if;
  return jsonb_build_object('apply',p_apply,'projection','courses','projection_version','course-v3','generation',v_generation,'base',v_base,'enrichment',v_enrichment,'full_content_hash',v_full_hash);
end
$function$;

revoke all on function search.refresh_course_documents_v3(boolean) from public,anon,authenticated;
grant execute on function search.refresh_course_documents_v3(boolean) to service_role;
