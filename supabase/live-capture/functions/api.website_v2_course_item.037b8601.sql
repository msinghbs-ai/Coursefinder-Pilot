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
end $function$
