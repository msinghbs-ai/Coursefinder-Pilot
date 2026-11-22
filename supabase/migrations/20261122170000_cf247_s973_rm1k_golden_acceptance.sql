-- CF-247 s973 (session S1-API-Frontend-Delivery, consolidated batch Part 2; Platform Admin 22 Nov 2026 14:22 AEDT): RM1K (IR-002), golden
-- acceptance of the Australia page across Admin and Website API v3.
-- public.admin_golden_acceptance_v1(records) reads the golden records (fixture tests/fixtures/rm1k/australia-golden.json) through Admin
-- (admin_read course_detail and the tables Admin shows) and through Website API v3 (website_v3_course, website_v3_destination), and returns,
-- for each of ten sections (course detail, entry requirements, English requirements, tuition fees, scholarships, campuses, accreditations,
-- study rules, career outcomes, rankings), the fields both show and whether they agree. Read-only; Pipeline Operator and above.
-- Rehearsed live 22 Nov 2026 (rolled back): 10 of 10 sections agree. The deployed spec runs it after every deploy.
-- Consumer API untouched (G3 checked before and after; the function reads Website v3, which is not yet frozen, and changes nothing).
-- $0. G1: no new job. G2: no operational value. Locks unchanged.
-- Parity: live head 20261122150000 (s971) read 22 Nov 2026 16:20 AEDT; s972 is 20261122160000; this file is numbered above both.
-- Replaces: nothing (the RM1K acceptance read of 22 Nov 01:55 was a one-off).
-- Retires: nothing. Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s973_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s973_cron on commit drop as select count(*) n from cron.job where active;

create or replace function public.admin_golden_acceptance_v1(p_records jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
-- CF-247 s973 (RM1K, IR-002): the Australia golden records read through Admin and through Website API v3, section by section, with the
-- fields both show and whether they agree. Read-only. Pipeline Operator and above. The records come from the spec's fixture.
declare
  v_rank int := security.current_role_rank();
  v_course text := nullif(btrim(coalesce(p_records->>'course', '')), '');
  v_rule uuid := nullif(btrim(coalesce(p_records->>'study_rule_id', '')), '')::uuid;
  v_outcome uuid := nullif(btrim(coalesce(p_records->>'career_outcome_id', '')), '')::uuid;
  v_cid uuid; v_pid uuid;
  a jsonb; w jsonb; aa jsonb; ww jsonb; v_sections jsonb := '[]'::jsonb; v_d jsonb;
begin
  if auth.uid() is null then raise exception 'INVALID_INPUT: sign in first' using errcode = '42501'; end if;
  if v_rank < 4 then raise exception 'INVALID_INPUT: golden acceptance needs the Pipeline Operator role or above' using errcode = '42501'; end if;
  if v_course is null then raise exception 'INVALID_INPUT: the golden records need a course stable key'; end if;
  select c.id, c.provider_id into v_cid, v_pid from catalogue.courses c where c.stable_key = v_course;
  if v_cid is null then raise exception 'INVALID_INPUT: golden course % not found', v_course; end if;

  a := public.admin_read('course_detail', jsonb_build_object('id', v_cid));
  w := public.website_v3_course(v_course)->'item';

  -- 1. Course detail
  aa := jsonb_build_object('course_id', a->>'stable_key', 'title', coalesce(a->>'display_title', a->>'canonical_title'), 'course_code', a->>'course_code',
                           'provider', a->>'provider_name', 'level', a->>'level_code');
  ww := jsonb_build_object('course_id', w->>'course_id', 'title', w->>'title', 'course_code', w->>'course_code',
                           'provider', w->'provider'->>'name', 'level', w->'study_level'->>'code');
  v_sections := v_sections || jsonb_build_object('section', 'course_detail', 'admin', aa, 'website_v3', ww, 'present', w is not null and aa->>'title' is not null, 'match', aa = ww);

  -- 2. Entry requirements (academic): the course's active entry rows on Admin, the requirement note on the website
  aa := jsonb_build_object('notes', coalesce((select jsonb_agg(distinct btrim(r.description)) from catalogue.course_entry_requirements r where r.course_id = v_cid and r.status = 'active' and nullif(btrim(r.description), '') is not null), '[]'::jsonb));
  ww := jsonb_build_object('note', btrim(w->'entry'->>'requirements_note'));
  v_sections := v_sections || jsonb_build_object('section', 'entry_requirements', 'admin', aa, 'website_v3', ww,
    'present', jsonb_array_length(aa->'notes') > 0 and ww->>'note' is not null, 'match', (aa->'notes') ? (ww->>'note'));

  -- 3. English requirements: test and overall score
  aa := coalesce((select jsonb_agg(distinct (e->>'test_code') || ' ' || (e->>'overall_score')::numeric::text) from jsonb_array_elements(coalesce(a->'english', '[]'::jsonb)) e), '[]'::jsonb);
  ww := coalesce((select jsonb_agg(distinct (e->>'test_code') || ' ' || (e->>'min_overall_score')::numeric::text) from jsonb_array_elements(coalesce(w->'english_requirements', '[]'::jsonb)) e), '[]'::jsonb);
  v_sections := v_sections || jsonb_build_object('section', 'english_requirements', 'admin', aa, 'website_v3', ww, 'present', jsonb_array_length(ww) > 0, 'match', aa @> ww and ww @> aa);

  -- 4. Tuition fees: the website's amount is one Admin holds for the course, in the same currency
  aa := coalesce((select jsonb_agg(distinct (f->>'amount')::numeric::text || ' ' || coalesce(f->>'currency_code', f->>'currency', a->'fee_summary'->'fee_used'->>'currency', ''))
                    from jsonb_array_elements(coalesce(a->'fee_summary'->'cricos_registered', '[]'::jsonb) || coalesce(a->'fee_summary'->'provider_current', '[]'::jsonb) || coalesce(a->'fees', '[]'::jsonb)) f
                   where f->>'amount' is not null), '[]'::jsonb);
  ww := jsonb_build_object('amount', (w->'tuition'->>'amount')::numeric::text || ' ' || coalesce(w->'tuition'->>'currency', ''), 'basis', w->'tuition'->>'basis', 'source', w->'tuition'->>'source');
  v_sections := v_sections || jsonb_build_object('section', 'tuition_fees', 'admin', aa, 'website_v3', ww, 'present', ww->>'amount' is not null, 'match', aa ? (ww->>'amount'));

  -- 5. Scholarships: every scholarship the website shows for the course (name and page) is one Admin maps to it
  aa := coalesce((select jsonb_agg(distinct btrim(s->>'name') || ' | ' || coalesce(s->>'source_url', '')) from jsonb_array_elements(coalesce(a->'course_scholarships'->'items', '[]'::jsonb)) s), '[]'::jsonb);
  ww := coalesce((select jsonb_agg(distinct btrim(s->>'name') || ' | ' || coalesce(s->>'official_url', '')) from jsonb_array_elements(coalesce(w->'scholarships', '[]'::jsonb)) s), '[]'::jsonb);
  v_sections := v_sections || jsonb_build_object('section', 'scholarships', 'admin', jsonb_build_object('mapped', jsonb_array_length(aa)), 'website_v3', jsonb_build_object('shown', jsonb_array_length(ww), 'count', (w->>'scholarship_count')::int, 'scholarships', ww),
    'present', jsonb_array_length(ww) > 0, 'match', aa @> ww and jsonb_array_length(ww) = coalesce((w->>'scholarship_count')::int, -1));

  -- 6. Campuses: city and postcode
  aa := coalesce((select jsonb_agg(distinct lower(btrim(c->>'city')) || ' ' || coalesce(c->>'postcode', '')) from jsonb_array_elements(coalesce(a->'campuses', '[]'::jsonb)) c), '[]'::jsonb);
  ww := coalesce((select jsonb_agg(distinct lower(btrim(c->>'city')) || ' ' || coalesce(c->>'postcode', '')) from jsonb_array_elements(coalesce(w->'campuses', '[]'::jsonb)) c), '[]'::jsonb);
  v_sections := v_sections || jsonb_build_object('section', 'campuses', 'admin', aa, 'website_v3', ww, 'present', jsonb_array_length(ww) > 0, 'match', aa @> ww and ww @> aa);

  -- 7. Accreditations: the course registration codes the website shows are the ones Admin holds
  aa := coalesce((select jsonb_agg(distinct upper(r->>'registration_code')) from jsonb_array_elements(coalesce(a->'regulatory_facts', '[]'::jsonb)) r where r->>'registration_code' is not null), '[]'::jsonb);
  ww := coalesce((select jsonb_agg(distinct upper(r->>'code')) from jsonb_array_elements(coalesce(w->'recognition', '[]'::jsonb)) r where r->>'code' is not null), '[]'::jsonb);
  v_sections := v_sections || jsonb_build_object('section', 'accreditations', 'admin', aa, 'website_v3', ww, 'present', jsonb_array_length(ww) > 0, 'match', aa @> ww);

  -- 8. Study rules: the golden rule as the website serves it and as Admin holds it
  v_d := public.website_v3_destination(jsonb_build_object('country_code', 'au', 'section', 'study_rules'), 1, 100);
  ww := coalesce((select jsonb_build_object('rule_id', r->>'rule_id', 'title', r->>'title', 'source_url', r->>'source_url') from jsonb_array_elements(coalesce(v_d->'study_rules', '[]'::jsonb)) r where (r->>'rule_id')::uuid = v_rule limit 1), '{}'::jsonb);
  aa := coalesce((select jsonb_build_object('rule_id', s.id::text, 'title', s.title, 'source_url', s.source_url) from destination.study_rules s where s.id = v_rule), '{}'::jsonb);
  v_sections := v_sections || jsonb_build_object('section', 'study_rules', 'admin', aa, 'website_v3', ww, 'present', ww ? 'rule_id', 'match', aa = ww,
    'total_on_website', (v_d->'totals'->>'study_rules')::int);

  -- 9. Career outcomes: the golden outcome as the website serves it and as Admin holds it
  v_d := public.website_v3_destination(jsonb_build_object('country_code', 'au', 'section', 'career_outcomes'), 1, 100);
  ww := coalesce((select jsonb_build_object('outcome_id', r->>'outcome_id', 'occupation_code', r->>'occupation_code', 'occupation_title', r->>'occupation_title', 'employment_count', (r->>'employment_count')::numeric)
                    from jsonb_array_elements(coalesce(v_d->'career_outcomes', '[]'::jsonb)) r where (r->>'outcome_id')::uuid = v_outcome limit 1), '{}'::jsonb);
  aa := coalesce((select jsonb_build_object('outcome_id', c.id::text, 'occupation_code', c.occupation_code, 'occupation_title', c.occupation_title, 'employment_count', c.employment_count::numeric) from destination.career_outcomes c where c.id = v_outcome), '{}'::jsonb);
  v_sections := v_sections || jsonb_build_object('section', 'career_outcomes', 'admin', aa, 'website_v3', ww, 'present', ww ? 'outcome_id', 'match', aa = ww,
    'total_on_website', (v_d->'totals'->>'career_outcomes')::int);

  -- 10. Rankings: each ranking body's latest published rank for the provider, kept side by side
  ww := coalesce((select jsonb_object_agg(k, jsonb_build_object('edition_year', (w->'provider'->'ranking_summary'->k->>'edition_year')::int, 'rank_display', w->'provider'->'ranking_summary'->k->>'rank_display'))
                    from jsonb_object_keys(coalesce(w->'provider'->'ranking_summary', '{}'::jsonb)) k), '{}'::jsonb);
  aa := coalesce((select jsonb_object_agg(x.code, jsonb_build_object('edition_year', x.edition_year, 'rank_display', x.rank_display)) from (
                    select distinct on (sy.code) sy.code, e.edition_year, o.rank_display
                      from ranking.observations o
                      join ranking.editions e on e.id = o.edition_id and e.status = 'accepted'
                      join ranking.systems sy on sy.id = e.system_id
                     where o.provider_id = v_pid or exists (select 1 from ranking.observation_provider_links l where l.observation_id = o.id and l.provider_id = v_pid)
                     order by sy.code, e.edition_year desc, o.rank_low nulls last) x where x.code in (select jsonb_object_keys(ww))), '{}'::jsonb);
  v_sections := v_sections || jsonb_build_object('section', 'rankings', 'admin', aa, 'website_v3', ww, 'present', (select count(*) from jsonb_object_keys(ww)) > 0, 'match', aa = ww);

  return jsonb_build_object('suite', 'rm1k_australia_golden_v1', 'checked_at', now(), 'course', v_course,
    'sections', v_sections,
    'passed', (select count(*) from jsonb_array_elements(v_sections) s where (s->>'present')::boolean and (s->>'match')::boolean),
    'total', jsonb_array_length(v_sections));
end $f$;;
comment on function public.admin_golden_acceptance_v1(jsonb) is 'CF-247 s973 (RM1K, IR-002): the Australia golden records read through Admin and Website API v3, ten sections, with whether each agrees. Read-only; Pipeline Operator and above.';
revoke all on function public.admin_golden_acceptance_v1(jsonb) from public, anon;
grant execute on function public.admin_golden_acceptance_v1(jsonb) to authenticated, service_role;

do $c$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if to_regprocedure('public.admin_golden_acceptance_v1(jsonb)') is null then raise exception 'post-check: the golden acceptance function is missing'; end if;
  if (select count(*) from cron.job where active) <> (select n from s973_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s973_locks) then raise exception 'post-check: the manual locks changed'; end if;
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
