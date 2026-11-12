-- CF-247 API v3, release 1 (Platform Admin 12 Nov 2026 21:12: "API v3 is getting prepared - any new field that needs programing or missing in v2
-- should defined, added to v3 and be ready for website and zoho"). Field definition: admin repo docs/integrations/api-v3/API-V3-FIELD-DEFINITION.md.
--
-- v3 is built BESIDE v2. Nothing the website or Zoho reads today changes: no v2 function, table or edge function is altered (G3). v3 is v2 plus
-- additions (nothing renamed or removed), served by the new edge functions website-api-v3 and zoho-api-v3 with the same keys, through one
-- dispatcher each: public.website_v3_call and public.zoho_v3_call. Each calls the unchanged v2 function for the action and adds the v3 fields.
--
-- Added in release 1 (data held):
--   scholarships  description, award_type, sponsor, programme, award_code, benefits[], application {method, url, rolling}, award_duration,
--                 academic_year, nationality_eligibility_status (R24), excluded_nationality_codes[], nationality_regions[]
--   providers     campuses[]: one item per campus with campus_id, campus_name, course_count (R23); logo_dark, brand_colour (R11, null: not held)
--   courses       intakes[].start_date_status (R28, closed list); description_excerpt (O26); defined and null until held: teaching_language (O17),
--                 study_load (O25), post_study_work (O27), field_of_study_codes (O28), recognition (O29), admission_tests (O18),
--                 entry_conditions (O19), application_route (O23)
--   reference     the closed lists of the new coded fields
-- Null means not held. Release gate: pipeline setting api.v3_released (0 = built, not released: the dispatchers refuse callers other than a
-- direct database session). Release is a separate, deliberate step with the developer communication (standing rule for Wix and Zoho changes).
-- Replaces: nothing (new schema api_v3 and new functions beside v2). Retires: nothing. Supersedes the unmerged v2 additions in Pilot #1077, #945
-- and #954 (closed unmerged once this is merged, so v2 stays frozen).

create schema if not exists api_v3;
comment on schema api_v3 is 'CF-247 API v3 (12 Nov 2026): the fields v3 adds to the unchanged v2 items. Read only by public.website_v3_call and public.zoho_v3_call.';
revoke all on schema api_v3 from public;

-- settings (G2)
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values
 ('pipeline', 'api.v3_released', 'API v3 released to the website and Zoho', '0 = built, not released: website-api-v3 and zoho-api-v3 refuse every key. 1 = released. Set to 1 only with the release authorisation and the developer communication.', 'number', '0'::jsonb, 0, 1, 'on (1) or off (0)', 803, 'Platform Admin 12 Nov 2026 21:12: API v3 prepared beside v2; release held until authorised', 'Website API', 'public.website_v3_call, public.zoho_v3_call'),
 ('pipeline', 'api.v3_description_excerpt_chars', 'API v3 course description excerpt, longest', 'description_excerpt on v3 course items is cut at the last full word within this many characters.', 'number', '280'::jsonb, 80, 1000, 'characters', 804, 'Platform Admin 12 Nov 2026 21:12: O26 description on search items', 'Website API', 'api_v3.course_extra')
on conflict (toolset_key, key) do nothing;

-- scholarships: the developer field contract fields (written by the F-SCH detail fill) and R24
create or replace function api_v3.scholarship_extra(p_id uuid) returns jsonb language sql stable
set search_path to 'pg_catalog' as $function$
  with s as (select * from scholarship.scholarships where id = p_id),
  ad as (select * from scholarship.award_details where scholarship_id = p_id),
  cr as (select c.* from scholarship.criteria c where c.scholarship_id = p_id and coalesce(c.status, 'active') not in ('rejected', 'superseded', 'withdrawn')),
  nat as (select coalesce((select nr.codes from scholarship.nationality_readings nr where nr.scholarship_id = p_id),
                          (select array_agg(distinct x) from cr, unnest(cr.value_codes) x where cr.criterion_type in ('nationality', 'citizenship_and_residency'))) codes)
  select jsonb_build_object(
    'description', s.description,
    'award_type', (select award_type from ad),
    'sponsor', (select sponsor from ad),
    'programme', (select programme from ad),
    'award_code', (select award_code from ad),
    'benefits', coalesce((select jsonb_agg(jsonb_build_object('type', cv.coverage_type, 'amount', cv.amount, 'currency', cv.currency_code, 'percentage', cv.percentage,
                                 'is_maximum', cv.notes like 'sch-extract-v3:% (maximum)%') order by cv.coverage_type, cv.id)
                          from scholarship.coverage cv where cv.scholarship_id = p_id and cv.notes like 'sch-extract-v3:%' and cv.coverage_type <> 'award_duration'), '[]'::jsonb),
    'application', jsonb_build_object(
        'method', (select w.application_method from scholarship.application_windows w where w.scholarship_id = p_id and w.application_method is not null order by w.created_at desc limit 1),
        'url', (select w.application_url from scholarship.application_windows w where w.scholarship_id = p_id and w.application_url is not null order by w.created_at desc limit 1),
        'rolling', (select application_rolling from ad)),
    'award_duration', (select jsonb_build_object('value', cv.duration_value, 'unit', cv.duration_unit) from scholarship.coverage cv
                        where cv.scholarship_id = p_id and cv.coverage_type = 'award_duration' and cv.duration_unit is not null order by cv.id desc limit 1),
    'academic_year', s.academic_year,
    'nationality_eligibility_status', case
       when exists (select 1 from pipeline.layer4_review_items li where li.entity_id = p_id and li.status = 'pending'
                     and li.field_code in ('nationalities', 'nationality', 'citizenship_eligibility')) then 'under_review'
       when cardinality(coalesce((select codes from nat), '{}'::text[])) > 0
         or exists (select 1 from cr where cr.criterion_type = 'nationality' and (jsonb_array_length(coalesce(cr.value_json->'excluded', '[]')) > 0 or jsonb_array_length(coalesce(cr.value_json->'regions', '[]')) > 0)) then 'restricted'
       when exists (select 1 from scholarship.nationality_readings nr where nr.scholarship_id = p_id and nr.phrases ? 'ANY') then 'unrestricted'
       else 'unknown' end,
    'excluded_nationality_codes', coalesce((select jsonb_agg(distinct x) from cr, jsonb_array_elements_text(coalesce(cr.value_json->'excluded', '[]')) x where cr.criterion_type = 'nationality'), '[]'::jsonb),
    'nationality_regions', coalesce((select jsonb_agg(distinct x) from cr, jsonb_array_elements_text(coalesce(cr.value_json->'regions', '[]')) x where cr.criterion_type = 'nationality'), '[]'::jsonb))
  from s
$function$;

-- providers: R23, one item per campus by its stable identity (never merged by city or postcode), the v2 keys kept on each item
create or replace function api_v3.provider_extra(p_provider_id uuid) returns jsonb language sql stable
set search_path to 'pg_catalog' as $function$
  with k as (
    select k.id, k.stable_key, k.name, k.city, k.postcode, k.subdivision_id
      from catalogue.campuses k
     where k.provider_id = p_provider_id and nullif(btrim(k.city), '') is not null and coalesce(k.status, 'active') <> 'inactive'),
  n as (
    select cc.campus_id, count(distinct cc.course_id) n
      from search.course_documents d
      join catalogue.course_campuses cc on cc.course_id = d.course_id
     where d.provider_id = p_provider_id
       and not exists (select 1 from security.layer4_search_blocked_courses b where b.course_id = cc.course_id)
     group by cc.campus_id)
  select jsonb_build_object(
    'campuses', coalesce((select jsonb_agg(jsonb_build_object('city', security.place_presentable(k.city), 'postcode', k.postcode, 'subdivision_code', s.code,
                   'metro_area', rc.metro_area, 'regional_category', rc.category, 'regional_category_name', rc.category_name,
                   'campus_id', k.stable_key, 'campus_name', nullif(btrim(k.name), ''), 'course_count', coalesce(n.n, 0))
                   order by lower(nullif(btrim(k.name), '')) nulls last, k.stable_key)
                 from k
                 left join ref.subdivisions s on s.id = k.subdivision_id
                 left join pipeline.campus_regional_class rc on rc.campus_id = k.id
                 left join n on n.campus_id = k.id), '[]'::jsonb),
    'logo_dark', null, 'brand_colour', null)
$function$;

-- courses: R28 start_date_status on each intake, O26 excerpt, and the fields defined in v3 that are not held yet
create or replace function api_v3.course_extra(p_course_id uuid, p_item jsonb) returns jsonb language plpgsql stable
set search_path to 'pg_catalog' as $function$
declare v_provider uuid; v_cal boolean; v_desc text; v_max int := greatest(security.pipeline_num_v1('api.v3_description_excerpt_chars', 280)::int, 80);
        v_intakes jsonb;
begin
  select c.provider_id into v_provider from catalogue.courses c where c.id = p_course_id;
  v_cal := exists (select 1 from pipeline.course_intake_dates x where x.provider_id = v_provider and x.calendar_evidence_id is not null);
  select jsonb_agg(i || jsonb_build_object('start_date_status',
           case when nullif(i->>'start_date', '') is not null then 'known' else coalesce((
             select case
               when ci.start_date is not null then 'known'
               when coalesce(d.reason, '') || ' ' || coalesce(ci.intake_label, '') ~* '\m(rolling|any time|anytime|flexible start)' then 'rolling'
               when d.next_action = 'human_decision_required' then 'held_for_review'
               when d.next_action = 'course_identity_unresolved' then 'course_page_not_verified'
               when d.next_action = 'waiting_for_next_academic_year' and d.reason ~* 'does not state .* as an intake' then 'not_on_course_page'
               when d.next_action = 'waiting_for_next_academic_year' then 'next_year_calendar_pending'
               when d.next_action in ('calendar_needs_correction', 'awaiting_official_calendar') then 'no_official_calendar'
               when d.next_action = 'reader_correction_needed' then 'not_yet_read'
               when d.reason ~* 'names no study period' then 'month_only'
               when d.reason ~* 'vocational or pathway|research degree' then 'own_calendar'
               when d.intake_id is null and v_cal then 'not_yet_read'
               when d.intake_id is null then 'no_official_calendar'
               else 'conflicting_evidence' end
               from catalogue.course_intakes ci
               left join pipeline.course_intake_dates d on d.intake_id = ci.id
              where ci.course_id = p_course_id and coalesce(ci.status, 'active') = 'active'
                and lower(btrim(ci.intake_label)) = lower(btrim(i->>'label'))
                and ci.intake_year is not distinct from nullif(i->>'year', '')::int
              order by (ci.start_date is not null) desc, d.applied_at desc nulls last
              limit 1), case when v_cal then 'not_yet_read' else 'no_official_calendar' end) end)
           order by nullif(i->>'year', '')::int nulls last, nullif(i->>'month', '')::int nulls last, i->>'label')
    into v_intakes
    from jsonb_array_elements(case when jsonb_typeof(p_item->'intakes') = 'array' then p_item->'intakes' else '[]'::jsonb end) i;
  select nullif(btrim(d.description), '') into v_desc from search.course_documents d where d.course_id = p_course_id;
  if v_desc is not null and length(v_desc) > v_max then
    v_desc := coalesce(nullif(regexp_replace(left(v_desc, v_max), '\s+\S*$', ''), ''), left(v_desc, v_max)) || '…';
  end if;
  return jsonb_build_object('intakes', coalesce(v_intakes, '[]'::jsonb), 'description_excerpt', v_desc,
    'teaching_language', null, 'study_load', null, 'post_study_work', null, 'field_of_study_codes', null, 'recognition', null,
    'admission_tests', null, 'entry_conditions', null, 'application_route', null);
end $function$;

-- one item: the v2 item plus the v3 fields, found by the item's stable id
create or replace function api_v3.enrich(p_entity text, p_item jsonb) returns jsonb language plpgsql stable
set search_path to 'pg_catalog' as $function$
declare v_id uuid; v_x jsonb;
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' then return p_item; end if;
  if p_entity = 'scholarship' then
    select s.id into v_id from scholarship.scholarships s where s.stable_key = p_item->>'scholarship_id';
    if v_id is not null then v_x := api_v3.scholarship_extra(v_id); end if;
  elsif p_entity = 'course' then
    select c.id into v_id from catalogue.courses c where c.stable_key = p_item->>'course_id';
    if v_id is not null then v_x := api_v3.course_extra(v_id, p_item); end if;
  elsif p_entity = 'provider' then
    select p.id into v_id from catalogue.providers p where p.stable_key = p_item->>'provider_id';
    if v_id is not null then v_x := api_v3.provider_extra(v_id); end if;
  end if;
  return p_item || coalesce(v_x, '{}'::jsonb);
end $function$;

-- a v2 reply made v3: items (lists), item (detail) and sync items enriched; the version label changed
create or replace function api_v3.reply(p_entity text, p_reply jsonb, p_label_key text, p_label text) returns jsonb language sql stable
set search_path to 'pg_catalog' as $function$
  select case when p_reply is null or jsonb_typeof(p_reply) <> 'object' or p_reply ? 'error' then p_reply else
    p_reply
    || case when jsonb_typeof(p_reply->'items') = 'array' then jsonb_build_object('items', coalesce((
         select jsonb_agg(case when p_entity = 'sync' then x || jsonb_build_object('item', api_v3.enrich(x->>'entity', x->'item')) else api_v3.enrich(p_entity, x) end order by o)
           from jsonb_array_elements(p_reply->'items') with ordinality t(x, o)), '[]'::jsonb)) else '{}'::jsonb end
    || case when jsonb_typeof(p_reply->'item') = 'object' then jsonb_build_object('item', api_v3.enrich(p_entity, p_reply->'item')) else '{}'::jsonb end
    || case when p_reply ? p_label_key then jsonb_build_object(p_label_key, p_label) else '{}'::jsonb end end
$function$;

create or replace function api_v3.reference_lists() returns jsonb language sql immutable
set search_path to 'pg_catalog' as $function$
  select jsonb_build_object(
    'start_date_statuses', '["known","no_official_calendar","month_only","not_on_course_page","course_page_not_verified","next_year_calendar_pending","not_yet_read","own_calendar","conflicting_evidence","held_for_review","rolling"]'::jsonb,
    'nationality_eligibility_statuses', '["restricted","unrestricted","under_review","unknown"]'::jsonb,
    'award_types', '["scholarship","bursary","tuition_waiver","fee_discount","research_funding","grant","stipend","other"]'::jsonb,
    'application_methods', '["separate_application","automatic_consideration","nomination"]'::jsonb)
$function$;

-- the release gate: a direct database session (owner, migration, verification) is always answered; API callers only once released
create or replace function api_v3.released() returns boolean language sql stable
set search_path to 'pg_catalog' as $function$
  select coalesce(security.pipeline_num_v1('api.v3_released', 0), 0) >= 1  -- fixed: governance switch, 1 = released
$function$;

-- Website: one dispatcher; the arguments are the v2 function's own (p_filters, p_page, ...), so a v3 call answers exactly as v2 plus the additions
create or replace function public.website_v3_call(p_action text, p_args jsonb) returns jsonb language plpgsql security definer
set search_path to '' as $function$
declare a jsonb := coalesce(p_args, '{}'::jsonb); r jsonb; e text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if current_user <> 'postgres' and not api_v3.released() then raise exception 'V3_NOT_RELEASED' using errcode = '42501'; end if;
  case p_action
    when 'reference' then r := public.website_v2_reference() || jsonb_build_object('v3', api_v3.reference_lists()); e := 'none';
    when 'search' then r := public.website_v2_course_search(a->'p_filters', (a->>'p_page')::int, (a->>'p_page_size')::int, a->>'p_sort'); e := 'course';
    when 'providers' then r := public.website_v2_providers(a->'p_filters', (a->>'p_page')::int, (a->>'p_page_size')::int, a->>'p_sort'); e := 'provider';
    when 'rankings' then r := public.website_v2_rankings(a->'p_filters', (a->>'p_page')::int, (a->>'p_page_size')::int); e := 'none';
    when 'scholarships' then r := public.website_v2_scholarships(a->'p_filters', (a->>'p_page')::int, (a->>'p_page_size')::int); e := 'scholarship';
    when 'course' then r := case when a ? 'p_edu_country' then public.website_v2_course(a->>'p_identifier', a->>'p_edu_country') else public.website_v2_course(a->>'p_identifier') end; e := 'course';
    when 'provider' then r := case when a ? 'p_edu_country' then public.website_v2_provider(a->>'p_provider_id', a->>'p_edu_country') else public.website_v2_provider(a->>'p_provider_id') end; e := 'provider';
    when 'scholarship' then r := public.website_v2_scholarship(a->>'p_scholarship_id'); e := 'scholarship';
    when 'sync' then r := public.website_v2_sync(a->>'p_cursor', coalesce((a->>'p_full')::boolean, false),
                                case when jsonb_typeof(a->'p_entities') = 'array' then array(select jsonb_array_elements_text(a->'p_entities')) end, (a->>'p_page_size')::int); e := 'sync';
    else raise exception 'INVALID_INPUT: action' using errcode = '22023';
  end case;
  return api_v3.reply(e, r, 'contract_version', 'website-v3');
end $function$;

-- Zoho: the same, over the Zoho v2 functions; report and report_status are unchanged writes
create or replace function public.zoho_v3_call(p_action text, p_args jsonb) returns jsonb language plpgsql security definer
set search_path to '' as $function$
declare a jsonb := coalesce(p_args, '{}'::jsonb); r jsonb; e text := 'none';
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if current_user <> 'postgres' and not api_v3.released() then raise exception 'V3_NOT_RELEASED' using errcode = '42501'; end if;
  case p_action
    when 'reference' then r := public.zoho_v2_reference() || jsonb_build_object('v3', api_v3.reference_lists());
    when 'search' then r := public.zoho_v2_course_search(a->'p_filters', (a->>'p_page')::int, (a->>'p_page_size')::int, a->>'p_sort'); e := 'course';
    when 'course' then r := public.zoho_v2_course(a->>'p_identifier'); e := 'course';
    when 'courses' then r := public.zoho_v2_courses(array(select jsonb_array_elements_text(a->'p_identifiers'))); e := 'course';
    when 'providers' then r := public.zoho_v2_providers(a->'p_filters', (a->>'p_page')::int, (a->>'p_page_size')::int, a->>'p_sort'); e := 'provider';
    when 'provider' then r := public.zoho_v2_provider(a->>'p_identifier'); e := 'provider';
    when 'list' then r := public.zoho_v2_list(a->>'p_entity', a->'p_filters', (a->>'p_page')::int, (a->>'p_page_size')::int);
    when 'statistics' then r := public.zoho_v2_statistics(a->>'p_kind', a->'p_filters', (a->>'p_page')::int, (a->>'p_page_size')::int);
    when 'passthrough' then r := public.zoho_v2_passthrough(a->>'p_action', a->'p_filters', (a->>'p_page')::int, (a->>'p_page_size')::int, a->>'p_id', a->'p_body');
                            e := case when a->>'p_action' in ('scholarships', 'scholarship') then 'scholarship' else 'none' end;
    when 'report' then r := public.zoho_v2_report(a->'p_body');
    when 'report_status' then r := public.zoho_v2_report_status(a->'p_flag_ids');
    when 'sync' then r := public.zoho_v2_sync(a->>'p_cursor', coalesce((a->>'p_full')::boolean, false),
                                case when jsonb_typeof(a->'p_entities') = 'array' then array(select jsonb_array_elements_text(a->'p_entities')) end, (a->>'p_page_size')::int); e := 'sync';
    when 'export_page' then r := public.zoho_v2_export_page(a->>'p_entity', (a->>'p_page')::int);
    else raise exception 'INVALID_INPUT: action' using errcode = '22023';
  end case;
  return api_v3.reply(e, r, 'api_version', 'zoho-v3');
end $function$;

revoke all on function public.website_v3_call(text, jsonb) from public, anon, authenticated;
revoke all on function public.zoho_v3_call(text, jsonb) from public, anon, authenticated;
grant execute on function public.website_v3_call(text, jsonb) to service_role;
grant execute on function public.zoho_v3_call(text, jsonb) to service_role;
revoke all on all functions in schema api_v3 from public, anon, authenticated;
