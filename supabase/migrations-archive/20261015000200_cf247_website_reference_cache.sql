-- CF-247 (15 Oct 2026, preparing the developer pack): the reference action took 5.5-6.6 s and passed the API's 8 s statement limit under
-- load (HTTP 503 seen in the live check). It now returns a copy built every 15 minutes by the catalogued job website-reference-cache
-- (the same content; generated_at is when the copy was built). With no copy yet, it builds one live as before. Nothing dropped or deleted.

do $guard$
declare v_expected jsonb := '{"public.website_v2_reference()": "28ea2093f42a1886380ae444b6bf37dd"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

create table if not exists pipeline.website_reference_cache (
  id int primary key check (id = 1),
  payload jsonb not null,
  built_at timestamptz not null default now(),
  build_ms int);
alter table pipeline.website_reference_cache enable row level security;

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
                   from (select security.place_presentable(k.city) city, min(rc.metro_area) metro, count(distinct cc.course_id) n
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
revoke all on function api.website_v2_reference_build() from public, anon, authenticated;

CREATE OR REPLACE FUNCTION security.website_reference_cache_refresh_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t0 timestamptz := clock_timestamp(); v jsonb;
begin
  v := api.website_v2_reference_build();
  insert into pipeline.website_reference_cache(id, payload, built_at, build_ms)
  values (1, v, now(), round(extract(epoch from clock_timestamp() - t0) * 1000)::int)
  on conflict (id) do update set payload = excluded.payload, built_at = excluded.built_at, build_ms = excluded.build_ms;
  return jsonb_build_object('bytes', length(v::text), 'ms', round(extract(epoch from clock_timestamp() - t0) * 1000));
end $function$;
revoke all on function security.website_reference_cache_refresh_v1() from public, anon, authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('website-reference-cache', 'Search and API', 41, 'Website reference: build the copy',
        'Every 15 minutes: builds the website API reference (vocabularies with counts) so the reference action answers at once.', 6, false)
on conflict do nothing;
select cron.schedule('website-reference-cache', '2-59/15 * * * *', 'select security.website_reference_cache_refresh_v1()');

CREATE OR REPLACE FUNCTION public.website_v2_reference()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'search', 'ref', 'catalogue', 'scholarship', 'security', 'api'
AS $function$
  select coalesce((select c.payload - 'generated_at' || jsonb_build_object('generated_at', c.built_at) from pipeline.website_reference_cache c where c.id = 1),
                  api.website_v2_reference_build())  -- 15 Oct 2026: the copy built every 15 minutes (job website-reference-cache); live only when none
$function$;
select security.website_reference_cache_refresh_v1();

do $post$
declare v_expected jsonb := '{"public.website_v2_reference()": "4f3bc6dbfd1490ea2f56ff27cbdc30e9"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'reference cache post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;

do $$ begin
  if (select count(*) from pipeline.website_reference_cache) <> 1 then raise exception 'reference cache post-check: no copy built'; end if;
  if (public.website_v2_reference()->>'contract_version') is distinct from 'website-search-v2' then raise exception 'reference cache post-check: reference broken'; end if;
end $$;
