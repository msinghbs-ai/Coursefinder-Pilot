CREATE OR REPLACE FUNCTION api.website_v2_scholarship_item(p_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'scholarship', 'catalogue', 'search', 'ref', 'security', 'api'
AS $function$
  with s as (select * from scholarship.scholarships where id = p_id),
  p as (select pr.* from catalogue.providers pr join s on s.provider_id = pr.id),
  cr as (select c.* from scholarship.criteria c join s on c.scholarship_id = s.id where coalesce(c.status,'active') not in ('rejected','superseded','withdrawn')),
  st as (select case when bool_or('international' = any(value_codes)) and bool_or('domestic' = any(value_codes)) then 'both'
                     when bool_or('international' = any(value_codes)) then 'international'
                     when bool_or('domestic' = any(value_codes)) then 'domestic' end v from cr where criterion_type='student_type'),
  acad as (select value_number, coalesce(value_json->>'scale', value_text) scale, human_text from cr where criterion_type='academic_minimum' order by confidence desc nulls last limit 1),
  nat as (select coalesce((select codes from scholarship.nationality_readings nr join s on nr.scholarship_id=s.id),
                          (select array_agg(distinct x) from cr, unnest(cr.value_codes) x where cr.criterion_type in ('nationality','citizenship_and_residency'))) codes),
  lv as (select array_agg(distinct d.study_level_code order by d.study_level_code) levels, count(distinct m.course_id) n
         from scholarship.course_mappings m join s on m.scholarship_id=s.id join search.course_documents d on d.course_id=m.course_id where m.mapping_state='mapped'),
  areas as (select array_agg(distinct d.primary_field_code order by d.primary_field_code) codes from scholarship.course_mappings m join s on m.scholarship_id=s.id join search.course_documents d on d.course_id=m.course_id where m.mapping_state='mapped' and d.primary_field_code is not null)
  select jsonb_build_object(
    'scholarship_id', s.stable_key,
    'name', s.name,
    'official_url', s.source_url, 'official_scholarship_url', s.source_url,
    'provider', jsonb_build_object('provider_id', p.stable_key, 'name', security.provider_presentable_name(coalesce(p.display_name,p.canonical_name)),
                  'cities', (select coalesce(jsonb_agg(distinct security.place_presentable(k.city)), '[]'::jsonb) from catalogue.campuses k where k.provider_id=p.id and nullif(btrim(k.city),'') is not null),
                  'country_code', (select trim(c.iso_alpha2::text) from ref.countries c where c.id=p.country_id),
                  'logo', api.website_v2_provider_logo(p.id)),
    'university_id', p.stable_key,
    'campus_city', coalesce(security.place_presentable(p.primary_city), (select security.place_presentable(min(k.city)) from catalogue.campuses k where k.provider_id=p.id and nullif(btrim(k.city),'') is not null)),
    'scholarship_type', s.scholarship_type, 'scholarship_type_bucket', s.scholarship_type,
    'amount_value', coalesce(s.award_amount, s.award_percentage),
    'amount_type', case when s.award_value_type='fixed_amount' then 'fixed_amount'
                        when s.award_value_type='percentage' and s.award_percentage >= 100 then 'full_tuition'
                        when s.award_value_type='percentage' then 'percentage_tuition' end,
    'amount_type_detail', s.award_value_type,
    'amount_currency', s.award_currency_code,
    'amount_is_maximum', coalesce(s.award_value_is_maximum,false),
    'amount_note', s.award_value_text,
    'scholarship_percentage', s.award_percentage,
    'value_classification', case when s.award_value_type='percentage' and s.award_percentage >= 100 then 'full_tuition'
                                 when s.award_value_type='percentage' then 'partial_tuition'
                                 when s.award_value_type='fixed_amount' then 'fixed_amount' else 'not_stated' end,
    'application_open_date', s.application_open_date,
    'application_deadline', s.application_close_date, 'application_closing_date', s.application_close_date,
    'deadline_is_rolling', (coalesce(s.description,'') || ' ' || coalesce(s.award_value_text,'')) ~* '(rolling (basis|applications|intake|admission)|until (all )?(places|funds|positions) (are )?(filled|allocated)|open (all|throughout the) year|year[- ]round)',
    'current_status', case when s.application_close_date is null then 'check_provider'
                           when s.application_close_date < current_date then 'closed'
                           when s.application_open_date > current_date then 'opening_soon' else 'open' end,
    'study_levels', to_jsonb(coalesce((select levels from lv), '{}'::text[])), 'study_levels_list', to_jsonb(coalesce((select levels from lv), '{}'::text[])),
    'study_levels_source', case when (select n from lv) > 0 then 'linked_courses' end,
    'study_stages', coalesce((select jsonb_agg(distinct value_text) from cr where criterion_type='study_stage' and value_text is not null), '[]'::jsonb),
    'student_type', (select v from st),
    'study_load', (select string_agg(distinct value_text, ', ') from cr where criterion_type='study_load'),
    'study_area_codes', case when (select codes from areas) is not null then to_jsonb((select codes from areas)) end,
    'academic_minimum', (select jsonb_build_object('value', value_number, 'scale', scale, 'text', human_text) from acad),
    'min_academic_score', (select value_number from acad where upper(scale) in ('WAM','PERCENTAGE','%') and value_number between 0 and 100),
    'automatic_consideration', case when exists (select 1 from cr where criterion_type='application_method' and value_text='automatic') then true
                                    when s.application_required then false end,
    'citizenship_eligibility', to_jsonb((select codes from nat)), 'eligible_countries_list', to_jsonb((select codes from nat)),
    'gender', (select string_agg(distinct value_text, ', ') from cr where criterion_type='gender'),
    'age_min', (select min(value_number) from cr where criterion_type='minimum_age'),
    'age_max', null,
    'renewable', case when s.award_duration_basis in ('annual','annual_program_duration','program_duration','per_semester') then true
                      when s.award_duration_basis in ('one_off','first_year') then false end,
    'eligibility_summary', (select string_agg(human_text, ' ') from cr where criterion_type='published_eligibility_narrative'),
    'reference_code', (select i.identifier_value from scholarship.identifiers i where i.scholarship_id=s.id and i.scheme in ('study_australia_scholarship_id','dfat_award_scheme') order by i.is_primary desc limit 1),
    'course_count', coalesce((select n from lv), 0),
    'last_verified_date', s.updated_at::date,
    'publication_status', s.publication_status)
  from s, p
$function$
