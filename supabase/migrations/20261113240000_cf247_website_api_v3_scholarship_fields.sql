-- CF-247 Website API v3: scholarship detail fields (F-SCH developer field contract, Platform Admin 12 Nov 2026 20:19), built in v3 only.
-- Platform Admin 12 Nov 2026 22:37: "Fix pr 1077 decide to merge it on v3". Decision 277: new consumer fields go into Website API v3; v2 is frozen.
-- This is the v3 home of the unmerged v2 draft Pilot #1077 (migration 20261113069000, never applied), which is closed unmerged.
-- Scholarship items (scholarships, scholarship, sync scholarship items) gain, beside every v2 key and the R24 status already in v3:
--   description                   the scholarship description (v2 has it on `scholarship` only; the same stored value)
--   award_type                    scholarship | bursary | tuition_waiver | fee_discount | research_funding | grant | stipend | other | null
--   sponsor, programme, award_code  the funding body when it is not the provider, the umbrella programme, the provider's award code
--   benefits[]                    {type, amount, currency, percentage, is_maximum}: every verified benefit
--   application                   {method: separate_application | automatic_consideration | nomination | null, url, rolling}
--   award_duration                {value, unit}: how long the award runs
--   academic_year                 the funding round's academic year
--   excluded_nationality_codes[]  countries the source names as not eligible
--   nationality_regions[]         regions as the source names them (never expanded into countries)
-- Null (or an empty list) means not held. The expressions are the ones of the #1077 draft, unchanged. nationality_eligibility_status keeps the
-- R24 rule already live in v3 (migration 20261113190000); it is not redefined here.
-- v2 is not touched: api.website_v2_scholarship_item and every other consumer object is only read (G3, s57).
-- Replaces: public.website_v3_scholarship_item(jsonb) (same name and signature; md5-guarded against the WP-1.2 definition). Supersedes the unmerged
--   v2 draft on branch cf247-fsch-api-fields (Pilot #1077).
-- Retires: nothing.

do $guard$
begin
  if md5(pg_get_functiondef('public.website_v3_scholarship_item(jsonb)'::regprocedure)) <> 'd6df05bd54b5fef9b4e508893470ba75' then
    raise exception 'live public.website_v3_scholarship_item(jsonb) differs from the WP-1.2 definition this change replaces (md5 %)',
      md5(pg_get_functiondef('public.website_v3_scholarship_item(jsonb)'::regprocedure));
  end if;
end $guard$;

create or replace function public.website_v3_scholarship_item(p_item jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_id uuid; v_status text; v_more jsonb;
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' or not (p_item ? 'scholarship_id') then return p_item; end if;
  select s.id into v_id from scholarship.scholarships s where s.stable_key = p_item->>'scholarship_id';
  if v_id is null then return p_item; end if;
  v_status := case
    when exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'scholarship' and r.entity_id = v_id and r.status = 'pending'
                   and r.field_code in ('nationalities', 'nationality', 'citizenship_eligibility', 'audience', 'student_type'))
      or exists (select 1 from pipeline.scholarship_ai_reviews a where a.scholarship_id = v_id and a.status = 'pending' and a.reason ~* 'who it is for')
      then 'under_review'
    when (jsonb_typeof(p_item->'citizenship_eligibility') = 'array' and jsonb_array_length(p_item->'citizenship_eligibility') > 0)
      or p_item->>'student_type' = 'domestic'
      or exists (select 1 from scholarship.criteria c where c.scholarship_id = v_id and coalesce(c.status, 'active') not in ('rejected', 'superseded', 'withdrawn')
                   and c.criterion_type in ('nationality', 'citizenship_and_residency') and cardinality(c.value_codes) > 0)
      then 'restricted'
    when exists (select 1 from scholarship.nationality_readings nr where nr.scholarship_id = v_id and cardinality(nr.codes) = 0 and nr.phrases ? 'ANY')
      then 'unrestricted'
    else 'unknown' end;
  -- F-SCH developer field contract: one read of each source per scholarship; null means not held
  with cr as (
    select c.value_json from scholarship.criteria c
     where c.scholarship_id = v_id and coalesce(c.status, 'active') not in ('rejected', 'superseded', 'withdrawn') and c.criterion_type = 'nationality'),
  ad as (select d.award_type, d.sponsor, d.programme, d.award_code, d.application_rolling from scholarship.award_details d where d.scholarship_id = v_id)
  select jsonb_build_object(
    'description', (select s.description from scholarship.scholarships s where s.id = v_id),
    'award_type', (select ad.award_type from ad),
    'sponsor', (select ad.sponsor from ad),
    'programme', (select ad.programme from ad),
    'award_code', (select ad.award_code from ad),
    'benefits', coalesce((select jsonb_agg(jsonb_build_object('type', cv.coverage_type, 'amount', cv.amount, 'currency', cv.currency_code, 'percentage', cv.percentage,
                                 'is_maximum', cv.notes like 'sch-extract-v3:% (maximum)%') order by cv.coverage_type, cv.id)
                          from scholarship.coverage cv where cv.scholarship_id = v_id and cv.notes like 'sch-extract-v3:%'), '[]'::jsonb),
    'application', jsonb_build_object(
        'method', (select w.application_method from scholarship.application_windows w where w.scholarship_id = v_id and w.application_method is not null order by w.created_at desc limit 1),
        'url', (select w.application_url from scholarship.application_windows w where w.scholarship_id = v_id and w.application_url is not null order by w.created_at desc limit 1),
        'rolling', (select ad.application_rolling from ad)),
    'award_duration', (select jsonb_build_object('value', cv.duration_value, 'unit', cv.duration_unit) from scholarship.coverage cv
                        where cv.scholarship_id = v_id and cv.coverage_type = 'award_duration' and cv.duration_unit is not null order by cv.id desc limit 1),
    'academic_year', (select s.academic_year from scholarship.scholarships s where s.id = v_id),
    'excluded_nationality_codes', coalesce((select jsonb_agg(distinct x) from cr, jsonb_array_elements_text(coalesce(cr.value_json->'excluded', '[]'::jsonb)) x), '[]'::jsonb),
    'nationality_regions', coalesce((select jsonb_agg(distinct x) from cr, jsonb_array_elements_text(coalesce(cr.value_json->'regions', '[]'::jsonb)) x), '[]'::jsonb))
    into v_more;
  -- the v2 keys win: a key v2 already returns (description on `scholarship`) is never replaced
  return v_more || p_item || jsonb_build_object('nationality_eligibility_status', v_status);
end $$;
comment on function public.website_v3_scholarship_item(jsonb) is
  'Website API v3: a v2 scholarship item with nationality_eligibility_status (R24) and the F-SCH detail fields (description, award_type, sponsor, programme, award_code, benefits, application, award_duration, academic_year, excluded_nationality_codes, nationality_regions); v2 keys unchanged.';
