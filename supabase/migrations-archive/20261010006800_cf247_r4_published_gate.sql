-- CF-247 v2.15.236 (R4): Platform Admin bug list of 10 Oct 2026 — Feature 4, Published switch. Decision: "Hide and pause work".
-- This release makes publication a real gate (the pause of related work follows in the next release).
--  1. security.provider_hidden_v1: providers not published or not active. The Layer 4 search-block views that every consumer API
--     already reads now include them, with their courses, campuses and scholarships.
--  2. Every active provider is published now; new providers start published (column default and an insert trigger).
--  3. admin_provider_publish: the switch in the provider list (PIM Operator and above, no reason, logged, search rebuilt).
--  4. The consumer paths that did not read the block views do now: course index build, Wix/website provider list, single course,
--     scholarships (list and one), rankings, Zoho scholarships.
-- md5-checked before and after. Nothing is dropped or deleted.
do $guard$
declare v_expected jsonb := jsonb_build_object('search.refresh_course_base_v3(boolean)', 'b7139dc51771973044c4d554cc2fe9b7', 'public.website_v2_scholarships(jsonb,integer,integer)', '48c2240a8b99521cba8c3f86fa5682d4', 'public.website_v2_scholarship(text)', 'd948c919da1d2f37e36fa36e29600821', 'public.zoho_edge_scholarships_v1(text)', '1c4446248ee63ed2aad35a79de9c84ee', 'public.website_v2_rankings(jsonb,integer,integer)', '2cfa72d4b45491e936dfdbad7bb08cb0', 'api.website_v2_course_item(uuid,text[],text[])', 'a05b163b1bba1835f04c22ab3a3b6cbe', 'public.website_v2_providers(jsonb,integer,integer,text)', '780d080dfc113df3e2e38d8db7cdb672');
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- 1. Hidden providers: not published, or not active (archived). Their courses, campuses and scholarships are hidden with them.
--    The existing Layer 4 search-block views, which every consumer API already reads, now include them.
create or replace view security.provider_hidden_v1 as
  select p.id as provider_id from catalogue.providers p
   where p.publication_status is distinct from 'published' or p.lifecycle_status is distinct from 'active';
revoke all on security.provider_hidden_v1 from public, anon, authenticated;

create or replace view security.layer4_search_blocked_providers as
 SELECT entity_id AS provider_id
   FROM security.layer4_active_blocks
  WHERE block_scope = 'search'::text AND entity_type = 'provider'::text
UNION
 SELECT h.provider_id FROM security.provider_hidden_v1 h;

create or replace view security.layer4_search_blocked_courses as
 SELECT layer4_active_blocks.entity_id AS course_id
   FROM security.layer4_active_blocks
  WHERE layer4_active_blocks.block_scope = 'search'::text AND layer4_active_blocks.entity_type = 'course'::text
UNION
 SELECT c.id AS course_id
   FROM security.layer4_active_blocks b
     JOIN catalogue.courses c ON c.provider_id = b.entity_id
  WHERE b.block_scope = 'search'::text AND b.entity_type = 'provider'::text
UNION
 SELECT c.id AS course_id FROM security.provider_hidden_v1 h JOIN catalogue.courses c ON c.provider_id = h.provider_id;

create or replace view security.layer4_search_blocked_campuses as
 SELECT layer4_active_blocks.entity_id AS campus_id
   FROM security.layer4_active_blocks
  WHERE layer4_active_blocks.block_scope = 'search'::text AND layer4_active_blocks.entity_type = 'campus'::text
UNION
 SELECT c.id AS campus_id
   FROM security.layer4_active_blocks b
     JOIN catalogue.campuses c ON c.provider_id = b.entity_id
  WHERE b.block_scope = 'search'::text AND b.entity_type = 'provider'::text
UNION
 SELECT c.id AS campus_id FROM security.provider_hidden_v1 h JOIN catalogue.campuses c ON c.provider_id = h.provider_id;

create or replace view security.layer4_search_blocked_scholarships as
 SELECT layer4_active_blocks.entity_id AS scholarship_id
   FROM security.layer4_active_blocks
  WHERE layer4_active_blocks.block_scope = 'search'::text AND layer4_active_blocks.entity_type = 'scholarship'::text
UNION
 SELECT s.id AS scholarship_id
   FROM security.layer4_active_blocks b
     JOIN scholarship.scholarships s ON s.provider_id = b.entity_id
  WHERE b.block_scope = 'search'::text AND b.entity_type = 'provider'::text
UNION
 SELECT s.id AS scholarship_id FROM security.provider_hidden_v1 h JOIN scholarship.scholarships s ON s.provider_id = h.provider_id;

-- 2. Published by default: every active provider is published now, and a provider added later starts published.
alter table catalogue.providers alter column publication_status set default 'published';
create or replace function security.provider_publish_by_default() returns trigger language plpgsql security definer set search_path to '' as $f$
begin
  if new.lifecycle_status = 'active' then new.publication_status := 'published'; end if;
  return new;
end $f$;
create or replace trigger provider_publish_by_default before insert on catalogue.providers for each row execute function security.provider_publish_by_default();
update catalogue.providers set publication_status = 'published', updated_at = now()
 where lifecycle_status = 'active' and publication_status is distinct from 'published';

-- 3. The Published switch (provider list and panel). PIM Operator and above; no reason asked; logged; search documents rebuilt.
create or replace function public.admin_provider_publish(p_provider_id uuid, p_published boolean) returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_before text; v_after text := case when p_published then 'published' else 'unpublished' end;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  select publication_status into v_before from catalogue.providers where id = p_provider_id;
  if not found then raise exception 'provider not found'; end if;
  if p_published and exists (select 1 from catalogue.providers where id = p_provider_id and lifecycle_status <> 'active') then
    raise exception 'an archived provider cannot be published: restore it first';
  end if;
  if v_before is distinct from v_after then
    perform set_config('cf.manual_edit', 'on', true);
    update catalogue.providers set publication_status = v_after, updated_at = now() where id = p_provider_id;
    insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
    values ('provider', p_provider_id, 'publication_status', case when p_published then 'publish' else 'unpublish' end, to_jsonb(v_before), to_jsonb(v_after), null, auth.uid());
    insert into search.refresh_requests(requested_by) values (format('provider %s %s', left(p_provider_id::text, 8), v_after));
  end if;
  return jsonb_build_object('provider_id', p_provider_id, 'publication_status', v_after);
end $f$;
revoke all on function public.admin_provider_publish(uuid, boolean) from public, anon;
grant execute on function public.admin_provider_publish(uuid, boolean) to authenticated;

-- 4. Consumer paths

CREATE OR REPLACE FUNCTION search.refresh_course_base_v3(p_apply boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'search', 'catalogue', 'publishing', 'ref', 'pipeline', 'extensions', 'pg_temp'
AS $function$
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
  where c.lifecycle_status='active'
    and p.publication_status='published' and p.lifecycle_status='active';  -- v2.15.236 (Feature 4): an unpublished or archived provider's courses leave search

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
    )::text,'sha256'),'hex') where true;

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
      generated_at=excluded.generated_at,content_hash=excluded.content_hash,semantic_content_hash=case when nullif(trim(search.course_documents.enrichment_semantic_text),'') is null then excluded.semantic_content_hash else encode(extensions.digest(jsonb_build_object('base',excluded.course_stable_key,'provider',excluded.provider_name,'title',excluded.course_title,'code',excluded.course_code,'level',excluded.study_level_code,'field',excluded.primary_field_code,'collections',excluded.collection_names,'academic_options',excluded.academic_option_names,'description',excluded.description,'enrichment',nullif(trim(search.course_documents.enrichment_semantic_text),''))::text,'sha256'),'hex') end,updated_at=now()
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

CREATE OR REPLACE FUNCTION public.website_v2_scholarships(p_filters jsonb DEFAULT '{}'::jsonb, p_page integer DEFAULT 1, p_page_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'catalogue', 'search', 'ref', 'pipeline', 'security', 'api'
AS $function$
declare
  f jsonb := coalesce(p_filters,'{}'::jsonb);
  v_page int := coalesce(p_page,1); v_size int := coalesce(p_page_size,20);
  v_kw text := nullif(btrim(coalesce(f->>'keyword','')),'');
  v_countries text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(coalesce(f->'country_codes',f->'country_code'))) x);
  v_providers text[] := api.website_text_array(f->'provider_ids');
  v_cities text[] := (select array_agg(lower(x)) from unnest(api.website_text_array(coalesce(f->'cities',f->'city'))) x);
  v_subdivs text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(f->'subdivision_codes')) x);
  v_groups text[] := (select array_agg(lower(regexp_replace(btrim(x),'^au_','','i'))) from unnest(api.website_text_array(coalesce(f->'university_groups',f->'university_group'))) x);
  v_types text[] := api.website_text_array(f->'amount_types');
  v_levels text[] := api.website_text_array(f->'study_level_codes');
  v_areas text[] := api.website_text_array(f->'study_area_codes');
  v_student text[] := api.website_text_array(f->'student_types');
  v_stages text[] := api.website_text_array(f->'study_stages');
  v_nat text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(f->'nationality_codes')) x);
  v_course text := nullif(btrim(coalesce(f->>'course_id','')),'');
  v_known text[] := array['keyword','country_codes','country_code','provider_ids','cities','city','subdivision_codes','university_groups','university_group','amount_types',
                          'open_only','published_only','study_level_codes','study_area_codes','student_types','study_stages','automatic_consideration','nationality_codes','course_id'];
  v_not_applied jsonb; v_total bigint; v_ids uuid[];
begin
  if v_page < 1 or v_size < 1 or v_size > 50 then raise exception 'INVALID_INPUT: page must be >= 1 and page_size 1-50' using errcode='22023'; end if;
  select coalesce(jsonb_agg(k),'[]'::jsonb) into v_not_applied from jsonb_object_keys(f) k where k <> all(v_known);
  with base as (
    select s.id, s.name, s.stable_key
    from scholarship.scholarships s join catalogue.providers p on p.id=s.provider_id join ref.countries c on c.id=p.country_id
    where s.lifecycle_status='active'
      and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id=s.id)  -- v2.15.236: hidden providers' scholarships too
      and (not coalesce((f->>'published_only')::boolean,false) or s.publication_status='published')
      and (not coalesce((f->>'open_only')::boolean,false) or (s.application_close_date >= current_date and (s.application_open_date is null or s.application_open_date <= current_date)))
      and (v_kw is null or s.name ilike '%'||v_kw||'%' or coalesce(p.display_name,p.canonical_name) ilike '%'||v_kw||'%')
      and (v_countries is null or trim(c.iso_alpha2::text) = any(v_countries))
      and (v_providers is null or p.stable_key = any(v_providers))
      and (v_cities is null or exists (select 1 from catalogue.campuses k left join pipeline.campus_regional_class rc on rc.campus_id=k.id where k.provider_id=p.id and (lower(btrim(k.city)) = any(v_cities) or lower(rc.metro_area) = any(v_cities))))
      and (v_subdivs is null or exists (select 1 from catalogue.campuses k join ref.subdivisions sd on sd.id=k.subdivision_id where k.provider_id=p.id and sd.code = any(v_subdivs)))
      and (v_groups is null or exists (select 1 from catalogue.provider_collection_memberships gm join ref.institution_collections gic on gic.id=gm.collection_id
            where gm.provider_id=p.id and gm.status='active' and gic.collection_type='university_group' and gic.status='active' and replace(gic.code,'au_','') = any(v_groups)))
      and (v_types is null or (case when s.award_value_type='fixed_amount' then 'fixed_amount' when s.award_value_type='percentage' and s.award_percentage >= 100 then 'full_tuition'
                                    when s.award_value_type='percentage' then 'percentage_tuition' end) = any(v_types) or s.award_value_type = any(v_types))
      and (v_levels is null or exists (select 1 from scholarship.course_mappings m join search.course_documents d on d.course_id=m.course_id where m.scholarship_id=s.id and m.mapping_state='mapped' and d.study_level_code = any(v_levels)))
      and (v_areas is null or exists (select 1 from scholarship.course_mappings m join search.course_documents d on d.course_id=m.course_id where m.scholarship_id=s.id and m.mapping_state='mapped' and d.primary_field_code = any(v_areas)))
      and (v_stages is null or exists (select 1 from scholarship.criteria cr where cr.scholarship_id=s.id and cr.criterion_type='study_stage' and cr.value_text = any(v_stages)))
      and (v_student is null or exists (select 1 from scholarship.criteria cr where cr.scholarship_id=s.id and cr.criterion_type='student_type'
            and (('international' = any(v_student) and 'international' = any(cr.value_codes)) or ('domestic' = any(v_student) and 'domestic' = any(cr.value_codes))
                 or ('both' = any(v_student) and 'international' = any(cr.value_codes) and 'domestic' = any(cr.value_codes)))))
      and ((f->>'automatic_consideration') is null or (case when exists (select 1 from scholarship.criteria cr where cr.scholarship_id=s.id and cr.criterion_type='application_method' and cr.value_text='automatic') then true
                                                             when s.application_required then false end) = (f->>'automatic_consideration')::boolean)
      and (v_nat is null or exists (select 1 from scholarship.nationality_readings nr where nr.scholarship_id=s.id and nr.codes && v_nat))
      and (v_course is null or exists (select 1 from scholarship.course_mappings m join search.course_documents d on d.course_id=m.course_id where m.scholarship_id=s.id and m.mapping_state='mapped'
            and (lower(d.course_stable_key) = lower(v_course) or lower(d.course_code) = lower(v_course))))
  ), ordered as (select id, count(*) over () total, row_number() over (order by lower(name), stable_key) rn from base)
  select coalesce(max(total),0), array_agg(id order by rn) filter (where rn > (v_page-1)*v_size and rn <= v_page*v_size) into v_total, v_ids from ordered;
  return jsonb_build_object('contract_version','website-search-v2','total',v_total,'page',v_page,'page_size',v_size,'filters_not_applied',v_not_applied,
    'items', coalesce((select jsonb_agg(api.website_v2_scholarship_item(x.id) order by x.ord) from unnest(v_ids) with ordinality x(id, ord)), '[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.website_v2_scholarship(p_scholarship_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'catalogue', 'search', 'security', 'api'
AS $function$
declare v_id uuid; v jsonb;
begin
  if nullif(btrim(coalesce(p_scholarship_id,'')),'') is null then raise exception 'INVALID_INPUT: scholarship_id required' using errcode='22023'; end if;
  select s.id into v_id from scholarship.scholarships s where s.stable_key = btrim(p_scholarship_id)
     and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id = s.id) limit 1;  -- v2.15.236
  if v_id is null then return jsonb_build_object('contract_version','website-search-v2','error',jsonb_build_object('code','NOT_FOUND')); end if;
  v := api.website_v2_scholarship_item(v_id);
  v := v || jsonb_build_object(
    'description', (select s.description from scholarship.scholarships s where s.id=v_id),
    'award_tiers', coalesce((select jsonb_agg(jsonb_build_object('label', t.label, 'amount', t.amount, 'currency', t.currency_code, 'percentage', t.percentage, 'basis', t.basis, 'maximum_amount', t.maximum_amount, 'notes', t.notes) order by t.display_order)
                             from scholarship.award_tiers t where t.scholarship_id=v_id), '[]'::jsonb),
    'linked_courses', coalesce((select jsonb_agg(x.j order by x.t) from (
         select d.course_title t, jsonb_build_object('course_id', d.course_stable_key, 'course_code', d.course_code, 'title', d.course_title,
                  'saving_per_year', (select fc.scholarship_saving_amount from scholarship.course_financial_calculations fc where fc.scholarship_id=v_id and fc.course_id=d.course_id and fc.calculation_status='calculated' order by fc.fee_year desc nulls last limit 1),
                  'saving_currency', (select fc.currency_code from scholarship.course_financial_calculations fc where fc.scholarship_id=v_id and fc.course_id=d.course_id and fc.calculation_status='calculated' order by fc.fee_year desc nulls last limit 1),
                  'saving_basis', (select fc.fee_basis from scholarship.course_financial_calculations fc where fc.scholarship_id=v_id and fc.course_id=d.course_id and fc.calculation_status='calculated' order by fc.fee_year desc nulls last limit 1)) j
         from scholarship.course_mappings m join search.course_documents d on d.course_id=m.course_id
         where m.scholarship_id=v_id and m.mapping_state='mapped' order by d.course_title limit 200) x), '[]'::jsonb),
    'linked_courses_truncated', (select count(*) > 200 from scholarship.course_mappings m where m.scholarship_id=v_id and m.mapping_state='mapped'));
  return jsonb_build_object('contract_version','website-search-v2','item',v);
end $function$;

CREATE OR REPLACE FUNCTION public.zoho_edge_scholarships_v1(p_course text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_course uuid; v_sel jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select c.id into v_course from catalogue.courses c where c.id::text = p_course or c.stable_key = p_course limit 1;
  if v_course is null then return jsonb_build_object('error', 'NOT_FOUND'); end if;
  v_sel := security.scholarship_selection_for_course_impl(v_course);
  return jsonb_build_object(
    'course_id', v_course,
    'audience_filter', 'international',
    'scholarships', coalesce((
      select jsonb_agg(jsonb_build_object(
          'scholarship_id', s.id, 'stable_key', s.stable_key, 'name', s.name, 'provider', coalesce(p.display_name, p.canonical_name),
          'audience', s.audience, 'nationalities', s.nationalities,
          'value', jsonb_build_object('text', scholarship.value_label(s.id), 'type', s.award_value_type, 'percentage', s.award_percentage, 'amount', s.award_amount, 'currency', s.award_currency_code, 'is_maximum', s.award_value_is_maximum,
                                      'tiers', (select jsonb_agg(jsonb_build_object('label', t.label, 'percentage', t.percentage, 'amount', t.amount, 'currency', t.currency_code, 'basis', t.basis) order by t.display_order) from scholarship.award_tiers t where t.scholarship_id = s.id)),
          'saving', (select jsonb_build_object('year', fc.fee_year, 'currency', fc.currency_code, 'tuition', fc.fee_amount, 'saving', fc.scholarship_saving_amount, 'net', fc.net_fee_amount, 'basis', fc.fee_basis, 'estimate', fc.fee_basis = 'estimated_annual_from_registered_total')
                       from scholarship.course_financial_calculations fc where fc.scholarship_id = s.id and fc.course_id = v_course and fc.calculation_status = 'calculated' order by fc.fee_year desc nulls last limit 1),
          'who_qualifies', (select jsonb_agg(jsonb_build_object('type', cr.criterion_type, 'text', cr.human_text, 'mandatory', cr.is_mandatory) order by cr.created_at) from scholarship.criteria cr where cr.scholarship_id = s.id and cr.status = 'active'),
          'application', jsonb_build_object('required', s.application_required, 'opens', s.application_open_date, 'closes', s.application_close_date, 'academic_year', s.academic_year),
          'page', s.source_url,
          'match', e->'derived_score', 'selection_state', e->'selection_state', 'eligibility_state', e->'eligibility_state'))
        from jsonb_array_elements(coalesce(v_sel->'candidates', '[]'::jsonb)) e
        join scholarship.scholarships s on s.id = (e->>'scholarship_id')::uuid
        left join catalogue.providers p on p.id = s.provider_id
       where s.lifecycle_status = 'active' and s.publication_status = 'published'
         and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id = s.id)), '[]'::jsonb),  -- v2.15.236
    'read_at', now());
end $function$;

CREATE OR REPLACE FUNCTION public.website_v2_rankings(p_filters jsonb DEFAULT '{}'::jsonb, p_page integer DEFAULT 1, p_page_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'ranking', 'catalogue', 'ref', 'search', 'security', 'api'
AS $function$
declare
  f jsonb := coalesce(p_filters,'{}'::jsonb);
  v_page int := coalesce(p_page,1); v_size int := coalesce(p_page_size,20);
  v_systems text[] := coalesce(api.website_text_array(f->'system_codes'), array['qs_wur','the_wur']);
  v_year int := nullif(f->>'edition_year','')::int;
  v_countries text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(coalesce(f->'country_codes',f->'country_code'))) x);
  v_providers text[] := api.website_text_array(f->'provider_ids');
  v_rank_max int := nullif(f->>'rank_max','')::int;
  v_known text[] := array['system_codes','edition_year','country_codes','country_code','provider_ids','rank_max'];
  v_not_applied jsonb; v_total bigint; v_items jsonb;
begin
  if v_page < 1 or v_size < 1 or v_size > 50 then raise exception 'INVALID_INPUT: page must be >= 1 and page_size 1-50' using errcode='22023'; end if;
  select coalesce(jsonb_agg(k),'[]'::jsonb) into v_not_applied from jsonb_object_keys(f) k where k <> all(v_known);
  with ed as (
    select e.id, e.edition_year, s.code, s.ranking_name, s.publisher_name, e.methodology_url, coalesce(e.source_url, s.official_url) source_url
    from ranking.editions e join ranking.systems s on s.id=e.system_id
    where e.status='accepted' and s.code = any(v_systems)
      and e.edition_year = coalesce(v_year, (select max(e2.edition_year) from ranking.editions e2 where e2.system_id=s.id and e2.status='accepted'))
  ), rows as (
    select distinct on (ed.id, l.provider_id) ed.*, o.id obs_id, o.rank_display, coalesce(o.rank_low,o.rank_exact) rank_low, coalesce(o.rank_high,o.rank_exact) rank_high,
           coalesce(o.is_tied,false) is_tied, o.overall_score_display, l.provider_id, p.stable_key provider_stable_key, coalesce(p.display_name,p.canonical_name) provider_name, c.iso_alpha2 country_code
    from ed join ranking.observations o on o.edition_id=ed.id
    join ranking.observation_provider_links l on l.observation_id=o.id
    join catalogue.providers p on p.id=l.provider_id join ref.countries c on c.id=p.country_id
    where (v_countries is null or trim(c.iso_alpha2::text) = any(v_countries))
      and not exists (select 1 from security.layer4_search_blocked_providers b where b.provider_id = p.id)  -- v2.15.236
      and (v_providers is null or p.stable_key = any(v_providers))
      and (v_rank_max is null or coalesce(o.rank_low,o.rank_exact) <= v_rank_max)
    order by ed.id, l.provider_id, l.is_primary desc nulls last
  ), ordered as (select *, count(*) over () total, row_number() over (order by code, rank_low nulls last, provider_name) rn from rows)
  select coalesce(max(total),0), coalesce(jsonb_agg(jsonb_build_object(
      'provider', jsonb_build_object('provider_id', o.provider_stable_key, 'name', security.provider_presentable_name(o.provider_name), 'country_code', trim(o.country_code::text), 'logo', api.website_v2_provider_logo(o.provider_id)),
      'system_code', o.code, 'system_name', o.ranking_name, 'publisher', o.publisher_name, 'edition_year', o.edition_year,
      'rank_display', o.rank_display, 'rank_low', o.rank_low, 'rank_high', o.rank_high, 'is_tied', o.is_tied, 'overall_score_display', o.overall_score_display,
      'indicators', (select coalesce(jsonb_agg(jsonb_build_object('code', io.indicator_code, 'label', io.indicator_label, 'value_display', io.value_display, 'rank_display', io.rank_display) order by io.indicator_code), '[]'::jsonb)
                     from ranking.indicator_observations io where io.observation_id=o.obs_id),
      'methodology_url', o.methodology_url, 'source_url', o.source_url,
      'attribution', o.publisher_name || ', ' || o.ranking_name || ' ' || o.edition_year,
      'terms_status', 'management_decision_pending') order by o.rn) filter (where o.rn > (v_page-1)*v_size and o.rn <= v_page*v_size), '[]'::jsonb)
  into v_total, v_items from ordered o;
  return jsonb_build_object('contract_version','website-search-v2','total',v_total,'page',v_page,'page_size',v_size,'filters_not_applied',v_not_applied,'items',v_items);
end $function$;

CREATE OR REPLACE FUNCTION api.website_v2_course_item(p_course_id uuid, p_cities text[] DEFAULT NULL::text[], p_postcodes text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'search', 'catalogue', 'ref', 'pipeline', 'security', 'api'
AS $function$
declare d search.course_documents; v jsonb;
begin
  select * into d from search.course_documents where course_id = p_course_id;
  if not found then return null; end if;
  if exists (select 1 from security.layer4_search_blocked_courses b where b.course_id = p_course_id) then return null; end if;  -- v2.15.236
  v := jsonb_build_object(
    'course_id', d.course_stable_key,
    'course_code', d.course_code,
    'title', d.course_title,
    'country_code', d.country_code,
    'provider', jsonb_build_object('provider_id', d.provider_stable_key, 'name', security.provider_presentable_name(d.provider_name), 'legal_name', d.provider_name,
                  'university_groups', security.provider_university_groups(d.provider_id),
                  'ranking_summary', api.website_v2_ranking_summary(d.provider_id),
                  'logo', api.website_v2_provider_logo(d.provider_id)),
    'campuses', coalesce((select jsonb_agg(jsonb_build_object('city', security.place_presentable(k.city), 'postcode', k.postcode, 'subdivision_code', s.code,
                   'is_primary', coalesce(cc.is_primary,false), 'metro_area', rc.metro_area, 'regional_category', rc.category, 'regional_category_name', rc.category_name)
                   order by (p_cities is not null and (lower(btrim(k.city)) = any(p_cities) or lower(rc.metro_area) = any(p_cities))) desc,
                            (p_postcodes is not null and btrim(k.postcode) = any(p_postcodes)) desc, cc.is_primary desc nulls last, k.city)
                 from catalogue.course_campuses cc join catalogue.campuses k on k.id = cc.campus_id
                 left join ref.subdivisions s on s.id = k.subdivision_id left join pipeline.campus_regional_class rc on rc.campus_id = k.id
                 where cc.course_id = d.course_id), '[]'::jsonb),
    'study_level', jsonb_build_object('code', d.study_level_code, 'name', (select sl.name from ref.study_levels sl where sl.code = d.study_level_code limit 1)),
    'study_area', jsonb_build_object('code', d.primary_field_code, 'name', d.primary_field_name),
    'duration_months', (select round(c.duration_value * case lower(coalesce(c.duration_unit,'')) when 'weeks' then 12.0/52 when 'months' then 1 when 'years' then 12 end)::int
                        from catalogue.courses c where c.id = d.course_id),
    'delivery_modes', to_jsonb(d.delivery_modes),
    'tuition', api.website_v2_tuition(d),
    'intakes', coalesce((select jsonb_agg(distinct jsonb_build_object('label', i->>'label', 'month', api.website_v2_label_month(i->>'label'), 'year', i->'year',
                  'start_date', i->'start_date', 'application_deadline', i->'application_deadline'))
                 from jsonb_array_elements(coalesce(d.intake_options,'[]'::jsonb)) i where nullif(i->>'label','') is not null), '[]'::jsonb),
    'entry_requirements', jsonb_build_object(
        'summary', (select 'English: ' || string_agg(
                case e->>'test_code' when 'IELTS' then 'IELTS ' || to_char((e->>'overall_score')::numeric,'FM90.0')
                     when 'PTE' then 'PTE Academic ' || trim(to_char((e->>'overall_score')::numeric,'FM999'))
                     when 'TOEFL_IBT' then 'TOEFL iBT ' || trim(to_char((e->>'overall_score')::numeric,'FM999'))
                     else coalesce(e->>'test_name', e->>'test_code') || ' ' || (e->>'overall_score') end, ', '
                order by case e->>'test_code' when 'IELTS' then 1 when 'PTE' then 2 when 'TOEFL_IBT' then 3 else 4 end)
              from jsonb_array_elements(coalesce(d.english_requirement_options,'[]'::jsonb)) e where (e->>'overall_score') ~ '^[0-9]+(\.[0-9]+)?$'),
        'basis', case when jsonb_array_length(coalesce(d.english_requirement_options,'[]'::jsonb)) > 0 then 'english_only' end),
    'english_requirements', coalesce((select jsonb_agg(jsonb_build_object('test_code', e->>'test_code', 'test_name', e->>'test_name',
                  'min_overall_score', e->'overall_score',
                  'min_band_score', (select min(z.v::numeric) from jsonb_each_text(case when jsonb_typeof(e->'component_scores')='object' then e->'component_scores' else '{}'::jsonb end) z(k2,v) where z.v ~ '^[0-9]+(\.[0-9]+)?$'),
                  'source', case when e->>'notes' ~* 'policy|central|university standard' then 'university_policy' else 'course_page' end))
                 from jsonb_array_elements(coalesce(d.english_requirement_options,'[]'::jsonb)) e), '[]'::jsonb),
    'official_url', d.official_course_url,
    'scholarship_count', jsonb_array_length(coalesce(d.scholarship_options,'[]'::jsonb)),
    'subdivision_codes', to_jsonb(d.subdivision_codes),
    'publication_status', d.publication_status,
    'freshness', jsonb_build_object('projection_updated_at', d.updated_at, 'source_updated_at', d.source_updated_at));
  v := v || jsonb_build_object(
    'campus_city', v->'campuses'->0->'city',
    'campus_metro_area', v->'campuses'->0->'metro_area');
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.website_v2_providers(p_filters jsonb DEFAULT '{}'::jsonb, p_page integer DEFAULT 1, p_page_size integer DEFAULT 20, p_sort text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'search', 'catalogue', 'ref', 'pipeline', 'ranking', 'security', 'api'
AS $function$
declare
  f jsonb := coalesce(p_filters,'{}'::jsonb);
  v_page int := coalesce(p_page,1);
  v_size int := coalesce(p_page_size,20);
  v_kw text := nullif(btrim(coalesce(f->>'keyword','')),'');
  v_countries text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(coalesce(f->'country_codes',f->'country_code'))) x);
  v_subdivs text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(f->'subdivision_codes')) x);
  v_cities text[] := (select array_agg(lower(x)) from unnest(api.website_text_array(coalesce(f->'cities',f->'city'))) x);
  v_regional int[] := (select array_agg(x::int) from unnest(api.website_text_array(f->'regional_categories')) x where x ~ '^[1-3]$');
  v_groups text[] := (select array_agg(lower(regexp_replace(btrim(x),'^au_','','i'))) from unnest(api.website_text_array(coalesce(f->'university_groups',f->'university_group'))) x);
  v_levels text[] := api.website_text_array(f->'study_level_codes');
  v_areas text[] := api.website_text_array(f->'study_area_codes');
  v_ranked text[] := api.website_text_array(f->'ranked_in');
  v_qs_max int := nullif(f->>'qs_rank_max','')::int;
  v_the_max int := nullif(f->>'the_rank_max','')::int;
  v_sort text := coalesce(nullif(p_sort,''),'name_asc');
  v_known text[] := array['keyword','country_codes','country_code','subdivision_codes','cities','city','regional_categories','university_groups','university_group',
                          'study_level_codes','study_area_codes','has_scholarship','ranked_in','qs_rank_max','the_rank_max','has_logo','provider_ids'];
  v_providers text[] := api.website_text_array(f->'provider_ids');
  v_not_applied jsonb; v_total bigint; v_items jsonb;
begin
  if v_page < 1 or v_size < 1 or v_size > 50 then raise exception 'INVALID_INPUT: page must be >= 1 and page_size 1-50' using errcode='22023'; end if;
  if v_sort not in ('name_asc','qs_rank_asc','the_rank_asc','course_count_desc') then raise exception 'INVALID_INPUT: unknown sort' using errcode='22023'; end if;
  select coalesce(jsonb_agg(k),'[]'::jsonb) into v_not_applied from jsonb_object_keys(f) k where k <> all(v_known);

  with agg as (
    select d.provider_id, min(d.provider_stable_key) provider_stable_key, min(d.provider_name) provider_name, min(d.country_code) country_code,
      count(*) course_count, bool_or(d.has_scholarship) any_scholarship,
      array_agg(distinct d.study_level_code) levels, array_agg(distinct d.primary_field_code) areas
    from search.course_documents d
   where not exists (select 1 from security.layer4_search_blocked_providers b where b.provider_id = d.provider_id)  -- v2.15.236
   group by d.provider_id
  ), rk as (
    select l.provider_id,
      min(case when s.code='qs_wur' and e.edition_year = (select max(e2.edition_year) from ranking.editions e2 where e2.system_id=s.id and e2.status='accepted') then coalesce(o.rank_low,o.rank_exact) end) qs_rank,
      min(case when s.code='the_wur' and e.edition_year = (select max(e2.edition_year) from ranking.editions e2 where e2.system_id=s.id and e2.status='accepted') then coalesce(o.rank_low,o.rank_exact) end) the_rank,
      array_agg(distinct s.code) systems
    from ranking.observation_provider_links l join ranking.observations o on o.id=l.observation_id
    join ranking.editions e on e.id=o.edition_id and e.status='accepted' join ranking.systems s on s.id=e.system_id
    group by l.provider_id
  ), base as (
    select a.*, p.website, rk.qs_rank, rk.the_rank, rk.systems,
      exists (select 1 from catalogue.provider_assets pa where pa.provider_id=a.provider_id and pa.asset_type='logo' and pa.status='approved' and pa.is_primary) has_logo,
      (select count(*) from scholarship.scholarships sc where sc.provider_id=a.provider_id and sc.lifecycle_status='active' and sc.publication_status='published') sch_count
    from agg a join catalogue.providers p on p.id=a.provider_id
    left join rk on rk.provider_id=a.provider_id
    where (v_kw is null or a.provider_name ilike '%'||v_kw||'%' or security.provider_presentable_name(a.provider_name) ilike '%'||v_kw||'%')
      and (v_countries is null or a.country_code = any(v_countries))
      and (v_providers is null or a.provider_stable_key = any(v_providers))
      and (v_subdivs is null or exists (select 1 from search.course_documents d2 where d2.provider_id=a.provider_id and d2.subdivision_codes && v_subdivs))
      and (v_levels is null or a.levels && v_levels)
      and (v_areas is null or a.areas && v_areas)
      and (v_groups is null or exists (select 1 from catalogue.provider_collection_memberships gm join ref.institution_collections gic on gic.id=gm.collection_id
            where gm.provider_id=a.provider_id and gm.status='active' and (gm.valid_to is null or gm.valid_to>=current_date)
              and gic.collection_type='university_group' and gic.status='active' and replace(gic.code,'au_','') = any(v_groups)))
      and ((v_cities is null and v_regional is null) or exists (select 1 from catalogue.campuses k left join pipeline.campus_regional_class rc on rc.campus_id=k.id
            where k.provider_id=a.provider_id and (v_cities is null or lower(btrim(k.city)) = any(v_cities) or lower(rc.metro_area) = any(v_cities))
              and (v_regional is null or rc.category = any(v_regional))))
      and (v_ranked is null or rk.systems && v_ranked)
      and (v_qs_max is null or rk.qs_rank <= v_qs_max)
      and (v_the_max is null or rk.the_rank <= v_the_max)
  ), filtered as (
    select * from base
    where (not coalesce((f->>'has_scholarship')::boolean,false) or sch_count > 0)
      and (not coalesce((f->>'has_logo')::boolean,false) or has_logo)
  ), ordered as (
    select *, count(*) over () total, row_number() over (order by
      case when v_sort='qs_rank_asc' then qs_rank end asc nulls last,
      case when v_sort='the_rank_asc' then the_rank end asc nulls last,
      case when v_sort='course_count_desc' then course_count end desc,
      lower(security.provider_presentable_name(provider_name)), provider_stable_key) rn
    from filtered
  )
  select coalesce(max(total),0),
    coalesce(jsonb_agg(jsonb_build_object(
      'provider_id', o.provider_stable_key,
      'name', security.provider_presentable_name(o.provider_name),
      'legal_name', o.provider_name,
      'website', o.website,
      'country_code', o.country_code,
      'campuses', api.website_v2_provider_campuses(o.provider_id),
      'course_count', o.course_count,
      'study_levels_offered', (select jsonb_agg(jsonb_build_object('code', x.code, 'name', (select sl.name from ref.study_levels sl where sl.code=x.code limit 1), 'courses', x.n) order by x.n desc)
                               from (select d.study_level_code code, count(*) n from search.course_documents d where d.provider_id=o.provider_id and d.study_level_code is not null group by 1) x),
      'study_areas_offered', (select jsonb_agg(jsonb_build_object('code', x.code, 'name', x.name, 'courses', x.n) order by x.n desc)
                               from (select d.primary_field_code code, min(d.primary_field_name) name, count(*) n from search.course_documents d where d.provider_id=o.provider_id and d.primary_field_code is not null group by 1) x),
      'university_groups', security.provider_university_groups(o.provider_id),
      'scholarship_count', o.sch_count,
      'ranking_summary', api.website_v2_ranking_summary(o.provider_id),
      'logo', api.website_v2_provider_logo(o.provider_id),
      'publication_status', (select p.publication_status from catalogue.providers p where p.id=o.provider_id)
    ) order by o.rn) filter (where o.rn > (v_page-1)*v_size and o.rn <= v_page*v_size), '[]'::jsonb)
  into v_total, v_items
  from ordered o;

  return jsonb_build_object('contract_version','website-search-v2','total',v_total,'page',v_page,'page_size',v_size,'sort',v_sort,
                            'filters_not_applied',v_not_applied,'items',v_items);
end $function$;

-- 4. Search documents are rebuilt with the published providers only.
insert into search.refresh_requests(requested_by) values ('v2.15.236: provider publication becomes a real gate; all active providers published');

do $post$
declare v_expected jsonb := jsonb_build_object('search.refresh_course_base_v3(boolean)', 'bbb65ede2d426cd58bdfb96b02d0dc18', 'public.website_v2_scholarships(jsonb,integer,integer)', 'f0a9139a1bbfbe4a4e28eb4d9e35d31c', 'public.website_v2_scholarship(text)', '4168bdab5d6f2a3024adebfd476d8118', 'public.zoho_edge_scholarships_v1(text)', 'c1ba4d2d765cd9799be9e0f6f5f6dd32', 'public.website_v2_rankings(jsonb,integer,integer)', '9a9e95982ae5db7d318e16a86f7ac9cc', 'api.website_v2_course_item(uuid,text[],text[])', '6f3547292e5bd3d7e91ffa28131ac81f', 'public.website_v2_providers(jsonb,integer,integer,text)', '9e6674ed2d00102629a18a2396c5eff6');
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'CF-247 v2.15.236 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
