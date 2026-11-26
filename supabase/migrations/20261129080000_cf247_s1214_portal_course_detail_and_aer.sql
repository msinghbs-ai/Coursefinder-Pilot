-- CF-247 s1214 (S2-Build; Atlas brief 26 Nov 2026 12:02 AEDT, for S1-API-Frontend-Delivery's Expandable Course Details and Entry
-- Requirements screens in portal/). Version above main's 20261129061000 and S2-Build's pending s1213 (20261129070000).
-- Two read-only portal reads, each a portal schema function behind a public wrapper (authenticated execute, Viewer rank and above; anon
-- and public refused):
--   public.portal_course_detail_v1(p_course_id uuid): one course of a published provider in full: description, campuses, fees (every
--     active fee row, plus the annual tuition the search shows), upcoming intakes, academic entry requirements, English requirements by
--     test, the provider's graduate outcomes for the course's cohort (employment and salary, QILT), the official course page and when it was
--     last checked. A course outside the portal's scope answers not found (P0002), never another provider's data.
--   public.portal_aer_list_v1(p_args jsonb): pages of published-provider courses with their active academic and English entry requirements;
--     filters q (course or provider words), country (where the course is taught), source_country (requirements stated for that country of
--     qualification, with those that name no country, which apply to everyone; on 26 Nov no active requirement names one),
--     level (study level code), provider_id and has (academic, english, both or any); page from 1; page size portal.aer_page_size (G2).
-- Scope is the portal search's own: courses in search.course_documents (published providers only) whose catalogue course is active, with
-- portal_search.visibility_scope. Values the catalogue does not hold are returned as null ("Not recorded" on screen), never guessed.
-- Not the consumer API: no consumer function, table or column is changed (G3 checked). G1: no job. G2: one setting with label, range,
-- unit and used_by. Locks untouched. Nothing dropped. No AI or Firecrawl call; US$0.
-- Replaces: nothing (new reads).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function creates

create temp table s1214_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before;

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
end $pre$;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('portal', 'aer_page_size', 'Entry requirements: courses a page',
        'How many courses one page of the portal''s Entry requirements screen returns; further pages are fetched by page number.',
        'number', to_jsonb(20), 10, 100, 'courses', 6160, 'Portal', 'public.portal_aer_list_v1',
        'CF-247 s1214 (Atlas brief 26 Nov 2026 12:02 AEDT): portal Entry requirements screen')
on conflict do nothing;

-- the portal's course scope (published providers, active courses, the search's visibility setting)
create or replace function portal.course_in_scope_v1(p_course_id uuid)
returns boolean language sql stable security definer set search_path = '' as $function$
  select exists (select 1 from search.course_documents d join catalogue.courses c on c.id = d.course_id
                  where d.course_id = p_course_id and c.lifecycle_status = 'active'
                    and (security.portal_search_text_v1('visibility_scope', 'active') <> 'published' or c.publication_status = 'published'))
$function$;

-- one course's entry requirements and English requirements, as the screens show them
create or replace function portal.course_entry_json_v1(p_course_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
           'kind', e.kind, 'audience', e.audience, 'country_code', co.iso_alpha2, 'country_name', co.name,
           'description', e.description, 'min_grade', e.min_grade, 'min_value', e.min_value, 'grade_scale', e.grade_scale,
           'min_entry_score', e.min_entry_score, 'min_entry_score_basis', e.min_entry_score_basis, 'as_at', e.as_at, 'source_url', e.source_url)
         order by case e.kind when 'minimum_grade' then 1 when 'prior_qualification' then 2 when 'subject_prerequisite' then 3 else 4 end, co.name nulls first, e.id), '[]'::jsonb)  -- fixed: display order of the kinds
    from catalogue.course_entry_requirements e left join ref.countries co on co.id = e.country_id
   where e.course_id = p_course_id and e.status = 'active'
$function$;

create or replace function portal.course_english_json_v1(p_course_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
           'test_code', t.code, 'test_name', t.name, 'overall_score', r.overall_score, 'component_scores', r.component_scores,
           'score_grade', r.score_grade, 'subtest_grades', r.subtest_grades, 'notes', r.notes, 'last_checked', r.last_verified_at)
         order by t.name, r.overall_score nulls last, r.id), '[]'::jsonb)
    from catalogue.course_english_requirements r left join ref.english_tests t on t.id = r.english_test_id
   where r.course_id = p_course_id and r.status = 'active'
$function$;

create or replace function portal.course_detail_v1(p_course_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_today date := (now() at time zone 'Australia/Melbourne')::date;  -- fixed: Melbourne calendar day
        v_cohort text; r record;
begin
  if p_course_id is null or not portal.course_in_scope_v1(p_course_id) then
    raise exception 'course not found' using errcode = 'P0002';
  end if;
  select c.*, d.official_course_url, d.description doc_description, d.provider_annual_tuition_amount, d.provider_annual_tuition_currency,
         d.provider_tuition_options, d.country_code, d.study_level_code, d.primary_field_name, d.generated_at,
         p.id prov_id, coalesce(nullif(p.display_name, ''), p.canonical_name) provider_name, sl.name level_name
    into r
    from catalogue.courses c join search.course_documents d on d.course_id = c.id join catalogue.providers p on p.id = c.provider_id
    left join ref.study_levels sl on sl.id = c.study_level_id
   where c.id = p_course_id;
  -- the graduate survey cohort for the course's level (QILT: undergraduate, postgraduate coursework, postgraduate research)
  v_cohort := case when r.study_level_code in ('doctorate', 'masters_research') then 'PGR'
                   when r.study_level_code like 'masters%' or r.study_level_code in ('graduate_certificate', 'graduate_diploma') then 'PGC'
                   else 'UG' end;  -- fixed: the survey's own cohort codes
  return jsonb_build_object(
    'course_id', r.id, 'title', coalesce(nullif(r.display_title, ''), r.canonical_title), 'course_code', r.course_code,
    'provider', jsonb_build_object('id', r.prov_id, 'name', r.provider_name, 'country_code', r.country_code),
    'level', jsonb_build_object('code', r.study_level_code, 'name', r.level_name), 'field', r.primary_field_name,
    'duration_value', r.duration_value, 'duration_unit', r.duration_unit, 'delivery_mode', r.delivery_mode, 'study_load', r.study_load,
    'open_to_international', r.open_to_international,
    'description', coalesce(nullif(btrim(r.description), ''), nullif(btrim(r.doc_description), '')),
    'official_url', coalesce(r.official_course_url, r.course_url),
    'campuses', (select coalesce(jsonb_agg(jsonb_build_object('campus_id', ca.id, 'name', ca.name, 'city', ca.city, 'state_code', s.code,
                   'postcode', ca.postcode, 'delivery_mode', cc.delivery_mode, 'is_primary', coalesce(cc.is_primary, false))
                   order by cc.is_primary desc nulls last, ca.name, ca.id), '[]'::jsonb)
                   from catalogue.course_campuses cc join catalogue.campuses ca on ca.id = cc.campus_id left join ref.subdivisions s on s.id = ca.subdivision_id
                  where cc.course_id = r.id),
    'annual_tuition', case when r.provider_annual_tuition_amount is not null then jsonb_build_object('amount', r.provider_annual_tuition_amount, 'currency', r.provider_annual_tuition_currency) end,
    'fees', (select coalesce(jsonb_agg(jsonb_build_object('year', f.fee_year, 'audience', f.audience, 'fee_type', f.fee_type, 'amount', f.amount,
               'currency', f.currency_code, 'basis', f.basis, 'load_basis', f.load_basis, 'is_csp', f.is_csp, 'campus', ca.name, 'notes', f.notes,
               'last_checked', f.last_verified_at)
               order by f.fee_year desc nulls last, f.audience, f.fee_type, f.amount, f.id), '[]'::jsonb)
               from catalogue.course_fees f left join catalogue.campuses ca on ca.id = f.campus_id
              where f.course_id = r.id and f.status = 'active'),
    'intakes', (select coalesce(jsonb_agg(jsonb_build_object('year', i.intake_year, 'label', i.intake_label, 'start_date', i.start_date,
                  'application_deadline', i.application_deadline, 'campus', ca.name)
                  order by i.start_date nulls last, i.intake_label, i.id), '[]'::jsonb)
                  from catalogue.course_intakes i left join catalogue.campuses ca on ca.id = i.campus_id
                 where i.course_id = r.id and i.status = 'active' and (i.start_date is null or i.start_date >= v_today)),
    'entry_requirements', portal.course_entry_json_v1(r.id),
    'english_requirements', portal.course_english_json_v1(r.id),
    'career_outcomes', (select coalesce(jsonb_agg(jsonb_build_object('survey', sv.name, 'metric', m.name, 'category', m.category, 'unit', m.unit,
                          'value', o.metric_value, 'national_benchmark', o.national_benchmark, 'cohort', o.source_cohort_code,
                          'years', case when o.collection_year_from = o.collection_year_to then o.collection_year_to::text
                                        else o.collection_year_from || '-' || o.collection_year_to end)
                          order by m.category, m.name), '[]'::jsonb)
                          from catalogue.provider_outcomes o join ref.outcome_metrics m on m.id = o.metric_id left join ref.outcome_surveys sv on sv.id = o.survey_id
                         where o.provider_id = r.prov_id and o.status = 'current' and o.external_study_area_id is null
                           and m.category in ('employment', 'salary') and o.source_cohort_code = v_cohort),
    'last_checked', r.last_verified_at,
    'details_built_at', r.generated_at,
    'saved', exists (select 1 from portal.saved_courses sc where sc.course_id = r.id and sc.user_id = auth.uid()));
end $function$;

create or replace function portal.aer_list_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare v_size integer := least(greatest(coalesce(security.portal_setting_v1('aer_page_size'), 20), 10), 100);  -- fixed: the setting's own range
        v_page integer := greatest(coalesce(case when jsonb_typeof(p_args->'page') = 'number' then (p_args->>'page')::numeric::int end, 1), 1);
        v_q text := nullif(btrim(regexp_replace(coalesce(p_args->>'q', ''), '\s+', ' ', 'g')), '');
        v_country text := case when upper(btrim(coalesce(p_args->>'country', ''))) ~ '^[A-Z]{2}$' then upper(btrim(p_args->>'country')) end;
        v_src text := case when upper(btrim(coalesce(p_args->>'source_country', ''))) ~ '^[A-Z]{2}$' then upper(btrim(p_args->>'source_country')) end;
        v_level text := nullif(btrim(lower(coalesce(p_args->>'level', ''))), '');
        v_provider uuid := case when btrim(coalesce(p_args->>'provider_id', '')) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then btrim(p_args->>'provider_id')::uuid end;
        v_has text := case when lower(coalesce(p_args->>'has', '')) in ('academic', 'english', 'both') then lower(p_args->>'has') else 'any' end;
        v_scope text := security.portal_search_text_v1('visibility_scope', 'active');
        v_like text; v_total integer; v_items jsonb; v_counts jsonb;
begin
  if char_length(coalesce(v_q, '')) > 200 then v_q := left(v_q, 200); end if;  -- fixed: a search phrase is short
  v_like := case when v_q is not null then security.portal_like_v1(v_q) end;
  create temp table if not exists portal_aer_set (course_id uuid primary key, ac boolean, en boolean, prov text, title text) on commit drop;
  truncate pg_temp.portal_aer_set;
  insert into pg_temp.portal_aer_set
  select x.course_id, x.ac, x.en, x.prov, x.title from (
    select d.course_id, d.provider_name prov, d.course_title title,
           exists (select 1 from catalogue.course_entry_requirements e left join ref.countries co on co.id = e.country_id
                    where e.course_id = d.course_id and e.status = 'active' and (v_src is null or co.iso_alpha2 = v_src or e.country_id is null)) ac,  -- a requirement naming no country applies to every applicant
           exists (select 1 from catalogue.course_english_requirements g where g.course_id = d.course_id and g.status = 'active') en
      from search.course_documents d join catalogue.courses c on c.id = d.course_id
     where c.lifecycle_status = 'active' and (v_scope <> 'published' or c.publication_status = 'published')
       and (v_country is null or d.country_code = v_country)
       and (v_level is null or d.study_level_code = v_level or d.study_level_code like v_level || '\_%')
       and (v_provider is null or d.provider_id = v_provider)
       and (v_like is null or d.course_title ilike v_like or d.provider_name ilike v_like)) x
   where case v_has when 'academic' then x.ac when 'english' then x.en when 'both' then x.ac and x.en
                    else x.ac or x.en end;
  select count(*), jsonb_build_object('academic', count(*) filter (where ac), 'english', count(*) filter (where en), 'both', count(*) filter (where ac and en))
    into v_total, v_counts from pg_temp.portal_aer_set;
  select coalesce(jsonb_agg(jsonb_build_object(
           'course_id', c.id, 'title', coalesce(nullif(c.display_title, ''), c.canonical_title), 'provider_id', d.provider_id, 'provider_name', d.provider_name,
           'country_code', d.country_code, 'level_code', d.study_level_code, 'level_name', sl.name, 'official_url', coalesce(d.official_course_url, c.course_url),
           'entry_requirements', portal.course_entry_json_v1(c.id), 'english_requirements', portal.course_english_json_v1(c.id))
         order by s.prov, s.title, s.course_id), '[]'::jsonb)
    into v_items
    from (select * from pg_temp.portal_aer_set order by prov, title, course_id limit v_size offset (v_page - 1) * v_size) s
    join catalogue.courses c on c.id = s.course_id join search.course_documents d on d.course_id = s.course_id
    left join ref.study_levels sl on sl.id = c.study_level_id;
  return jsonb_build_object('items', v_items, 'total', v_total, 'page', v_page, 'page_size', v_size, 'facets', jsonb_build_object('counts', v_counts),
    'filters', jsonb_build_object('q', v_q, 'country', v_country, 'source_country', v_src, 'level', v_level, 'provider_id', v_provider, 'has', v_has));
end $function$;

-- public wrappers: Viewer rank and above
create or replace function public.portal_course_detail_v1(p_course_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
begin
  perform security.portal_rank_v1(1);  -- fixed: Viewer and above
  return portal.course_detail_v1(p_course_id);
end $function$;

create or replace function public.portal_aer_list_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
begin
  perform security.portal_rank_v1(1);  -- fixed: Viewer and above
  return portal.aer_list_v1(coalesce(p_args, '{}'::jsonb));
end $function$;

comment on function public.portal_course_detail_v1(uuid) is 'CF-247 s1214: portal Expandable Course Details: one published-provider course in full (Viewer and above).';
comment on function public.portal_aer_list_v1(jsonb) is 'CF-247 s1214: portal Entry requirements: pages of published-provider courses with academic and English entry requirements (Viewer and above).';

revoke all on function portal.course_in_scope_v1(uuid), portal.course_entry_json_v1(uuid), portal.course_english_json_v1(uuid),
                       portal.course_detail_v1(uuid), portal.aer_list_v1(jsonb) from public, anon, authenticated;
revoke all on function public.portal_course_detail_v1(uuid), public.portal_aer_list_v1(jsonb) from public, anon;
grant execute on function public.portal_course_detail_v1(uuid), public.portal_aer_list_v1(jsonb) to authenticated;

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('function', 'public.portal_course_detail_v1', 'Service', 'Portal', 'Portal Expandable Course Details: one published-provider course in full', 'active', '{}', '20261129080000'),
  ('function', 'public.portal_aer_list_v1', 'Service', 'Portal', 'Portal Entry requirements: pages of published-provider courses with academic and English requirements', 'active', '{}', '20261129080000')
on conflict do nothing;

do $post$
declare v jsonb := security.consumer_api_check_v1(); v_id uuid; x jsonb; y jsonb; v_out uuid;
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'post-check: consumer API baseline changed: %', v;
  end if;
  if (select count(*) from cron.job where active) <> (select cron_before from s1214_guard) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1214_guard) then raise exception 'post-check: manual locks changed'; end if;
  if has_function_privilege('anon', 'public.portal_course_detail_v1(uuid)', 'execute') or has_function_privilege('anon', 'public.portal_aer_list_v1(jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'public.portal_aer_list_v1(jsonb)', 'execute')
     or has_function_privilege('authenticated', 'portal.course_detail_v1(uuid)', 'execute') then
    raise exception 'post-check: execute privileges are not as released';
  end if;
  -- a course with entry and English requirements reads in full; one outside the scope is not found
  select d.course_id into v_id from search.course_documents d join catalogue.courses c on c.id = d.course_id and c.lifecycle_status = 'active'
   where exists (select 1 from catalogue.course_entry_requirements e where e.course_id = d.course_id and e.status = 'active')
     and exists (select 1 from catalogue.course_english_requirements g where g.course_id = d.course_id and g.status = 'active') limit 1;
  x := portal.course_detail_v1(v_id);
  if x->>'course_id' <> v_id::text or jsonb_array_length(x->'entry_requirements') = 0 or jsonb_array_length(x->'english_requirements') = 0
     or not (x ? 'campuses' and x ? 'fees' and x ? 'intakes' and x ? 'career_outcomes' and x ? 'official_url' and x ? 'last_checked') then
    raise exception 'post-check: course detail is incomplete: %', left(x::text, 400);
  end if;
  select c.id into v_out from catalogue.courses c where not exists (select 1 from search.course_documents d where d.course_id = c.id) limit 1;
  begin
    perform portal.course_detail_v1(v_out);
    raise exception 'post-check: a course outside the portal scope was returned';
  exception when sqlstate 'P0002' then null;
  end;
  y := portal.aer_list_v1(jsonb_build_object('country', 'AU', 'has', 'both', 'page', 1));
  if (y->>'total')::int = 0 or jsonb_array_length(y->'items') = 0 or (y->>'page_size')::int <> security.portal_setting_v1('aer_page_size') then
    raise exception 'post-check: the entry requirements list is empty or not paged: %', left(y::text, 300);
  end if;
end $post$;
