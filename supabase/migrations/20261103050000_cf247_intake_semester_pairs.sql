-- CF-247 Workstream D, intake wording (Platform Admin direction 2 Nov 2026 23:24, admin nz-enrichment-brief/2026-11-02-overnight-continuous-delivery-
-- direction-2324.md §1 "Intake wording": "Treat the explicit phrase 'Semester 1 and 2' as evidence that both teaching periods are named. Do not derive
-- exact calendar dates from semester labels alone.")
-- Why: under "Named period only" (20261102100000, v2.15.407, job on since 2 Nov) a page that says "Semester 1 and 2" named Semester 1 only, so its
--   July intake kept its month. The reader also turned "Starting dates Throughout the year excluding January & December" (UWA, Master of Philosophy)
--   into January and December intakes. And pipeline.course_intake_dates kept the calendar's quote but not the page's wording that named the period.
-- What:
--   1 security.intake_period_text_v1(text): the page wording as the plan compares it ("Semester One" = "semester 1"), with explicit pairs and lists
--     written out: "Semester 1 and 2", "Semesters 1 & 2", "Trimester 1, 2 and 3", "Terms 1 or 2" name each period. Only single digits after the
--     period word count, so "Term 1, 2027" names Term 1 only.
--   2 security.intake_month_negated_v1(text, month): true when every mention of the month in the wording sits in an excluding clause: the word
--     and at most two months joined by "and", "&", "or" or a comma ("excluding January & December", "(Except December)", "except June and December",
--     "not offered in July"). A run-together list after the word ("Except January February March April ...", an SSC adapter pattern) is ambiguous
--     and is not read as excluded.
--   3 security.intake_page_wording_v1(course, evidence, page): the stored wording of the page behind an intake (the page reader's intake quotes for that
--     address, and the AI reading whose evidence is the intake's), unchanged; the plan's source, kept as provenance.
--   4 security.intake_dates_plan_v2: the v1 plan (live md5 4e3847587271c68e70018de23d0b74b6) with (1) and (2), and four more columns: page_quote
--     (the page wording that named the period), calendar_evidence_id and calendar_url (the approved calendar's stored document), and rule. A date
--     still needs the approved calendar's dated start for the named period: a label alone gives nothing. A row the earlier rule looked at and did
--     not fill is looked at once more under this rule; a filled row is not looked at again for the same calendar.
--   5 security.intake_dates_apply_v1 (md5-guarded edit): uses plan v2, records the four columns, and first completes the provenance of rows filled
--     before the page wording was kept (batched; the wording as stored now).
--   6 security.enrich_parse_intakes_v1 (md5-guarded edit, the AI reader's month parser): a month the quote mentions only in an excluding clause is not
--     an intake. (The page reader's extract.ts intakes() drops such months by the same rule; the worker string is unchanged because s216 pins it.)
--   7 security.intake_negated_months_v1(): read-only list of active month intakes whose own page wording excludes the month. Those rows are not
--     withdrawn here: the paste files docs/paste/PASTE-20261103-intake-excluded-months-withdrawal(-rollback).sql do it after the Platform Admin
--     approves. Until then plan v2 records them as skipped ("the page excludes this month") and fills nothing for them.
-- Replaces: security.intake_dates_plan_v1 (by security.intake_dates_plan_v2; marked retiring); security.intake_dates_apply_v1 and
--   security.enrich_parse_intakes_v1 (md5-guarded edits, same names)
-- Retires: security.intake_dates_plan_v1 (retiring; dropped by a paste file after hygiene.retire_after_days once unused)
-- Nothing is dropped, deleted or switched on. No catalogue row changes when this migration is applied. Consumer API untouched (G3).

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

-- the plan v1 this change replaces must be the live one
do $$
begin
  if md5(pg_get_functiondef('security.intake_dates_plan_v1(uuid[],integer)'::regprocedure)) <> '4e3847587271c68e70018de23d0b74b6' then
    raise exception 'live security.intake_dates_plan_v1 differs from the definition plan v2 is built from (md5 %)', md5(pg_get_functiondef('security.intake_dates_plan_v1(uuid[],integer)'::regprocedure));
  end if;
end $$;

-- provenance columns --------------------------------------------------------------------------------------------------------------------
alter table pipeline.course_intake_dates add column if not exists page_quote text;
alter table pipeline.course_intake_dates add column if not exists calendar_evidence_id uuid;
alter table pipeline.course_intake_dates add column if not exists calendar_url text;
alter table pipeline.course_intake_dates add column if not exists rule text;
comment on table pipeline.course_intake_dates is 'CF-247 intake dates (Platform Admin 2 Nov 2026 11:10 §2; "Named period only" ~14:50; pairs 23:24): one row per course intake looked at by security.intake_dates_apply_v1 (job intake-dates-apply), for the approved calendar (proposal_id) it was matched against: the outcome, the reason when nothing was filled, the period(s), how precise the start is (day, year or month only), whether the deadline is a date, rolling (kept as text, never a date) or not stated, the evidence of every filled value (page_quote: the stored page wording that named the period; start_quote and deadline_quote: the calendar rows; calendar_evidence_id and calendar_url: the approved calendar document), the rule that decided it, and the values before and after. Never read by the consumer API.';

-- 1 the wording as compared, with pairs and lists written out ---------------------------------------------------------------------------
create or replace function security.intake_period_text_v1(p_text text)
 returns text
 language sql
 immutable
 set search_path to ''
as $function$
  with t as (
    -- "Semester One", "first semester" and "semester 1" are the same period (as security.enrich_parse_intake_periods_v1)
    select regexp_replace(regexp_replace(regexp_replace(lower(coalesce(p_text, '')), '\mone\M|\mfirst\M', '1', 'g'), '\mtwo\M|\msecond\M', '2', 'g'), '\mthree\M|\mthird\M', '3', 'g') t)
  select t.t || coalesce(' | ' || (
    -- "semester 1 and 2", "semesters 1 & 2", "trimester 1, 2 and 3", "terms 1 or 2": each period named; single digits only ("term 1, 2027" is term 1)
    select string_agg(m[1] || ' ' || n, ' | ')
      from regexp_matches(t.t, '\m(semester|trimester|term|study period|teaching period|session|block|quarter)s?\s*([0-9](?:\s*(?:,|&|\mand\M|\mor\M|/)\s*[0-9])+)\M', 'g') m,
           regexp_split_to_table(m[2], '\s*(?:,|&|\mand\M|\mor\M|/)\s*') n), '')
    from t
$function$;
revoke all on function security.intake_period_text_v1(text) from public, anon, authenticated;

-- 2 a month the wording only excludes ----------------------------------------------------------------------------------------------------
create or replace function security.intake_month_negated_v1(p_text text, p_month int)
 returns boolean
 language sql
 immutable
 set search_path to ''
as $function$
  with x as (
    select lower(coalesce(p_text, '')) t,
           '\m' || left((array['january','february','march','april','may','june','july','august','september','october','november','december'])[p_month], 3) || '[a-z]*\M' mon)
  -- the excluding clause is the word and at most two months joined by "and", "&", "or" or a comma ("except June and December", "(Except December)");
  -- a month followed by a further month list ("Except January February March ...") is ambiguous and is not read as excluded
  select p_month between 1 and 12 and x.t ~ x.mon
         and regexp_replace(x.t, '\m(exclud(e|es|ed|ing)|except(ing)?|other than|apart from|but not|not (offered|available|run)|no (intakes?|entry|start))\M\s*(in|during)?\s*\(?\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*(\s*(,|&|\mand\M|\mor\M)\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*)?\M(?!\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\M)', ' ', 'g') !~ x.mon
    from x
$function$;
revoke all on function security.intake_month_negated_v1(text, int) from public, anon, authenticated;

-- 3 the stored wording of the page behind an intake --------------------------------------------------------------------------------------
create or replace function security.intake_page_wording_v1(p_course uuid, p_evidence uuid, p_url text)
 returns text
 language sql
 stable security definer
 set search_path to ''
as $function$
  select string_agg(z.t, ' | ') from (
    select x t from pipeline.coverage_course_pages g,
           jsonb_array_elements_text(case when jsonb_typeof(g.candidates->'intake_context') = 'array' then g.candidates->'intake_context' else '[]'::jsonb end) x
     where g.course_id = p_course and (g.url = p_url or g.candidates->>'final_url' = p_url)
    union all
    select f.quote from pipeline.field_enrich_items f
     where f.course_id = p_course and f.field = 'intakes' and f.state = 'filled' and f.evidence_id = p_evidence and nullif(btrim(f.quote), '') is not null) z
$function$;
revoke all on function security.intake_page_wording_v1(uuid, uuid, text) from public, anon, authenticated;

-- 4 plan v2 ---------------------------------------------------------------------------------------------------------------------------
create or replace function security.intake_dates_plan_v2(p_course_ids uuid[] default null, p_limit int default null)
 returns table(intake_id uuid, course_id uuid, provider_id uuid, proposal_id uuid, outcome text, reason text, periods text[],
               new_year int, new_start date, new_deadline date, start_precision text, deadline_kind text, deadline_text text,
               start_quote text, deadline_quote text, before_value jsonb, page_quote text, calendar_evidence_id uuid, calendar_url text, rule text)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  v_rule constant text := 'named-period-pairs-v2';  -- fixed: the name of this rule in the record
  v_today date := (now() at time zone 'Australia/Melbourne')::date;  -- fixed: the calendar day in Australia (month roll-over)
  v_max_before int := security.pipeline_num_v1('intake_dates.deadline_max_days_before', 366)::int;
  v_limit int := coalesce(p_limit, security.pipeline_num_v1('batch.intake_dates_apply', 200)::int);
  r record; v_m int; v_prop uuid; v_year int; v_starts date[]; v_start date; v_pers text[]; v_sq text; v_dl date[]; v_dq text; v_roll text; v_url text; v_chk jsonb;
  v_raw text; v_pq text; v_named text[];
begin
  for r in
    select i.id, i.course_id, c.provider_id, i.intake_label, i.intake_year, i.start_date, i.application_deadline, i.evidence_id
      from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id
     where i.status = 'active' and c.lifecycle_status = 'active'
       and (p_course_ids is null or i.course_id = any (p_course_ids))
       and (i.intake_year is null or i.start_date is null or i.application_deadline is null)
       and exists (select 1 from pipeline.provider_policy_proposals p where p.provider_id = c.provider_id and p.kind = 'intake_calendar' and p.status = 'approved')
       -- each row once for each approved calendar under this rule; a row an earlier rule filled is not looked at again for that calendar
       and not exists (select 1 from pipeline.course_intake_dates d where d.intake_id = i.id
                          and d.proposal_id is not distinct from (select p.id from pipeline.provider_policy_proposals p where p.provider_id = c.provider_id and p.kind = 'intake_calendar' and p.status = 'approved'
                                                                   order by p.decided_at desc nulls last, p.created_at desc limit 1)
                          and (d.rule is not distinct from v_rule or d.outcome = 'filled'))
     order by i.course_id, i.id
     limit v_limit
  loop
    intake_id := r.id; course_id := r.course_id; provider_id := r.provider_id; periods := null; new_year := null; new_start := null; new_deadline := null;
    start_precision := null; deadline_kind := null; deadline_text := null; start_quote := null; deadline_quote := null; reason := null;
    page_quote := null; calendar_evidence_id := null; calendar_url := null; rule := v_rule;
    before_value := jsonb_build_object('year', r.intake_year, 'start_date', r.start_date, 'application_deadline', r.application_deadline);
    select p.id, p.evidence_id, p.url into v_prop, calendar_evidence_id, calendar_url from pipeline.provider_policy_proposals p
     where p.provider_id = r.provider_id and p.kind = 'intake_calendar' and p.status = 'approved'
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
    -- Named period only (Platform Admin 2 Nov 2026 ~14:50), with explicit pairs and lists (23:24): the period must be named in the stored reading of
    -- the page that gave the intake. No month-to-period inference; a label alone gives no date.
    v_raw := security.intake_page_wording_v1(r.course_id, r.evidence_id, v_url);
    page_quote := left(v_raw, 600);
    -- a month the page only excludes ("throughout the year excluding January & December") is not an intake: nothing is filled for it
    if security.intake_month_negated_v1(v_raw, v_m) then
      outcome := 'skipped'; reason := 'the page excludes this month (listed for withdrawal)'; return next; continue;
    end if;
    v_pq := security.intake_period_text_v1(v_raw);
    select array_agg(distinct s.period) into v_named from security.calendar_dated_periods_v1(r.provider_id) s
     where s.kind = 'start' and s.period ~ '^[a-z][a-z _-]*[0-9]+$'
       and v_pq ~ ('\m' || regexp_replace(s.period, '[ _-]+', '[ _-]*', 'g') || '\M');
    if v_named is null then
      outcome := 'skipped'; start_precision := 'month';
      reason := case when coalesce(v_raw, '') = '' then 'no stored reading of the page''s intake wording (month only)'
                     else 'the course page names no study period of the calendar (month only)' end;
      return next; continue;
    end if;
    -- the next start of a named period in this month, on or after today; its year printed in the period's calendar quote or on the page
    select min(s.year) into v_year from security.calendar_dated_periods_v1(r.provider_id) s
     where s.kind = 'start' and s.period = any (v_named) and s.month = v_m and s.year is not null
       and (s.quote ~ ('\m' || s.year || '\M') or v_pq ~ ('\m' || s.year || '\M'))
       and (s.on_date >= v_today or (s.on_date is null and make_date(s.year, s.month, 1) >= date_trunc('month', v_today)::date))
       and (r.intake_year is null or s.year = r.intake_year);
    if v_year is null then
      outcome := 'skipped';
      reason := case when r.intake_year is not null then 'the calendar prints no start of the named period in the intake''s own year'
                     when exists (select 1 from security.calendar_dated_periods_v1(r.provider_id) s where s.kind = 'start' and s.period = any (v_named) and s.month = v_m
                                     and s.year is not null and (s.quote ~ ('\m' || s.year || '\M') or v_pq ~ ('\m' || s.year || '\M')))
                       then 'the named period''s starts in this month are past'
                     when exists (select 1 from security.calendar_dated_periods_v1(r.provider_id) s where s.kind = 'start' and s.period = any (v_named) and s.month = v_m)
                       then 'the year of the named period is not printed (month only)'
                     else 'the named period does not start in this month' end;
      start_precision := 'month'; return next; continue;
    end if;
    select array_agg(distinct s.on_date) filter (where s.on_date is not null), array_agg(distinct s.period), min(s.quote)
      into v_starts, v_pers, v_sq
      from security.calendar_dated_periods_v1(r.provider_id) s where s.kind = 'start' and s.period = any (v_named) and s.month = v_m and s.year = v_year
       and (s.quote ~ ('\m' || s.year || '\M') or v_pq ~ ('\m' || s.year || '\M'));
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
revoke all on function security.intake_dates_plan_v2(uuid[], int) from public, anon, authenticated;
comment on function security.intake_dates_plan_v2(uuid[], int) is 'CF-247 intake dates, named period only with explicit pairs and lists (Platform Admin 2 Nov 2026 ~14:50 and 23:24): read-only plan of what each active month intake would gain from the approved calendar, with the page wording and calendar document behind each value, or the reason it gains nothing. Replaces security.intake_dates_plan_v1.';

-- 5 the apply uses plan v2 and keeps the evidence of every filled value -------------------------------------------------------------------
select pg_temp.edit_once('security.intake_dates_apply_v1(integer)', '2ee1ce769cb5de8d300d9ad6e1bdbf7f', 'd15c04c680dc0128ca5da33556426c43', array[
  array[$o$        v_filled int := 0; v_seen int := 0; v_courses uuid[] := '{}'; p record; v_n int;$o$,
        $n$        v_filled int := 0; v_seen int := 0; v_courses uuid[] := '{}'; p record; v_n int; v_prov int := 0;$n$],
  array[$o$  perform pg_advisory_xact_lock(hashtext('cf247 intake dates apply'));  -- fixed: one run at a time
$o$,
        $n$  perform pg_advisory_xact_lock(hashtext('cf247 intake dates apply'));  -- fixed: one run at a time
  -- 23:24 provenance: values filled before the page wording was kept get it now (as stored now), with the approved calendar's document
  update pipeline.course_intake_dates d
     set page_quote = coalesce(left(security.intake_page_wording_v1(d.course_id, i.evidence_id, e.source_url), 600), ''),
         calendar_evidence_id = cal.evidence_id, calendar_url = cal.url
    from catalogue.course_intakes i left join pipeline.evidence_artifacts e on e.id = i.evidence_id, pipeline.provider_policy_proposals cal
   where d.intake_id in (select d2.intake_id from pipeline.course_intake_dates d2 where d2.outcome = 'filled' and d2.calendar_url is null
                          limit security.pipeline_num_v1('batch.intake_dates_apply', 200)::int)
     and i.id = d.intake_id and cal.id = d.proposal_id;
  get diagnostics v_prov = row_count;
$n$],
  array[$o$security.intake_dates_plan_v1(null, p_limit)$o$, $n$security.intake_dates_plan_v2(null, p_limit)$n$],
  array[$o$                                             start_quote, deadline_quote, before_value, after_value, applied_at)$o$,
        $n$                                             start_quote, deadline_quote, before_value, after_value, applied_at, page_quote, calendar_evidence_id, calendar_url, rule)$n$],
  array[$o$from catalogue.course_intakes i where i.id = p.intake_id), now()$o$,
        $n$from catalogue.course_intakes i where i.id = p.intake_id), now(),
           p.page_quote, p.calendar_evidence_id, p.calendar_url, p.rule$n$],
  array[$o$deadline_quote = excluded.deadline_quote, before_value = excluded.before_value, after_value = excluded.after_value, applied_at = excluded.applied_at;$o$,
        $n$deadline_quote = excluded.deadline_quote, before_value = excluded.before_value, after_value = excluded.after_value, applied_at = excluded.applied_at,
           page_quote = excluded.page_quote, calendar_evidence_id = excluded.calendar_evidence_id, calendar_url = excluded.calendar_url, rule = excluded.rule;$n$],
  array[$o$'filled', v_filled, 'courses',$o$, $n$'filled', v_filled, 'provenance_completed', v_prov, 'courses',$n$]],
  array[1, 1, 1, 1, 1, 1, 1]);

-- 6 the AI reader's month parser: a month mentioned only to exclude it is not an intake ------------------------------------------------------
select pg_temp.edit_once('security.enrich_parse_intakes_v1(text,text)', '28beada5c58b585bd9e655381231f20f', '4372e1ccce2242733433607aed8b6924', array[
  array[$o$and coalesce(p_quote, '') ~* ('\m' || left(m.label, 3))$o$,
        $n$and coalesce(p_quote, '') ~* ('\m' || left(m.label, 3))
     and not security.intake_month_negated_v1(p_quote, m.n)  -- 23:24: "excluding January & December" names no January or December intake$n$]],
  array[1]);

-- 7 the rows to withdraw (read-only list; the paste file withdraws them after approval) ------------------------------------------------------
create or replace function security.intake_negated_months_v1(p_provider uuid default null)
 returns table(intake_id uuid, course_id uuid, provider_id uuid, intake_label text, source_intake_key text, page_url text, page_wording text)
 language sql
 stable security definer
 set search_path to ''
as $function$
  select i.id, i.course_id, c.provider_id, i.intake_label, i.source_intake_key, e.source_url, left(w.t, 400)
    from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id
    left join pipeline.evidence_artifacts e on e.id = i.evidence_id
    cross join lateral (select security.intake_page_wording_v1(i.course_id, i.evidence_id, e.source_url) t) w
   where i.status = 'active' and (p_provider is null or c.provider_id = p_provider)
     and w.t ~* '\m(exclud(e|es|ed|ing)|except(ing)?|other than|apart from|but not|not (in|during|available|offered|run)|no (intakes?|entry|start) in)\M'
     and security.intake_month_negated_v1(w.t, array_position(array['january','february','march','april','may','june','july','august','september','october','november','december'], lower(btrim(i.intake_label))))
$function$;
revoke all on function security.intake_negated_months_v1(uuid) from public, anon, authenticated;
comment on function security.intake_negated_months_v1(uuid) is 'CF-247 intake wording (Platform Admin 2 Nov 2026 23:24): active month intakes whose own stored page wording mentions the month only to exclude it (UWA "Throughout the year excluding January & December"). Read-only; the withdrawal is the paste file PASTE-20261103-intake-excluded-months-withdrawal.sql, run after approval.';

-- housekeeping ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.intake_dates_plan_v2', 'Layer 2', 'Admission', 'Intake dates plan: named period only, with explicit pairs and lists; evidence of each value', 'active', '{security.intake_dates_plan_v1}', '20261103050000'),
 ('function', 'security.intake_period_text_v1', 'Layer 2', 'Admission', 'Page wording as compared, with "Semester 1 and 2" written out as each period', 'active', '{}', '20261103050000'),
 ('function', 'security.intake_month_negated_v1', 'Layer 2', 'Admission', 'A month the wording mentions only to exclude it', 'active', '{}', '20261103050000'),
 ('function', 'security.intake_page_wording_v1', 'Layer 2', 'Admission', 'Stored wording of the page behind an intake', 'active', '{}', '20261103050000'),
 ('function', 'security.intake_negated_months_v1', 'Layer 2', 'Admission', 'Active month intakes the page only excludes (for the withdrawal paste file)', 'active', '{}', '20261103050000')
on conflict do nothing;
update pipeline.component_register
   set status = 'retiring', replaced_by = 'security.intake_dates_plan_v2', retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int, updated_at = now()
 where kind = 'function' and name = 'security.intake_dates_plan_v1' and status = 'active';

-- post-check
do $$
begin
  if md5(pg_get_functiondef('security.intake_dates_apply_v1(integer)'::regprocedure)) <> 'd15c04c680dc0128ca5da33556426c43'
     or md5(pg_get_functiondef('security.enrich_parse_intakes_v1(text,text)'::regprocedure)) <> '4372e1ccce2242733433607aed8b6924' then
    raise exception 'semester pairs post-check: an edited function has an unexpected definition'; end if;
  if security.intake_period_text_v1('Semester 1 and 2') !~ '\msemester 2\M' or security.intake_period_text_v1('Term 1, 2027') ~ '\mterm 2\M' then
    raise exception 'semester pairs post-check: pair reading'; end if;
  if not security.intake_month_negated_v1('Starting dates Throughout the year excluding January & December, by agreement with supervisors', 1)
     or security.intake_month_negated_v1('Intakes in February and July', 2) then
    raise exception 'semester pairs post-check: excluded months'; end if;
  if (security.enrich_parse_intakes_v1('January, December', 'Starting dates Throughout the year excluding January & December')) is not null then
    raise exception 'semester pairs post-check: the AI month parser still reads excluded months'; end if;
end $$;
select 'intake wording: semester pairs and lists; excluded months; evidence of every filled value' ok;
