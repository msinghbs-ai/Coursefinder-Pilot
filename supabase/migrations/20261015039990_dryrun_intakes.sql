-- CF-247 (15 Oct 2026): bug fix. Platform Admin, 15 Oct 2026 12:31: "Bug/Fix: intake are duplicated and state is not listed for CA courses."
-- Found: 410 courses (Australia 60, New Zealand 182, Canada 168) held the same intake month twice: four writers key a course's intakes
-- differently (CRICOS code, course id, or the source code), so the same month from the same page was stored as two rows. Canada: 2,391 courses
-- have no campus, so the search projection (website state filter and API) held no province, and the course detail never showed one; every
-- one of their providers has its province (the 14 Oct decision "keep CA" accepts a Canadian provider's province).
-- Replaces: nothing (writers unchanged; a guard on the table stops a second active row for the same month, whichever writer sends it)
-- Retires: search.refresh_course_documents_v2 (no caller and no job since search.refresh_course_base_v3; marked retiring, dropped by paste file after 14 days)
-- 1 Setting   2 Guard on catalogue.course_intakes; regions from the provider for the listed countries; register kind for functions
-- 3 Replaced functions (md5-guarded): search.refresh_course_base_v3 (province), security.admin_read_impl (course detail gives country and province)
-- 4 Duplicates withdrawn (status, kept), projection refreshed   Nothing dropped or deleted.

do $guard$
declare v_expected jsonb := '{"search.refresh_course_base_v3(boolean)": "a3737e584163ca71ce4d240b268435e3", "security.admin_read_impl(text,jsonb)": "056bef9a8a2b0290cd3939403af5eef6"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- 1 Setting
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'search.region_from_provider_countries', 'Courses with no campus take the provider''s state or province in', 'For these countries a course with no campus is listed under its provider''s state or province (website state filter and API). Other countries list a region only from a campus.', 'list', '["CA"]'::jsonb, null, null, 'countries', 305, 'Platform Admin 15 Oct 2026: "state is not listed for CA courses"; 14 Oct decision "keep CA" (a Canadian provider''s province is accepted)', 'Website API', 'search projection (search.refresh_course_base_v3)')
on conflict do nothing;

-- 2 Rules
CREATE OR REPLACE FUNCTION security.region_fallback_countries_v1()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select array(select jsonb_array_elements_text(s.value)) from pipeline.platform_toolset_settings s
                    where s.toolset_key = 'pipeline' and s.key = 'search.region_from_provider_countries' and jsonb_typeof(s.value) = 'array'), '{}'::text[])
$function$;

CREATE OR REPLACE FUNCTION security.course_intake_same_month_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- one active row per course, month, year and campus, whichever writer sends it (writers key intakes differently)
  if coalesce(new.status, 'active') = 'active' and exists (
       select 1 from catalogue.course_intakes i
        where i.course_id = new.course_id and i.id <> new.id and coalesce(i.status, 'active') = 'active'
          and lower(btrim(i.intake_label)) = lower(btrim(new.intake_label))
          and i.intake_year is not distinct from new.intake_year and i.campus_id is not distinct from new.campus_id
          and i.start_date is not distinct from new.start_date) then
    return null;  -- the month is already held: the second row is not stored
  end if;
  return new;
end $function$;

create trigger course_intake_same_month_guard before insert or update on catalogue.course_intakes
  for each row execute function security.course_intake_same_month_guard();

alter table pipeline.component_register drop constraint if exists component_register_kind_check;
alter table pipeline.component_register add constraint component_register_kind_check check (kind in ('job', 'table', 'view', 'edge_function', 'screen', 'function'));

revoke execute on function security.region_fallback_countries_v1(), security.course_intake_same_month_guard() from public, anon, authenticated;

-- 3 Replaced functions

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
    case when cardinality(coalesce(geo.subdivision_codes,'{}'::text[])) > 0 then geo.subdivision_codes
         when co.iso_alpha2 = any (security.region_fallback_countries_v1()) and psd.code is not null then array[psd.code]  -- CF-247 15 Oct: no campus, the provider's province (listed countries)
         else '{}'::text[] end as subdivision_codes,
    case when cardinality(coalesce(geo.delivery_modes,'{}'::text[])) > 0 then geo.delivery_modes
         when nullif(btrim(c.delivery_mode),'') is not null then array[c.delivery_mode] else '{}'::text[] end as delivery_modes,  -- v2.15.276 O1: the course's own mode when no campus mode is held
    (cardinality(coalesce(geo.subdivision_codes,'{}'::text[])) > 0 or (co.iso_alpha2 = any (security.region_fallback_countries_v1()) and psd.code is not null)) as has_state,
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
  left join ref.subdivisions psd on psd.id=p.subdivision_id
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

CREATE OR REPLACE FUNCTION security.admin_read_impl(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'security', 'catalogue', 'ref', 'pim', 'scholarship', 'pipeline', 'workflow', 'integration', 'search', 'publishing', 'auth'
AS $function$
declare
  v_rank integer := 0;
  v_result jsonb;
  v_id uuid;
  v_limit integer := least(greatest(coalesce((p_args->>'limit')::integer,500),1),2000);
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank < 1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  if p_operation='context' then return public.ui_context();
  elsif p_operation='dashboard' then return public.ui_dashboard();
  elsif p_operation='providers' then select coalesce(jsonb_agg(to_jsonb(x) order by x.canonical_name),'[]'::jsonb) into v_result from public.ui_providers_list(v_limit) x; return v_result;
  elsif p_operation='provider_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    select coalesce(public.ui_provider_detail(v_id),'{}'::jsonb)||jsonb_build_object('evidence',coalesce(public.ui_provider_related_evidence(v_id,100,0,null,null)->'rows','[]'::jsonb),'courses',coalesce(public.ui_provider_related_courses(v_id,100,0,null,null,null)->'rows','[]'::jsonb)) into v_result; return v_result;
  elsif p_operation='campuses' then select coalesce(jsonb_agg(to_jsonb(x) order by x.provider_name,x.name),'[]'::jsonb) into v_result from public.ui_campuses_list(v_limit) x; return v_result;
  elsif p_operation='campus_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    select jsonb_build_object('id',ca.id,'stable_key',ca.stable_key,'name',ca.name,'campus_code',ca.campus_code,'provider_id',ca.provider_id,'provider_name',coalesce(p.display_name,p.canonical_name),'country_code',co.iso_alpha2,'subdivision_code',sd.code,'subdivision_name',sd.name,'city',ca.city,'address_line1',ca.address_line1,'address_line2',ca.address_line2,'postcode',ca.postcode,'latitude',ca.latitude,'longitude',ca.longitude,'phone',ca.phone,'website',ca.website,'status',ca.status,'publication_status',ca.publication_status,'valid_from',ca.valid_from,'valid_to',ca.valid_to,'last_verified_at',ca.last_verified_at,'created_at',ca.created_at,'updated_at',ca.updated_at,'source',jsonb_build_object('source_id',ca.source_id,'source_label',s.label,'source_type',s.source_type,'source_url',s.url),'evidence',case when e.id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('id',e.id,'type',e.evidence_type,'source_url',e.source_url,'storage_path',e.storage_path,'content_hash',e.content_hash,'captured_at',e.captured_at)) end,'courses',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'title',c.canonical_title,'delivery_mode',cc.delivery_mode,'is_primary',cc.is_primary) order by c.canonical_title) from catalogue.course_campuses cc join catalogue.courses c on c.id=cc.course_id where cc.campus_id=ca.id),'[]'::jsonb)) into v_result from catalogue.campuses ca join catalogue.providers p on p.id=ca.provider_id join ref.countries co on co.id=ca.country_id left join ref.subdivisions sd on sd.id=ca.subdivision_id left join pipeline.sources s on s.id=ca.source_id left join pipeline.evidence_artifacts e on e.id=ca.evidence_id where ca.id=v_id; return coalesce(v_result,'{}'::jsonb);
  elsif p_operation='courses' or p_operation='completeness' then select coalesce(jsonb_agg(to_jsonb(x) order by x.provider_name,x.canonical_title),'[]'::jsonb) into v_result from public.ui_course_completeness_list(v_limit) x; return v_result;
  elsif p_operation='course_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    select coalesce(public.ui_course_detail(v_id),'{}'::jsonb)||jsonb_build_object(
      'fee_summary',jsonb_build_object(
        'cricos_registered',coalesce((select jsonb_agg(jsonb_build_object('id',cf.id,'fee_type',cf.fee_type,'amount',cf.amount,'currency',cf.currency_code,'basis',cf.basis,'fee_year',cf.fee_year,'audience',cf.audience,'status',cf.status,'source_snapshot_at',cf.source_snapshot_at,'evidence_id',cf.evidence_id) order by cf.fee_type) from catalogue.course_fees cf where cf.course_id=v_id and cf.basis='registered_total_course' and coalesce(cf.status,'active')='active'),'[]'::jsonb),
        'provider_current',coalesce((select jsonb_agg(jsonb_build_object('id',cf.id,'fee_type',cf.fee_type,'amount',cf.amount,'currency',cf.currency_code,'basis',cf.basis,'fee_year',cf.fee_year,'audience',cf.audience,'status',cf.status,'source_snapshot_at',cf.source_snapshot_at,'source_id',cf.source_id,'evidence_id',cf.evidence_id) order by cf.fee_year desc nulls last,cf.created_at desc) from catalogue.course_fees cf where cf.course_id=v_id and cf.basis is distinct from 'registered_total_course' and coalesce(cf.status,'active')='active'),'[]'::jsonb)
      ),
      'regulatory_facts',coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('scheme',o.scheme,'registration_code',o.registration_code,'status',o.status,'course_language',o.course_language,'work_component',o.work_component,'work_component_total_hours',o.work_component_total_hours,'foundation_studies',o.foundation_studies,'dual_qualification',o.dual_qualification,'source_snapshot_at',o.source_snapshot_at,'evidence_id',o.evidence_id)) order by o.source_snapshot_at desc) from catalogue.course_regulatory_observations o where o.course_id=v_id and o.valid_to is null),'[]'::jsonb),
      -- CF-247 15 Oct: the provider's country and state or province, shown with the provider on the course detail
      'country_code',(select k.iso_alpha2 from catalogue.courses c2 join catalogue.providers p2 on p2.id=c2.provider_id join ref.countries k on k.id=p2.country_id where c2.id=v_id),
      'subdivision_code',(select s2.code from catalogue.courses c2 join catalogue.providers p2 on p2.id=c2.provider_id join ref.subdivisions s2 on s2.id=p2.subdivision_id where c2.id=v_id),
      'subdivision_name',(select s2.name from catalogue.courses c2 join catalogue.providers p2 on p2.id=c2.provider_id join ref.subdivisions s2 on s2.id=p2.subdivision_id where c2.id=v_id),
      'campuses',coalesce(public.ui_course_related_campuses(v_id),'[]'::jsonb),
      'evidence',coalesce((select jsonb_agg(distinct jsonb_build_object('id',e.id,'evidence_type',e.evidence_type,'source_url',e.source_url,'storage_path',e.storage_path,'content_hash',e.content_hash,'captured_at',e.captured_at,'valid_from',e.valid_from,'valid_to',e.valid_to)) from pipeline.evidence_artifacts e where e.id in (
        select evidence_id from catalogue.course_fees where course_id=v_id and evidence_id is not null
        union select evidence_id from catalogue.course_registrations where course_id=v_id and evidence_id is not null
        union select evidence_id from catalogue.course_regulatory_observations where course_id=v_id and evidence_id is not null
        union select evidence_id from catalogue.course_links where course_id=v_id and evidence_id is not null
        union select av.evidence_id from pim.attribute_values av join pim.entity_registry er on er.id=av.entity_id where er.entity_type='course' and er.stable_key=(select stable_key from catalogue.courses where id=v_id) and av.evidence_id is not null
      ) or e.entity_id=v_id),'[]'::jsonb)
    ) into v_result;
    return v_result;
  elsif p_operation='scholarships' then select coalesce(jsonb_agg(to_jsonb(x) order by x.provider_name,x.name),'[]'::jsonb) into v_result from public.ui_scholarships_list(v_limit) x; return v_result;
  elsif p_operation='scholarship_detail' then v_id:=nullif(p_args->>'id','')::uuid; return coalesce(public.ui_scholarship_detail(v_id),'{}'::jsonb);
  elsif p_operation='evidence' then if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if; select coalesce(jsonb_agg(to_jsonb(x) order by x.captured_at desc),'[]'::jsonb) into v_result from public.ui_evidence_governance_list(v_limit) x; return v_result;
  elsif p_operation='reviews' then if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if; select coalesce(jsonb_agg(to_jsonb(x) order by x.priority desc,x.created_at desc),'[]'::jsonb) into v_result from public.ui_review_queue(v_limit) x; return v_result;
  elsif p_operation='attributes' then if v_rank<5 then raise exception 'pim_admin role required' using errcode='42501'; end if; select jsonb_build_object('families',coalesce((select jsonb_agg(to_jsonb(x)) from public.ui_attribute_families_list() x),'[]'::jsonb),'groups',coalesce((select jsonb_agg(to_jsonb(x)) from public.ui_attribute_groups_list() x),'[]'::jsonb),'attributes',coalesce((select jsonb_agg(to_jsonb(x)) from public.ui_attributes_list() x),'[]'::jsonb),'options',coalesce((select jsonb_agg(to_jsonb(x)) from public.ui_attribute_options_list(v_limit) x),'[]'::jsonb),'completeness_profiles',coalesce((select jsonb_agg(to_jsonb(x)) from public.ui_completeness_profiles_list() x),'[]'::jsonb)) into v_result; return v_result;
  elsif p_operation='jobs' then if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if; select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_result from public.ui_jobs_list(v_limit) x; return v_result;
  elsif p_operation='sources' then if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if; select coalesce(jsonb_agg(to_jsonb(x) order by x.country_code,x.source_label),'[]'::jsonb) into v_result from public.ui_regulatory_sources_list() x; return v_result;
  else raise exception 'unsupported admin read operation: %',p_operation using errcode='22023';
  end if;
end$function$;

-- 4 Duplicates withdrawn (one active row kept per course, month, year, campus and start date: the oldest key that names the course id, else the first)
do $dedupe$
declare v_ids uuid[]; v_n int;
begin
  with d as (
    select i.id, i.course_id,
           row_number() over (partition by i.course_id, lower(btrim(i.intake_label)), i.intake_year, i.campus_id, i.start_date
                              order by (i.source_intake_key like i.course_id::text || ':%') desc, i.id) rn
      from catalogue.course_intakes i where coalesce(i.status, 'active') = 'active'),
  w as (update catalogue.course_intakes i set status = 'withdrawn' from d where d.id = i.id and d.rn > 1 returning i.course_id)
  select array_agg(distinct course_id), count(*) into v_ids, v_n from w;
  raise notice 'intake duplicates withdrawn: % rows, % courses', v_n, coalesce(cardinality(v_ids), 0);
  if cardinality(v_ids) > 0 then perform search.refresh_course_enrichment_scoped_v1(v_ids, true); end if;
end $dedupe$;
-- the projection takes the provinces on its next run
insert into search.refresh_requests(requested_by) values ('CF-247 15 Oct 2026: Canadian provinces for courses with no campus');
-- housekeeping: the old projection function is retiring
insert into pipeline.component_register(kind, name, layer, purpose, status, replaced_by, introduced_in, retire_after, note)
values ('function', 'search.refresh_course_documents_v2(boolean)', 'Website API', 'Former search projection build', 'retiring', 'search.refresh_course_base_v3(boolean)',
        '20261015040000', current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int, 'No caller and no job (15 Oct 2026)')
on conflict (kind, name) do nothing;

do $post$
declare v_expected jsonb := '{"search.refresh_course_base_v3(boolean)": "d9b021b2ac51c48c4818d54dcb6c4042", "security.admin_read_impl(text,jsonb)": "2c2da9acdacaa6a99b37e527718aec6c"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'intake duplicates and CA regions post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;

do $post2$
begin
  if exists (select 1 from catalogue.course_intakes where coalesce(status, 'active') = 'active'
              group by course_id, lower(btrim(intake_label)), intake_year, campus_id, start_date having count(*) > 1) then
    raise exception 'intake post-check: duplicates remain';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'course_intake_same_month_guard' and tgrelid = 'catalogue.course_intakes'::regclass) then
    raise exception 'intake post-check: guard missing';
  end if;
end $post2$;

do $dry$
declare v jsonb; c uuid; t0 timestamptz;
begin
  select co.id into c from catalogue.courses co join catalogue.providers p on p.id=co.provider_id where p.canonical_name ilike 'Athabasca%' and co.canonical_title ilike 'Bachelor of Arts Women%' limit 1;
  t0 := clock_timestamp();
  perform search.refresh_course_base_v3(true);
  v := jsonb_build_object(
    'refresh_s', extract(epoch from clock_timestamp()-t0),
    'atha_intakes', (select jsonb_agg(intake_label order by intake_label) from catalogue.course_intakes where course_id=c and coalesce(status,'active')='active'),
    'atha_doc_sub', (select subdivision_codes from search.course_documents where course_id=c),
    'atha_detail', (select jsonb_build_object('country',x->>'country_code','sub',x->>'subdivision_name') from (select security.admin_read_impl('course_detail', jsonb_build_object('id',c)) x) z),
    'ca_with_sub', (select count(*) filter (where cardinality(subdivision_codes)>0) from search.course_documents where country_code='CA'),
    'nz_with_sub', (select count(*) filter (where cardinality(subdivision_codes)>0) from search.course_documents where country_code='NZ'),
    'au_with_sub', (select count(*) filter (where cardinality(subdivision_codes)>0) from search.course_documents where country_code='AU'),
    'withdrawn_now', (select count(*) from catalogue.course_intakes where status='withdrawn'),
    'guard_test', (select count(*) from catalogue.course_intakes where course_id=c and coalesce(status,'active')='active'));
  -- the guard: a second active April from another key is not stored
  insert into catalogue.course_intakes(course_id, intake_label, status, source_id, source_intake_key) values (c, 'April', 'active', '8a259e96-b4bd-4dfe-89c2-1a46c32b3595', 'dryrun:current:april');
  v := v || jsonb_build_object('after_guard_insert', (select count(*) from catalogue.course_intakes where course_id=c and coalesce(status,'active')='active'));
  raise exception 'DRYRUN %', v;
end $dry$;
