-- CF-247 v2.15.239 (S1): Platform Admin decision 11 Oct 2026 "Published only, always". The website (Wix) and Zoho scholarship APIs
-- serve published, active scholarships only, whatever the caller asks for. Before this, website_v2_scholarships and the website
-- scholarship search returned every active record unless the caller sent published_only, and the Zoho lookup and search also
-- returned unpublished and inactive ones. md5-checked before and after. Nothing is dropped or deleted.
do $guard$
declare v_expected jsonb := jsonb_build_object('public.website_v2_scholarships(jsonb,integer,integer)', 'f0a9139a1bbfbe4a4e28eb4d9e35d31c', 'public.website_edge_scholarship_search_v1(jsonb,integer,integer)', '1cb75221bdbe043243d89242af388fef', 'public.website_v2_scholarship(text)', '4168bdab5d6f2a3024adebfd476d8118', 'api.website_v2_scholarship_item(uuid)', 'f30e2ba8bb604d2de77a9229774e9fad', 'api.zoho_scholarship_lookup_v1(text)', 'a7b69e4e03d639ecd8f5c0e284f7b5e8', 'api.zoho_scholarship_search_v1(text,text[],timestamp with time zone,integer,integer)', '1c1fa5c4cf652b28ad201b591cb8767f', 'api.zoho_sync_manifest_v1(timestamp with time zone)', '69a8ea24245da2dee64228492c400f8f');
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

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
      and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id=s.id)  -- v2.15.236: hidden providers' scholarships too
      and s.publication_status='published'  -- v2.15.239 (S1): published scholarships only, always
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
end $function$;

CREATE OR REPLACE FUNCTION public.website_edge_scholarship_search_v1(p_filters jsonb DEFAULT '{}'::jsonb, p_page integer DEFAULT 1, p_page_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'catalogue', 'ref', 'security', 'api'
AS $function$
declare
  f jsonb := coalesce(p_filters,'{}'::jsonb);
  v_page int := coalesce(p_page,1);
  v_size int := coalesce(p_page_size,20);
  v_kw text := nullif(btrim(coalesce(f->>'keyword','')),'');
  v_providers text[] := api.website_text_array(f->'provider_ids');
  v_cities text[] := (select array_agg(lower(x)) from unnest(api.website_text_array(coalesce(f->'cities',f->'city'))) x);
  v_levels text[] := api.website_text_array(f->'study_level_codes');
  v_types text[] := api.website_text_array(f->'amount_types');
  v_open boolean := coalesce((f->>'open_only')::boolean,false);
  v_published boolean := coalesce((f->>'published_only')::boolean,false);
  v_groups text[] := (select array_agg(lower(regexp_replace(btrim(x),'^au_','','i'))) from unnest(api.website_text_array(coalesce(f->'university_groups',f->'university_group'))) x);
  v_not_applied text[] := '{}';
  v_result jsonb;
begin
  if v_page < 1 then raise exception 'INVALID_INPUT: page must be >= 1' using errcode='22023'; end if;
  if v_size < 1 or v_size > 50 then raise exception 'INVALID_INPUT: page_size must be 1-50' using errcode='22023'; end if;
  if api.website_text_array(f->'study_area_codes') is not null then v_not_applied := array_append(v_not_applied,'study_area_codes'); end if;
  if f ? 'min_academic_score' then v_not_applied := array_append(v_not_applied,'min_academic_score'); end if;
  if f ? 'citizenship' then v_not_applied := array_append(v_not_applied,'citizenship'); end if;

  with base as (
    select s.*, pr.stable_key provider_key, security.provider_presentable_name(coalesce(nullif(pr.display_name,''), pr.canonical_name)) provider_name,
      case when s.award_value_type='percentage' and s.award_percentage >= 100 and coalesce(s.award_applies_to_fee_type,s.award_fee_basis)='tuition_fee' then 'full_tuition'
           when s.award_value_type='percentage' and coalesce(s.award_applies_to_fee_type,s.award_fee_basis)='tuition_fee' then 'percentage_tuition'
           when s.award_value_type='percentage' then 'percentage'
           when s.award_value_type='fixed_amount' then 'fixed_amount' end as amount_type,
      case when s.application_close_date is null then 'unknown'
           when s.application_close_date < current_date then 'closed' else 'open' end as deadline_status
    from scholarship.scholarships s
    left join catalogue.providers pr on pr.id = s.provider_id
    where s.lifecycle_status = 'active'
      and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id = s.id)
      and not exists (select 1 from security.layer4_search_blocked_providers b where b.provider_id = s.provider_id)
      and (v_kw is null or s.name ilike '%'||v_kw||'%' or pr.canonical_name ilike '%'||v_kw||'%' or pr.display_name ilike '%'||v_kw||'%'
           or exists (select 1 from scholarship.criteria c where c.scholarship_id=s.id and c.human_text ilike '%'||v_kw||'%'))
      and (v_providers is null or pr.stable_key = any(v_providers))
      and s.publication_status='published'  -- v2.15.239 (S1): published scholarships only, always
      and (v_groups is null or exists (select 1 from catalogue.provider_collection_memberships gm join ref.institution_collections gic on gic.id=gm.collection_id
            where gm.provider_id=s.provider_id and gm.status='active' and (gm.valid_to is null or gm.valid_to>=current_date)
              and gic.collection_type='university_group' and gic.status='active' and replace(gic.code,'au_','') = any(v_groups)))
      and (v_cities is null or exists (select 1 from catalogue.campuses k where k.provider_id = s.provider_id and lower(btrim(k.city)) = any(v_cities)))
      -- excluded only when a level restriction is stated and none matches
      and (v_levels is null or not exists (select 1 from scholarship.scopes sc where sc.scholarship_id=s.id and sc.study_level_id is not null and sc.include_exclude='include')
           or exists (select 1 from scholarship.scopes sc join ref.study_levels sl on sl.id=sc.study_level_id
                      where sc.scholarship_id=s.id and sc.include_exclude='include' and sl.code = any(v_levels)))
  ), filtered as (
    select * from base b
    where (not v_open or b.deadline_status <> 'closed')
      and (v_types is null or b.amount_type = any(v_types))
  ), counted as (select count(*) total from filtered),
  paged as (
    select * from filtered
    order by (deadline_status='open') desc, application_close_date nulls last, lower(name), stable_key
    limit v_size offset (v_page-1)*v_size
  )
  select jsonb_build_object(
    'contract_version','website-scholarship-search-v1',
    'total',(select total from counted),
    'page',v_page,'page_size',v_size,'sort','open_deadline_first',
    'filters_not_applied',to_jsonb(v_not_applied),
    'items',coalesce((select jsonb_agg(jsonb_build_object(
      'scholarship_id',p.stable_key,
      'reference_code',(select i.identifier_value from scholarship.identifiers i where i.scholarship_id=p.id and i.scheme='study_australia_scholarship_id' and i.status is distinct from 'retired' order by i.is_primary desc limit 1),
      'name',p.name,
      'provider',jsonb_build_object('provider_id',p.provider_key,'name',p.provider_name,'university_groups',security.provider_university_groups(p.provider_id)),
      'campus_city',null,
      'provider_cities',coalesce((select jsonb_agg(distinct k.city order by k.city) from catalogue.campuses k where k.provider_id=p.provider_id and nullif(btrim(k.city),'') is not null),'[]'::jsonb),
      'amount_type',p.amount_type,
      'amount_value',case p.amount_type when 'fixed_amount' then p.award_amount when 'full_tuition' then 100 when 'percentage_tuition' then p.award_percentage when 'percentage' then p.award_percentage end,
      'amount_currency',case when p.amount_type='fixed_amount' then p.award_currency_code end,
      'amount_note',p.award_value_text,
      'amount_is_maximum',p.award_value_is_maximum,
      'renewable',case when p.award_duration_basis in ('annual_program_duration','program_duration') then true end,
      'coverage_duration',p.award_duration_basis,
      'study_levels',null,
      'study_area_codes',null,
      'min_academic_score',null,
      'age_min',(select c.value_number from scholarship.criteria c where c.scholarship_id=p.id and c.criterion_type='minimum_age' and c.machine_evaluable limit 1),
      'age_max',null,
      'citizenship_eligibility',null,
      'eligibility_summary',(select left(c.human_text,1200) from scholarship.criteria c where c.scholarship_id=p.id and c.criterion_type='published_eligibility_narrative' limit 1),
      'application_open_date',p.application_open_date,
      'application_deadline',p.application_close_date,
      'deadline_status',p.deadline_status,
      'deadline_is_rolling',null,
      'official_url',coalesce((select i.identifier_value from scholarship.identifiers i where i.scholarship_id=p.id and i.scheme='first_party_detail_url' order by i.is_primary desc limit 1), p.source_url),
      'official_url_source',case when exists(select 1 from scholarship.identifiers i where i.scholarship_id=p.id and i.scheme='first_party_detail_url') then 'first_party' else 'study_australia' end,
      'academic_year',p.academic_year,
      'publication_status',p.publication_status,
      'freshness',jsonb_build_object('updated_at',p.updated_at)
    ) order by (p.deadline_status='open') desc, p.application_close_date nulls last, lower(p.name), p.stable_key) from paged p),'[]'::jsonb)
  ) into v_result;
  return v_result;
end $function$;

CREATE OR REPLACE FUNCTION public.website_v2_scholarship(p_scholarship_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'catalogue', 'search', 'security', 'api'
AS $function$
declare v_id uuid; v jsonb;
begin
  if nullif(btrim(coalesce(p_scholarship_id,'')),'') is null then raise exception 'INVALID_INPUT: scholarship_id required' using errcode='22023'; end if;
  select s.id into v_id from scholarship.scholarships s where s.stable_key = btrim(p_scholarship_id)
     and s.lifecycle_status = 'active' and s.publication_status = 'published'  -- v2.15.239 (S1): published scholarships only, always
     and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id = s.id) limit 1;  -- v2.15.236
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
end $function$;

CREATE OR REPLACE FUNCTION api.website_v2_scholarship_item(p_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'scholarship', 'catalogue', 'search', 'ref', 'security', 'api'
AS $function$
  with s as (select * from scholarship.scholarships where id = p_id and lifecycle_status = 'active' and publication_status = 'published'),  -- v2.15.239 (S1): published scholarships only, always
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
$function$;

CREATE OR REPLACE FUNCTION api.zoho_scholarship_lookup_v1(p_identifier text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'catalogue', 'api'
AS $function$
  with x as (
    select s.*, p.stable_key provider_stable_key, p.canonical_name provider_name
    from scholarship.scholarships s
    left join catalogue.providers p on p.id=s.provider_id
    where not exists (select 1 from security.layer4_search_blocked_scholarships cf_block where cf_block.scholarship_id=s.id)
      and lower(s.stable_key)=lower(btrim(p_identifier))
      and s.lifecycle_status='active' and s.publication_status='published'  -- v2.15.239 (S1): published scholarships only, always
    limit 1
  )
  select case when exists(select 1 from x) then jsonb_build_object(
    'contract_version','zoho-integration-v1',
    'resource','scholarship',
    'item',(select jsonb_build_object(
      'scholarship_id',stable_key,'name',name,
      'provider',case when provider_stable_key is null then null else jsonb_build_object('provider_id',provider_stable_key,'name',provider_name) end,
      'scholarship_type',scholarship_type,'description',description,'audience',audience,
      'award_value_text',award_value_text,'application_required',application_required,
      'application_open_date',application_open_date,'application_close_date',application_close_date,
      'academic_year',academic_year,'source_url',source_url,
      'lifecycle_status',lifecycle_status,'publication_status',publication_status,
      'freshness',jsonb_build_object('updated_at',updated_at)
    ) from x),
    'generated_at',now()
  ) else jsonb_build_object(
    'contract_version','zoho-integration-v1','resource','scholarship','error',
    jsonb_build_object('code','NOT_FOUND','message','Scholarship identifier not found')
  ) end;
$function$;

CREATE OR REPLACE FUNCTION api.zoho_scholarship_search_v1(p_query text DEFAULT NULL::text, p_provider_ids text[] DEFAULT NULL::text[], p_changed_since timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'catalogue', 'api'
AS $function$
  with base as (
    select s.*, p.stable_key provider_stable_key, p.canonical_name provider_name
    from scholarship.scholarships s
    left join catalogue.providers p on p.id=s.provider_id
    where not exists (select 1 from security.layer4_search_blocked_scholarships cf_block where cf_block.scholarship_id=s.id)
      and (p_query is null or btrim(p_query)='' or s.name ilike '%'||btrim(p_query)||'%' or s.stable_key ilike '%'||btrim(p_query)||'%')
      and (p_provider_ids is null or p.stable_key = any(p_provider_ids))
      and (p_changed_since is null or s.updated_at > p_changed_since)
      and s.lifecycle_status='active' and s.publication_status='published'  -- v2.15.239 (S1): published scholarships only, always
  ),
  page as (
    select * from base
    order by lower(name), stable_key
    limit greatest(1, least(coalesce(p_limit,20),50))
    offset greatest(coalesce(p_offset,0),0)
  )
  select jsonb_build_object(
    'contract_version','zoho-integration-v1',
    'resource','scholarships',
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'scholarship_id',stable_key,'name',name,
      'provider',case when provider_stable_key is null then null else jsonb_build_object('provider_id',provider_stable_key,'name',provider_name) end,
      'scholarship_type',scholarship_type,'audience',audience,'award_value_text',award_value_text,
      'application_required',application_required,'application_open_date',application_open_date,
      'application_close_date',application_close_date,'academic_year',academic_year,
      'source_url',source_url,'lifecycle_status',lifecycle_status,'publication_status',publication_status,
      'freshness',jsonb_build_object('updated_at',updated_at)
    ) order by lower(name), stable_key),'[]'::jsonb),
    'page',jsonb_build_object(
      'limit',greatest(1, least(coalesce(p_limit,20),50)),
      'offset',greatest(coalesce(p_offset,0),0),
      'total',(select count(*) from base)
    ),
    'ordering','name_asc,scholarship_id_asc',
    'generated_at',now()
  ) from page;
$function$;

CREATE OR REPLACE FUNCTION api.zoho_sync_manifest_v1(p_changed_since timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'scholarship', 'search', 'api'
AS $function$
  select jsonb_build_object(
    'contract_version','zoho-integration-v1',
    'boundary','server-side-pilot-only',
    'changed_since',p_changed_since,
    'providers',jsonb_build_object(
      'count',(select count(*) from catalogue.providers p where not exists (select 1 from security.layer4_search_blocked_providers cf_block where cf_block.provider_id=p.id) and (p_changed_since is null or p.updated_at > p_changed_since)),
      'max_updated_at',(select max(p.updated_at) from catalogue.providers p where not exists (select 1 from security.layer4_search_blocked_providers cf_block where cf_block.provider_id=p.id))
    ),
    'courses',jsonb_build_object(
      'count',(select count(*) from search.course_documents d where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id) and (p_changed_since is null or greatest(d.updated_at,d.source_updated_at,d.generated_at) > p_changed_since)),
      'max_updated_at',(select max(greatest(d.updated_at,d.source_updated_at,d.generated_at)) from search.course_documents d where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id))
    ),
    'scholarships',jsonb_build_object(
      'count',(select count(*) from scholarship.scholarships s where not exists (select 1 from security.layer4_search_blocked_scholarships cf_block where cf_block.scholarship_id=s.id) and s.lifecycle_status='active' and s.publication_status='published' and (p_changed_since is null or s.updated_at > p_changed_since)),
      'max_updated_at',(select max(s.updated_at) from scholarship.scholarships s where not exists (select 1 from security.layer4_search_blocked_scholarships cf_block where cf_block.scholarship_id=s.id) and s.lifecycle_status='active' and s.publication_status='published')
    ),
    'ordering',jsonb_build_object(
      'providers','name_asc,provider_id_asc',
      'courses','title_asc,course_id_asc',
      'scholarships','name_asc,scholarship_id_asc'
    ),
    'generated_at',now()
  );
$function$;

do $post$
declare v_expected jsonb := jsonb_build_object('public.website_v2_scholarships(jsonb,integer,integer)', 'b3a616d8ec31a86ffa3e770cf24db0af', 'public.website_edge_scholarship_search_v1(jsonb,integer,integer)', 'a97c1ab33ca8ec9b4d85570a29e78eb1', 'public.website_v2_scholarship(text)', '79131c22331c7439438177517bd1ba12', 'api.website_v2_scholarship_item(uuid)', '06dd99e2d2c3a4e559afbef04b4f9f3c', 'api.zoho_scholarship_lookup_v1(text)', 'bcae4e7d9f3310c21b6a7c37830f7c14', 'api.zoho_scholarship_search_v1(text,text[],timestamp with time zone,integer,integer)', '6da1f3a3d060c8c565df5b86414c8c58', 'api.zoho_sync_manifest_v1(timestamp with time zone)', 'ca03f289970122428561fe8c32ee35e2');
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'CF-247 v2.15.239 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
