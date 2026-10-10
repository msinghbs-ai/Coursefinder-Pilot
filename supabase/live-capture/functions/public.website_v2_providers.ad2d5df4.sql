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
end $function$
