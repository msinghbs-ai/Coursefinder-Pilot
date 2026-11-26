-- CF-247 s1213 (S1-API-Frontend-Delivery; Atlas brief for the Platform Admin, 26 Nov 2026 12:02 AEDT, from the live UAT of studysearch-portal.techm.workers.dev):
-- the read side of two portal screens that did not exist: the expandable Course details panel (Courses and Saved courses) and the new
-- Entry Requirements (AER) screen. Both read rows the platform already holds; nothing is written, nothing is calculated, nothing is dropped.
-- Version above main's and the live head, 20261129061000.
--
-- What is added
--   public.portal_course_detail_v1(p_args jsonb)         one course in full: overview, campuses and delivery, fees as recorded (annual and whole-course lines,
--                                                          never added together), intakes and deadlines, entry requirements for the student's country, English,
--                                                          the provider's career-outcome figures (labelled provider-level), and the official source link.
--   public.portal_entry_requirements_v1(p_args jsonb)    courses that hold a recorded academic or English requirement, searched by destination country,
--                                                          study level, provider or course text and the student's country of education, with each course's entry lines.
--   catalogue.portal_course_detail_v1 / catalogue.portal_entry_requirements_v1 and three internal row helpers do the work.
-- Access: both public functions check the person's own role through security.portal_rank_v1(1) (Viewer and above, as every portal read); execute is
-- granted to authenticated only, anon and public have none. The Save and Add to proposal buttons stay Counsellor-only in the screens, as before.
-- Visibility is the search's own: catalogue.courses.lifecycle_status = 'active' and, when portal_search.visibility_scope = 'published', publication_status
-- = 'published'; the course must have its search document and an active provider. Admitted rows only (status 'active'); audience all or international;
-- a requirement with a country applies to that country only. A value the platform does not hold is returned null or as an empty list, never a guess.
-- Settings (G2): two row caps in toolset portal_search, each with label, range, unit and used_by, read through security.portal_search_num_v1; the page
-- size is the search's own result_page_size. G1: no job. G3: only new portal_* functions; no website_v2_*, website_edge_*, website_api_v2_*,
-- zoho_edge_*, api.* object or edge function is touched. Locks untouched. Spend $0.
--
-- Replaces: nothing (no portal course-detail or entry-requirements read existed)
-- Retires: nothing

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
 ('portal_search', 'entry_rows_per_course', 'Entry Requirements: lines shown per course', 'How many academic entry lines and English lines the Entry Requirements list shows under each course (the full course panel shows more).', 'number', '6'::jsonb, 1, 20, 'lines', 6285, 'Portal search', 'catalogue.portal_entry_requirements_v1', 'CF-247 s1213'),
 ('portal_search', 'detail_rows_max', 'Course details: rows shown per section', 'The most rows the Course details panel returns for each section (campuses, fees, intakes, entry lines, English, outcome figures).', 'number', '40'::jsonb, 10, 100, 'rows', 6295, 'Portal search', 'catalogue.portal_course_detail_v1', 'CF-247 s1213')
on conflict do nothing;

-- Internal helper 1: the course's own entry lines for a student's country (null = every line that applies to all countries or to any).
create or replace function catalogue.portal_course_entry_rows_v1(p_course uuid, p_market_country uuid, p_max integer)
returns jsonb language sql stable security definer set search_path = '' as $function$
  select coalesce(jsonb_agg(x.j order by x.o1 desc, x.o2 desc, x.o3, x.o4 desc nulls last, x.id), '[]'::jsonb)
    from (select r.id,
                 (rc.iso_alpha2 is not null) as o1, (r.audience = 'international') as o2, r.kind as o3, r.as_at as o4,
                 jsonb_build_object('kind', r.kind, 'audience', r.audience, 'country_code', rc.iso_alpha2, 'description', nullif(btrim(r.description), ''),
                                    'min_grade', nullif(btrim(r.min_grade), ''), 'min_value', r.min_value, 'grade_scale', nullif(btrim(r.grade_scale), ''),
                                    'min_entry_score', r.min_entry_score, 'basis', nullif(btrim(r.min_entry_score_basis), ''), 'benchmark_band', nullif(btrim(r.benchmark_band), ''),
                                    'quote', nullif(btrim(r.quote), ''), 'source_url', nullif(btrim(r.source_url), ''), 'as_at', r.as_at) as j
            from catalogue.course_entry_requirements r
            left join ref.countries rc on rc.id = r.country_id
           where r.course_id = p_course and r.status = 'active' and r.audience in ('all', 'international')
             and (p_market_country is null or r.country_id is null or r.country_id = p_market_country)
             and coalesce(nullif(btrim(r.description), ''), nullif(btrim(r.min_grade), ''), nullif(btrim(r.min_entry_score_basis), ''), nullif(btrim(r.quote), ''), r.min_value::text, r.min_entry_score::text) is not null
           order by (rc.iso_alpha2 is not null) desc, (r.audience = 'international') desc, r.kind, r.as_at desc nulls last, r.id
           limit greatest(p_max, 1)) x  -- fixed: a row count of at least one
$function$;

-- Internal helper 2: the provider's published entry matrix for one country of education, for this course (or the provider's level rows).
create or replace function catalogue.portal_provider_entry_rows_v1(p_provider uuid, p_course uuid, p_level uuid, p_market text, p_max integer)
returns jsonb language sql stable security definer set search_path = '' as $function$
  select coalesce(jsonb_agg(x.j order by x.o1 desc, x.o2, x.o3, x.id), '[]'::jsonb)
    from (select m.id, (m.course_id is not null) as o1, m.matrix_kind as o2, m.qualification_name as o3,
                 jsonb_build_object('matrix_kind', m.matrix_kind, 'country_code', m.country_code, 'qualification', nullif(btrim(m.qualification_name), ''),
                                    'level_label', nullif(btrim(m.level_label), ''), 'min_grade', nullif(btrim(m.min_grade), ''), 'min_value', m.min_value,
                                    'grade_scale', nullif(btrim(m.grade_scale), ''), 'benchmark_band', nullif(btrim(m.benchmark_band), ''), 'quote', nullif(btrim(m.quote), ''),
                                    'for_this_course', m.course_id is not null, 'source_url', nullif(btrim(m.source_url), ''), 'as_at', m.as_at) as j
            from catalogue.provider_entry_matrix m
           where p_market is not null and m.provider_id = p_provider and m.status = 'active' and m.audience = 'international' and m.country_code = p_market
             and (m.course_id = p_course
                  or (m.course_id is null and (m.study_level_id is null or m.study_level_id = p_level
                       or m.study_level_id = (select sl.parent_id from ref.study_levels sl where sl.id = p_level))))
           order by (m.course_id is not null) desc, m.matrix_kind, m.qualification_name, m.id
           limit greatest(p_max, 1)) x  -- fixed: a row count of at least one
$function$;

-- Internal helper 3: the course's English requirements as recorded.
create or replace function catalogue.portal_course_english_rows_v1(p_course uuid, p_max integer)
returns jsonb language sql stable security definer set search_path = '' as $function$
  select coalesce(jsonb_agg(x.j order by x.o1 desc, x.o2, x.id), '[]'::jsonb)
    from (select e.id, (t.code = 'IELTS') as o1, t.name as o2,
                 jsonb_build_object('test_code', t.code, 'test_name', t.name, 'overall_score', e.overall_score, 'component_scores', e.component_scores,
                                    'score_grade', nullif(btrim(e.score_grade), ''), 'subtest_grades', e.subtest_grades, 'last_verified_at', e.last_verified_at) as j
            from catalogue.course_english_requirements e
            join ref.english_tests t on t.id = e.english_test_id
           where e.course_id = p_course and e.status = 'active'
           order by (t.code = 'IELTS') desc, t.name, e.id
           limit greatest(p_max, 1)) x  -- fixed: a row count of at least one
$function$;

create or replace function catalogue.portal_course_detail_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_a jsonb := case when jsonb_typeof(p_args) = 'object' then p_args else '{}'::jsonb end;
  v_id uuid := case when v_a->>'course_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (v_a->>'course_id')::uuid end;
  v_market text := case when upper(btrim(coalesce(v_a->>'market', ''))) ~ '^[A-Z]{2}$' then upper(btrim(v_a->>'market')) end;
  v_scope text := security.portal_search_text_v1('visibility_scope', 'active');
  v_max integer := greatest(security.portal_search_num_v1('detail_rows_max', 40)::int, 1);  -- fixed: a row count of at least one
  v_today date := (now() at time zone 'Australia/Melbourne')::date;  -- fixed: Melbourne day
  v_mc uuid;
  v_c catalogue.courses%rowtype; v_p catalogue.providers%rowtype; v_d search.course_documents%rowtype;
  v_level_name text; v_parent uuid; v_country text;
begin
  if v_id is null then raise exception 'INVALID_INPUT: course_id is required' using errcode = '22023'; end if;
  select c.* into v_c from catalogue.courses c
   where c.id = v_id and c.lifecycle_status = 'active' and (v_scope <> 'published' or c.publication_status = 'published');
  if not found then return jsonb_build_object('found', false); end if;
  select d.* into v_d from search.course_documents d where d.course_id = v_id;
  if not found then return jsonb_build_object('found', false); end if;
  select p.* into v_p from catalogue.providers p where p.id = v_c.provider_id and p.lifecycle_status = 'active';
  if not found then return jsonb_build_object('found', false); end if;
  select sl.name, sl.parent_id into v_level_name, v_parent from ref.study_levels sl where sl.id = v_c.study_level_id;
  select co.iso_alpha2 into v_country from ref.countries co where co.id = v_p.country_id;
  if v_market is not null then select co.id into v_mc from ref.countries co where co.iso_alpha2 = v_market; end if;

  return jsonb_build_object(
    'found', true,
    'market', v_market,
    'course', jsonb_build_object(
      'course_id', v_c.id,
      'title', coalesce(nullif(v_c.display_title, ''), v_c.canonical_title),
      'code', nullif(btrim(v_c.course_code), ''),
      'level', v_level_name, 'level_code', v_d.study_level_code,
      'description', coalesce(nullif(btrim(v_d.description), ''), nullif(btrim(v_c.description), '')),
      'duration_value', v_c.duration_value, 'duration_unit', v_c.duration_unit,
      'delivery_mode', nullif(v_c.delivery_mode, ''), 'study_load', nullif(v_c.study_load, ''),
      'open_to_international', v_c.open_to_international,
      'course_url', coalesce(nullif(btrim(v_d.official_course_url), ''), nullif(btrim(v_c.course_url), '')),
      'last_verified_at', v_c.last_verified_at,
      'provider', jsonb_build_object('id', v_p.id, 'name', coalesce(nullif(v_p.display_name, ''), v_p.canonical_name), 'website', nullif(btrim(v_p.website), ''), 'country_code', v_country)),
    'campuses', (select coalesce(jsonb_agg(x.j order by x.o1 desc nulls last, x.o2), '[]'::jsonb)
                   from (select cc.is_primary o1, ca.name o2,
                                jsonb_build_object('name', ca.name, 'city', ca.city, 'state_code', s.code, 'country_code', co.iso_alpha2,
                                                   'delivery_mode', nullif(cc.delivery_mode, ''), 'is_primary', cc.is_primary,
                                                   'accepts_international', ca.accepts_international, 'website', nullif(btrim(ca.website), '')) j
                           from catalogue.course_campuses cc
                           join catalogue.campuses ca on ca.id = cc.campus_id and ca.status = 'active'
                           left join ref.subdivisions s on s.id = ca.subdivision_id
                           left join ref.countries co on co.id = ca.country_id
                          where cc.course_id = v_id
                          order by cc.is_primary desc nulls last, ca.name
                          limit v_max) x),
    'fees', (select coalesce(jsonb_agg(x.j order by x.o1, x.o2 desc nulls last, x.o3), '[]'::jsonb)
               from (select case f.fee_type when 'provider_current_tuition' then 1 when 'tuition' then 2 when 'estimated_total_course_cost' then 3 else 4 end o1,
                            f.fee_year o2, f.fee_type o3,
                            jsonb_build_object('fee_type', f.fee_type, 'basis', nullif(btrim(f.basis), ''),
                                               'period', case when f.basis ~* 'annual' then 'year' when f.basis ~* 'total' then 'course' end,
                                               'amount', f.amount, 'currency', f.currency_code, 'fee_year', f.fee_year,
                                               'campus', (select ca.name from catalogue.campuses ca where ca.id = f.campus_id),
                                               'notes', nullif(btrim(f.notes), ''), 'last_verified_at', f.last_verified_at) j
                       from catalogue.course_fees f
                      where f.course_id = v_id and f.status = 'active' and f.audience in ('international', 'all') and f.amount is not null
                      order by 1, f.fee_year desc nulls last, f.fee_type
                      limit v_max) x),
    'intakes', (select coalesce(jsonb_agg(x.j order by x.o1 nulls last, x.o2, x.o3), '[]'::jsonb)
                  from (select i.start_date o1, i.intake_year o2, i.intake_label o3,
                               jsonb_build_object('label', nullif(btrim(i.intake_label), ''), 'year', i.intake_year, 'start_date', i.start_date,
                                                  'application_deadline', i.application_deadline,
                                                  'campus', (select ca.name from catalogue.campuses ca where ca.id = i.campus_id)) j
                          from catalogue.course_intakes i
                         where i.course_id = v_id and i.status = 'active' and (i.start_date is null or i.start_date >= v_today)
                         order by i.start_date nulls last, i.intake_year, i.intake_label
                         limit v_max) x),
    'entry', catalogue.portal_course_entry_rows_v1(v_id, v_mc, v_max),
    'provider_entry', catalogue.portal_provider_entry_rows_v1(v_p.id, v_id, v_c.study_level_id, v_market, v_max),
    'provider_entry_countries', (select count(distinct m.country_code) from catalogue.provider_entry_matrix m
                                  where m.provider_id = v_p.id and m.status = 'active' and m.audience = 'international'),
    'english', catalogue.portal_course_english_rows_v1(v_id, v_max),
    'outcomes', (select coalesce(jsonb_agg(x.j order by x.o1, x.o2), '[]'::jsonb)
                   from (select distinct on (m.id) case m.category when 'employment' then 1 when 'salary' then 2 when 'employer_satisfaction' then 3 else 4 end o1, m.name o2,
                                jsonb_build_object('metric', m.code, 'name', m.name, 'category', m.category, 'unit', m.unit, 'value', o.metric_value,
                                                   'year_from', o.collection_year_from, 'year_to', o.collection_year_to, 'responses', o.response_count,
                                                   'national_benchmark', o.national_benchmark, 'level', 'provider') j
                           from catalogue.provider_outcomes o
                           join ref.outcome_metrics m on m.id = o.metric_id
                          where o.provider_id = v_p.id and o.status = 'current' and o.audience = 'all'
                            and o.external_study_area_id is null and o.study_level_id is null
                            and m.category in ('employment', 'salary', 'employer_satisfaction', 'experience')
                          order by m.id, o.collection_year_to desc nulls last, o.observed_at desc nulls last
                          limit v_max) x));
end $function$;

create or replace function catalogue.portal_entry_requirements_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_a jsonb := case when jsonb_typeof(p_args) = 'object' then p_args else '{}'::jsonb end;
  v_country text := case when upper(btrim(coalesce(v_a->>'country', ''))) ~ '^[A-Z]{2}$' then upper(btrim(v_a->>'country')) end;
  v_market text := case when upper(btrim(coalesce(v_a->>'market', ''))) ~ '^[A-Z]{2}$' then upper(btrim(v_a->>'market')) end;
  v_level text := case when btrim(coalesce(v_a->>'level', '')) ~ '^[a-z0-9_]{1,60}$' then btrim(v_a->>'level') end;
  v_provider uuid := case when v_a->>'provider_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (v_a->>'provider_id')::uuid end;
  v_q text := nullif(btrim(left(coalesce(v_a->>'q', ''), least(greatest(security.portal_search_num_v1('query_max_chars', 200)::int, 20), 1000))), '');  -- fixed: the search's own bound
  v_like text;
  v_kind text := case when v_a->>'has' in ('entry', 'english') then v_a->>'has' end;
  v_page integer := greatest(coalesce(case when (v_a->>'page') ~ '^[0-9]{1,6}$' then (v_a->>'page')::int end, 1), 1);  -- fixed: first page
  v_size integer := greatest(security.portal_search_num_v1('result_page_size', 20)::int, 1);  -- fixed: a page of at least one
  v_rows integer := greatest(security.portal_search_num_v1('entry_rows_per_course', 6)::int, 1);  -- fixed: a row count of at least one
  v_scope text := security.portal_search_text_v1('visibility_scope', 'active');
  v_today date := (now() at time zone 'Australia/Melbourne')::date;  -- fixed: Melbourne day
  v_mc uuid; v_level_id uuid; v_total integer; v_out jsonb; v_levels jsonb;
begin
  if v_q is not null then v_like := security.portal_like_v1(v_q); end if;
  if v_market is not null then select co.id into v_mc from ref.countries co where co.iso_alpha2 = v_market; end if;
  if v_level is not null then select sl.id into v_level_id from ref.study_levels sl where sl.code = v_level; end if;

  with hits as materialized (
    select z.course_id, z.provider_id, z.provider_name, z.title, z.has_entry, z.has_english, z.has_matrix
      from (select d.course_id, d.provider_id, d.provider_name, d.course_title as title,
                   exists (select 1 from catalogue.course_entry_requirements r
                            where r.course_id = d.course_id and r.status = 'active' and r.audience in ('all', 'international')
                              and (v_mc is null or r.country_id is null or r.country_id = v_mc)
                              and coalesce(nullif(btrim(r.description), ''), nullif(btrim(r.min_grade), ''), nullif(btrim(r.min_entry_score_basis), ''), nullif(btrim(r.quote), ''), r.min_value::text, r.min_entry_score::text) is not null) as has_entry,
                   exists (select 1 from catalogue.course_english_requirements e where e.course_id = d.course_id and e.status = 'active') as has_english,
                   (v_market is not null and exists (select 1 from catalogue.provider_entry_matrix m
                            where m.provider_id = d.provider_id and m.status = 'active' and m.audience = 'international' and m.country_code = v_market
                              and (m.course_id = d.course_id
                                   or (m.course_id is null and (m.study_level_id is null or m.study_level_id = d.study_level_id
                                        or m.study_level_id = (select sl.parent_id from ref.study_levels sl where sl.id = d.study_level_id)))))) as has_matrix
              from search.course_documents d
              join catalogue.courses c on c.id = d.course_id and c.lifecycle_status = 'active' and (v_scope <> 'published' or c.publication_status = 'published')
              join catalogue.providers p on p.id = d.provider_id and p.lifecycle_status = 'active'
             where (v_country is null or d.country_code = v_country)
               and (v_provider is null or d.provider_id = v_provider)
               and (v_level is null or d.study_level_code = v_level or d.study_level_id in (select sl.id from ref.study_levels sl where sl.parent_id = v_level_id))
               and (v_q is null or d.course_title ilike v_like or d.provider_name ilike v_like)) z
     where case v_kind when 'entry' then z.has_entry or z.has_matrix when 'english' then z.has_english else z.has_entry or z.has_english or z.has_matrix end),
  pg as (select * from hits order by provider_name, title, course_id offset (v_page - 1) * v_size limit v_size)
  select (select count(*) from hits),
         coalesce((select jsonb_agg(x.j order by x.o1, x.o2, x.o3)
                     from (select h.provider_name o1, h.title o2, h.course_id o3,
                                  jsonb_build_object(
                                    'course_id', c.id, 'title', coalesce(nullif(c.display_title, ''), c.canonical_title),
                                    'provider_id', p.id, 'provider_name', coalesce(nullif(p.display_name, ''), p.canonical_name),
                                    'level', sl.name, 'country_code', d.country_code,
                                    'state_code', cam.state_code, 'city', coalesce(cam.city, p.primary_city),
                                    'duration_value', c.duration_value, 'duration_unit', c.duration_unit,
                                    'fee', case when d.provider_annual_tuition_amount is not null then jsonb_build_object('per_year', d.provider_annual_tuition_amount, 'currency', d.provider_annual_tuition_currency) end,
                                    'next_intake', (select jsonb_build_object('label', i.intake_label, 'start_date', i.start_date) from catalogue.course_intakes i
                                                     where i.course_id = c.id and i.status = 'active' and (i.start_date is null or i.start_date >= v_today)
                                                     order by i.start_date nulls last, i.id limit 1),
                                    'course_url', coalesce(nullif(btrim(d.official_course_url), ''), nullif(btrim(c.course_url), '')),
                                    'entry', case when h.has_entry then catalogue.portal_course_entry_rows_v1(c.id, v_mc, v_rows) else '[]'::jsonb end,
                                    'provider_entry', case when h.has_matrix then catalogue.portal_provider_entry_rows_v1(p.id, c.id, c.study_level_id, v_market, v_rows) else '[]'::jsonb end,
                                    'english', case when h.has_english then catalogue.portal_course_english_rows_v1(c.id, v_rows) else '[]'::jsonb end) j
                             from pg h
                             join catalogue.courses c on c.id = h.course_id
                             join catalogue.providers p on p.id = h.provider_id
                             join search.course_documents d on d.course_id = c.id
                             left join ref.study_levels sl on sl.id = c.study_level_id
                             left join lateral (select ca.city, s.code state_code from catalogue.course_campuses cc join catalogue.campuses ca on ca.id = cc.campus_id left join ref.subdivisions s on s.id = ca.subdivision_id
                                                 where cc.course_id = c.id order by cc.is_primary desc nulls last, ca.city limit 1) cam on true) x), '[]'::jsonb)
    into v_total, v_out;

  if coalesce((v_a->>'lookups')::boolean, false) then
    select coalesce(jsonb_agg(jsonb_build_object('code', l.code, 'name', l.name, 'courses', l.n) order by l.sort_order, l.name), '[]'::jsonb) into v_levels
      from (select sl.code, sl.name, sl.sort_order, count(*) n
              from search.course_documents d join ref.study_levels sl on sl.code = d.study_level_code
             where sl.status = 'active' group by sl.code, sl.name, sl.sort_order) l;
  end if;

  return jsonb_build_object('total', v_total, 'page', v_page, 'page_size', v_size, 'market', v_market, 'country', v_country, 'level', v_level,
                            'results', v_out) || case when v_levels is not null then jsonb_build_object('levels', v_levels) else '{}'::jsonb end;
end $function$;

create or replace function public.portal_course_detail_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
begin
  perform security.portal_rank_v1(1);  -- fixed: Viewer and above
  return catalogue.portal_course_detail_v1(coalesce(p_args, '{}'::jsonb));
end $function$;

create or replace function public.portal_entry_requirements_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
begin
  perform security.portal_rank_v1(1);  -- fixed: Viewer and above
  return catalogue.portal_entry_requirements_v1(coalesce(p_args, '{}'::jsonb));
end $function$;

comment on function public.portal_course_detail_v1(jsonb) is 'CF-247 s1213: one course in full for the portal Course details panel: overview, campuses and delivery, fee lines as recorded (annual and whole-course, never added), intakes and deadlines, entry lines (for the student''s country when given), English, provider-level career-outcome figures, source link. Read only; Viewer and above.';
comment on function public.portal_entry_requirements_v1(jsonb) is 'CF-247 s1213: the portal Entry Requirements screen: courses holding a recorded academic or English requirement, by destination country, study level, provider or course text and the student''s country of education, with each course''s entry lines. Read only; Viewer and above.';
comment on function catalogue.portal_course_detail_v1(jsonb) is 'CF-247 s1213: implementation of public.portal_course_detail_v1 (visibility as the portal search: active course, active provider, search document, visibility_scope).';
comment on function catalogue.portal_entry_requirements_v1(jsonb) is 'CF-247 s1213: implementation of public.portal_entry_requirements_v1.';
comment on function catalogue.portal_course_entry_rows_v1(uuid, uuid, integer) is 'CF-247 s1213: a course''s admitted entry lines for a student''s country (internal).';
comment on function catalogue.portal_provider_entry_rows_v1(uuid, uuid, uuid, text, integer) is 'CF-247 s1213: a provider''s admitted entry-matrix lines for one country of education (internal).';
comment on function catalogue.portal_course_english_rows_v1(uuid, integer) is 'CF-247 s1213: a course''s admitted English requirements (internal).';

revoke all on function public.portal_course_detail_v1(jsonb), public.portal_entry_requirements_v1(jsonb) from public, anon;
grant execute on function public.portal_course_detail_v1(jsonb), public.portal_entry_requirements_v1(jsonb) to authenticated;
revoke all on function catalogue.portal_course_detail_v1(jsonb), catalogue.portal_entry_requirements_v1(jsonb), catalogue.portal_course_entry_rows_v1(uuid, uuid, integer),
                       catalogue.portal_provider_entry_rows_v1(uuid, uuid, uuid, text, integer), catalogue.portal_course_english_rows_v1(uuid, integer)
  from public, anon, authenticated;

-- Post-check: the two settings exist, anon cannot execute, and the sample course (a masters course with fees, English and entry lines) reads back whole.
do $post$
declare x jsonb; n integer;
begin
  select count(*) into n from pipeline.platform_toolset_settings where toolset_key = 'portal_search' and key in ('entry_rows_per_course', 'detail_rows_max');
  if n <> 2 then raise exception 's1213 post-check: expected 2 settings, found %', n; end if;
  if has_function_privilege('anon', 'public.portal_course_detail_v1(jsonb)', 'execute') or has_function_privilege('anon', 'public.portal_entry_requirements_v1(jsonb)', 'execute') then
    raise exception 's1213 post-check: anon can execute a portal function';
  end if;
  if not has_function_privilege('authenticated', 'public.portal_course_detail_v1(jsonb)', 'execute') or not has_function_privilege('authenticated', 'public.portal_entry_requirements_v1(jsonb)', 'execute') then
    raise exception 's1213 post-check: authenticated cannot execute a portal function';
  end if;
  x := catalogue.portal_course_detail_v1(jsonb_build_object('course_id', '66826f02-4280-4824-a4e1-e1eeded80a70'));
  if (x->>'found')::boolean is not true or jsonb_array_length(x->'fees') = 0 or jsonb_array_length(x->'english') = 0 or jsonb_array_length(x->'entry') = 0 then
    raise exception 's1213 post-check: the sample course did not read back whole: %', left(x::text, 300);
  end if;
  x := catalogue.portal_entry_requirements_v1(jsonb_build_object('country', 'AU', 'level', 'masters', 'lookups', true));
  if coalesce((x->>'total')::int, 0) = 0 or jsonb_array_length(x->'levels') = 0 then
    raise exception 's1213 post-check: the entry-requirements search found nothing: %', left(x::text, 300);
  end if;
end $post$;
