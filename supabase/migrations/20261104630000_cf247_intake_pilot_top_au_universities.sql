-- CF-247 intake pilot cohort scope (Platform Admin 4 Nov 2026 20:53: "Make sure cohort includes top Australian unis with maximum courses only"),
-- on the pilot authority of 20:05 §1 (admin docs/platform/2026-11-04-course-intake-pilot-authority-2005.md) and Run now (20261104610000, v2.15.476).
-- What: security.run_now_cohort_create_v1 (md5-guarded replace, live 0fd43a771a427530995c20f88eb1af1c read 4 Nov 2026 20:56) picks only from the
--   run_now.cohort_top_au_universities (10) active Australian universities with the most active courses: institution type from
--   catalogue.providers.provider_type_id -> ref.provider_types.code 'university' (the TEQSA / NZQA register type, Decision 258), country from
--   country_id -> ref.countries.iso_alpha2 'AU'; ties by md5(provider id). Their active course ids go to the job's own plan
--   (security.intake_dates_plan_v2(uuid[], run_now.cohort_scan_rows)); round-robin over those universities and the md5 tie-break are kept.
--   The cohort record keeps the university list with active course counts, eligible courses and values each, and the scope's denominator.
--   A scope with fewer than run_now.pilot_cap eligible courses gives a smaller cohort; it is never widened.
-- Replaces: security.run_now_cohort_create_v1 (md5-guarded replace, same name and signature)
-- Retires: nothing
-- Nothing is dropped, deleted or switched on; no job, cohort or catalogue row changes when this migration is applied. Consumer API untouched (G3).

do $g$ begin
  if md5(pg_get_functiondef('security.run_now_cohort_create_v1(text,uuid,text,text)'::regprocedure)) not in ('0fd43a771a427530995c20f88eb1af1c', '410db5ca480e038e32d12c16f66eefa9') then
    raise exception 'live security.run_now_cohort_create_v1 differs from the definition this change replaces (md5 %)',
      md5(pg_get_functiondef('security.run_now_cohort_create_v1(text,uuid,text,text)'::regprocedure));
  end if;
end $g$;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'run_now.cohort_top_au_universities', 'Run now: Australian universities a cohort is picked from',
  'A Run now cohort is picked only from this many active Australian universities, those with the most active courses. If they hold fewer eligible courses than the cohort size, the cohort is smaller; it is never widened to other providers.', 'number',
  to_jsonb(10), 1, 50, 'universities', 1104, 'Run now', 'security.run_now_cohort_create_v1',
  'Platform Admin 4 Nov 2026 20:53: cohort from the top Australian universities with the most courses only')
on conflict (toolset_key, key) do nothing;

create or replace function security.run_now_cohort_create_v1(p_job text, p_requester uuid, p_reason text, p_label text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_cap int := security.pipeline_num_v1('run_now.pilot_cap', 20)::int;
        v_scan int := security.pipeline_num_v1('run_now.cohort_scan_rows', 1500)::int;
        v_top int := security.pipeline_num_v1('run_now.cohort_top_au_universities', 10)::int;
        v_id uuid := gen_random_uuid(); v_rows int; v_filled_rows int; v_courses int; v_providers int; v_n int; v_unis jsonb; v_provs uuid[]; v_scope uuid[];
        v_rule constant text := 'top run_now.cohort_top_au_universities Australian universities by active courses; intake-dates-plan-v2 filled within them; most fields gained first; round-robin over universities, then evidence patterns; md5(course id) breaks ties';  -- fixed: the name of this rule in the record
begin
  if p_job is distinct from 'intake-dates-apply' then raise exception 'no cohort rule for job %', p_job; end if;
  if p_requester is null then raise exception 'a requester is required'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'a reason is required'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = p_job) then raise exception 'job % is not catalogued', p_job; end if;
  -- the scope (Platform Admin 4 Nov 2026 20:53: "top Australian unis with maximum courses only"): the active Australian universities
  -- (institution type 'university', country AU) with the most active courses; the cohort is never widened beyond them
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', x.id, 'name', x.name, 'active_courses', x.n) order by x.n desc, md5(x.id::text)), '[]'::jsonb), array_agg(x.id)
    into v_unis, v_provs
    from (select p.id, coalesce(p.display_name, p.canonical_name) name, count(c.id) n
            from catalogue.providers p
            join ref.countries co on co.id = p.country_id and co.iso_alpha2 = 'AU'  -- fixed: the Platform Admin's scope (Australian)
            join ref.provider_types t on t.id = p.provider_type_id and t.code = 'university'  -- fixed: the Platform Admin's scope (universities)
            join catalogue.courses c on c.provider_id = p.id and c.lifecycle_status = 'active'
           where p.lifecycle_status = 'active'
           group by p.id, 2 order by count(c.id) desc, md5(p.id::text) limit v_top) x;
  v_scope := array(select c.id from catalogue.courses c where c.provider_id = any (coalesce(v_provs, '{}')) and c.lifecycle_status = 'active');
  -- one statement: the job's plan for the scope's courses (read only), the denominator, the cohort record and its members
  with plan as materialized (select * from security.intake_dates_plan_v2(v_scope, v_scan)),
  f as (select * from plan where outcome = 'filled'),
  sel as (select (select count(*) from plan) rows_planned, count(*) rows_eligible, count(distinct course_id) courses_eligible, count(distinct provider_id) providers_eligible from f),
  coh as (
    insert into pipeline.run_now_cohorts(id, job, label, selection_rule, selection, requested_by, reason)
    select v_id, p_job, coalesce(nullif(btrim(p_label), ''), 'Intake dates pilot ' || to_char(now() at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI')), v_rule,
           jsonb_build_object('rows_planned', sel.rows_planned, 'rows_eligible', sel.rows_eligible, 'courses_eligible', sel.courses_eligible,
                              'providers_eligible', sel.providers_eligible, 'cap', v_cap, 'scan_rows', v_scan,
                              'top_au_universities', v_top, 'scope_courses', cardinality(v_scope),
                              'universities', (select coalesce(jsonb_agg(u || jsonb_build_object('eligible_courses', (select count(distinct f.course_id) from f where f.provider_id = (u->>'provider_id')::uuid),
                                                                                    'eligible_values', (select count(*) from f where f.provider_id = (u->>'provider_id')::uuid))), '[]'::jsonb)
                                               from jsonb_array_elements(v_unis) u),
                              'skipped_by_reason',
                              (select coalesce(jsonb_object_agg(r, n), '{}'::jsonb) from (select coalesce(reason, outcome) r, count(*) n from plan where outcome <> 'filled' group by 1) x)),
           p_requester, btrim(p_reason)
      from sel returning id),
  c as (select course_id, min(provider_id::text)::uuid provider_id,
               array_remove(array[case when bool_or(new_year is not null) then 'year' end, case when bool_or(new_start is not null) then 'start_date' end,
                                  case when bool_or(new_deadline is not null) then 'application_deadline' end], null) fills,
               string_agg(distinct coalesce(start_precision, '-') || '/' || coalesce(deadline_kind, '-'), '+') pattern,
               jsonb_agg(jsonb_build_object('intake_id', intake_id, 'proposal_id', proposal_id, 'calendar_evidence_id', calendar_evidence_id, 'calendar_url', calendar_url,
                         'periods', periods, 'page_quote', page_quote, 'start_quote', start_quote, 'deadline_quote', deadline_quote, 'deadline_kind', deadline_kind,
                         'before', before_value, 'planned', jsonb_build_object('year', new_year, 'start_date', new_start, 'application_deadline', new_deadline), 'rule', rule)
                         order by intake_id) evidence
          from f group by course_id),
  r as (select c.*, row_number() over (partition by provider_id order by cardinality(fills) desc, md5(course_id::text)) rp,
               row_number() over (partition by pattern order by cardinality(fills) desc, md5(course_id::text)) rq from c),
  pick as (select r.*, row_number() over (order by rp, rq, cardinality(fills) desc, md5(course_id::text)) n from r),
  ins as (insert into pipeline.run_now_cohort_members(cohort_id, course_id, provider_id, pick, pattern, fills, evidence)
          select coh.id, pick.course_id, pick.provider_id, pick.n, pick.pattern, pick.fills, pick.evidence from pick, coh where pick.n <= v_cap returning 1)
  select (select count(*) from ins), sel.rows_planned, sel.rows_eligible, sel.courses_eligible, sel.providers_eligible
    into v_n, v_rows, v_filled_rows, v_courses, v_providers from sel;
  return jsonb_build_object('cohort_id', v_id, 'job', p_job, 'members', v_n, 'universities', (select selection->'universities' from pipeline.run_now_cohorts where id = v_id), 'cap', v_cap, 'rows_planned', v_rows, 'rows_eligible', v_filled_rows,
                            'courses_eligible', v_courses, 'providers_eligible', v_providers,
                            'providers_in_cohort', (select count(distinct provider_id) from pipeline.run_now_cohort_members where cohort_id = v_id),
                            'patterns_in_cohort', (select count(distinct pattern) from pipeline.run_now_cohort_members where cohort_id = v_id));
end $function$;
revoke all on function security.run_now_cohort_create_v1(text, uuid, text, text) from public, anon, authenticated;
comment on function security.run_now_cohort_create_v1(text, uuid, text, text) is 'CF-247 Run now (Platform Admin 4 Nov 2026 20:05 §1): picks a fixed cohort of at most run_now.pilot_cap courses for job intake-dates-apply, only from the run_now.cohort_top_au_universities Australian universities with the most active courses (Platform Admin 20:53), from its own plan (security.intake_dates_plan_v2, read only) over run_now.cohort_scan_rows candidate rows of their courses; a short scope gives a smaller cohort, never a wider one; records the rule, the denominator and each member''s evidence. Never hand-picked.';

do $$
begin
  if md5(pg_get_functiondef('security.run_now_cohort_create_v1(text,uuid,text,text)'::regprocedure)) <> '410db5ca480e038e32d12c16f66eefa9' then
    raise exception 'cohort scope post-check: run_now_cohort_create_v1 has an unexpected definition (md5 %)', md5(pg_get_functiondef('security.run_now_cohort_create_v1(text,uuid,text,text)'::regprocedure)); end if;
end $$;
select 'run now cohort: top Australian universities by active courses only' ok;
