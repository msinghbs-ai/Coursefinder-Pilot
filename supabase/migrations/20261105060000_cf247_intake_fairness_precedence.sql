-- CF-247 intake recovery: UNSW blockage and cross-university fairness (Platform Admin direction 5 Nov 2026 15:50, recorded verbatim in admin
-- docs/platform/2026-11-05-intake-recovery-unsw-blockage-fairness-1550.md; P0 IQ-00313; process record docs/platform/processes/intake-dates.md §9).
-- Why (measured after v2.15.481, 14:26 and 15:26):
--   * Five UNSW start dates were admitted by the unique-month rule without course-specific evidence: a testimonial ("I commenced ... in
--     February 2023") read as an intake, and a diploma whose intakes (January, May, August) follow another academic calendar.
--   * An approved 2023 reading of the UNSW key-dates page still supplies the period "term 1", so course pages naming "Term 1" never reach
--     the 2027 calendar, whose reader names the same period "teaching period t1" (151 and 138 rows held).
--   * security.intake_dates_plan_v3 orders candidates by focus rank and course before the batch limit, so UNSW takes every hourly batch.
-- What (existing architecture; no new job, scheduler, engine or screen):
--   1 Obsolete editions: security.calendar_sources_v1 (md5-guarded replacement, 3064e209) sets aside a reading whose latest proved teaching
--     start is before the current year ("obsolete edition"), with the reason; nothing replaced or deleted. Its calendar set changes, so the
--     affected rows are looked at again (an input change).
--   2 Equivalent period labels: security.calendar_period_canonical_v1 ("teaching period t1", "t1", "term one" -> "term 1"; "teaching period
--     s1", "sem 1", "semester one" -> "semester 1"; "tri 2" -> "trimester 2"); security.calendar_dated_periods_v2 (md5-guarded edit,
--     972f5c48) returns canonical periods. Two different dates for one period stay ambiguous as before.
--   3 Course-specific evidence and calendar applicability: security.intake_course_applicability_v1, called by intake_dates_plan_v3 before a
--     value is admitted: the course page must state the month as an offering (an intake, start, entry, term or semester statement; never a
--     personal account or a past year), and a month-only match (unique-month rule) needs every intake month the page offers to start in
--     that academic year of the university's main calendars; otherwise another academic calendar applies and the row is held.
--   4 Provider fairness: intake_dates_plan_v3 (md5-guarded edit, 0eb4f9fd) takes eligible rows round by round, intake_dates.provider_share
--     rows per university a round; within a round the university served longest ago first (from its saved decisions, so progress persists
--     across runs), then focus rank; fingerprints, revisits, holds and locks unchanged; batch size unchanged.
--   5 Governed withdrawal: security.intake_date_withdraw_v1 / public.admin_intake_date_withdraw_v1 (Platform Admin, with a reason) revert
--     only the fields this process admitted, only while the catalogue still holds them, keep every record (a withdrawn event is appended),
--     respect manual locks, hold the course's intakes with the existing manual lock (mode value) so no lane refills them until a person
--     lifts it, refresh the projection and verify the Website API v2 source.
--   6 Failure classes (security.intake_failure_class_v1, md5-guarded edit e9344ecf): offering evidence missing and withdrawn -> course-level
--     exception; another academic calendar -> wrong institution or campus.
-- Consumer API: unchanged (G3). Values reach intakes[] only through intake_dates_apply_v1 and the existing projection refresh; the withdrawal
--   writes catalogue.course_intakes as the apply does and refreshes the same projection.
-- Replaces: md5-guarded edits of security.calendar_sources_v1, security.calendar_dated_periods_v2, security.intake_dates_plan_v3, security.intake_failure_class_v1
-- Retires: nothing
-- Nothing is dropped or deleted.

create or replace function pg_temp.edit(p_sig text, p_md5 text, p_marker text, p_old text[], p_new text[], p_times int[]) returns text language plpgsql as $e$
declare v text := pg_get_functiondef(p_sig::regprocedure); i int; n int;
begin
  if position(p_marker in v) > 0 then return p_sig || ': already applied'; end if;
  if md5(v) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %, expected %)', p_sig, md5(v), p_md5; end if;
  for i in 1 .. array_length(p_old, 1) loop
    n := (length(v) - length(replace(v, p_old[i], ''))) / length(p_old[i]);
    if n <> p_times[i] then raise exception '%: edit % must apply exactly % time(s), found %', p_sig, i, p_times[i], n; end if;
    v := replace(v, p_old[i], p_new[i]);
  end loop;
  execute v;
  return p_sig || ': edited';
end $e$;

-- 0 settings (G2) ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'intake_dates.provider_share', 'Intake dates: rows a university takes each round',
  'The intake-dates job and its plan take eligible rows round by round: each university with eligible rows gets up to this many rows a round, focus universities first within a round, until the batch is full. A university with no eligible rows takes nothing and blocks nobody. The batch size is unchanged.',
  'number', to_jsonb(25), 5, 200, 'rows', 1011, 'Intake dates', 'security.intake_dates_plan_v3; job intake-dates-apply',
  'Platform Admin direction 5 Nov 2026 15:50 §3: no provider monopolises the bounded workload')
on conflict (toolset_key, key) do nothing;

-- 1 obsolete editions (md5-guarded replacement) ----------------------------------------------------------------------------------------------
do $$ begin
  if position('obsolete edition' in pg_get_functiondef('security.calendar_sources_v1(uuid)'::regprocedure)) = 0
     and md5(pg_get_functiondef('security.calendar_sources_v1(uuid)'::regprocedure)) <> '3064e2096d87ce93756d52bc99f5ab4b' then
    raise exception 'live security.calendar_sources_v1 differs from the definition this change replaces (md5 %)', md5(pg_get_functiondef('security.calendar_sources_v1(uuid)'::regprocedure));
  end if;
end $$;
create or replace function security.calendar_sources_v1(p_provider uuid)
returns table(proposal_id uuid, fact_source_id uuid, url text, evidence_id uuid, parser text, decided_at timestamptz, scope text, used boolean, set_aside_reason text, proposal jsonb)
language sql stable security definer set search_path to '' as $function$
  with latest as (
    select distinct on (coalesce(p.fact_source_id::text, p.url)) p.id, p.fact_source_id, p.url, p.evidence_id, p.parser, p.decided_at, p.proposal
      from pipeline.provider_policy_proposals p
     where p.provider_id = p_provider and p.kind = 'intake_calendar' and p.status = 'approved'
     order by coalesce(p.fact_source_id::text, p.url), p.decided_at desc nulls last, p.created_at desc)
  select l.id, l.fact_source_id, l.url, l.evidence_id, l.parser, l.decided_at, s.scope,
         s.scope = 'main_teaching' and not coalesce(y.latest < extract(year from (now() at time zone 'Australia/Melbourne'))::int, false),  -- fixed: the calendar year in Australia
         case when s.scope = 'excluded_by_address' then 'the address names another campus, college, exchange or pathway calendar'
              when s.scope <> 'main_teaching' then 'the reader found this calendar is ' || replace(s.scope, '_', ' ')
              -- direction 5 Nov 2026 15:50 §2: an obsolete edition never supplies a current or future commencement, or a period name
              when y.latest < extract(year from (now() at time zone 'Australia/Melbourne'))::int then 'obsolete edition: its latest proved teaching start is in ' || y.latest end,
         l.proposal
    from latest l, lateral (select security.calendar_scope_v1(l.proposal, l.url, l.parser) scope) s,
         lateral (select max(d.year) latest from security.calendar_proposal_dates_v1(l.id) d
                   where d.kind = 'start' and d.year is not null and (d.quote ~ ('\m' || d.year || '\M') or coalesce(d.year_quote, '') ~ ('\m' || d.year || '\M'))) y
$function$;
comment on function security.calendar_sources_v1(uuid) is 'CF-247 (decision 5 Nov 2026 §2; direction 5 Nov 2026 15:50 §2): each calendar document of a university with its latest approved reading, its scope and whether intake dates use it: set aside with a reason when it is not the main teaching calendar or is an obsolete edition (its latest proved teaching start is before the current year); nothing replaced or deleted.';

-- 2 equivalent period labels ----------------------------------------------------------------------------------------------------------------
create or replace function security.calendar_period_canonical_v1(p_period text) returns text
language sql immutable as $function$
  with w as (select regexp_replace(regexp_replace(lower(btrim(coalesce(p_period, ''))), '\s+', ' ', 'g'), '\m(one)\M', '1', 'g') a),
  x as (select regexp_replace(regexp_replace(a, '\m(two)\M', '2', 'g'), '\m(three)\M', '3', 'g') b from w)
  select case
    when b ~ '^(teaching period|study period|tp) ?t ?[1-6]$' then 'term ' || substring(b from '([1-6])$')
    when b ~ '^t[1-6]$' then 'term ' || substring(b from '([1-6])$')
    when b ~ '^(teaching period|study period) ?s ?[1-3]$' or b ~ '^s[1-3]$' or b ~ '^sem\.? ?[1-3]$' then 'semester ' || substring(b from '([1-3])$')
    when b ~ '^tri\.? ?[1-3]$' then 'trimester ' || substring(b from '([1-3])$')
    else b end
  from x
$function$;
comment on function security.calendar_period_canonical_v1(text) is 'CF-247 (direction 5 Nov 2026 15:50 §2): one name for equivalent official period labels (Teaching period T1, T1, Term one -> term 1; Teaching period S1, Sem 1, Semester one -> semester 1; Tri 2 -> trimester 2); sub-periods such as T1A keep their own name.';

select pg_temp.edit('security.calendar_dated_periods_v2(uuid)', '972f5c48e8d13ca2216027658e50fac5', 'calendar_period_canonical_v1',
  array['  select d.proposal_id, d.period, d.kind,'],
  array['  select d.proposal_id, security.calendar_period_canonical_v1(d.period), d.kind,'], array[1]);

-- 3 course-specific offering evidence and calendar applicability ------------------------------------------------------------------------------
create or replace function security.intake_course_applicability_v1(p_raw text, p_month int, p_year int, p_cal jsonb, p_month_only boolean, p_periods text[] default null, p_period_text text default null) returns text
language plpgsql stable security definer set search_path to '' as $function$
declare v_names text[] := array['january','february','march','april','may','june','july','august','september','october','november','december'];
        v_cur int := extract(year from (now() at time zone 'Australia/Melbourne'))::int;  -- fixed: the calendar year in Australia
        v_offered int[] := '{}'; v_missing text[]; f text; k int; v_y int; v_per text;
begin
  -- a named study period (the course page names the calendar's own period, e.g. "Term 1"): the page must state it as the course's own
  -- offering, never only in a personal account or with a past year ("I commenced in Term 1 2023")
  if not p_month_only and p_periods is not null then
    -- the period text as the plan reads it (security.intake_period_text_v1: "Semester Two" -> semester 2, lists expanded)
    foreach f in array regexp_split_to_array(lower(coalesce(p_period_text, p_raw, '')), '(\.\s|[;\n]|\|\|)') loop
      continue when f ~ '\m(i|we|my|our)\M (have |had )?(commenced|started|began|joined|enrolled|studied|completed)\M';
      foreach v_per in array p_periods loop
        continue when f !~ ('\m' || regexp_replace(v_per, '[ _-]+', '[ _-]*', 'g') || '\M');
        v_y := (regexp_match(f, '\m' || regexp_replace(v_per, '[ _-]+', '[ _-]*', 'g') || '\M,? (20\d\d)\M'))[1]::int;
        if v_y is null or v_y >= v_cur then return null; end if;
      end loop;
    end loop;
    return 'the course page does not state ' || array_to_string(p_periods, ', ') || ' as its own intake (offering evidence missing: only a personal account or a past year)';
  end if;
  -- each statement of the page wording (split at sentence ends, line breaks and list separators) that names a month
  foreach f in array regexp_split_to_array(lower(coalesce(p_raw, '')), '(\.\s|[;\n]|\|\|)') loop
    -- an offering: intake, start, entry or study-period wording; never a personal account
    continue when f !~ '\m(intakes?|commenc\w*|starts?|entry|offered|available|admissions?|semesters?|terms?|trimesters?|sessions?|begins?)\M'
               or f ~ '\m(i|we|my|our)\M (have |had )?(commenced|started|began|joined|enrolled|studied|completed)\M';
    for k in 1 .. 12 loop
      continue when f !~ ('\m' || left(v_names[k], 3) || '[a-z]*\M') or k = any (v_offered);
      -- never a month of a past year ("February 2023")
      v_y := (regexp_match(f, '\m' || left(v_names[k], 3) || '[a-z]*,? (20\d\d)\M'))[1]::int;
      if v_y is null or v_y >= v_cur then v_offered := array_append(v_offered, k); end if;
    end loop;
  end loop;
  if not (p_month = any (v_offered)) then
    return 'the course page does not state ' || initcap(v_names[p_month]) || ' as an intake (offering evidence missing: no intake, start, entry or study period statement for this month, or only a personal account or a past year)';
  end if;
  if p_month_only then
    -- a month-only match: every month the course offers must start in that academic year of the main calendars, or another calendar applies
    select array_agg(initcap(v_names[o]) order by o) into v_missing from unnest(v_offered) o
     where not exists (select 1 from jsonb_to_recordset(p_cal) s(kind text, year int, month int, year_ok boolean) where s.kind = 'start' and s.month = o and s.year = p_year and s.year_ok);
    if v_missing is not null then
      return 'the course''s intakes (' || (select string_agg(initcap(v_names[o]), ', ' order by o) from unnest(v_offered) o) || ') do not all start in the university''s ' || p_year
             || ' main teaching calendar (no start in ' || array_to_string(v_missing, ', ') || '): another academic calendar applies';
    end if;
  end if;
  return null;
end $function$;
comment on function security.intake_course_applicability_v1(text, int, int, jsonb, boolean, text[], text) is 'CF-247 (direction 5 Nov 2026 15:50 §1, §2): null when the course page names the calendar''s study period as its own offering (never only in a personal account or with a past year), or states the month as an offering (intake, start, entry or study-period wording; never a personal account or a past year) and, for a month-only match, every month the course offers starts in that academic year of the university''s main teaching calendars; otherwise the reason the row is held. A valid general calendar alone is not proof that a course offers the intake.';

-- 4 provider fairness and the evidence gate in the plan (md5-guarded edit) --------------------------------------------------------------------
select pg_temp.edit('security.intake_dates_plan_v3(uuid[],integer)', '0eb4f9fdec574d089f9e869aa7d443dd', 'intake_dates.provider_share',
  array[$o$  v_limit int := coalesce(p_limit, security.pipeline_num_v1('batch.intake_dates_apply', 200)::int);$o$,
        $o$    sets as materialized (select prov.provider_id, security.calendar_set_v1(prov.provider_id) s from prov)$o$,
        $o$     order by f.rank nulls last, i.course_id, i.id
     limit v_limit$o$,
        $o$    start_precision := case when v_start is not null then 'day' else 'year' end;$o$],
  array[$n$  v_limit int := coalesce(p_limit, security.pipeline_num_v1('batch.intake_dates_apply', 200)::int);
  -- direction 5 Nov 2026 15:50 §3: rows taken round by round, this many a university a round (focus rank first within a round)
  v_share int := greatest(1, security.pipeline_num_v1('intake_dates.provider_share', 25)::int);$n$,
        $n$    -- direction 5 Nov 2026 15:50 §3: when each university was last served, so a round that does not fit the batch starts with the one waiting longest
    sets as materialized (select prov.provider_id, security.calendar_set_v1(prov.provider_id) s,
                                 (select max(d.applied_at) from pipeline.course_intake_dates d where d.provider_id = prov.provider_id) served from prov)$n$,
        $n$     order by ceil(row_number() over (partition by c.provider_id order by i.course_id, i.id)::numeric / v_share), sets.served nulls first, f.rank nulls last, c.provider_id, i.course_id, i.id
     limit v_limit$n$,
        $n$    -- direction 5 Nov 2026 15:50 §1, §2: the course page must offer this intake, and a month-only match needs a calendar that applies to the course
    reason := security.intake_course_applicability_v1(v_raw, v_m, v_year, v_cal, rule = 'calendar-v3-unique-month', case when rule <> 'calendar-v3-unique-month' then v_pers end, v_pq);
    if reason is not null then
      outcome := 'skipped'; start_precision := 'month'; periods := v_pers; start_quote := null;
      next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action);
      return next; outcome := null; continue;
    end if;
    start_precision := case when v_start is not null then 'day' else 'year' end;$n$],
  array[1, 1, 1, 1]);

-- 5 failure classes for the new reasons (md5-guarded edit) --------------------------------------------------------------------------------
select pg_temp.edit('security.intake_failure_class_v1(text,text,boolean,text,uuid,integer,integer)', 'e9344ecf77edd58240bf1d73a6073974', 'offering evidence missing',
  array[$o$    when p_reason in ('intakes locked by hand', 'course held', 'kept by a lock or the same-month guard') then 'admission_held'$o$],
  array[$n$    when p_reason in ('intakes locked by hand', 'course held', 'kept by a lock or the same-month guard') then 'admission_held'
    -- direction 5 Nov 2026 15:50 §1: offering evidence missing, a governed withdrawal, another academic calendar
    when p_reason like 'the course page does not state % as %intake (offering evidence missing%' or p_reason like 'withdrawn:%' then 'course_level_exception'
    when p_reason like 'the course''s intakes (%) do not all start in%' then 'wrong_institution_or_campus'$n$], array[1]);

-- 6 governed withdrawal of admitted values ---------------------------------------------------------------------------------------------------
create or replace function security.intake_date_withdraw_v1(p_intake uuid, p_reason text, p_actor text, p_hold boolean default true) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare d pipeline.course_intake_dates%rowtype; i catalogue.course_intakes%rowtype; v_before jsonb; v_after jsonb; v_year int; v_start date; v_dl date; v_pub jsonb;
begin
  if coalesce(btrim(p_reason), '') = '' or length(btrim(p_reason)) < 8 then raise exception 'give the reason for the withdrawal' using errcode = '22023'; end if;
  select * into d from pipeline.course_intake_dates where intake_id = p_intake for update;
  if d.intake_id is null or d.outcome <> 'filled' or d.after_value is null then
    return jsonb_build_object('intake_id', p_intake, 'withdrawn', false, 'why', 'no value admitted by the intake-dates process for this intake');
  end if;
  if exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = d.course_id and k.field in ('intakes', 'intake')) then
    return jsonb_build_object('intake_id', p_intake, 'withdrawn', false, 'why', 'the intakes are locked by hand');
  end if;
  select * into i from catalogue.course_intakes where id = p_intake for update;
  -- only the fields this process set, and only while the catalogue still holds the value it admitted
  v_year := case when d.before_value->>'year' is null and d.after_value->>'year' is not null and i.intake_year is not distinct from (d.after_value->>'year')::int then null else i.intake_year end;
  v_start := case when d.before_value->>'start_date' is null and d.after_value->>'start_date' is not null and i.start_date is not distinct from (d.after_value->>'start_date')::date then null else i.start_date end;
  v_dl := case when d.before_value->>'application_deadline' is null and d.after_value->>'application_deadline' is not null
                    and i.application_deadline is not distinct from (d.after_value->>'application_deadline')::date then null else i.application_deadline end;
  v_before := jsonb_build_object('year', i.intake_year, 'start_date', i.start_date, 'application_deadline', i.application_deadline);
  v_after := jsonb_build_object('year', v_year, 'start_date', v_start, 'application_deadline', v_dl);
  if v_before = v_after then
    return jsonb_build_object('intake_id', p_intake, 'withdrawn', false, 'why', 'the catalogue no longer holds the value this process admitted');
  end if;
  update catalogue.course_intakes set intake_year = v_year, start_date = v_start, application_deadline = v_dl where id = p_intake;
  update pipeline.course_intake_dates set outcome = 'skipped', reason = left('withdrawn: ' || btrim(p_reason), 500), start_precision = 'month',
         after_value = v_after, applied_at = now(), publication_state = null, publication_checked_at = null, publication_attempts = 0, next_action = 'human_decision_required'
   where intake_id = p_intake;
  insert into pipeline.course_intake_date_events(intake_id, course_id, provider_id, run_at, rule, outcome, reason, next_action, calendar_set, proposal_id, periods, start_precision,
                                                 deadline_kind, before_value, after_value, page_quote, start_quote, deadline_quote, calendar_url, calendar_evidence_id, bounded)
  values (p_intake, d.course_id, d.provider_id, now(), 'withdrawal', 'withdrawn', left('withdrawn: ' || btrim(p_reason) || ' (by ' || coalesce(p_actor, 'unknown') || ')', 500),
          'human_decision_required', d.calendar_set, d.proposal_id, d.periods, 'month', d.deadline_kind, v_before, v_after, d.page_quote, d.start_quote, d.deadline_quote,
          d.calendar_url, d.calendar_evidence_id, false);
  -- the existing hold: the course's intakes are locked as they now are, so no automated lane fills them again until a person lifts the lock
  if p_hold then
    insert into pipeline.manual_locks(entity, entity_id, field, mode, set_by, set_at)
    values ('course', d.course_id, 'intakes', 'value', case when p_actor ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then p_actor::uuid end, now())
    on conflict (entity, entity_id, field) do nothing;
  end if;
  perform search.refresh_course_enrichment_scoped_v1(array[d.course_id], true);
  select jsonb_agg(e) into v_pub from search.course_documents cd, jsonb_array_elements(case when jsonb_typeof(cd.intake_options) = 'array' then cd.intake_options else '[]'::jsonb end) e
   where cd.course_id = d.course_id and e->>'label' = i.intake_label;
  return jsonb_build_object('intake_id', p_intake, 'course_id', d.course_id, 'withdrawn', true, 'held', p_hold, 'before', v_before, 'after', v_after, 'website_source', coalesce(v_pub, '[]'::jsonb),
    'website_verified', not exists (select 1 from jsonb_array_elements(coalesce(v_pub, '[]'::jsonb)) e
                                     where e->>'start_date' is distinct from v_start::text or e->>'year' is distinct from v_year::text));
end $function$;
comment on function security.intake_date_withdraw_v1(uuid, text, text, boolean) is 'CF-247 (direction 5 Nov 2026 15:50 §1, P0 IQ-00313): withdraws a value the intake-dates process admitted: reverts only the fields it set, only while the catalogue still holds them, never under a manual lock; the decision row becomes a course-level exception and, with p_hold (the default), the course''s intakes are held by the existing manual lock (mode value) until a person lifts it, a withdrawn event is appended (nothing earlier is changed or deleted), the projection is refreshed and the Website API v2 source is read back.';

create or replace function public.admin_intake_date_withdraw_v1(p_intake_ids uuid[], p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v jsonb := '[]'::jsonb; x uuid; r jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if coalesce(array_length(p_intake_ids, 1), 0) = 0 or array_length(p_intake_ids, 1) > 50 then raise exception 'name 1 to 50 intakes' using errcode = '22023'; end if;  -- fixed: a reviewed list, not a bulk tool
  foreach x in array p_intake_ids loop
    r := security.intake_date_withdraw_v1(x, p_reason, auth.uid()::text, true); v := v || r;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('intake_dates', 'withdraw', 'catalogue.course_intakes', jsonb_build_object('reason', p_reason, 'results', v), auth.uid());
  return jsonb_build_object('results', v, 'withdrawn', (select count(*) from jsonb_array_elements(v) e where (e->>'withdrawn')::boolean));
end $function$;
comment on function public.admin_intake_date_withdraw_v1(uuid[], text) is 'CF-247 (direction 5 Nov 2026 15:50 §1): the Platform Admin''s governed withdrawal of intake values the intake-dates process admitted (security.intake_date_withdraw_v1), with a reason, recorded in the admin control log.';
revoke all on function security.intake_date_withdraw_v1(uuid, text, text, boolean), public.admin_intake_date_withdraw_v1(uuid[], text) from public, anon;
grant execute on function public.admin_intake_date_withdraw_v1(uuid[], text) to authenticated;

-- 7 component register (housekeeping) -------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.calendar_period_canonical_v1', 'Layer 2', 'Admission', 'One name for equivalent official period labels', 'active', '{}', '20261105060000'),
 ('function', 'security.intake_course_applicability_v1', 'Layer 2', 'Admission', 'Course-specific offering evidence and calendar applicability', 'active', '{}', '20261105060000'),
 ('function', 'security.intake_date_withdraw_v1', 'Layer 2', 'Admission', 'Governed withdrawal of admitted intake values', 'active', '{}', '20261105060000'),
 ('function', 'public.admin_intake_date_withdraw_v1', 'Layer 2', 'Admission', 'Platform Admin withdrawal of admitted intake values', 'active', '{}', '20261105060000')
on conflict (kind, name) do nothing;
