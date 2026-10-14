create or replace function public.website_v2_providers(p_filters jsonb default '{}'::jsonb, p_page integer default 1, p_page_size integer default 20, p_sort text default null)
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','search','catalogue','ref','pipeline','ranking','security','api' as $$
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
    from search.course_documents d group by d.provider_id
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
end $$;

create or replace function public.website_v2_provider_rankings(p_provider_id uuid)
returns jsonb language sql stable security definer set search_path to 'pg_catalog','ranking' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'system_code', s.code, 'system_name', s.ranking_name, 'publisher', s.publisher_name, 'edition_year', e.edition_year,
      'rank_display', o.rank_display, 'rank_low', coalesce(o.rank_low,o.rank_exact), 'rank_high', coalesce(o.rank_high,o.rank_exact), 'is_tied', coalesce(o.is_tied,false),
      'overall_score_display', o.overall_score_display,
      'indicators', (select coalesce(jsonb_agg(jsonb_build_object('code', io.indicator_code, 'label', io.indicator_label, 'value_display', io.value_display, 'rank_display', io.rank_display) order by io.indicator_code), '[]'::jsonb)
                     from ranking.indicator_observations io where io.observation_id=o.id),
      'methodology_url', e.methodology_url, 'source_url', coalesce(e.source_url, s.official_url),
      'attribution', s.publisher_name || ', ' || s.ranking_name || ' ' || e.edition_year,
      'terms_status', 'management_decision_pending')
    order by s.code, e.edition_year desc), '[]'::jsonb)
  from (select distinct on (o2.edition_id) o2.* from ranking.observation_provider_links l join ranking.observations o2 on o2.id=l.observation_id
        where l.provider_id=p_provider_id order by o2.edition_id, l.is_primary desc nulls last) o
  join ranking.editions e on e.id=o.edition_id and e.status='accepted' join ranking.systems s on s.id=e.system_id
$$;

create or replace function public.website_v2_provider(p_provider_id text)
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','search','catalogue','ref','security','api' as $$
declare v_pid uuid; v jsonb; v_outcomes_ok boolean;
begin
  if nullif(btrim(coalesce(p_provider_id,'')),'') is null then raise exception 'INVALID_INPUT: provider_id required' using errcode='22023'; end if;
  select p.id into v_pid from catalogue.providers p where lower(p.stable_key)=lower(btrim(p_provider_id)) limit 1;
  if v_pid is null then return jsonb_build_object('contract_version','website-search-v2','error',jsonb_build_object('code','NOT_FOUND')); end if;
  v := (public.website_v2_providers(jsonb_build_object('provider_ids', jsonb_build_array(btrim(p_provider_id))),1,1))->'items'->0;
  if v is null then return jsonb_build_object('contract_version','website-search-v2','error',jsonb_build_object('code','NOT_FOUND')); end if;
  select exists (select 1 from search.enrichment_gates g where g.projection_code='courses' and g.domain_code='provider_outcomes' and g.gate_status='approved') into v_outcomes_ok;
  v := v || jsonb_build_object(
    'description', (select p.description from catalogue.providers p where p.id=v_pid),
    'rankings', public.website_v2_provider_rankings(v_pid),
    'outcomes_state', case when v_outcomes_ok then 'admitted' else 'not_admitted' end,
    'outcomes', case when v_outcomes_ok then coalesce((select jsonb_agg(jsonb_build_object('survey', sv.code, 'metric_code', m.code, 'metric_name', m.name,
                   'study_level', o.source_cohort_code, 'value', o.metric_value, 'unit', m.unit, 'ci_low', o.confidence_low, 'ci_high', o.confidence_high,
                   'reference_year', o.collection_year_to, 'responses', o.response_count, 'grain', 'provider'))
                 from catalogue.provider_outcomes o join ref.outcome_metrics m on m.id=o.metric_id join ref.outcome_surveys sv on sv.id=o.survey_id
                 where o.provider_id=v_pid and o.external_study_area_id is null), '[]'::jsonb) else '[]'::jsonb end);
  return jsonb_build_object('contract_version','website-search-v2','item',v);
end $$;

create or replace function public.website_v2_rankings(p_filters jsonb default '{}'::jsonb, p_page integer default 1, p_page_size integer default 20)
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','ranking','catalogue','ref','search','security','api' as $$
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
end $$;

create or replace function public.website_v2_reference()
returns jsonb language sql stable security definer
set search_path to 'pg_catalog','search','ref','catalogue','scholarship','security','api' as $$
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
    'university_groups', (select jsonb_agg(jsonb_build_object('code', replace(gic.code,'au_',''), 'name', gic.name,
                           'members', (select count(*) from catalogue.provider_collection_memberships gm where gm.collection_id=gic.id and gm.status='active')))
                          from ref.institution_collections gic where gic.collection_type='university_group' and gic.status='active'),
    'ranking_systems', (select jsonb_agg(jsonb_build_object('code', s.code, 'name', s.ranking_name, 'publisher', s.publisher_name,
                         'editions', (select jsonb_agg(e.edition_year order by e.edition_year desc) from ranking.editions e where e.system_id=s.id and e.status='accepted'),
                         'terms_status', 'management_decision_pending')) from ranking.systems s where exists (select 1 from ranking.editions e where e.system_id=s.id and e.status='accepted')),
    'scholarship_amount_types', jsonb_build_array('percentage_tuition','fixed_amount','full_tuition'),
    'scholarship_study_stages', jsonb_build_array('commencing','current'),
    'scholarship_student_types', jsonb_build_array('international','domestic','both'),
    'course_sorts', jsonb_build_array('relevance','title_asc','tuition_annual_asc','tuition_annual_desc','duration_asc','updated_asc'),
    'provider_sorts', jsonb_build_array('name_asc','qs_rank_asc','the_rank_asc','course_count_desc'),
    'generated_at', now())
$$;

revoke all on function public.website_v2_providers(jsonb, integer, integer, text) from public, anon, authenticated;
grant execute on function public.website_v2_providers(jsonb, integer, integer, text) to service_role;
revoke all on function public.website_v2_provider_rankings(uuid) from public, anon, authenticated;
grant execute on function public.website_v2_provider_rankings(uuid) to service_role;
revoke all on function public.website_v2_provider(text) from public, anon, authenticated;
grant execute on function public.website_v2_provider(text) to service_role;
revoke all on function public.website_v2_rankings(jsonb, integer, integer) from public, anon, authenticated;
grant execute on function public.website_v2_rankings(jsonb, integer, integer) to service_role;
revoke all on function public.website_v2_reference() from public, anon, authenticated;
grant execute on function public.website_v2_reference() to service_role;
