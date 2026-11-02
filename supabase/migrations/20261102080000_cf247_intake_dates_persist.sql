-- CF-247 intake year, exact start date and application deadline (Platform Admin 2 Nov 2026 11:10 §2: "Prioritise persistence of intake
-- year, actual start date and application deadline where the existing calendar reader already extracts those values"; 11:18: "demonstrate
-- actual dates flowing from stored evidence through catalogue, search projection and consumer API").
-- Why (admin nz-enrichment-brief/2026-11-02-missing-field-coverage-reconciliation.md): catalogue.course_intakes has intake_year, start_date and
--   application_deadline, but all 31,516 active intake rows hold none of them. The calendar parser (coverage-sweep policy.ts calendarStarts)
--   matched the day and year of each period start and kept only the month; it skipped "applications close" rows; and the common admission
--   write (security.coverage_apply_course_v1) sets intake_year and start_date to whatever a writer sends, so a re-admission without a year
--   would blank a filled one.
-- What:
--   1 security.calendar_dated_periods_v1(provider): the dated starts and deadlines of the provider's latest approved calendar (the same
--     choice as security.enrich_parse_intake_periods_v1). From the parser's new starts/deadlines (calendar-dates-v1) where present; for
--     calendars approved before it, from the approved proposal's own stored quotes (no re-read): a day and month with the year printed in
--     the same quote. A year is never assumed and a day is never invented; rolling or "check with the provider" wording stays text.
--   2 security.intake_dates_plan_v1(course ids, limit): what each active month intake row would gain, with the reason when it gains
--     nothing. Rules: the row's own page must be proved to be the course's (E16 security.course_page_check_v1 pass, not refused); no
--     manual intake lock; course not held; only empty columns are filled; the next start on or after today in the row's month; a row that
--     already holds a year is never moved to another year (past intakes stay history); two different start days in that month and year
--     give the year only; a deadline only when exactly one dated deadline of the matched period lies before the start, within
--     intake_dates.deadline_max_days_before.
--   3 security.intake_dates_apply_v1(limit): the governed, idempotent, batched re-apply. Each row once per approved calendar (recorded in
--     pipeline.course_intake_dates, which also holds the rolling-deadline marker and the quotes). Off by default: setting
--     intake_dates.apply_enabled is false and job intake-dates-apply is catalogued but paused.
--   4 security.coverage_apply_course_v1 (md5-guarded edit): a re-admission without a year keeps the held year, start date and deadline, and
--     an older year never replaces a later one.
-- Consumer API: unchanged (G3). The values reach intakes[].year, intakes[].start_date and intakes[].application_deadline through the
--   existing projection (search.refresh_course_enrichment_core_v1 / _scoped_v1 -> search.course_documents.intake_options ->
--   api.website_v2_course_item); filling them is a value change only.
-- Replaces: security.coverage_apply_course_v1 (md5-guarded edit, same name); calendarStarts output shape (adds starts and deadlines; months unchanged)
-- Retires: nothing
-- Nothing is dropped, deleted or switched on. Nothing in the catalogue changes when this migration is applied.

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': edited';
end $f$;

-- 1 settings (G2) --------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'intake_dates.apply_enabled', 'Intake dates: on',
  'Fills the intake year, start date and application deadline of month intakes from the university''s approved academic calendar, only where the calendar prints them and the course''s own page gave the month. Off until the Platform Admin switches it on.', 'boolean',
  to_jsonb(false), null, null, null, 990, 'Intake dates', 'security.intake_dates_apply_v1 (job intake-dates-apply)', 'Platform Admin 2 Nov 2026 11:10 §2: persist intake year, start date and deadline; off by default'),
 ('pipeline', 'batch.intake_dates_apply', 'Intake dates: rows a run',
  'Most intake rows looked at in one run of intake-dates-apply. Each row is looked at once for each approved calendar.', 'number',
  to_jsonb(200), 1, 2000, 'rows', 991, 'Job sizes', 'security.intake_dates_apply_v1 (job intake-dates-apply)', 'Platform Admin 2 Nov 2026 11:10 §2: batched re-apply'),
 ('pipeline', 'intake_dates.deadline_max_days_before', 'Intake dates: deadline at most this long before the start',
  'An "applications close" date of the period counts as an intake''s deadline only when it falls on or before the start date and no more than this many days before it.', 'number',
  to_jsonb(366), 1, 731, 'days', 992, 'Intake dates', 'security.intake_dates_plan_v1', 'Platform Admin 2 Nov 2026 11:10 §2: deadlines from the calendar, never assumed')
on conflict do nothing;

-- 2 record of what was applied (and the rolling-deadline marker) -----------------------------------------------------------------------
create table if not exists pipeline.course_intake_dates (
  intake_id uuid primary key references catalogue.course_intakes(id),
  course_id uuid not null,
  provider_id uuid not null,
  proposal_id uuid,
  outcome text not null check (outcome in ('filled', 'nothing_new', 'skipped')),
  reason text,
  periods text[],
  start_precision text check (start_precision in ('day', 'year', 'month')),
  deadline_kind text check (deadline_kind in ('date', 'rolling', 'not_stated')),
  deadline_text text,
  start_quote text,
  deadline_quote text,
  before_value jsonb,
  after_value jsonb,
  applied_at timestamptz not null default now()
);
create index if not exists course_intake_dates_course_idx on pipeline.course_intake_dates (course_id);
comment on table pipeline.course_intake_dates is 'CF-247 intake dates (Platform Admin 2 Nov 2026 11:10 §2): one row per course intake looked at by security.intake_dates_apply_v1 (job intake-dates-apply), for the approved calendar (proposal_id) it was matched against: the outcome, the reason when nothing was filled, the period(s), how precise the start is (day, year or month only), whether the deadline is a date, rolling (kept as text, never a date) or not stated, the calendar quotes, and the values before and after. A row is looked at again only when the approved calendar changes. Never read by the consumer API.';
alter table pipeline.course_intake_dates enable row level security;
revoke all on pipeline.course_intake_dates from public, anon, authenticated;

-- 3 the dated periods of the provider's approved calendar ------------------------------------------------------------------------------
create or replace function security.calendar_dated_periods_v1(p_provider uuid)
 returns table(proposal_id uuid, period text, kind text, year int, month int, day int, on_date date, rolling_text text, quote text)
 language sql
 stable security definer
 set search_path to ''
as $function$
  with cal as (
    -- the latest approved calendar only (as security.enrich_parse_intake_periods_v1)
    select p.id, p.proposal from pipeline.provider_policy_proposals p
     where p.provider_id = p_provider and p.kind = 'intake_calendar' and p.status = 'approved'
     order by p.decided_at desc nulls last, p.created_at desc limit 1),
  per as (select cal.id, lower(btrim(e->>'period')) period, e from cal, jsonb_array_elements(coalesce(cal.proposal->'periods', '[]'::jsonb)) e),
  -- calendar-dates-v1: the parser's own dated starts and deadlines
  given as (
    select per.id, per.period, k.kind, nullif(x->>'year', '')::int y, nullif(x->>'month', '')::int m, nullif(x->>'day', '')::int d, x->>'quote' q
      from per, lateral (values ('start', per.e->'starts'), ('deadline', per.e->'deadlines')) k(kind, arr), jsonb_array_elements(coalesce(k.arr, '[]'::jsonb)) x
     where jsonb_typeof(k.arr) = 'array'),
  -- calendars approved before calendar-dates-v1: the start quotes the approved proposal holds (the first date in the quote, as the parser
  -- read it; the year only when printed in the same quote)
  quoted as (
    select per.id, per.period, 'start'::text kind, q,
           regexp_match(q, '(?:\m(\d{1,2})(?:st|nd|rd|th)?\s+(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\M|\m(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+(\d{1,2})(?:st|nd|rd|th)?\M)(?:,?\s+(20\d\d))?', 'i') d
      from per, jsonb_array_elements_text(coalesce(per.e->'quotes', '[]'::jsonb)) q
     where not (per.e ? 'starts')
       -- a stored quote about exams, census, results or a break is never a start date (live: "Supplementary exams start from | Tuesday 2 July 2024")
       and q !~* '\m(exams?|examinations?|supplementary|census|results|holidays?|break|recess|graduation|enrolment|withdraw\w*)\M'),
  quoted_dates as (
    select z.id, z.period, z.kind, coalesce(nullif(z.d[5], '')::int, (regexp_match(z.q, '\m(20\d\d)\M'))[1]::int) y,
           (array_position(array['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'], lower(left(coalesce(z.d[2], z.d[3]), 3))))::int m,
           -- a day range ("18 – 20 January 2027", live): which day the period starts is not certain, so no day (the year still counts)
           case when z.q !~ '\m\d{1,2}(st|nd|rd|th)?\s*[–—-]\s*\d{1,2}(st|nd|rd|th)?\s+[A-Za-z]' then coalesce(z.d[1], z.d[4])::int end d, z.q
      from quoted z where z.d is not null),
  quoted_kept as (
    -- a quoted start counts only for a month the approved proposal lists for that period
    select q.* from quoted_dates q join per on per.id = q.id and per.period = q.period
     where per.e->'months' @> to_jsonb(q.m)),
  dated as (select * from given union all select * from quoted_kept)
  select a.id, a.period, a.kind, a.y, a.m, a.d,
         case when a.y is not null and a.d between 1 and extract(day from (make_date(a.y, a.m, 1) + interval '1 month - 1 day'))::int  -- fixed: the last day of the month
              then make_date(a.y, a.m, a.d) end,
         null::text, left(a.q, 300)
    from dated a where a.m between 1 and 12
  union all
  select per.id, per.period, 'rolling', null, null, null, null, left(r, 300), left(r, 300)
    from per, jsonb_array_elements_text(coalesce(per.e->'deadline_rolling', '[]'::jsonb)) r
$function$;
revoke all on function security.calendar_dated_periods_v1(uuid) from public, anon, authenticated;
comment on function security.calendar_dated_periods_v1(uuid) is 'CF-247 intake dates (Platform Admin 2 Nov 2026 11:10 §2): the dated starts, dated deadlines and rolling-deadline wording of the provider''s latest approved academic calendar, from the parser''s calendar-dates-v1 fields or, for calendars approved before it, from the approved proposal''s stored start quotes (the year only when printed in the same quote). No date is formed without a printed day and year.';

-- 4 the plan: what each month intake row would gain ----------------------------------------------------------------------------------
create or replace function security.intake_dates_plan_v1(p_course_ids uuid[] default null, p_limit int default null)
 returns table(intake_id uuid, course_id uuid, provider_id uuid, proposal_id uuid, outcome text, reason text, periods text[],
               new_year int, new_start date, new_deadline date, start_precision text, deadline_kind text, deadline_text text,
               start_quote text, deadline_quote text, before_value jsonb)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  v_today date := (now() at time zone 'Australia/Melbourne')::date;  -- fixed: the calendar day in Australia (month roll-over)
  v_max_before int := security.pipeline_num_v1('intake_dates.deadline_max_days_before', 366)::int;
  v_limit int := coalesce(p_limit, security.pipeline_num_v1('batch.intake_dates_apply', 200)::int);
  r record; v_m int; v_prop uuid; v_year int; v_starts date[]; v_start date; v_pers text[]; v_sq text; v_dl date[]; v_dq text; v_roll text; v_url text; v_chk jsonb;
begin
  for r in
    select i.id, i.course_id, c.provider_id, i.intake_label, i.intake_year, i.start_date, i.application_deadline, i.evidence_id
      from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id
     where i.status = 'active' and c.lifecycle_status = 'active'
       and (p_course_ids is null or i.course_id = any (p_course_ids))
       and (i.intake_year is null or i.start_date is null or i.application_deadline is null)
       and exists (select 1 from pipeline.provider_policy_proposals p where p.provider_id = c.provider_id and p.kind = 'intake_calendar' and p.status = 'approved')
       -- each row once for each approved calendar
       and not exists (select 1 from pipeline.course_intake_dates d where d.intake_id = i.id
                          and d.proposal_id is not distinct from (select p.id from pipeline.provider_policy_proposals p where p.provider_id = c.provider_id and p.kind = 'intake_calendar' and p.status = 'approved'
                                                                   order by p.decided_at desc nulls last, p.created_at desc limit 1))
     order by i.course_id, i.id
     limit v_limit
  loop
    intake_id := r.id; course_id := r.course_id; provider_id := r.provider_id; periods := null; new_year := null; new_start := null; new_deadline := null;
    start_precision := null; deadline_kind := null; deadline_text := null; start_quote := null; deadline_quote := null; reason := null;
    before_value := jsonb_build_object('year', r.intake_year, 'start_date', r.start_date, 'application_deadline', r.application_deadline);
    select p.id into v_prop from pipeline.provider_policy_proposals p where p.provider_id = r.provider_id and p.kind = 'intake_calendar' and p.status = 'approved'
     order by p.decided_at desc nulls last, p.created_at desc limit 1;
    proposal_id := v_prop;
    v_m := array_position(array['january','february','march','april','may','june','july','august','september','october','november','december'], lower(btrim(r.intake_label)));
    -- the guards: a person's lock or hold, and the E16 page check on the page the month came from
    if exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.course_id and k.field in ('intakes', 'intake')) then
      outcome := 'skipped'; reason := 'intakes locked by hand'; return next; continue;
    end if;
    if security.course_held_v1(r.course_id) then outcome := 'skipped'; reason := 'course held'; return next; continue; end if;
    if v_m is null then outcome := 'skipped'; reason := 'intake is not a month'; return next; continue; end if;
    select e.source_url into v_url from pipeline.evidence_artifacts e where e.id = r.evidence_id;
    if v_url is null then outcome := 'skipped'; reason := 'no page behind the intake'; return next; continue; end if;
    if security.page_refused_v1(r.course_id, v_url) then outcome := 'skipped'; reason := 'page refused for this course'; return next; continue; end if;
    v_chk := security.course_page_check_v1(r.course_id, v_url, null, null);
    if v_chk->>'verdict' is distinct from 'pass' then
      outcome := 'skipped'; reason := 'page not proved to be the course''s own (E16 ' || coalesce(v_chk->>'verdict', 'no verdict') || ')'; return next; continue;
    end if;
    -- the next start in this month, on or after today, with its year printed (a start with a year but no day counts for its year)
    select min(s.year) into v_year from security.calendar_dated_periods_v1(r.provider_id) s
     where s.kind = 'start' and s.month = v_m and s.year is not null
       and (s.on_date >= v_today or (s.on_date is null and make_date(s.year, s.month, 1) >= date_trunc('month', v_today)::date))
       and (r.intake_year is null or s.year = r.intake_year);
    if v_year is null then
      outcome := 'skipped';
      reason := case when r.intake_year is not null then 'the calendar prints no start in the intake''s own year'
                     when exists (select 1 from security.calendar_dated_periods_v1(r.provider_id) s where s.kind = 'start' and s.month = v_m and s.year is not null)
                       then 'the calendar''s starts in this month are past'
                     when exists (select 1 from security.calendar_dated_periods_v1(r.provider_id) s where s.kind = 'start' and s.month = v_m)
                       then 'the calendar prints no year for this month (month only)'
                     else 'the calendar has no start in this month' end;
      start_precision := 'month'; return next; continue;
    end if;
    select array_agg(distinct s.on_date) filter (where s.on_date is not null), array_agg(distinct s.period), min(s.quote)
      into v_starts, v_pers, v_sq
      from security.calendar_dated_periods_v1(r.provider_id) s where s.kind = 'start' and s.month = v_m and s.year = v_year;
    periods := v_pers; start_quote := v_sq;
    v_start := case when cardinality(v_starts) = 1 then v_starts[1] end;
    start_precision := case when v_start is not null then 'day' else 'year' end;
    if cardinality(v_starts) > 1 then reason := 'two start days in this month: year only'; end if;
    -- the deadline of the matched period(s): one dated "applications close" before the start
    select array_agg(distinct s.on_date), min(s.quote) into v_dl, v_dq
      from security.calendar_dated_periods_v1(r.provider_id) s
     where s.kind = 'deadline' and s.period = any (v_pers) and s.on_date is not null
       and s.on_date <= coalesce(v_start, make_date(v_year, v_m, 1)) and s.on_date >= coalesce(v_start, make_date(v_year, v_m, 1)) - v_max_before;
    select min(s.rolling_text) into v_roll from security.calendar_dated_periods_v1(r.provider_id) s where s.kind = 'rolling' and s.period = any (v_pers);
    if cardinality(v_dl) = 1 then deadline_kind := 'date'; new_deadline := v_dl[1]; deadline_quote := v_dq;
    elsif v_roll is not null then deadline_kind := 'rolling'; deadline_text := v_roll; deadline_quote := v_roll;
    else deadline_kind := 'not_stated'; end if;
    -- only empty columns are filled
    new_year := case when r.intake_year is null then v_year end;
    new_start := case when r.start_date is null then v_start end;
    new_deadline := case when r.application_deadline is null then new_deadline end;
    outcome := case when new_year is not null or new_start is not null or new_deadline is not null then 'filled' else 'nothing_new' end;
    return next;
  end loop;
end $function$;
revoke all on function security.intake_dates_plan_v1(uuid[], int) from public, anon, authenticated;
comment on function security.intake_dates_plan_v1(uuid[], int) is 'CF-247 intake dates (Platform Admin 2 Nov 2026 11:10 §2): read-only plan of what each active month intake row would gain from the provider''s approved calendar (year, start date, deadline), with the reason when it gains nothing. E16 page check, manual locks and holds respected; only empty columns; never another year. Settings intake_dates.deadline_max_days_before, batch.intake_dates_apply.';

-- 5 the governed re-apply (off by default) ---------------------------------------------------------------------------------------------
create or replace function security.intake_dates_apply_v1(p_limit int default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_on boolean := coalesce((security.toolset_setting('pipeline', 'intake_dates.apply_enabled') #>> '{}')::boolean, false);
        v_filled int := 0; v_seen int := 0; v_courses uuid[] := '{}'; p record; v_n int;
begin
  if not v_on then return jsonb_build_object('enabled', false, 'filled', 0); end if;
  perform pg_advisory_xact_lock(hashtext('cf247 intake dates apply'));  -- fixed: one run at a time
  for p in select * from security.intake_dates_plan_v1(null, p_limit) loop
    v_seen := v_seen + 1;
    if p.outcome = 'filled' then
      update catalogue.course_intakes i
         set intake_year = coalesce(i.intake_year, p.new_year), start_date = coalesce(i.start_date, p.new_start),
             application_deadline = coalesce(i.application_deadline, p.new_deadline)
       where i.id = p.intake_id and i.status = 'active'
         and (i.intake_year is null or i.intake_year = coalesce(p.new_year, i.intake_year));
      get diagnostics v_n = row_count;  -- 0 when a lock or the same-month guard kept the row as it was
      if v_n = 1 then v_filled := v_filled + 1; v_courses := v_courses || p.course_id; end if;
    end if;
    insert into pipeline.course_intake_dates(intake_id, course_id, provider_id, proposal_id, outcome, reason, periods, start_precision, deadline_kind, deadline_text,
                                             start_quote, deadline_quote, before_value, after_value, applied_at)
    select p.intake_id, p.course_id, p.provider_id, p.proposal_id,
           case when p.outcome = 'filled' and v_n = 0 then 'skipped' else p.outcome end,
           case when p.outcome = 'filled' and v_n = 0 then 'kept by a lock or the same-month guard' else p.reason end,
           p.periods, p.start_precision, p.deadline_kind, p.deadline_text, p.start_quote, p.deadline_quote, p.before_value,
           (select jsonb_build_object('year', i.intake_year, 'start_date', i.start_date, 'application_deadline', i.application_deadline) from catalogue.course_intakes i where i.id = p.intake_id), now()
    on conflict (intake_id) do update set proposal_id = excluded.proposal_id, outcome = excluded.outcome, reason = excluded.reason, periods = excluded.periods,
           start_precision = excluded.start_precision, deadline_kind = excluded.deadline_kind, deadline_text = excluded.deadline_text, start_quote = excluded.start_quote,
           deadline_quote = excluded.deadline_quote, before_value = excluded.before_value, after_value = excluded.after_value, applied_at = excluded.applied_at;
    v_n := null;
  end loop;
  if cardinality(v_courses) > 0 then
    perform search.refresh_course_enrichment_scoped_v1((select array_agg(distinct x) from unnest(v_courses) x), true);
  end if;
  return jsonb_build_object('enabled', true, 'looked_at', v_seen, 'filled', v_filled, 'courses', coalesce(cardinality((select array_agg(distinct x) from unnest(v_courses) x)), 0));
end $function$;
revoke all on function security.intake_dates_apply_v1(int) from public, anon, authenticated;
comment on function security.intake_dates_apply_v1(int) is 'CF-247 intake dates (Platform Admin 2 Nov 2026 11:10 §2): job intake-dates-apply. Off unless pipeline setting intake_dates.apply_enabled is true. Applies security.intake_dates_plan_v1 to at most batch.intake_dates_apply rows, fills only empty columns, records each row in pipeline.course_intake_dates (once per approved calendar) and refreshes the search projection for the courses changed.';

-- 6 a re-admission without a year keeps the held year, start date and deadline -------------------------------------------------------
select pg_temp.edit_once('security.coverage_apply_course_v1(uuid,uuid,uuid,text,text,jsonb)', '8674165fa03b97ca15c3bc82923b1288', 'c2cbc9ab616a77487d447991f33daaeb', array[
  array[$o$    insert into catalogue.course_intakes(course_id, intake_year, intake_label, start_date, status, source_id, evidence_id, confidence, source_intake_key)$o$,
        $n$    insert into catalogue.course_intakes as ci(course_id, intake_year, intake_label, start_date, status, source_id, evidence_id, confidence, source_intake_key)$n$],
  array[$o$    do update set intake_year = excluded.intake_year, intake_label = excluded.intake_label, start_date = excluded.start_date, status = 'active',$o$,
        $n$    -- 2 Nov 2026 (intake dates): a write without a year keeps the held year, start date and deadline; an older year never replaces a later one
    do update set intake_year = case when excluded.intake_year is null or excluded.intake_year < ci.intake_year then ci.intake_year else excluded.intake_year end,
                  intake_label = excluded.intake_label,
                  start_date = case when excluded.intake_year > ci.intake_year then excluded.start_date when excluded.intake_year < ci.intake_year then ci.start_date
                                    else coalesce(excluded.start_date, ci.start_date) end,
                  application_deadline = case when excluded.intake_year > ci.intake_year then null else ci.application_deadline end,
                  status = 'active',$n$]],
  array[1, 1]);

-- 7 the job: catalogued, scheduled and paused (G1); the setting is off as well -----------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('intake-dates-apply', 'Admission', 65, 'Intake dates from the approved calendar',
  'Hourly at :26 when switched on (Intake dates: on, off by default): gives month intakes the year, start date and application deadline the university''s approved academic calendar prints for that month, at most Intake dates: rows a run (200). Only where the course''s own page (E16) gave the month; never over a value already held or locked by hand; never another year; rolling deadlines stay text. No Firecrawl and no AI: it reads stored calendar readings only.',
  5, true, null)
on conflict (jobname) do nothing;
-- scheduled once and paused at once; a second run of this migration leaves the job as it finds it
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'intake-dates-apply') then
    perform cron.schedule('intake-dates-apply', '26 * * * *', 'select security.intake_dates_apply_v1(security.pipeline_num_v1(''batch.intake_dates_apply'', 200)::int)');
    perform cron.alter_job((select jobid from cron.job where jobname = 'intake-dates-apply'), active := false);
  end if;
end $j$;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'intake-dates-apply', 'Layer 2', 'Admission', 'Intake year, start date and deadline from the approved calendar (paused; setting off)', 'active', '{}', '20261102080000'),
 ('table', 'pipeline.course_intake_dates', 'Layer 2', 'Admission', 'Intake dates applied per intake row and approved calendar, with the rolling-deadline marker', 'active', '{}', '20261102080000'),
 ('function', 'security.calendar_dated_periods_v1', 'Layer 2', 'Admission', 'Dated starts and deadlines of the approved calendar (stored readings)', 'active', '{}', '20261102080000'),
 ('function', 'security.intake_dates_plan_v1', 'Layer 2', 'Admission', 'What each month intake would gain from the approved calendar', 'active', '{}', '20261102080000'),
 ('function', 'security.intake_dates_apply_v1', 'Layer 2', 'Admission', 'Job intake-dates-apply', 'active', '{}', '20261102080000')
on conflict do nothing;

-- post-check: nothing switched on, nothing changed in the catalogue, the edit is the intended one
do $$
begin
  if coalesce((select (value #>> '{}')::boolean from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'intake_dates.apply_enabled'), true) then
    raise exception 'intake dates post-check: the setting must be off'; end if;
  if exists (select 1 from cron.job where jobname = 'intake-dates-apply' and active) then
    raise exception 'intake dates post-check: the job must be paused'; end if;
  if not exists (select 1 from cron.job j join pipeline.automation_catalogue a on a.jobname = j.jobname where j.jobname = 'intake-dates-apply') then
    raise exception 'intake dates post-check: the job is not scheduled and catalogued'; end if;
  if (security.intake_dates_apply_v1(null)->>'enabled')::boolean then
    raise exception 'intake dates post-check: the apply must do nothing while off'; end if;
  if md5(pg_get_functiondef('security.coverage_apply_course_v1(uuid,uuid,uuid,text,text,jsonb)'::regprocedure)) <> 'c2cbc9ab616a77487d447991f33daaeb' then
    raise exception 'intake dates post-check: coverage_apply_course_v1 has an unexpected definition'; end if;
end $$;
select 'intake dates: calendar periods, plan and paused apply; admission keeps held dates' ok;
