CREATE OR REPLACE FUNCTION public.website_v2_course_search(p_filters jsonb DEFAULT '{}'::jsonb, p_page integer DEFAULT 1, p_page_size integer DEFAULT 20, p_sort text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'search', 'catalogue', 'ref', 'pipeline', 'security', 'api'
AS $function$
declare
  f jsonb := coalesce(p_filters,'{}'::jsonb);
  v_page int := coalesce(p_page,1);
  v_size int := coalesce(p_page_size,20);
  v_kw text := nullif(btrim(coalesce(f->>'keyword','')),'');
  v_q tsquery;
  v_countries text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(coalesce(f->'country_codes',f->'country_code'))) x);
  v_areas text[] := api.website_text_array(f->'study_area_codes');
  v_levels text[] := api.website_text_array(f->'study_level_codes');
  v_subdivs text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(f->'subdivision_codes')) x);
  v_cities text[] := (select array_agg(lower(x)) from unnest(api.website_text_array(coalesce(f->'cities',f->'city'))) x);
  v_postcodes text[] := api.website_text_array(f->'postcodes');
  v_regional int[] := (select array_agg(x::int) from unnest(api.website_text_array(f->'regional_categories')) x where x ~ '^[1-3]$');
  v_providers text[] := api.website_text_array(f->'provider_ids');
  v_groups text[] := (select array_agg(lower(regexp_replace(btrim(x),'^au_','','i'))) from unnest(api.website_text_array(coalesce(f->'university_groups',f->'university_group'))) x);
  v_modes text[] := api.website_text_array(f->'delivery_modes');
  v_months int[] := (select array_agg(x::int) from unnest(api.website_text_array(f->'intake_months')) x where x ~ '^([1-9]|1[0-2])$');
  v_tests text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(f->'english_test_codes')) x);
  v_score_max numeric := nullif(f->>'english_score_max','')::numeric;
  v_min numeric := nullif(f->>'tuition_annual_min','')::numeric;
  v_max numeric := nullif(f->>'tuition_annual_max','')::numeric;
  v_changed timestamptz := nullif(f->>'changed_since','')::timestamptz;
  v_sort text := coalesce(nullif(p_sort,''), case when nullif(btrim(coalesce(f->>'keyword','')),'') is not null then 'relevance' else 'title_asc' end);
  v_known text[] := array['keyword','country_codes','country_code','study_area_codes','study_level_codes','subdivision_codes','cities','city','postcodes','regional_categories',
                          'provider_ids','university_groups','university_group','delivery_modes','intake_months','english_test_codes','english_score_max',
                          'tuition_annual_min','tuition_annual_max','has_intake','has_english','has_official_url','has_scholarship','has_tuition','changed_since'];
  v_not_applied jsonb;
  v_total bigint; v_ids uuid[];
  v_need_fee boolean;
begin
  if v_page < 1 then raise exception 'INVALID_INPUT: page must be >= 1' using errcode='22023'; end if;
  if v_size < 1 or v_size > 50 then raise exception 'INVALID_INPUT: page_size must be 1-50' using errcode='22023'; end if;
  if v_sort not in ('relevance','title_asc','tuition_annual_asc','tuition_annual_desc','duration_asc','updated_asc') then raise exception 'INVALID_INPUT: unknown sort' using errcode='22023'; end if;
  if v_score_max is not null and coalesce(cardinality(v_tests),0) <> 1 then raise exception 'INVALID_INPUT: english_score_max needs exactly one english_test_codes value' using errcode='22023'; end if;
  if v_kw is not null then v_q := websearch_to_tsquery('english', v_kw); end if;
  v_need_fee := (v_min is not null or v_max is not null or coalesce((f->>'has_tuition')::boolean,false) or v_sort in ('tuition_annual_asc','tuition_annual_desc'));
  select coalesce(jsonb_agg(k),'[]'::jsonb) into v_not_applied from jsonb_object_keys(f) k where k <> all(v_known);

  with base as (
    select d.course_id, d.course_title, d.course_stable_key, d.updated_at, d.provider_name,
      case when not v_need_fee then null
           when pt.amt is not null then
             case when pt.bas ~* 'total|course' and pt.bas !~* 'annual' then case when w.wk >= 52 then round(pt.amt / (w.wk/52.0)) end
                  when pt.bas ~* 'session|semester|trimester|unit|credit' then null
                  when pt.bas ~* 'indicative|annual|per.?year|yearly' then pt.amt end
           when d.regulatory_tuition_amount >= 1000 and w.wk >= 52 then round(d.regulatory_tuition_amount / (w.wk/52.0)) end ann,
      case when v_need_fee then (pt.amt is not null or coalesce(d.regulatory_tuition_amount,0) >= 1000) end has_fee,
      w.wk * 12.0 / 52 dur_months,
      case when v_kw is null then 0 else
        ts_rank(d.search_tsv, v_q) + case when d.course_title ilike '%'||v_kw||'%' then 1 else 0 end
          + case when d.course_title ilike v_kw||'%' then 0.5 else 0 end + case when lower(d.course_code) = lower(v_kw) then 2 else 0 end end rel
    from search.course_documents d
    left join catalogue.courses c on c.id = d.course_id
    cross join lateral (select case lower(coalesce(c.duration_unit,'')) when 'weeks' then c.duration_value when 'months' then c.duration_value*52/12.0 when 'years' then c.duration_value*52 end wk) w
    left join lateral (select (o->>'amount')::numeric amt, o->>'basis' bas
                       from jsonb_array_elements(coalesce(d.provider_tuition_options,'[]'::jsonb)) o
                       where (o->>'amount') ~ '^[0-9]+(\.[0-9]+)?$' and (o->>'amount')::numeric >= 1000
                       order by nullif(o->>'fee_year','')::int desc nulls last limit 1) pt on v_need_fee
    where not exists (select 1 from security.layer4_search_blocked_courses b where b.course_id = d.course_id)
      and (v_kw is null or d.search_tsv @@ v_q or d.course_title ilike '%'||v_kw||'%' or d.provider_name ilike '%'||v_kw||'%'
           or lower(d.course_code) = lower(v_kw) or lower(d.course_stable_key) = lower(v_kw))
      and (v_countries is null or d.country_code = any(v_countries))
      and (v_areas is null or d.primary_field_code = any(v_areas))
      and (v_levels is null or d.study_level_code = any(v_levels))
      and (v_subdivs is null or d.subdivision_codes && v_subdivs)
      and (v_providers is null or d.provider_stable_key = any(v_providers))
      and (v_groups is null or exists (select 1 from catalogue.provider_collection_memberships gm join ref.institution_collections gic on gic.id=gm.collection_id
            where gm.provider_id=d.provider_id and gm.status='active' and (gm.valid_to is null or gm.valid_to>=current_date)
              and gic.collection_type='university_group' and gic.status='active' and replace(gic.code,'au_','') = any(v_groups)))
      and (v_modes is null or d.delivery_modes && v_modes)
      and (not coalesce((f->>'has_intake')::boolean,false) or d.has_intake)
      and (not coalesce((f->>'has_english')::boolean,false) or d.has_english)
      and (not coalesce((f->>'has_official_url')::boolean,false) or d.has_link)
      and (not coalesce((f->>'has_scholarship')::boolean,false) or d.has_scholarship)
      and (v_changed is null or greatest(d.updated_at, d.source_updated_at) >= v_changed)
      and (v_months is null or exists (select 1 from jsonb_array_elements(coalesce(d.intake_options,'[]'::jsonb)) i where api.website_v2_label_month(i->>'label') = any(v_months)))
      and (v_tests is null or exists (select 1 from jsonb_array_elements(coalesce(d.english_requirement_options,'[]'::jsonb)) e
            where upper(e->>'test_code') = any(v_tests) and (v_score_max is null or ((e->>'overall_score') ~ '^[0-9]+(\.[0-9]+)?$' and (e->>'overall_score')::numeric <= v_score_max))))
      and ((v_cities is null and v_postcodes is null and v_regional is null) or exists (
            select 1 from catalogue.course_campuses cc join catalogue.campuses k on k.id = cc.campus_id left join pipeline.campus_regional_class rc on rc.campus_id = k.id
            where cc.course_id = d.course_id
              and (v_cities is null or lower(btrim(k.city)) = any(v_cities) or lower(rc.metro_area) = any(v_cities))
              and (v_postcodes is null or btrim(k.postcode) = any(v_postcodes))
              and (v_regional is null or rc.category = any(v_regional))))
  ), filtered as (
    select * from base b
    where (not coalesce((f->>'has_tuition')::boolean,false) or b.has_fee)
      and (v_min is null or b.ann >= v_min)
      and (v_max is null or b.ann <= v_max)
  ), ordered as (
    select course_id, count(*) over () total,
      row_number() over (order by
        case when v_sort='relevance' then rel end desc nulls last,
        case when v_sort='tuition_annual_asc' then ann end asc nulls last,
        case when v_sort='tuition_annual_desc' then ann end desc nulls last,
        case when v_sort='duration_asc' then dur_months end asc nulls last,
        case when v_sort='updated_asc' then updated_at end asc,
        lower(course_title), course_stable_key) rn
    from filtered
  )
  select coalesce(max(total),0), array_agg(course_id order by rn) filter (where rn > (v_page-1)*v_size and rn <= v_page*v_size)
    into v_total, v_ids from ordered;

  return jsonb_build_object(
    'contract_version','website-search-v2',
    'total', v_total, 'page', v_page, 'page_size', v_size, 'sort', v_sort,
    'filters_not_applied', v_not_applied,
    'items', coalesce((select jsonb_agg(api.website_v2_course_item(x.id, v_cities, v_postcodes) order by x.ord) from unnest(v_ids) with ordinality x(id, ord)), '[]'::jsonb));
end $function$
