-- CF-247 s1216 (S2-Build; Atlas brief 26 Nov 2026 13:07 AEDT: the four fields S1-API-Frontend-Delivery recorded in the plan (item 13) after
-- wiring s1214 into its Course details panel and Entry Requirements screen, Pilot s1215 #1657). Version above main's 20261129090000 (s1215).
-- Adds to the two s1214 reads (same function names and arguments, additive keys only):
--   public.portal_course_detail_v1:
--     provider_website   the provider's own website (catalogue.providers.website), null when not held
--     entry_matrix       the provider's country-by-country entry requirements for this course, from catalogue.provider_entry_matrix (active rows,
--                        international or all applicants): rows naming the course first, then rows for the course's study level (or the level above
--                        or below it) that name no course, and provider-wide rows naming neither, by country; each {country_code, country_name, qualification, min_grade, min_value,
--                        grade_scale, benchmark_band, level_label, course_label, for_this_course, audience, edition, intake_year, conditions,
--                        as_at, source_url}; at most portal.entry_matrix_max_rows (new G2 setting, 300)
--     entry_matrix_total how many matrix rows matched before the cap
--   public.portal_aer_list_v1 items:
--     city, state_code   the course's primary campus, else the provider's own city and state
--     duration_value, duration_unit   the course length, as the detail read gives it (the screens' durationText reads these two)
--     annual_tuition_fee {amount, currency}: the provider's annual tuition the search shows, null when not held
-- Values the catalogue does not hold stay null ("Not recorded"). The live bodies are replaced only if they are the s1214 text (md5 598c749f...
-- and 764a2dec...). Not the consumer API (G3 checked). G1: no job. G2: one setting. Locks untouched. Nothing dropped. US$0.
-- Replaces: portal.course_detail_v1 and portal.aer_list_v1 s1214 bodies (without the provider website, entry matrix, city, length and fee).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function replace

create temp table s1216_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before;

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (select md5(prosrc) from pg_proc where oid = 'portal.course_detail_v1(uuid)'::regprocedure) <> '598c749fa25bc54934aa673399cda5fe'
     or (select md5(prosrc) from pg_proc where oid = 'portal.aer_list_v1(jsonb)'::regprocedure) <> '764a2dec6fec651d6f08bdff315741f0' then
    raise exception 'pre-check: the portal reads are not the s1214 bodies this change was written against';
  end if;
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
end $pre$;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('portal', 'entry_matrix_max_rows', 'Course details: most entry matrix rows',
        'The most rows of a provider''s country-by-country entry requirements shown in one course''s details (rows naming the course first, then by country). The total found is shown beside them.',
        'number', to_jsonb(300), 20, 2000, 'rows', 6161, 'Portal', 'public.portal_course_detail_v1',
        'CF-247 s1216 (Atlas brief 26 Nov 2026 13:07 AEDT): entry matrix in the Course details panel')
on conflict do nothing;

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
           'level_label', x.level_label, 'course_label', x.course_label, 'for_this_course', x.for_course, 'audience', x.audience,
           'edition', x.edition, 'intake_year', x.intake_year, 'conditions', x.conditions, 'as_at', x.as_at, 'source_url', x.source_url)
           order by x.rn) filter (where x.rn <= v_matrix_max), '[]'::jsonb), coalesce(max(x.total), 0)
    into v_matrix, v_matrix_total
    from (select m.*, co.name country_name, m.course_id is not distinct from r.id for_course,
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
           'annual_tuition_fee', case when d.provider_annual_tuition_amount is not null then jsonb_build_object('amount', d.provider_annual_tuition_amount, 'currency', d.provider_annual_tuition_currency) end,
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

revoke all on function portal.course_detail_v1(uuid), portal.aer_list_v1(jsonb) from public, anon, authenticated;

do $post$
declare v jsonb := security.consumer_api_check_v1(); v_id uuid; x jsonb; y jsonb;
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'post-check: consumer API baseline changed: %', v;
  end if;
  if (select count(*) from cron.job where active) <> (select cron_before from s1216_guard) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1216_guard) then raise exception 'post-check: manual locks changed'; end if;
  if has_function_privilege('anon', 'public.portal_course_detail_v1(uuid)', 'execute') or has_function_privilege('authenticated', 'portal.course_detail_v1(uuid)', 'execute') then
    raise exception 'post-check: execute privileges changed';
  end if;
  -- a course whose provider has an active entry matrix for its level returns the new keys
  select d.course_id into v_id from search.course_documents d join catalogue.courses c on c.id = d.course_id and c.lifecycle_status = 'active'
   where exists (select 1 from catalogue.provider_entry_matrix m where m.provider_id = c.provider_id and m.status = 'active' and m.course_id is null and m.study_level_id = c.study_level_id) limit 1;
  x := portal.course_detail_v1(v_id);
  if not (x ? 'provider_website' and x ? 'entry_matrix' and x ? 'entry_matrix_total') or jsonb_array_length(x->'entry_matrix') = 0
     or jsonb_array_length(x->'entry_matrix') > security.portal_setting_v1('entry_matrix_max_rows') then
    raise exception 'post-check: course detail lacks the entry matrix: %', left(x::text, 300);
  end if;
  y := portal.aer_list_v1(jsonb_build_object('country', 'AU', 'has', 'both'));
  if not ((y->'items'->0) ? 'city' and (y->'items'->0) ? 'duration_value' and (y->'items'->0) ? 'duration_unit' and (y->'items'->0) ? 'annual_tuition_fee') then
    raise exception 'post-check: entry requirements rows lack city, length or fee: %', left((y->'items'->0)::text, 300);
  end if;
end $post$;
