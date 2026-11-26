-- CF-247 s1222 (S2-Build; Atlas brief 26 Nov 2026 15:59 AEDT, the Platform Admin's live UAT of the portal: seven UI and data-binding fixes
-- before acceptance). The screens change in portal/ in the same release; this migration is the data they need. Version above main's
-- 20261129121500.
-- 1. One annual tuition fee. portal.primary_fee_v1 picks, from a course's provider annual fees, the current year's (Melbourne), else the
--    nearest later year, else the latest; it returns {per_year, amount, currency, year, basis}. 756 courses hold annual fees for more than one
--    year and the cards showed the latest (2027 beside a 2026 fee, the Platform Admin's feedback 5). Used by the search cards ('fee'), the
--    Entry Requirements rows ('annual_tuition_fee'), the course detail ('primary_fee') and saved courses ('primary_fee').
-- 2. The national course register code beside the title. portal.regulator_code_v1 returns the course's active CRICOS, NZQA or MTCU code as
--    {scheme, label, code} (catalogue.course_registrations: CRICOS 25,900, NZQA 6,520, MTCU 766 active); 'regulator' on the same four reads.
-- 3. Entry requirements by country inside Course details. Each matrix row carries 'scope' (course, study_level or provider), and
--    public.portal_entry_matrix_v1(p_args jsonb) returns every row for one course and one student country (with the rows naming no country),
--    so the country chosen is never hidden by the detail read's cap (portal.entry_matrix_max_rows).
-- 4. Countries pinned first. portal.priority_source_countries (new G2 list, ["IN", "NP"]) is read by every student-country list through
--    portal_settings_v1; the screens put those countries first, then the rest alphabetically.
-- The four replaced functions are replaced only if their bodies are the texts this change was written against (md5 checked). Not the
-- consumer API (G3 checked). G1: no job. G2: one setting. Locks untouched. Nothing dropped. US$0.
-- Replaces: the single-year fee choice in catalogue.portal_course_cards_v1, portal.aer_list_v1 (latest year) and the s1216 detail and the
-- s1143 saved-courses bodies (no regulator code, no primary fee).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function replaces

create temp table s1222_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before;

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (select md5(prosrc) from pg_proc where oid = 'catalogue.portal_course_cards_v1(uuid[], text[], numeric, jsonb)'::regprocedure) <> '2d4c96da6741d865f440b5d1a21980a1'
     or (select md5(prosrc) from pg_proc where oid = 'public.portal_saved_list_v1()'::regprocedure) <> 'dc9ed8ea2e47c52fbda609d4bd6c50d7'
     or (select md5(prosrc) from pg_proc where oid = 'portal.course_detail_v1(uuid)'::regprocedure) <> '10e320440fdd8c7b5ce37cf361dbdfb6'
     or (select md5(prosrc) from pg_proc where oid = 'portal.aer_list_v1(jsonb)'::regprocedure) <> '1e86de1c476a110939747e0e3a73a05f' then
    raise exception 'pre-check: a portal read is not the body this change was written against';
  end if;
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
end $pre$;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('portal', 'priority_source_countries', 'Student countries shown first',
        'Countries of education (two-letter codes) listed first, in this order, in every student-country list in the portal (Entry Requirements, Course details, Universities & Providers, Proposals); the rest follow alphabetically.',
        'list', '["IN", "NP"]'::jsonb, null, null, 'country codes', 6105, 'Portal', 'portal screens through public.portal_settings_v1',
        'CF-247 s1222 (Atlas brief 26 Nov 2026 15:59 AEDT): India and Nepal are the main incoming student markets')
on conflict do nothing;

-- one annual tuition fee: the current year's, else the nearest later year, else the latest
create or replace function portal.primary_fee_v1(p_options jsonb, p_amount numeric, p_currency text)
returns jsonb language sql stable security definer set search_path = '' as $function$
  select coalesce(
    (select jsonb_build_object('per_year', (o->>'amount')::numeric, 'amount', (o->>'amount')::numeric, 'currency', coalesce(o->>'currency', p_currency),
                               'year', (o->>'fee_year')::int, 'basis', 'annual')
       from jsonb_array_elements(case when jsonb_typeof(p_options) = 'array' then p_options else '[]'::jsonb end) o
      where o->>'basis' = 'annual' and (o->>'amount') ~ '^[0-9]+(\.[0-9]+)?$' and (o->>'amount')::numeric > 0
      order by case when (o->>'fee_year')::int = extract(year from now() at time zone 'Australia/Melbourne')::int then 0  -- fixed: the Melbourne calendar
                    when (o->>'fee_year')::int > extract(year from now() at time zone 'Australia/Melbourne')::int then 1 else 2 end,
               case when (o->>'fee_year')::int > extract(year from now() at time zone 'Australia/Melbourne')::int then (o->>'fee_year')::int else -(o->>'fee_year')::int end nulls last,
               o->>'last_verified_at' desc nulls last
      limit 1),
    case when p_amount is not null and p_amount > 0 then jsonb_build_object('per_year', p_amount, 'amount', p_amount, 'currency', p_currency, 'year', null, 'basis', 'annual') end)
$function$;

-- the national course register code shown beside the title
create or replace function portal.regulator_code_v1(p_course_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $function$
  select jsonb_build_object('scheme', r.scheme, 'label', upper(r.scheme), 'code', r.registration_code)
    from catalogue.course_registrations r
   where r.course_id = p_course_id and r.status = 'active' and r.scheme in ('cricos', 'nzqa', 'mtcu')  -- fixed: the national course registers
     and nullif(btrim(r.registration_code), '') is not null
   order by case r.scheme when 'cricos' then 1 when 'nzqa' then 2 else 3 end, r.registration_code
   limit 1
$function$;

create or replace function catalogue.portal_course_cards_v1(p_ids uuid[], p_cities text[], p_simmin numeric, p_near jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
begin
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'course_id', c.id, 'title', coalesce(nullif(c.display_title, ''), c.canonical_title),
      'provider_id', p.id, 'provider_name', coalesce(nullif(p.display_name, ''), p.canonical_name),
      'level', sl.name, 'country_code', d.country_code,
      'state_code', coalesce(cam.state_code, ps.code), 'city', coalesce(cam.city, p.primary_city),
      'duration_value', c.duration_value, 'duration_unit', c.duration_unit,
      'fee', portal.primary_fee_v1(d.provider_tuition_options, d.provider_annual_tuition_amount, d.provider_annual_tuition_currency),  -- s1222: one annual fee, the current year's first
      'regulator', portal.regulator_code_v1(c.id),  -- s1222
      'next_intake', (select jsonb_build_object('label', i.intake_label, 'start_date', i.start_date) from catalogue.course_intakes i
                       where i.course_id = c.id and i.status = 'active' and (i.start_date is null or i.start_date >= (now() at time zone 'Australia/Melbourne')::date)  -- fixed: Melbourne day
                       order by i.start_date nulls last, i.id limit 1),
      'topic_match', coalesce(rk.fts > 0, false) or coalesce(rk.sim >= p_simmin, false),
      'topic_score', case when rk.sim is not null then round(rk.sim::numeric, 3) end,
      'why', to_jsonb(array_remove(array[
               case when rk.sim >= p_simmin then 'Topic match by meaning' end,
               case when rk.fts > 0 then 'Topic words in the course text' end,
               case when cam.city is not null and cardinality(p_cities) > 0 then 'Campus in ' || cam.city end], null)),
      'course_url', coalesce(d.official_course_url, c.course_url),
      'saved', exists (select 1 from portal.saved_courses sc where sc.course_id = c.id and sc.user_id = auth.uid()))
    order by x.ord), '[]'::jsonb)
  from unnest(p_ids) with ordinality x(id, ord)
  join catalogue.courses c on c.id = x.id
  join catalogue.providers p on p.id = c.provider_id
  left join search.course_documents d on d.course_id = c.id
  left join ref.study_levels sl on sl.id = c.study_level_id
  left join ref.subdivisions ps on ps.id = p.subdivision_id
  left join lateral (select ca.city, s.code state_code from catalogue.course_campuses cc join catalogue.campuses ca on ca.id = cc.campus_id left join ref.subdivisions s on s.id = ca.subdivision_id
                      where cc.course_id = c.id
                      order by (lower(trim(ca.city)) = any(p_cities) or ca.postcode = any(array(select jsonb_array_elements_text(coalesce(p_near->'postcodes', '[]'::jsonb))))) desc,
                               cc.is_primary desc nulls last, ca.city limit 1) cam on true
  left join pg_temp.portal_search_rank rk on rk.course_id = c.id);
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
           'city', coalesce(cam.city, p.primary_city), 'state_code', coalesce(cam.state_code, ps.code),  -- s1216: the primary campus, else the provider
           'duration_value', c.duration_value, 'duration_unit', c.duration_unit,
           'annual_tuition_fee', portal.primary_fee_v1(d.provider_tuition_options, d.provider_annual_tuition_amount, d.provider_annual_tuition_currency),  -- s1222: one annual fee, the current year's first
           'regulator', portal.regulator_code_v1(c.id),
           'entry_requirements', portal.course_entry_json_v1(c.id), 'english_requirements', portal.course_english_json_v1(c.id))
         order by s.prov, s.title, s.course_id), '[]'::jsonb)
    into v_items
    from (select * from pg_temp.portal_aer_set order by prov, title, course_id limit v_size offset (v_page - 1) * v_size) s
    join catalogue.courses c on c.id = s.course_id join search.course_documents d on d.course_id = s.course_id
    left join ref.study_levels sl on sl.id = c.study_level_id
    join catalogue.providers p on p.id = c.provider_id left join ref.subdivisions ps on ps.id = p.subdivision_id
    left join lateral (select ca.city, sd.code state_code from catalogue.course_campuses cc join catalogue.campuses ca on ca.id = cc.campus_id
                        left join ref.subdivisions sd on sd.id = ca.subdivision_id
                       where cc.course_id = c.id order by cc.is_primary desc nulls last, ca.city limit 1) cam on true;  -- fixed: one campus is shown
  return jsonb_build_object('items', v_items, 'total', v_total, 'page', v_page, 'page_size', v_size, 'facets', jsonb_build_object('counts', v_counts),
    'filters', jsonb_build_object('q', v_q, 'country', v_country, 'source_country', v_src, 'level', v_level, 'provider_id', v_provider, 'has', v_has));
end $function$;

create or replace function portal.course_detail_v1(p_course_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_today date := (now() at time zone 'Australia/Melbourne')::date;  -- fixed: Melbourne calendar day
        v_cohort text; r record; v_matrix_max integer := least(greatest(coalesce(security.portal_setting_v1('entry_matrix_max_rows'), 300), 20), 2000);  -- s1216; fixed: the setting's own range
        v_matrix_total integer; v_matrix jsonb;
begin
  if p_course_id is null or not portal.course_in_scope_v1(p_course_id) then
    raise exception 'course not found' using errcode = 'P0002';
  end if;
  select c.*, d.official_course_url, d.description doc_description, d.provider_annual_tuition_amount, d.provider_annual_tuition_currency,
         d.provider_tuition_options, d.country_code, d.study_level_code, d.primary_field_name, d.generated_at,
         p.id prov_id, coalesce(nullif(p.display_name, ''), p.canonical_name) provider_name, p.website provider_website_url, sl.name level_name, sl.parent_id level_parent_id
    into r
    from catalogue.courses c join search.course_documents d on d.course_id = c.id join catalogue.providers p on p.id = c.provider_id
    left join ref.study_levels sl on sl.id = c.study_level_id
   where c.id = p_course_id;
  -- the graduate survey cohort for the course's level (QILT: undergraduate, postgraduate coursework, postgraduate research)
  v_cohort := case when r.study_level_code in ('doctorate', 'masters_research') then 'PGR'
                   when r.study_level_code like 'masters%' or r.study_level_code in ('graduate_certificate', 'graduate_diploma') then 'PGC'
                   else 'UG' end;  -- fixed: the survey's own cohort codes
  -- s1216: the provider's country-by-country entry matrix rows for this course: rows naming the course, or rows for its study level (or the
  -- level above or below it) that name no course, and provider-wide rows naming neither; active rows only, international or all applicants,
  -- at most portal.entry_matrix_max_rows
  select coalesce(jsonb_agg(jsonb_build_object('country_code', x.country_code, 'country_name', x.country_name, 'qualification', x.qualification_name,
           'min_grade', x.min_grade, 'min_value', x.min_value, 'grade_scale', x.grade_scale, 'benchmark_band', x.benchmark_band,
           'level_label', x.level_label, 'course_label', x.course_label, 'for_this_course', x.for_course, 'scope', x.scope, 'audience', x.audience,
           'edition', x.edition, 'intake_year', x.intake_year, 'conditions', x.conditions, 'as_at', x.as_at, 'source_url', x.source_url)
           order by x.rn) filter (where x.rn <= v_matrix_max), '[]'::jsonb), coalesce(max(x.total), 0)
    into v_matrix, v_matrix_total
    from (select m.*, co.name country_name, m.course_id is not distinct from r.id for_course,
                 case when m.course_id is not null then 'course' when m.study_level_id is not null then 'study_level' else 'provider' end scope,  -- s1222
                 row_number() over (order by (m.course_id is not distinct from r.id) desc, coalesce(co.name, m.country_code, ''), m.qualification_name, m.id) rn,
                 count(*) over () total
            from catalogue.provider_entry_matrix m left join ref.countries co on co.id = m.country_id
            left join ref.study_levels ml on ml.id = m.study_level_id
           where m.provider_id = r.prov_id and m.status = 'active' and coalesce(m.audience, 'all') in ('international', 'all')
             and (m.course_id = r.id
                  or (m.course_id is null and (m.study_level_id is null or m.study_level_id = r.study_level_id or m.study_level_id = r.level_parent_id or ml.parent_id = r.study_level_id)))) x;
  return jsonb_build_object(
    'course_id', r.id, 'title', coalesce(nullif(r.display_title, ''), r.canonical_title), 'course_code', r.course_code,
    'provider', jsonb_build_object('id', r.prov_id, 'name', r.provider_name, 'country_code', r.country_code),
    'level', jsonb_build_object('code', r.study_level_code, 'name', r.level_name), 'field', r.primary_field_name,
    'duration_value', r.duration_value, 'duration_unit', r.duration_unit, 'delivery_mode', r.delivery_mode, 'study_load', r.study_load,
    'open_to_international', r.open_to_international,
    'description', coalesce(nullif(btrim(r.description), ''), nullif(btrim(r.doc_description), '')),
    'official_url', coalesce(r.official_course_url, r.course_url),
    'primary_fee', portal.primary_fee_v1(r.provider_tuition_options, r.provider_annual_tuition_amount, r.provider_annual_tuition_currency),  -- s1222
    'regulator', portal.regulator_code_v1(r.id),
    'provider_website', nullif(btrim(r.provider_website_url), ''),
    'entry_matrix', v_matrix,
    'entry_matrix_total', v_matrix_total,
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

create or replace function public.portal_saved_list_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_today date := (now() at time zone 'Australia/Melbourne')::date;  -- fixed: Melbourne calendar day
begin
  perform security.portal_rank_v1(2);  -- fixed: Counsellor and above
  return jsonb_build_object(
    'saved_max', security.portal_setting_v1('saved_courses_max'),
    'compare_max', security.portal_setting_v1('compare_courses_max'),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'course_id', c.id, 'saved_at', sc.saved_at,
        'title', coalesce(nullif(c.display_title, ''), c.canonical_title), 'course_code', c.course_code, 'course_url', c.course_url,
        'level', sl.name, 'duration_value', c.duration_value, 'duration_unit', c.duration_unit, 'delivery_mode', c.delivery_mode,
        'active', c.lifecycle_status = 'active', 'published', c.publication_status = 'published', 'last_verified_at', c.last_verified_at,
        'provider_id', p.id, 'provider_name', coalesce(nullif(p.display_name, ''), p.canonical_name), 'country_code', co.iso_alpha2,
        'state_code', sd.code, 'state_name', sd.name, 'city', p.primary_city,
        'fee', security.admin_course_fee_summary(c.id) -> 'fee_used',
        'primary_fee', portal.primary_fee_v1(dd.provider_tuition_options, dd.provider_annual_tuition_amount, dd.provider_annual_tuition_currency),  -- s1222
        'regulator', portal.regulator_code_v1(c.id),
        'next_intake', (select jsonb_build_object('label', i.intake_label, 'start_date', i.start_date, 'deadline', i.application_deadline, 'status', i.status)
                          from catalogue.course_intakes i
                         where i.course_id = c.id and i.status = 'active' and (i.start_date is null or i.start_date >= v_today)
                         order by i.start_date nulls last, i.id limit 1))
        order by sc.saved_at desc, c.id)
      from portal.saved_courses sc
      join catalogue.courses c on c.id = sc.course_id
      join catalogue.providers p on p.id = c.provider_id
      left join ref.study_levels sl on sl.id = c.study_level_id
      left join ref.countries co on co.id = p.country_id
      left join ref.subdivisions sd on sd.id = p.subdivision_id
      left join search.course_documents dd on dd.course_id = c.id
     where sc.user_id = auth.uid()), '[]'::jsonb));
end $function$;

-- one course's entry matrix for one student country (with the rows naming no country), never cut by the detail cap
create or replace function portal.entry_matrix_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_id uuid := case when btrim(coalesce(p_args->>'course_id', '')) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then btrim(p_args->>'course_id')::uuid end;
        v_src text := case when upper(btrim(coalesce(p_args->>'source_country', ''))) ~ '^[A-Z]{2}$' then upper(btrim(p_args->>'source_country')) end;
        r record; v_rows jsonb;
begin
  if v_id is null or not portal.course_in_scope_v1(v_id) then raise exception 'course not found' using errcode = 'P0002'; end if;
  select c.id, c.provider_id, c.study_level_id, sl.parent_id level_parent_id into r
    from catalogue.courses c left join ref.study_levels sl on sl.id = c.study_level_id where c.id = v_id;
  select coalesce(jsonb_agg(jsonb_build_object('country_code', x.country_code, 'country_name', x.country_name, 'qualification', x.qualification_name,
           'min_grade', x.min_grade, 'min_value', x.min_value, 'grade_scale', x.grade_scale, 'benchmark_band', x.benchmark_band,
           'level_label', x.level_label, 'course_label', x.course_label, 'for_this_course', x.scope = 'course', 'scope', x.scope, 'audience', x.audience,
           'edition', x.edition, 'intake_year', x.intake_year, 'conditions', x.conditions, 'as_at', x.as_at, 'source_url', x.source_url)
           order by case x.scope when 'course' then 1 when 'study_level' then 2 else 3 end, (x.country_code is null), x.qualification_name, x.id), '[]'::jsonb)
    into v_rows
    from (select m.*, co.name country_name,
                 case when m.course_id is not null then 'course' when m.study_level_id is not null then 'study_level' else 'provider' end scope
            from catalogue.provider_entry_matrix m left join ref.countries co on co.id = m.country_id
            left join ref.study_levels ml on ml.id = m.study_level_id
           where m.provider_id = r.provider_id and m.status = 'active' and coalesce(m.audience, 'all') in ('international', 'all')
             and (v_src is null or m.country_code is null or m.country_code = v_src)
             and (m.course_id = r.id
                  or (m.course_id is null and (m.study_level_id is null or m.study_level_id = r.study_level_id or m.study_level_id = r.level_parent_id or ml.parent_id = r.study_level_id)))) x;
  return jsonb_build_object('course_id', v_id, 'source_country', v_src, 'rows', v_rows,
    'country_rows', (select count(*) from jsonb_array_elements(v_rows) e where e->>'country_code' is not null),
    'provider_has_matrix', exists (select 1 from catalogue.provider_entry_matrix m where m.provider_id = r.provider_id and m.status = 'active'));
end $function$;

create or replace function public.portal_entry_matrix_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
begin
  perform security.portal_rank_v1(1);  -- fixed: Viewer and above
  return portal.entry_matrix_v1(coalesce(p_args, '{}'::jsonb));
end $function$;

comment on function public.portal_entry_matrix_v1(jsonb) is 'CF-247 s1222: one course''s entry requirements by country for one student country, with the rows naming no country (Viewer and above).';
revoke all on function portal.primary_fee_v1(jsonb, numeric, text), portal.regulator_code_v1(uuid), portal.entry_matrix_v1(jsonb),
                       portal.course_detail_v1(uuid), portal.aer_list_v1(jsonb) from public, anon, authenticated;
revoke all on function public.portal_entry_matrix_v1(jsonb) from public, anon;
grant execute on function public.portal_entry_matrix_v1(jsonb) to authenticated;

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('function', 'public.portal_entry_matrix_v1', 'Service', 'Portal', 'Portal Course details: entry requirements by country for one student country', 'active', '{}', '20261129130000')
on conflict do nothing;

do $post$
declare v jsonb := security.consumer_api_check_v1(); v_id uuid; v_src text; x jsonb; f jsonb; y int := extract(year from now() at time zone 'Australia/Melbourne')::int;
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'post-check: consumer API baseline changed: %', v;
  end if;
  if (select count(*) from cron.job where active) <> (select cron_before from s1222_guard) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1222_guard) then raise exception 'post-check: manual locks changed'; end if;
  if has_function_privilege('anon', 'public.portal_entry_matrix_v1(jsonb)', 'execute') or not has_function_privilege('authenticated', 'public.portal_entry_matrix_v1(jsonb)', 'execute') then
    raise exception 'post-check: execute privileges are not as released';
  end if;
  -- the current year's fee wins over a later one; a later one over an earlier one
  f := portal.primary_fee_v1(jsonb_build_array(jsonb_build_object('basis', 'annual', 'amount', 2, 'currency', 'AUD', 'fee_year', y + 1), jsonb_build_object('basis', 'annual', 'amount', 1, 'currency', 'AUD', 'fee_year', y)), null, null);
  if (f->>'year')::int <> y or (f->>'per_year')::numeric <> 1 then raise exception 'post-check: the current year''s fee was not chosen: %', f; end if;
  f := portal.primary_fee_v1(jsonb_build_array(jsonb_build_object('basis', 'annual', 'amount', 3, 'fee_year', y - 1), jsonb_build_object('basis', 'annual', 'amount', 4, 'fee_year', y + 2)), null, 'AUD');
  if (f->>'year')::int <> y + 2 then raise exception 'post-check: a later year should win over an earlier one: %', f; end if;
  -- a course with a CRICOS code and a country row reads its code and its country's rows
  select m.course_id, m.country_code into v_id, v_src from catalogue.provider_entry_matrix m join search.course_documents d on d.course_id = m.course_id
   where m.status = 'active' and m.country_code is not null and exists (select 1 from catalogue.course_registrations r where r.course_id = m.course_id and r.scheme = 'cricos' and r.status = 'active') limit 1;
  x := portal.course_detail_v1(v_id);
  if x->'regulator'->>'label' <> 'CRICOS' or not (x ? 'primary_fee') then raise exception 'post-check: course detail lacks the regulator code or primary fee: %', left(x::text, 300); end if;
  x := portal.entry_matrix_v1(jsonb_build_object('course_id', v_id, 'source_country', v_src));
  if (x->>'country_rows')::int = 0 or exists (select 1 from jsonb_array_elements(x->'rows') e where e->>'country_code' is not null and e->>'country_code' <> v_src) then
    raise exception 'post-check: the country''s matrix rows are not returned: %', left(x::text, 300);
  end if;
  x := portal.aer_list_v1(jsonb_build_object('country', 'AU', 'has', 'both'));
  if not ((x->'items'->0) ? 'regulator') then raise exception 'post-check: entry requirements rows lack the regulator code'; end if;
end $post$;
