-- Consumer API change approved: PENDING (no approval): this restore needs a new, explicit Platform Admin G3 approval; complete this line with who, when and why, and only then move this file into supabase/migrations
-- DO NOT MERGE. DO NOT APPLY. HELD FORWARD-RESTORE MIGRATION for Website API v2 R23/R24 (prepared 9 Nov 2026, not part of the release).
-- It sits in supabase/held/, outside supabase/migrations/, so no release applies it and s57 does not see it. To use it after a future explicit approval:
-- complete line 1 (s57 rejects a line that says PENDING), move the file to supabase/migrations/ (version 20261109200000 or later, check it is free on
-- main and live), regenerate docs/platform/TEST-REGISTER.md, and release it as any consumer API change (G3).
--
-- What it does: returns the two consumer builders to the definitions live had before R23/R24 (5 Nov 2026), taken from the preserved live text in
-- tests/fixtures/website-api-v2-r23-r24/live/ (NOT the older supabase/live-capture file):
--   api.website_v2_provider_campuses(uuid)   698afad0bc236a314fb356632938c403 -> 57115d3b8ddbc40729ec04078ee15d41
--   api.website_v2_scholarship_item(uuid)    04532402307717c6dab17567551364e1 -> d1792cc7161101ce8c22abad70ecbd36
-- It refuses unless live equals the R23/R24 definitions (so it cannot run before R23/R24 is applied, twice, or over a later change), checks that nothing
-- else in the consumer API differs from the baseline, then re-takes the baseline last.
-- Effect when applied: campuses[] goes back to one item per city (merged), without campus_id, campus_name, course_count; scholarships lose
-- nationality_eligibility_status. That is a removal of keys the developers may by then rely on: a consumer-facing change that needs notice (guide
-- reissue, Wix and Zoho cover notes) as well as approval.
-- Replaces: api.website_v2_provider_campuses(uuid), api.website_v2_scholarship_item(uuid) (same names; md5-guarded replacement back to the 5 Nov 2026 definitions)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. No table, job, status or setting is created. No operational value is written into code.

-- 0. the live definitions must be exactly the R23/R24 ones (the md5s after migration 20261109160000); otherwise there is nothing to restore, or something
--    else has changed them, and this refuses
do $r$
begin
  if md5(pg_get_functiondef('api.website_v2_provider_campuses(uuid)'::regprocedure)) <> '698afad0bc236a314fb356632938c403'
     or md5(pg_get_functiondef('api.website_v2_scholarship_item(uuid)'::regprocedure)) <> '04532402307717c6dab17567551364e1' then
    raise exception 'CF-247 R23/R24 restore: live definitions are not the R23/R24 ones (698afad0, 04532402): not applied';
  end if;
end $r$;

create or replace function pg_temp.replace_once(p_sig text, p_before text, p_after text, p_def text) returns text language plpgsql as $f$
begin
  if md5(pg_get_functiondef(p_sig::regprocedure)) = p_after then return p_sig || ': already applied'; end if;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_before then
    raise exception 'live % differs from the definition this change replaces (md5 %)', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)); end if;
  execute p_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the replacement has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after; end if;
  return p_sig || ': applied';
end $f$;

-- 1. what the new code reads, and the consumer wrappers that embed it, are the live definitions this change was written and tested
--    against (live, 5 Nov 2026; none of them is changed here)
do $g$
declare r record;
begin
  for r in select * from (values
      ('security.place_presentable(text)', 'a7b720fc9b34203d0a23315376fd483a'),
      ('public.website_v2_providers(jsonb,integer,integer,text)', '73ba533ee2f4c20b840c4cf172c17912'),
      ('public.website_v2_scholarships(jsonb,integer,integer)', 'b3a616d8ec31a86ffa3e770cf24db0af'),
      ('public.website_v2_scholarship(text)', '79131c22331c7439438177517bd1ba12')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then
      raise exception 'live % differs from the definition this change was written against', r.sig; end if;
  end loop;
  for r in select * from (values
      ('security.layer4_search_blocked_courses', '35cdaa19a775ffaaf60fc2be302affec'),
      ('security.layer4_active_blocks', '300ac7ca5fe9b72b13e2647a861ea8c6'),
      ('security.provider_hidden_v1', 'c8e2c132cc6fa8a52dccdbb04317707b')) v(rel, m) loop
    if md5(pg_get_viewdef(r.rel::regclass)) <> r.m then
      raise exception 'live % differs from the definition this change was written against', r.rel; end if;
  end loop;
end $g$;

-- 2. restore the two builders (md5-guarded: from the R23/R24 definition to the preserved pre-R23/R24 definition)
select pg_temp.replace_once('api.website_v2_provider_campuses(uuid)', '698afad0bc236a314fb356632938c403', '57115d3b8ddbc40729ec04078ee15d41', $def$
CREATE OR REPLACE FUNCTION api.website_v2_provider_campuses(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'catalogue', 'ref', 'pipeline', 'security'
AS $function$
  select coalesce(jsonb_agg(distinct jsonb_build_object('city', security.place_presentable(k.city), 'postcode', k.postcode, 'subdivision_code', s.code,
           'metro_area', rc.metro_area, 'regional_category', rc.category, 'regional_category_name', rc.category_name)), '[]'::jsonb)
  from catalogue.campuses k
  left join ref.subdivisions s on s.id = k.subdivision_id
  left join pipeline.campus_regional_class rc on rc.campus_id = k.id
  where k.provider_id = p_provider_id and nullif(btrim(k.city),'') is not null and coalesce(k.status,'active') <> 'inactive'
$function$
$def$);
select pg_temp.replace_once('api.website_v2_scholarship_item(uuid)', '04532402307717c6dab17567551364e1', 'd1792cc7161101ce8c22abad70ecbd36', $def$
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
    'reference_code', null::text, -- 11 Oct 2026: no national register codes (Study Australia retired)
    'course_count', coalesce((select n from lv), 0),
    'last_verified_date', s.updated_at::date,
    'publication_status', s.publication_status)
  from s, p
$function$
$def$);

-- 3. G3 baseline. Re-taken last, after refusing if any other consumer API function differs from the baseline
create or replace function pg_temp.consumer_drift_v1() returns jsonb language sql stable set search_path = '' as $f$
  select coalesce(jsonb_agg(x.name order by x.name), '[]'::jsonb)
    from (select f.name from security.consumer_api_functions_v1() f
            left join pipeline.consumer_api_baseline b on b.kind = 'function' and b.name = f.name
           where b.name is null or b.md5 is distinct from pg_catalog.md5(pg_catalog.pg_get_functiondef(f.oid))
          union
          select b.name from pipeline.consumer_api_baseline b
           where b.kind = 'function' and not exists (select 1 from security.consumer_api_functions_v1() f where f.name = b.name)) x
$f$;
do $b$
declare v_other jsonb;
begin
  select coalesce(jsonb_agg(d), '[]'::jsonb) into v_other
    from jsonb_array_elements_text(pg_temp.consumer_drift_v1()) d
   where d not in ('api.website_v2_provider_campuses(uuid)', 'api.website_v2_scholarship_item(uuid)');
  if jsonb_array_length(v_other) > 0 then
    raise exception 'CF-247 R23/R24 restore: consumer API objects other than the two restored functions differ from the baseline (%): not re-baselined', left(v_other::text, 600);
  end if;
end $b$;

select security.consumer_api_rebaseline_v1('R23/R24 restore: the two builders returned to their 5 Nov 2026 definitions (57115d3b, d1792cc7); approval line on the first line of this migration');

-- 4. final check: live equals the restored definitions
do $c$
begin
  if md5(pg_get_functiondef('api.website_v2_provider_campuses(uuid)'::regprocedure)) <> '57115d3b8ddbc40729ec04078ee15d41'
     or md5(pg_get_functiondef('api.website_v2_scholarship_item(uuid)'::regprocedure)) <> 'd1792cc7161101ce8c22abad70ecbd36' then
    raise exception 'CF-247 R23/R24 restore: live does not equal the restored definitions after the restore';
  end if;
end $c$;
