CREATE OR REPLACE FUNCTION public.website_v2_scholarships(p_filters jsonb DEFAULT '{}'::jsonb, p_page integer DEFAULT 1, p_page_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'catalogue', 'search', 'ref', 'pipeline', 'security', 'api'
AS $function$
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
      and (v_areas is null or exists (select 1 from scholarship.course_mappings m join search.course_documents d on d.course_id=m.course_id where m.scholarship_id=s.id and m.mapping_state='mapped' and d.primary_field_code = any(v_areas)))
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
end $function$
