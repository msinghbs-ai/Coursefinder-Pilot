-- CF-247 v2.15.276, website requirements register O1 (Platform Admin, 14 Oct 2026 18:44: "recheck NZ and Canadian campus coverage in the
-- website API after today's Enrich fields campus links"). Platform Admin decisions (14 Oct 2026, multiple choice):
-- "Clear unproven NZ, keep CA" and "Refresh + delivery fix".
--   1 A campus made by Enrich fields took the provider's head-office region. In New Zealand a campus keeps a region only when it is in the
--     provider's own city; the others are cleared (null = not held). Each cleared value is kept in pipeline.campus_region_cleared so it
--     can be put back. Canada keeps the province. New campuses follow the same rule.
--   2 The search projection the website reads is refreshed when an Enrich fields task finishes, and once now: field of study, study level
--     and delivery mode written by the job reach the website API.
--   3 A course's delivery mode is its campus links' modes, or the course's own mode when no campus mode is held.
-- Additive for the website (rule 1 of the requirements register). Nothing dropped or deleted.

do $guard$
declare v_expected jsonb := '{"security.enrich_campus_list_apply_v1(bigint)": "adecd776ff7503c18d8b039805d0492f", "security.enrich_fields_slice_v1(uuid,integer)": "aa68e9a80a65f4e513b51ef1453b2751", "search.refresh_course_base_v3(boolean)": "bbb65ede2d426cd58bdfb96b02d0dc18"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

create table if not exists pipeline.campus_region_cleared (
  campus_id uuid primary key,
  subdivision_id uuid,
  reason text not null,
  cleared_at timestamptz not null default now());
alter table pipeline.campus_region_cleared enable row level security;

CREATE OR REPLACE FUNCTION security.enrich_campus_list_apply_v1(p_item bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare i pipeline.field_enrich_items%rowtype; x jsonb; v_cid uuid; v_min int := security.pipeline_num_v1('enrich.campus_min_pages', 2)::int;
        v_admitted jsonb := '[]'::jsonb; v_review jsonb := '[]'::jsonb; v_pages int; v_country uuid; v_sub uuid; v_cc text; v_pcity text; r record; v_ids jsonb; v_linked int := 0;
begin
  select * into i from pipeline.field_enrich_items where id = p_item for update;
  select p.country_id, p.subdivision_id, k.iso_alpha2::text, p.primary_city into v_country, v_sub, v_cc, v_pcity
    from catalogue.providers p join ref.countries k on k.id = p.country_id where p.id = i.provider_id;
  for x in select * from jsonb_array_elements(coalesce(i.value->'campuses', '[]'::jsonb)) loop
    -- agreement: the course pages that name this campus (its raw names) are counted from the job's own campus items
    select count(*) into v_pages from pipeline.field_enrich_items c
     where c.job_id = i.job_id and c.provider_id = i.provider_id and c.field = 'campus' and c.course_id is not null
       and exists (select 1 from jsonb_array_elements_text(coalesce(x->'raw', '[]'::jsonb)) rw where lower(c.quote) like '%' || lower(rw) || '%');
    if v_pages < v_min then v_review := v_review || (x || jsonb_build_object('pages', v_pages)); continue; end if;
    select ca.id into v_cid from catalogue.campuses ca where ca.provider_id = i.provider_id and lower(ca.name) = lower(x->>'name') limit 1;
    if v_cid is null then
      insert into catalogue.campuses(stable_key, provider_id, name, country_id, subdivision_id, city, address_line1, postcode, status, publication_status, evidence_id)
      values ('campus:studysearch:' || i.provider_id || ':' || regexp_replace(lower(x->>'name'), '[^a-z0-9]+', '-', 'g'), i.provider_id, left(x->>'name', 160), v_country,
              -- v2.15.276 O1: the provider's region only where it is proven for this campus (Canada: the province; elsewhere the provider's own city)
              case when v_cc = 'CA' or (nullif(btrim(x->>'city'), '') is not null and lower(btrim(x->>'city')) = lower(btrim(coalesce(v_pcity, '')))) then v_sub end,
              left(nullif(x->>'city', ''), 120), left(nullif(x->>'street', ''), 200), left(nullif(x->>'postcode', ''), 20), 'active', 'published', i.evidence_id)
      on conflict (stable_key) do update set updated_at = now()
      returning id into v_cid;
    end if;
    v_admitted := v_admitted || (x || jsonb_build_object('campus_id', v_cid, 'pages', v_pages));
  end loop;
  update pipeline.field_enrich_items set state = case when jsonb_array_length(v_admitted) > 0 then 'filled' when jsonb_array_length(v_review) > 0 then 'review' else 'skipped' end,
         value = value || jsonb_build_object('admitted', v_admitted, 'to_review', v_review),
         reason = case when jsonb_array_length(v_review) > 0 then jsonb_array_length(v_review) || ' campus name(s) named on too few course pages: a person decides' else reason end, updated_at = now()
   where id = i.id;
  return jsonb_build_object('admitted', jsonb_array_length(v_admitted), 'review', jsonb_array_length(v_review));
end $function$;

CREATE OR REPLACE FUNCTION security.enrich_fields_slice_v1(p_id uuid, p_items integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare j pipeline.admin_jobs%rowtype; it record; v_src text; v_srcs text[]; v_ai boolean; v_scr boolean; v_x jsonb; v_txt text; v_val jsonb;
        v_done int := 0; v_batch int := greatest(coalesce(p_items, 0), 1) * security.pipeline_num_v1('batch.enrich_fields', 400)::int / 10;
        v_cc text; v_path text; v_ev uuid; v_settled boolean; v_left int;
begin
  select * into j from pipeline.admin_jobs where id = p_id for update;
  v_ai := coalesce((j.args->>'ai')::boolean, true); v_scr := coalesce((j.args->>'scraper')::boolean, false);
  -- v2.15.275 hotfix: an item that has used its AI tries and is no longer being worked on is settled as failed, so the task can finish
  update pipeline.field_enrich_items e set state = 'failed', leased_until = null, updated_at = now(),
         reason = coalesce(e.reason, 'no answer could be recorded after ' || e.attempts || ' tries')
   where e.job_id = p_id and e.attempts >= 3 and (e.state = 'ai' or (e.state = 'leased' and e.leased_until < now()));
  -- items waiting for a requested page: move on when the page arrived, skip when the wait is over
  update pipeline.field_enrich_items e set state = 'queued', updated_at = now()
   where e.job_id = p_id and e.state = 'waiting' and e.field <> 'campus'
     and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = e.course_id and g.evidence_id is not null and g.read_at >= e.updated_at);
  update pipeline.field_enrich_items e set state = 'skipped', reason = 'the requested page read did not arrive in time', updated_at = now()
   where e.job_id = p_id and e.state = 'waiting' and e.field <> 'campus'
     and e.updated_at < now() - make_interval(hours => security.pipeline_num_v1('enrich.wait_page_hours', 6)::int);
  for it in select e.*, k.iso_alpha2::text cc from pipeline.field_enrich_items e join catalogue.providers p on p.id = e.provider_id join ref.countries k on k.id = p.country_id
             where e.job_id = p_id and e.state = 'queued' order by e.id limit v_batch for update of e skip locked loop
    v_settled := false; v_srcs := security.field_sources_for_v1(it.cc, case when it.field = 'campus_list' then 'campus' else it.field end);
    foreach v_src in array v_srcs loop
      continue when v_src = any (it.tried);
      continue when v_src in ('ai_stored', 'ai_title') and not v_ai;
      continue when v_src = 'scraper' and not v_scr;
      update pipeline.field_enrich_items set tried = tried || v_src where id = it.id;
      if v_src = 'adapter' and it.course_id is not null then
        select r.fields->'extra' into v_x from pipeline.uni_adapter_results r where r.course_id = it.course_id order by r.at desc limit 1;
        v_txt := nullif(btrim(case it.field when 'campus' then coalesce(v_x->>'campus', v_x->>'location') when 'duration' then v_x->>'duration'
                                            when 'level' then v_x->>'study_level' when 'delivery' then v_x->>'mode' when 'international' then v_x->>'student_type' end), '');
        if v_txt is null then continue; end if;
        v_ev := (select g.evidence_id from pipeline.coverage_course_pages g where g.course_id = it.course_id);
        v_val := case it.field when 'duration' then security.enrich_parse_duration_v1(v_txt)
                               when 'level' then (select jsonb_build_object('level_id', l) from (select security.enrich_parse_level_v1(v_txt) l) z where l is not null)
                               when 'delivery' then (select jsonb_build_object('mode', m) from (select security.enrich_parse_delivery_v1(left(v_txt, 120)) m) z where m is not null)
                               when 'international' then case when v_txt ~* 'international' then jsonb_build_object('open', true) end
                               else null end;
        if it.field = 'campus' then
          -- the campus text waits for the university's campus list
          update pipeline.field_enrich_items set state = 'waiting', source = 'adapter', quote = left(v_txt, 300), evidence_id = v_ev, updated_at = now() where id = it.id;
          v_settled := true; exit;
        end if;
        if v_val is null then continue; end if;
        update pipeline.field_enrich_items set source = 'adapter', value = v_val, quote = left(v_txt, 300), evidence_id = v_ev, updated_at = now() where id = it.id;
        perform security.enrich_apply_v1(it.id); v_settled := true; exit;
      elsif v_src = 'institution_rule' and it.field = 'international' then
        if it.cc = 'CA' and exists (select 1 from catalogue.provider_identifiers i where i.provider_id = it.provider_id and i.scheme = 'ircc_dli') then
          update pipeline.field_enrich_items set source = 'institution_rule', value = jsonb_build_object('open', true),
                 quote = 'Listed by IRCC as a designated learning institution (DLI ' || (select i.identifier from catalogue.provider_identifiers i where i.provider_id = it.provider_id and i.scheme = 'ircc_dli' limit 1) || ')', updated_at = now()
           where id = it.id;
          perform security.enrich_apply_v1(it.id); v_settled := true; exit;
        end if;
      elsif v_src = 'ai_stored' then
        if it.field = 'provider_address' then
          select e.storage_path, e.id into v_path, v_ev from pipeline.evidence_artifacts e join pipeline.sources s on s.id = e.source_id
           where s.provider_id = it.provider_id and e.evidence_type in ('provider_contact_html_snapshot', 'enrich_home_page') and e.storage_path is not null order by e.created_at desc limit 1;
        elsif it.field = 'campus_list' then
          v_path := null; v_ev := null;  -- the list is made from the campus names, with the contact page when one is stored
          select e.storage_path, e.id into v_path, v_ev from pipeline.evidence_artifacts e join pipeline.sources s on s.id = e.source_id
           where s.provider_id = it.provider_id and e.evidence_type in ('provider_contact_html_snapshot', 'enrich_home_page') and e.storage_path is not null order by e.created_at desc limit 1;
          update pipeline.field_enrich_items set state = 'ai', source = 'ai_stored', storage_path = v_path, evidence_id = v_ev, updated_at = now() where id = it.id;
          v_settled := true; exit;
        else
          select e.storage_path, e.id into v_path, v_ev from pipeline.coverage_course_pages g join pipeline.evidence_artifacts e on e.id = g.evidence_id where g.course_id = it.course_id;
        end if;
        if v_path is null then continue; end if;
        update pipeline.field_enrich_items set state = 'ai', source = 'ai_stored', storage_path = v_path, evidence_id = v_ev, updated_at = now() where id = it.id;
        v_settled := true; exit;
      elsif v_src = 'ai_title' and it.course_id is not null then
        update pipeline.field_enrich_items set state = 'ai', source = 'ai_title', updated_at = now() where id = it.id;
        v_settled := true; exit;
      elsif v_src = 'scraper' then
        if it.field = 'provider_address' then
          if exists (select 1 from catalogue.providers p where p.id = it.provider_id and p.website ~* '^https?://' and not security.third_party_host_v1(p.website)) then
            update pipeline.field_enrich_items set state = 'ai', source = 'scraper', storage_path = null, updated_at = now() where id = it.id;
            v_settled := true; exit;
          end if;
        elsif it.course_id is not null and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = it.course_id and g.url ~* '^https?://') then
          update pipeline.coverage_course_pages set next_read_at = now() where course_id = it.course_id and coalesce(next_read_at, 'infinity') > now();
          update pipeline.field_enrich_items set state = 'waiting', reason = 'course page asked to be read', updated_at = now() where id = it.id;
          v_settled := true; exit;
        end if;
      end if;
    end loop;
    if not v_settled then
      update pipeline.field_enrich_items set state = 'skipped', reason = coalesce(reason, 'no allowed source had a value'), updated_at = now() where id = it.id and state = 'queued';
    end if;
    v_done := v_done + 1;
  end loop;
  -- a university's campus list goes to the AI once its course campus items have all been read
  update pipeline.field_enrich_items l set state = 'queued', updated_at = now()
   where l.job_id = p_id and l.field = 'campus_list' and l.state = 'waiting'
     and not exists (select 1 from pipeline.field_enrich_items c where c.job_id = p_id and c.provider_id = l.provider_id and c.field = 'campus' and c.state in ('queued', 'ai', 'leased'));
  perform security.enrich_campus_link_v1(p_id);
  -- course campus items whose page named no campus: nothing to link
  update pipeline.field_enrich_items c set state = 'skipped', reason = 'no campus named on the page', updated_at = now()
   where c.job_id = p_id and c.field = 'campus' and c.state = 'waiting' and c.quote is null;
  if exists (select 1 from pipeline.field_enrich_items where job_id = p_id and state = 'ai') then perform security.enrich_ai_fire_v1(); end if;
  select count(*) into v_left from pipeline.field_enrich_items where job_id = p_id and state in ('queued', 'waiting', 'ai', 'leased');
  update pipeline.admin_jobs set progress = (select jsonb_build_object('done', count(*) filter (where state in ('filled', 'review', 'skipped', 'failed')), 'total', count(*),
                                                   'phase', case when v_left = 0 then 'finishing' when count(*) filter (where state in ('ai', 'leased')) > 0 then 'reading with AI' else 'settling stored values' end)
                                               from pipeline.field_enrich_items where job_id = p_id),
         result = (select jsonb_build_object('by_field', jsonb_object_agg(f, s), 'cost_usd', (select round(coalesce(sum(cost_usd), 0), 4) from pipeline.field_enrich_items where job_id = p_id))
                     from (select field f, jsonb_object_agg(state, n) s from (select field, state, count(*) n from pipeline.field_enrich_items where job_id = p_id group by 1, 2) z group by field) y),
         updated_at = now()
   where id = p_id;
  -- v2.15.276 O1: the values reach the website once the task finishes
  if v_left = 0 then insert into search.refresh_requests(requested_by) values ('enrich fields task ' || left(p_id::text, 8) || ' finished'); end if;
  return v_left = 0;
end $function$;

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
    case when cardinality(coalesce(geo.delivery_modes,'{}'::text[])) > 0 then geo.delivery_modes
         when nullif(btrim(c.delivery_mode),'') is not null then array[c.delivery_mode] else '{}'::text[] end as delivery_modes,  -- v2.15.276 O1: the course's own mode when no campus mode is held
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

-- 1 New Zealand campuses made by Enrich fields whose region is not proven (not in the provider's own city): keep the value, then clear it
insert into pipeline.campus_region_cleared(campus_id, subdivision_id, reason)
select k.id, k.subdivision_id, 'NZ campus made by Enrich fields: region copied from the provider, campus not in the provider''s city'
  from catalogue.campuses k join catalogue.providers p on p.id = k.provider_id join ref.countries c on c.id = p.country_id
 where c.iso_alpha2 = 'NZ' and k.stable_key like 'campus:studysearch:%' and k.subdivision_id is not null
   and not (nullif(btrim(k.city), '') is not null and lower(btrim(k.city)) = lower(btrim(coalesce(p.primary_city, ''))))
on conflict do nothing;
update catalogue.campuses k set subdivision_id = null, updated_at = now()
  from pipeline.campus_region_cleared x where x.campus_id = k.id and k.subdivision_id is not distinct from x.subdivision_id;
-- 2 refresh the search projection once now (processed by search-refresh-requested within 10 minutes)
insert into search.refresh_requests(requested_by) values ('v2.15.276 O1: NZ campus regions cleared where unproven; Enrich fields values reach the website');

do $post$
declare v_expected jsonb := '{"security.enrich_campus_list_apply_v1(bigint)": "2617420b455dea68f7cb2cbed8271088", "security.enrich_fields_slice_v1(uuid,integer)": "03cc5526a082f59867a8313cdefa04fd", "search.refresh_course_base_v3(boolean)": "a3737e584163ca71ce4d240b268435e3"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.276 O1 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
