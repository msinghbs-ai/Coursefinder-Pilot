-- Consumer API change approved: Platform Admin, 12 Nov 2026 20:19 AEDT ("proceed with 2 then decided best option and continue": the additive scholarship fields and R24 recommended at 20:00); release held under the standing rule of 12 Nov 2026 11:50 until the developer communication is issued and the release is authorised (gate below)
-- CF-247 F-SCH developer field contract step 2: Website API v2 scholarship fields, ADDITIVE only. Every existing key, value, filter, sort and page
-- stays exactly as it is; new keys are added beside them on api.website_v2_scholarship_item (so on `scholarships` items and on `scholarship`).
--   description                   the scholarship description (until now only on `scholarship`)
--   award_type                    scholarship | bursary | tuition_waiver | fee_discount | research_funding | grant | stipend | other | null (not held)
--   sponsor, programme, award_code  the funding body when it is not the provider, the umbrella programme, the provider's award code (null = not held)
--   benefits[]                    {type, amount, currency, percentage, is_maximum}: every verified benefit (tuition, stipend, living allowance,
--                                 accommodation, travel, health cover, fixed amount, in kind, other)
--   application                   {method: separate_application | automatic_consideration | nomination | null, url, rolling}
--   award_duration                {value, unit}: how long the award runs (null = not held)
--   academic_year                 the funding round's academic year (null = not held)
--   nationality_eligibility_status  R24: restricted | unrestricted | under_review | unknown. An empty country list is never unrestricted.
--   excluded_nationality_codes[]  countries the source names as not eligible
--   nationality_regions[]         regions as the source names them (never expanded into countries)
-- Null means not held. The data is written by the detail fill (security.scholarship_detail_apply_v1, scholarship.award_details, scholarship.coverage,
-- scholarship.application_windows, scholarship.criteria) from passages checked against the official evidence.
-- Supersedes the R24 part of the unmerged draft on branch cf247-devapi-r23-r24 (migration 20261106100000), whose md5 guards predate today.
-- Replaces: api.website_v2_scholarship_item(uuid) (same name and signature; one md5-guarded edit). Retires: nothing.

-- 0. release gate: refuse until the release is authorised (pipeline setting api.v2_scholarship_fields_released = 1, recorded with the developer
--    communication; fixed: governance flag, not an operational value)
do $gate$
begin
  if coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'api.v2_scholarship_fields_released'), 0) < 1 then
    raise exception 'Website API v2 scholarship fields: release not authorised (api.v2_scholarship_fields_released); not applied'
      using hint = 'Issue the developer communication and record the release authorisation before applying.';
  end if;
end $gate$;

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_n('api.website_v2_scholarship_item(uuid)', 'd1792cc7161101ce8c22abad70ecbd36', array[
  array[$o$    'publication_status', s.publication_status)
  from s, p$o$,
        $n$    'publication_status', s.publication_status)
  -- 20261113069000 (CF-247 F-SCH developer field contract): additive fields; null means not held
  || jsonb_build_object(
    'description', s.description,
    'award_type', (select ad.award_type from scholarship.award_details ad where ad.scholarship_id = s.id),
    'sponsor', (select ad.sponsor from scholarship.award_details ad where ad.scholarship_id = s.id),
    'programme', (select ad.programme from scholarship.award_details ad where ad.scholarship_id = s.id),
    'award_code', (select ad.award_code from scholarship.award_details ad where ad.scholarship_id = s.id),
    'benefits', coalesce((select jsonb_agg(jsonb_build_object('type', cv.coverage_type, 'amount', cv.amount, 'currency', cv.currency_code, 'percentage', cv.percentage,
                                 'is_maximum', cv.notes like 'sch-extract-v3:% (maximum)%') order by cv.coverage_type, cv.id)
                          from scholarship.coverage cv where cv.scholarship_id = s.id and cv.notes like 'sch-extract-v3:%'), '[]'::jsonb),
    'application', jsonb_build_object(
        'method', (select w.application_method from scholarship.application_windows w where w.scholarship_id = s.id and w.application_method is not null order by w.created_at desc limit 1),
        'url', (select w.application_url from scholarship.application_windows w where w.scholarship_id = s.id and w.application_url is not null order by w.created_at desc limit 1),
        'rolling', (select ad.application_rolling from scholarship.award_details ad where ad.scholarship_id = s.id)),
    'award_duration', (select jsonb_build_object('value', cv.duration_value, 'unit', cv.duration_unit) from scholarship.coverage cv
                        where cv.scholarship_id = s.id and cv.coverage_type = 'award_duration' and cv.duration_unit is not null order by cv.id desc limit 1),
    'academic_year', s.academic_year,
    'nationality_eligibility_status', case
       when exists (select 1 from pipeline.layer4_review_items li where li.entity_id = s.id and li.status = 'pending'
                     and li.field_code in ('nationalities', 'nationality', 'citizenship_eligibility')) then 'under_review'
       when cardinality(coalesce((select codes from nat), '{}'::text[])) > 0
         or exists (select 1 from cr where cr.criterion_type = 'nationality' and (jsonb_array_length(coalesce(cr.value_json->'excluded', '[]')) > 0 or jsonb_array_length(coalesce(cr.value_json->'regions', '[]')) > 0)) then 'restricted'
       when exists (select 1 from scholarship.nationality_readings nr where nr.scholarship_id = s.id and nr.phrases ? 'ANY') then 'unrestricted'
       else 'unknown' end,
    'excluded_nationality_codes', coalesce((select jsonb_agg(distinct x) from cr, jsonb_array_elements_text(coalesce(cr.value_json->'excluded', '[]')) x where cr.criterion_type = 'nationality'), '[]'::jsonb),
    'nationality_regions', coalesce((select jsonb_agg(distinct x) from cr, jsonb_array_elements_text(coalesce(cr.value_json->'regions', '[]')) x where cr.criterion_type = 'nationality'), '[]'::jsonb))
  from s, p$n$]
], array[1]);

-- the approved consumer change re-takes the consumer API baseline (Decision 266)
select security.consumer_api_rebaseline_v1('CF-247 F-SCH developer field contract (20261113069000): additive scholarship fields and R24; Platform Admin 12 Nov 2026 20:19; released under api.v2_scholarship_fields_released');
