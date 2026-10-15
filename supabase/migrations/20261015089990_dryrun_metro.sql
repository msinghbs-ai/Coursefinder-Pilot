-- CF-247 (15 Oct 2026): found while refreshing the website developer pack (Platform Admin 17:02: "refresh and repost deliverables for Developer
-- for Website v2 API with email"). The reference reply listed the city Sydney under the metro area Brisbane: a city's metro area was the
-- alphabetically first of its campuses' metro areas, so one campus whose register state was wrong (Berkeley Business Institute, "SYDNEY NSW
-- 2000", registered as Queensland) decided it for 2,484 courses. Five campuses have a register state that disagrees with their postcode; in two
-- (that one, and International Institute of Australia, "Springvale VIC 3171", registered as NSW) the campus address names the postcode's state.
-- Replaces: the reference's alphabetical metro area per city (now the metro area most of the city's campuses have)
-- Retires: nothing
-- 1 State from the postcode when the campus address names that state  2 Reference: most common metro area per city  Nothing dropped or deleted.

do $guard$
declare v_expected jsonb := '{"security.campus_regional_class_refresh_v1()": "c0055549ddab3e75a23f51a1930633c4", "api.website_v2_reference_build()": "a3d1dfa9891653904c4bb9b5786c2564"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- 1 The state a four-digit Australian postcode belongs to
CREATE OR REPLACE FUNCTION security.au_state_from_postcode_v1(p_postcode text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case when p_postcode !~ '^\d{4}$' then null
              when p_postcode ~ '^(26[0-1]\d|29[0-2]\d|02\d\d)$' then 'ACT'
              when p_postcode ~ '^(1|2)' then 'NSW' when p_postcode ~ '^(3|8)' then 'VIC' when p_postcode ~ '^(4|9)' then 'QLD'
              when p_postcode ~ '^5' then 'SA' when p_postcode ~ '^6' then 'WA' when p_postcode ~ '^7' then 'TAS' when p_postcode ~ '^0[89]' then 'NT' end
$function$;

CREATE OR REPLACE FUNCTION security.campus_regional_class_refresh_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'ref', 'security'
AS $function$
declare n int;
begin
  insert into pipeline.campus_regional_class(campus_id,state_code,postcode,category,category_name,metro_area,computed_at)
  select k.id, st.code, k.postcode, (c->>'category')::smallint,
         case (c->>'category')::int when 1 then 'Major city' when 2 then 'City or major regional centre' when 3 then 'Regional centre or other regional area' end,
         c->>'metro_area', now()
    from catalogue.campuses k left join ref.subdivisions s on s.id=k.subdivision_id
    -- CF-247 15 Oct 2026: when the register state disagrees with the postcode and the campus address names the postcode's state, the address wins
    cross join lateral (select case when security.au_state_from_postcode_v1(k.postcode) is not null and s.code is distinct from 'AU-' || security.au_state_from_postcode_v1(k.postcode)
                                     and concat_ws(' ', k.name, k.address_line1, k.address_line2) ~* ('\m' || security.au_state_from_postcode_v1(k.postcode) || '\M')
                                    then 'AU-' || security.au_state_from_postcode_v1(k.postcode) else s.code end code) st
    cross join lateral (select security.au_regional_class(st.code,k.postcode) c) z
  on conflict (campus_id) do update set state_code=excluded.state_code, postcode=excluded.postcode, category=excluded.category,
         category_name=excluded.category_name, metro_area=excluded.metro_area, computed_at=now()
   where pipeline.campus_regional_class.postcode is distinct from excluded.postcode or pipeline.campus_regional_class.state_code is distinct from excluded.state_code
      or pipeline.campus_regional_class.category is distinct from excluded.category;
  get diagnostics n=row_count;
  return jsonb_build_object('changed',n);
end $function$;

CREATE OR REPLACE FUNCTION api.website_v2_reference_build()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'search', 'ref', 'catalogue', 'scholarship', 'security', 'api'
AS $function$
  select jsonb_build_object(
    'contract_version','website-search-v2',
    'countries', (select jsonb_agg(jsonb_build_object(
        'country_code', c.country_code, 'courses', c.n,
        'study_levels', (select jsonb_agg(jsonb_build_object('code', x.code, 'name', (select sl.name from ref.study_levels sl where sl.code=x.code limit 1), 'courses', x.n) order by x.n desc)
                         from (select study_level_code code, count(*) n from search.course_documents where country_code=c.country_code and study_level_code is not null group by 1) x),
        'study_areas', (select jsonb_agg(jsonb_build_object('code', x.code, 'name', x.name, 'courses', x.n) order by x.n desc)
                        from (select primary_field_code code, min(primary_field_name) name, count(*) n from search.course_documents where country_code=c.country_code and primary_field_code is not null group by 1) x),
        'subdivisions', (select jsonb_agg(jsonb_build_object('code', x.code, 'courses', x.n) order by x.code)
                         from (select s code, count(*) n from search.course_documents d, unnest(d.subdivision_codes) s where d.country_code=c.country_code group by 1) x),
        'cities', (select jsonb_agg(jsonb_build_object('city', x.city, 'metro_area', x.metro, 'courses', x.n) order by x.n desc)
                   from (select security.place_presentable(k.city) city, mode() within group (order by rc.metro_area) metro, count(distinct cc.course_id) n
                         from search.course_documents d join catalogue.course_campuses cc on cc.course_id=d.course_id join catalogue.campuses k on k.id=cc.campus_id
                         left join pipeline.campus_regional_class rc on rc.campus_id=k.id
                         where d.country_code=c.country_code and nullif(btrim(k.city),'') is not null group by 1 having count(distinct cc.course_id) >= 5) x),
        'intake_months', (select jsonb_agg(jsonb_build_object('month', x.m, 'courses', x.n) order by x.m)
                          from (select api.website_v2_label_month(i->>'label') m, count(distinct d.course_id) n from search.course_documents d, jsonb_array_elements(coalesce(d.intake_options,'[]'::jsonb)) i
                                where d.country_code=c.country_code and api.website_v2_label_month(i->>'label') is not null group by 1) x),
        'english_tests', (select jsonb_agg(jsonb_build_object('code', x.code, 'courses', x.n) order by x.n desc)
                          from (select upper(e->>'test_code') code, count(distinct d.course_id) n from search.course_documents d, jsonb_array_elements(coalesce(d.english_requirement_options,'[]'::jsonb)) e
                                where d.country_code=c.country_code and e->>'test_code' is not null group by 1) x)
      ) order by c.n desc) from (select country_code, count(*) n from search.course_documents group by 1) c),
    'regional_categories', jsonb_build_array(jsonb_build_object('code',1,'name','Major city'), jsonb_build_object('code',2,'name','City or major regional centre'), jsonb_build_object('code',3,'name','Regional centre or other regional area')),
    'institution_types', (select jsonb_agg(jsonb_build_object('code', t.code, 'name', t.name, 'description', t.description,
                             'providers', (select count(*) from catalogue.providers p where p.provider_type_id = t.id and p.publication_status = 'published' and p.lifecycle_status = 'active')) order by t.name)
                           from ref.provider_types t where t.status = 'active'),
    'university_groups', (select jsonb_agg(jsonb_build_object('code', replace(gic.code,'au_',''), 'name', gic.name,
                           'members', (select count(*) from catalogue.provider_collection_memberships gm where gm.collection_id=gic.id and gm.status='active')))
                          from ref.institution_collections gic where gic.collection_type='university_group' and gic.status='active'),
    'ranking_systems', (select jsonb_agg(jsonb_build_object('code', s.code, 'name', s.ranking_name, 'publisher', s.publisher_name,
                         'editions', (select jsonb_agg(e.edition_year order by e.edition_year desc) from ranking.editions e where e.system_id=s.id and e.status='accepted'),
                         'terms_status', security.website_terms_status_v1('rankings'))) from ranking.systems s where exists (select 1 from ranking.editions e where e.system_id=s.id and e.status='accepted')),
    'scholarship_amount_types', jsonb_build_array('percentage_tuition','fixed_amount','full_tuition'),
    'scholarship_study_stages', jsonb_build_array('commencing','current'),
    'scholarship_student_types', jsonb_build_array('international','domestic','both'),
    'course_sorts', jsonb_build_array('relevance','title_asc','tuition_annual_asc','tuition_annual_desc','duration_asc','updated_asc'),
    'provider_sorts', jsonb_build_array('name_asc','qs_rank_asc','the_rank_asc','course_count_desc'),
    'generated_at', now())
$function$;

revoke execute on function security.au_state_from_postcode_v1(text) from public, anon, authenticated;
select security.campus_regional_class_refresh_v1();
select security.website_reference_cache_refresh_v1();
insert into search.refresh_requests(requested_by) values ('CF-247 15 Oct 2026: campus metro areas corrected for two campuses');

do $post$
declare v_expected jsonb := '{"security.campus_regional_class_refresh_v1()": "87893742e8b8a01b0a90fb22466a2671", "api.website_v2_reference_build()": "e33efde1d2b4c7cf5befb7a8ebe16021"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'reference city metro post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;

do $post2$
begin
  if exists (select 1 from jsonb_array_elements(public.website_v2_reference()->'countries') k, jsonb_array_elements(k->'cities') c where c->>'city' = 'Sydney' and c->>'metro_area' <> 'Sydney') then
    raise exception 'reference post-check: Sydney still listed under another metro area';
  end if;
end $post2$;
do $dry$ begin
  raise exception 'DRYRUN {"sydney": %, "fixed": %, "mismatch_left": %}',
    (select jsonb_agg(c) from jsonb_array_elements(public.website_v2_reference()->'countries') k, jsonb_array_elements(k->'cities') c where c->>'city' in ('Sydney','Springvale','Kensington')),
    (select jsonb_agg(jsonb_build_object('campus', k.name, 'state', rc.state_code, 'metro', rc.metro_area)) from catalogue.campuses k join pipeline.campus_regional_class rc on rc.campus_id=k.id where k.name ilike 'BBI@Sydney%' or k.name ilike '10 Blissington%'),
    (select count(*) from jsonb_array_elements(public.website_v2_reference()->'countries') k, jsonb_array_elements(k->'cities') c where c->>'metro_area' is not null and c->>'metro_area' <> c->>'city' and c->>'city' in ('Sydney','Melbourne','Brisbane','Perth','Adelaide','Canberra','Hobart','Darwin'));
end $dry$;
