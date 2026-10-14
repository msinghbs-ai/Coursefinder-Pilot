create or replace function api.website_v2_scholarship_item(p_id uuid)
returns jsonb language sql stable set search_path to 'pg_catalog','scholarship','catalogue','search','ref','security','api' as $$
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
  areas as (select array_agg(distinct f.code) codes from scholarship.scopes sc join s on sc.scholarship_id=s.id join ref.fields_of_study f on f.id=sc.field_id where sc.include_exclude is distinct from 'exclude')
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
$$;
revoke all on function api.website_v2_scholarship_item(uuid) from public;

create or replace function public.website_v2_scholarships(p_filters jsonb default '{}'::jsonb, p_page integer default 1, p_page_size integer default 20)
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','scholarship','catalogue','search','ref','pipeline','security','api' as $$
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
      and (v_areas is null or exists (select 1 from scholarship.scopes sc join ref.fields_of_study fo on fo.id=sc.field_id where sc.scholarship_id=s.id and fo.code = any(v_areas)))
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
end $$;

create or replace function public.website_v2_scholarship(p_scholarship_id text)
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','scholarship','catalogue','search','security','api' as $$
declare v_id uuid; v jsonb;
begin
  if nullif(btrim(coalesce(p_scholarship_id,'')),'') is null then raise exception 'INVALID_INPUT: scholarship_id required' using errcode='22023'; end if;
  select s.id into v_id from scholarship.scholarships s where s.stable_key = btrim(p_scholarship_id) limit 1;
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
end $$;

revoke all on function public.website_v2_scholarships(jsonb, integer, integer) from public, anon, authenticated;
grant execute on function public.website_v2_scholarships(jsonb, integer, integer) to service_role;
revoke all on function public.website_v2_scholarship(text) from public, anon, authenticated;
grant execute on function public.website_v2_scholarship(text) to service_role;
