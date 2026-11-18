-- CF-247 intake dates: "Named period only" (Platform Admin decision 2 Nov 2026 ~14:50, on the fill rule of 20261102080000 / v2.15.405).
-- Decision: "Exact start dates are filled only where the course's own page names the period (e.g. "Semester 1", "Trimester 2") and that named
--   period has a dated start in the approved calendar. A month-only row keeps its month only. A year is filled only when it is printed (on the
--   page, or in the same calendar quote as the named period). No month-to-period inference."
-- Why: v2.15.405 gave a page-stated month the date of whichever approved-calendar period starts in that month (an inference; e.g. a Monash
--   "February" intake would have taken "Teaching period start date | 1 February 2027"). The job is off and has written 0 rows.
-- What:
--   1 security.intake_dates_plan_v1 (md5-guarded edit): the period must be named in the stored reading of the course's own page, the page that
--     gave the intake: the page reader's intake quotes for that page (pipeline.coverage_course_pages.candidates->'intake_context', the same
--     address as the intake's evidence; adapter readings included) or the AI reading whose evidence is the intake's
--     (pipeline.field_enrich_items, field intakes, filled, its verbatim quote). Only those periods of the approved calendar count, in the
--     intake's month. The year counts only when printed in that period's calendar quote or in the page quote. A page that names no period
--     keeps its month only. Nothing is read again; no AI.
--   2 public.svc_coursefacts_apply_record (md5-guarded edit; the AU CRICOS admission write behind most intake rows): a write without a year
--     keeps the held year, start date and deadline; an older year never replaces a later one (as security.coverage_apply_course_v1 in
--     20261102080000).
--   3 The setting's help and the job's catalogue note say the new rule. The job stays paused and the setting off.
--   4 Index pipeline.field_enrich_items (course_id, field): the plan looks up a course's AI reading per intake row; the table (about 151,000 rows,
--     2 Nov 2026) had no index on course_id, so each lookup read the whole table (measured: a keyed read-only count over 21 providers hit the
--     statement time-out). A new index beside the table; nothing else changes.
-- Replaces: security.intake_dates_plan_v1 (md5-guarded edit, same name: month-to-period matching replaced by named-period matching);
--   public.svc_coursefacts_apply_record (md5-guarded edit, same name)
-- Retires: nothing (the month-to-period rule never ran: the job was off)
-- Nothing is dropped, deleted or switched on. Nothing in the catalogue changes when this migration is applied. Consumer API untouched (G3).

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

-- 1 named period only ----------------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.intake_dates_plan_v1(uuid[],integer)', 'a528b06b5fb7cd3a1cb4ec923e789328', '4e3847587271c68e70018de23d0b74b6', array[
  array[$o$v_url text; v_chk jsonb;$o$, $n$v_url text; v_chk jsonb; v_pq text; v_named text[];$n$],
  array[$o$    -- the next start in this month, on or after today, with its year printed (a start with a year but no day counts for its year)
    select min(s.year) into v_year from security.calendar_dated_periods_v1(r.provider_id) s
     where s.kind = 'start' and s.month = v_m and s.year is not null
       and (s.on_date >= v_today or (s.on_date is null and make_date(s.year, s.month, 1) >= date_trunc('month', v_today)::date))
       and (r.intake_year is null or s.year = r.intake_year);$o$,
        $n$    -- Named period only (Platform Admin 2 Nov 2026 ~14:50): the period must be named in the stored reading of the page that gave the intake:
    -- the page reader's intake quotes for that address, or the AI reading whose evidence is the intake's (its verbatim quote). No month-to-period inference.
    select lower(string_agg(z.t, ' | ')) into v_pq from (
      select x t from pipeline.coverage_course_pages g,
             jsonb_array_elements_text(case when jsonb_typeof(g.candidates->'intake_context') = 'array' then g.candidates->'intake_context' else '[]'::jsonb end) x
       where g.course_id = r.course_id and (g.url = v_url or g.candidates->>'final_url' = v_url)
      union all
      select f.quote from pipeline.field_enrich_items f
       where f.course_id = r.course_id and f.field = 'intakes' and f.state = 'filled' and f.evidence_id = r.evidence_id and nullif(btrim(f.quote), '') is not null) z;
    -- "Semester One", "first semester" and "semester 1" are the same period (as security.enrich_parse_intake_periods_v1)
    v_pq := regexp_replace(regexp_replace(regexp_replace(coalesce(v_pq, ''), '\mone\M|\mfirst\M', '1', 'g'), '\mtwo\M|\msecond\M', '2', 'g'), '\mthree\M|\mthird\M', '3', 'g');
    select array_agg(distinct s.period) into v_named from security.calendar_dated_periods_v1(r.provider_id) s
     where s.kind = 'start' and s.period ~ '^[a-z][a-z _-]*[0-9]+$'
       and v_pq ~ ('\m' || regexp_replace(s.period, '[ _-]+', '[ _-]*', 'g') || '\M');
    if v_named is null then
      outcome := 'skipped'; start_precision := 'month';
      reason := case when v_pq = '' then 'no stored reading of the page''s intake wording (month only)'
                     else 'the course page names no study period of the calendar (month only)' end;
      return next; continue;
    end if;
    -- the next start of a named period in this month, on or after today; its year printed in the period's calendar quote or on the page
    select min(s.year) into v_year from security.calendar_dated_periods_v1(r.provider_id) s
     where s.kind = 'start' and s.period = any (v_named) and s.month = v_m and s.year is not null
       and (s.quote ~ ('\m' || s.year || '\M') or v_pq ~ ('\m' || s.year || '\M'))
       and (s.on_date >= v_today or (s.on_date is null and make_date(s.year, s.month, 1) >= date_trunc('month', v_today)::date))
       and (r.intake_year is null or s.year = r.intake_year);$n$],
  array[$o$      reason := case when r.intake_year is not null then 'the calendar prints no start in the intake''s own year'
                     when exists (select 1 from security.calendar_dated_periods_v1(r.provider_id) s where s.kind = 'start' and s.month = v_m and s.year is not null)
                       then 'the calendar''s starts in this month are past'
                     when exists (select 1 from security.calendar_dated_periods_v1(r.provider_id) s where s.kind = 'start' and s.month = v_m)
                       then 'the calendar prints no year for this month (month only)'
                     else 'the calendar has no start in this month' end;$o$,
        $n$      reason := case when r.intake_year is not null then 'the calendar prints no start of the named period in the intake''s own year'
                     when exists (select 1 from security.calendar_dated_periods_v1(r.provider_id) s where s.kind = 'start' and s.period = any (v_named) and s.month = v_m
                                     and s.year is not null and (s.quote ~ ('\m' || s.year || '\M') or v_pq ~ ('\m' || s.year || '\M')))
                       then 'the named period''s starts in this month are past'
                     when exists (select 1 from security.calendar_dated_periods_v1(r.provider_id) s where s.kind = 'start' and s.period = any (v_named) and s.month = v_m)
                       then 'the year of the named period is not printed (month only)'
                     else 'the named period does not start in this month' end;$n$],
  array[$o$      from security.calendar_dated_periods_v1(r.provider_id) s where s.kind = 'start' and s.month = v_m and s.year = v_year;$o$,
        $n$      from security.calendar_dated_periods_v1(r.provider_id) s where s.kind = 'start' and s.period = any (v_named) and s.month = v_m and s.year = v_year
       and (s.quote ~ ('\m' || s.year || '\M') or v_pq ~ ('\m' || s.year || '\M'));$n$]],
  array[1, 1, 1, 1]);

-- 2 the AU CRICOS admission write keeps held dates ----------------------------------------------------------------------------------------
select pg_temp.edit_once('public.svc_coursefacts_apply_record(uuid,uuid,text,text,text,text,text,jsonb,boolean)', 'ec4a0997cb1b97bc4b390b1d5beebaeb', 'cfd84c9f3348772b983ffd3c0fc92f57', array[
  array[$o$insert into catalogue.course_intakes(course_id,intake_year,$o$, $n$insert into catalogue.course_intakes as ci(course_id,intake_year,$n$],
  array[$o$do update set intake_year=excluded.intake_year,intake_label=excluded.intake_label,start_date=excluded.start_date,application_deadline=excluded.application_deadline,status=excluded.status,$o$,
        $n$do update set intake_year=case when excluded.intake_year is null or excluded.intake_year<ci.intake_year then ci.intake_year else excluded.intake_year end,intake_label=excluded.intake_label,
     start_date=case when excluded.intake_year>ci.intake_year then excluded.start_date when excluded.intake_year<ci.intake_year then ci.start_date else coalesce(excluded.start_date,ci.start_date) end,
     application_deadline=case when excluded.intake_year>ci.intake_year then excluded.application_deadline when excluded.intake_year<ci.intake_year then ci.application_deadline else coalesce(excluded.application_deadline,ci.application_deadline) end,
     status=excluded.status,$n$]],
  array[1, 1]);

-- 4 the plan's per-row lookup of the AI reading is keyed ------------------------------------------------------------------------------------
create index if not exists field_enrich_items_course_field_idx on pipeline.field_enrich_items (course_id, field);

-- 3 what the switch and the job say ------------------------------------------------------------------------------------------------------
update pipeline.platform_toolset_settings
   set help = 'Fills the intake year, start date and application deadline of month intakes from the university''s approved academic calendar, only where the course''s own page names the study period ("Semester 1", "Trimester 2") and the calendar prints that period''s start; the year only when printed. Off until the Platform Admin switches it on.'
 where toolset_key = 'pipeline' and key = 'intake_dates.apply_enabled' and help not like '%names the study period%';
update pipeline.automation_catalogue
   set description = 'Hourly at :26 when switched on (Intake dates: on, off by default): gives a month intake the start date, year and application deadline of the study period its course page names ("Semester 1", "Trimester 2"), from the university''s approved academic calendar, at most Intake dates: rows a run (200). Named period only (Platform Admin 2 Nov 2026): a page that names no period keeps its month only; the year only when printed. Only the course''s own page (E16); never over a value already held or locked by hand; never another year; rolling deadlines stay text. No Firecrawl and no AI: stored readings only.'
 where jobname = 'intake-dates-apply' and description not like '%Named period only%';

-- post-check: still off and paused; both edits are the intended ones
do $$
begin
  if coalesce((select (value #>> '{}')::boolean from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'intake_dates.apply_enabled'), true) then
    raise exception 'named period post-check: the setting must be off'; end if;
  if exists (select 1 from cron.job where jobname = 'intake-dates-apply' and active) then
    raise exception 'named period post-check: the job must be paused'; end if;
  if md5(pg_get_functiondef('security.intake_dates_plan_v1(uuid[],integer)'::regprocedure)) <> '4e3847587271c68e70018de23d0b74b6'
     or md5(pg_get_functiondef('public.svc_coursefacts_apply_record(uuid,uuid,text,text,text,text,text,jsonb,boolean)'::regprocedure)) <> 'cfd84c9f3348772b983ffd3c0fc92f57' then
    raise exception 'named period post-check: an edited function has an unexpected definition'; end if;
  if to_regclass('pipeline.field_enrich_items_course_field_idx') is null then
    raise exception 'named period post-check: the AI reading index is missing'; end if;
end $$;
select 'intake dates: named period only; the AU CRICOS admission write keeps held dates' ok;
