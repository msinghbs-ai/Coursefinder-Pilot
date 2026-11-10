-- HELD (not a migration): forward recovery for 20261110170000 (the intake plan looks at a row whose stored page prints a date now and takes it first; the page route reads more date formats).
-- Run only if the Platform Admin decides to go back to the earlier text. It puts back, byte for byte, the bodies of security.intake_dates_plan_v3(uuid[],integer) (body md5 0d11bc5dfc4b0705f0722a1aa7905db6) and
-- security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer) (body md5 80eb7b805fa1d68910623c46308c15da) as they were before that migration, each guarded by the md5 of what is live now: it stops, and
-- changes nothing, if a live body is neither its earlier text nor the one the migration wrote (06255497ef431b0ae0d9fca6460c6cb5 and 52bad9ded722b889b97c746b7209e63a). Decisions, events, settings and dates already admitted are never touched. The read-only
-- hint function security.intake_page_date_hint_v1 stays, unused (nothing is dropped). A row whose fingerprint carries pagedate=1 is looked at once more by the earlier plan (its fingerprint no longer matches), which is harmless.
-- The migration applies again after it.
do $g$
declare v_p text; v_d text;
begin
  select md5(p.prosrc) into v_p from pg_proc p where p.oid = to_regprocedure('security.intake_dates_plan_v3(uuid[],integer)');
  select md5(p.prosrc) into v_d from pg_proc p where p.oid = to_regprocedure('security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer)');
  if v_p is null or v_d is null then raise exception 'the intake plan or the page route is missing'; end if;
  if v_p not in ('0d11bc5dfc4b0705f0722a1aa7905db6', '06255497ef431b0ae0d9fca6460c6cb5') or v_d not in ('80eb7b805fa1d68910623c46308c15da', '52bad9ded722b889b97c746b7209e63a') then
    raise exception 'live security.intake_dates_plan_v3 or security.intake_page_date_v1 differs from both texts this recovery knows (body md5 % and %)', v_p, v_d;
  end if;
end $g$;

CREATE OR REPLACE FUNCTION security.intake_dates_plan_v3(p_course_ids uuid[] DEFAULT NULL::uuid[], p_limit integer DEFAULT NULL::integer)
 RETURNS TABLE(intake_id uuid, course_id uuid, provider_id uuid, proposal_id uuid, outcome text, reason text, periods text[], new_year integer, new_start date, new_deadline date, start_precision text, deadline_kind text, deadline_text text, start_quote text, deadline_quote text, before_value jsonb, page_quote text, calendar_evidence_id uuid, calendar_url text, rule text, calendar_set text, inputs_fp text, next_action text, next_revisit_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lists boolean := security.pipeline_num_v1('intake_dates.name_period_lists', 0) = 1;
  v_unique boolean := security.pipeline_num_v1('intake_dates.month_unique_match', 0) = 1;
  v_settings text := 'lists=' || v_lists::text || ';unique=' || v_unique::text || ';rules=fair-evidence-1';
  v_today date := (now() at time zone 'Australia/Melbourne')::date;  -- fixed: the calendar day in Australia (month roll-over)
  v_max_before int := security.pipeline_num_v1('intake_dates.deadline_max_days_before', 366)::int;
  v_limit int := coalesce(p_limit, security.pipeline_num_v1('batch.intake_dates_apply', 200)::int);
  -- direction 5 Nov 2026 15:50 §3: rows taken round by round, this many a university a round (focus rank first within a round)
  v_share int := greatest(1, security.pipeline_num_v1('intake_dates.provider_share', 25)::int);
  -- Platform Admin 5 Nov 2026 18:00: the approved pilot (run_now.cohort_top_au_universities) takes up to this many rows of each batch
  v_pilot uuid[] := case when p_course_ids is null then (select coalesce(array_agg((e->>'id')::uuid), '{}') from jsonb_array_elements(security.intake_ui_scopes_v1()) e) else '{}' end;
  v_pilot_rows int := floor(coalesce(p_limit, security.pipeline_num_v1('batch.intake_dates_apply', 200)::int) * least(100, greatest(0, security.pipeline_num_v1('intake_dates.pilot_batch_share', 60))) / 100.0)::int;
  -- P0 IQ-00313: a calendar date is taken only within this many months of today
  v_ahead int := greatest(1, security.pipeline_num_v1('intake_dates.max_months_ahead', 18)::int);
  v_page_admit boolean := security.pipeline_num_v1('intake_dates.page_date_admit', 0) = 1;  -- F-INT D1: a date printed on the course page, default off
  v_pd jsonb;
  r record; v_m int; v_year int; v_starts date[]; v_start date; v_pers text[]; v_sq text; v_dl date[]; v_dq text; v_roll text; v_url text; v_chk jsonb;
  v_raw text; v_pq text; v_named text[]; v_cal jsonb := '[]'::jsonb; v_cal_provider uuid; v_n int; v_page_dates date[]; v_intl boolean;
begin
  for r in
    with prov as materialized (
      select distinct c.provider_id from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id
       where i.status = 'active' and c.lifecycle_status = 'active' and (p_course_ids is null or i.course_id = any (p_course_ids))
         and (i.intake_year is null or i.start_date is null or i.application_deadline is null)
         and exists (select 1 from pipeline.provider_policy_proposals p where p.provider_id = c.provider_id and p.kind = 'intake_calendar' and p.status = 'approved')),
    -- direction 5 Nov 2026 15:50 §3: when each university was last served, so a round that does not fit the batch starts with the one waiting longest
    sets as materialized (select prov.provider_id, security.calendar_set_v1(prov.provider_id) s,
                                 (select max(d.applied_at) from pipeline.course_intake_dates d where d.provider_id = prov.provider_id) served from prov)
    select q.id, q.course_id, q.provider_id, q.intake_label, q.intake_year, q.start_date, q.application_deadline, q.evidence_id, q.course_url, q.cal_set, q.fp from (
    select q0.*, row_number() over (partition by q0.pilot order by q0.rnd, q0.served nulls first, q0.frank nulls last, q0.provider_id, q0.course_id, q0.id) pilot_seq from (
    select i.id, i.course_id, c.provider_id, i.intake_label, i.intake_year, i.start_date, i.application_deadline, i.evidence_id, c.course_url, sets.s cal_set,
           security.intake_inputs_fp_v1(sets.s, i.evidence_id, c.course_url, v_settings) fp,
           ceil(row_number() over (partition by c.provider_id order by i.course_id, i.id)::numeric / v_share) rnd, sets.served, f.rank frank, c.provider_id = any (v_pilot) pilot
      from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id join sets on sets.provider_id = c.provider_id
      left join pipeline.enrich_focus_providers f on f.provider_id = c.provider_id and f.in_focus
     where i.status = 'active' and c.lifecycle_status = 'active'
       and (p_course_ids is null or i.course_id = any (p_course_ids))
       and (i.intake_year is null or i.start_date is null or i.application_deadline is null)
       -- decision §7.9, §8: looked at again only when an input changed or the row's revisit time passed
       and not exists (select 1 from pipeline.course_intake_dates d where d.intake_id = i.id
                          and d.inputs_fp is not distinct from security.intake_inputs_fp_v1(sets.s, i.evidence_id, c.course_url, v_settings || ';wording=' || security.intake_wording_fp_v1(i.course_id, i.evidence_id))
                          and (d.next_revisit_at is null or d.next_revisit_at > now()))
    ) q0) q
     -- the pilot's reserved rows first, then every other provider (focus first, longest waiting first), then any pilot rows beyond its share
     order by case when q.pilot and q.pilot_seq <= v_pilot_rows then 0 when not q.pilot then 1 else 2 end,
              q.rnd, (q.frank is null), q.served nulls first, q.frank nulls last, q.provider_id, q.course_id, q.id  -- focus universities first within a round (direction 5 Nov 2026 15:50 §3)
     limit v_limit
  loop
    intake_id := r.id; course_id := r.course_id; provider_id := r.provider_id; periods := null; new_year := null; new_start := null; new_deadline := null;
    outcome := null; start_precision := null; deadline_kind := null; deadline_text := null; start_quote := null; deadline_quote := null; reason := null; proposal_id := null;
    page_quote := null; calendar_evidence_id := null; calendar_url := null; rule := 'calendar-v3'; calendar_set := r.cal_set; inputs_fp := security.intake_inputs_fp_v1(r.cal_set, r.evidence_id, r.course_url, v_settings || ';wording=' || security.intake_wording_fp_v1(r.course_id, r.evidence_id));
    before_value := jsonb_build_object('year', r.intake_year, 'start_date', r.start_date, 'application_deadline', r.application_deadline);
    if v_cal_provider is distinct from r.provider_id then
      -- P0 IQ-00313: a calendar value recorded as rejected is never used again (provider, reading, quote, year)
      v_cal := coalesce((select jsonb_agg(to_jsonb(s)) from security.calendar_dated_periods_v2(r.provider_id) s
                          where not exists (select 1 from pipeline.intake_date_rejections j
                                             where j.provider_id = r.provider_id and j.proposal_id is not distinct from s.proposal_id
                                               and j.quote is not distinct from s.quote and j.year is not distinct from s.year)), '[]'::jsonb);
      v_cal_provider := r.provider_id;
    end if;
    -- a university whose approved calendars are all set aside, or give nothing, has no valid calendar
    if r.cal_set like 'none:%' then
      outcome := 'skipped';
      reason := case when split_part(r.cal_set, ':', 2)::int > 0 then 'no valid academic calendar: the approved calendars are set aside (not the main teaching calendar)'
                     else 'no valid academic calendar' end;
      next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action);
      return next; continue;
    end if;
    v_m := array_position(array['january','february','march','april','may','june','july','august','september','october','november','december'], lower(btrim(r.intake_label)));
    if exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.course_id and k.field in ('intakes', 'intake')) then
      outcome := 'skipped'; reason := 'intakes locked by hand';
    elsif security.course_held_v1(r.course_id) then outcome := 'skipped'; reason := 'course held';
    elsif v_m is null then outcome := 'skipped'; reason := 'intake is not a month';
    end if;
    if outcome = 'skipped' then
      next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action); return next; outcome := null; continue;
    end if;
    select e.source_url into v_url from pipeline.evidence_artifacts e where e.id = r.evidence_id;
    if v_url is null then reason := 'no page behind the intake';
    elsif security.page_refused_v1(r.course_id, v_url) then reason := 'page refused for this course';
    else
      v_chk := security.course_page_check_v1(r.course_id, v_url, null, null);
      if v_chk->>'verdict' is distinct from 'pass' then reason := 'page not proved to be the course''s own (E16 ' || coalesce(v_chk->>'verdict', 'no verdict') || ')'; end if;
    end if;
    if reason is not null then
      outcome := 'skipped'; next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action);
      return next; outcome := null; continue;
    end if;
    v_raw := security.intake_page_wording_v1(r.course_id, r.evidence_id, v_url);
    page_quote := left(v_raw, 600);
    if security.intake_month_negated_v1(v_raw, v_m) then
      outcome := 'skipped'; reason := 'the page excludes this month (listed for withdrawal)';
      next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := null; return next; outcome := null; continue;
    end if;
    v_pq := security.intake_period_text_canonical_v1(security.intake_period_text_v1(v_raw, v_lists));
    select array_agg(distinct s.period) into v_named
      from jsonb_to_recordset(v_cal) s(period text, kind text)
     where s.kind = 'start' and s.period ~ '^[a-z][a-z _-]*[0-9]+$' and v_pq ~ ('\m' || regexp_replace(s.period, '[ _-]+', '[ _-]*', 'g') || '\M');
    -- F-INT D1 (setting intake_dates.page_date_admit, default off): where the calendar route finds no named study period, the single full date the course page
    -- prints for this month is admitted when it is corroborated (security.intake_page_date_v1) and the course-specific offering gate passes
    if v_page_admit and v_named is null and r.start_date is null and coalesce(v_raw, '') <> '' then
      v_pd := security.intake_page_date_v1(r.provider_id, r.id, r.course_id, r.evidence_id, v_url, v_m, r.intake_year, v_cal, v_today, v_ahead);
      if (v_pd->>'admit')::boolean then
        v_start := (v_pd->>'date')::date; v_year := extract(year from v_start)::int;
        reason := security.intake_course_applicability_v1(coalesce(v_pd->>'gate', v_raw), v_m, v_year, v_cal, false, null, null);
        if reason is null then
          rule := 'page-date-v1'; start_precision := 'day'; start_quote := v_pd->>'quote'; deadline_kind := 'not_stated';
          periods := case when jsonb_typeof(v_pd->'periods') = 'array' then array(select jsonb_array_elements_text(v_pd->'periods')) end;
          proposal_id := nullif(v_pd->>'proposal_id', '')::uuid;
          calendar_url := coalesce(v_pd->>'calendar_url', v_url); calendar_evidence_id := coalesce(nullif(v_pd->>'calendar_evidence_id', '')::uuid, r.evidence_id);
          new_year := case when r.intake_year is null then v_year end; new_start := v_start;
          outcome := 'filled';
          next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action);
          return next; outcome := null; continue;
        end if;
        outcome := 'skipped'; start_precision := 'month'; start_quote := null;
        next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action);
        return next; outcome := null; continue;
      elsif v_pd->>'skip' is not null and not v_unique then   -- with the unique-month path on (intake_dates.month_unique_match) a page that is not admitted falls through to it, as before
        outcome := 'skipped'; start_precision := 'month'; reason := v_pd->>'skip';
        next_action := case when reason like 'withdrawn:%' then 'human_decision_required' else security.intake_next_action_v1(outcome, reason, false) end;
        next_revisit_at := case when reason like 'withdrawn:%' then null else security.intake_revisit_at_v1(next_action) end;
        return next; outcome := null; continue;
      end if;
    end if;
    if v_named is null then
      if coalesce(v_raw, '') = '' then
        outcome := 'skipped'; start_precision := 'month'; reason := 'no stored reading of the page''s intake wording (month only)';
        next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := null; return next; outcome := null; continue;
      end if;
      if not v_unique then
        outcome := 'skipped'; start_precision := 'month'; reason := 'the course page names no study period of the calendar (month only)';
        next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := null; return next; outcome := null; continue;
      end if;
      -- decision §3: the month takes the date only when exactly one eligible teaching start falls in that month of the intake's year
      select min(s.year) into v_year from jsonb_to_recordset(v_cal) s(kind text, year int, month int, on_date date, year_ok boolean)
       where s.kind = 'start' and s.month = v_m and s.year is not null
         and (s.year_ok or v_pq ~ ('\m' || s.year || '\M'))
         and (s.on_date >= v_today or (s.on_date is null and make_date(s.year, s.month, 1) >= date_trunc('month', v_today)::date))
         and (r.intake_year is null or s.year = r.intake_year);
      if v_year is null then
        outcome := 'skipped'; start_precision := 'month';
        reason := case when r.intake_year is not null then 'the calendar prints no start in this month of the intake''s own year (month only)'
                       when exists (select 1 from jsonb_to_recordset(v_cal) s(kind text, month int, year int, year_ok boolean) where s.kind = 'start' and s.month = v_m and s.year_ok)
                         then 'the calendar''s starts in this month are past (month only)'
                       when exists (select 1 from jsonb_to_recordset(v_cal) s(kind text, month int) where s.kind = 'start' and s.month = v_m)
                         then 'the calendar does not print the year of its start in this month (month only)'
                       else 'the calendar has no future start in this month (month only)' end;
        next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action);
        return next; outcome := null; continue;
      end if;
      -- one entry per period (its dated start when any calendar dates it); two periods, or two dates, are ambiguous
      select count(distinct coalesce(z.pd::text, z.period)), array_agg(distinct z.period) into v_n, v_named
        from (select s.period, min(s.on_date) pd from jsonb_to_recordset(v_cal) s(kind text, period text, year int, month int, on_date date, year_ok boolean)
               where s.kind = 'start' and s.month = v_m and s.year = v_year and (s.year_ok or v_pq ~ ('\m' || s.year || '\M')) group by s.period) z;
      if v_n > 1 then
        outcome := 'skipped'; start_precision := 'month'; periods := v_named;
        reason := 'several study periods start in this month (month only)';
        next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := null; return next; outcome := null; continue;
      end if;
      rule := 'calendar-v3-unique-month';
    end if;
    -- the next start of the period(s) in this month, on or after today, in the intake's own year when it holds one
    select min(s.year) into v_year from jsonb_to_recordset(v_cal) s(kind text, period text, year int, month int, on_date date, year_ok boolean)
     where s.kind = 'start' and s.period = any (v_named) and s.month = v_m and s.year is not null
       and (s.year_ok or v_pq ~ ('\m' || s.year || '\M'))
       and (s.on_date >= v_today or (s.on_date is null and make_date(s.year, s.month, 1) >= date_trunc('month', v_today)::date))
       and (r.intake_year is null or s.year = r.intake_year);
    if v_year is null then
      outcome := 'skipped'; start_precision := 'month';
      reason := case when r.intake_year is not null then 'the calendar prints no start of the named period in the intake''s own year'
                     when exists (select 1 from jsonb_to_recordset(v_cal) s(kind text, period text, year int, month int, year_ok boolean) where s.kind = 'start' and s.period = any (v_named)
                                     and s.month = v_m and s.year is not null and (s.year_ok or v_pq ~ ('\m' || s.year || '\M')))
                       then 'the named period''s starts in this month are past'
                     when exists (select 1 from jsonb_to_recordset(v_cal) s(kind text, period text, month int) where s.kind = 'start' and s.period = any (v_named) and s.month = v_m)
                       then 'the year of the named period is not printed (month only)'
                     else 'the named period does not start in this month' end;
      next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action);
      return next; outcome := null; continue;
    end if;
    -- P0 IQ-00313: the next dated start must lie within the horizon (intake_dates.max_months_ahead); a later one is a later cycle whose year is not proved
    if make_date(v_year, v_m, 1) > (date_trunc('month', v_today) + make_interval(months => v_ahead))::date then
      outcome := 'skipped'; start_precision := 'month';
      reason := 'the year of the named period is not printed for the next cycle: its next dated start is more than ' || v_ahead || ' months away (month only)';
      next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action);
      return next; outcome := null; continue;
    end if;
    select array_agg(distinct s.on_date) filter (where s.on_date is not null), array_agg(distinct s.period), min(s.quote), min(s.proposal_id::text)::uuid, min(s.url), min(s.evidence_id::text)::uuid
      into v_starts, v_pers, v_sq, proposal_id, calendar_url, calendar_evidence_id
      from jsonb_to_recordset(v_cal) s(proposal_id uuid, kind text, period text, year int, month int, on_date date, quote text, url text, evidence_id uuid, year_ok boolean)
     where s.kind = 'start' and s.period = any (v_named) and s.month = v_m and s.year = v_year and (s.year_ok or v_pq ~ ('\m' || s.year || '\M'));
    periods := v_pers; start_quote := v_sq;
    v_start := case when cardinality(v_starts) = 1 then v_starts[1] end;
    -- P0 IQ-00313: a value withdrawn from this intake (the withdrawn event's before_value is the rejected value) is not admitted to it again
    if exists (select 1 from pipeline.course_intake_date_events w
                where w.intake_id = r.id and w.outcome = 'withdrawn'
                  and (w.before_value->>'year')::int is not distinct from v_year and (w.before_value->>'start_date')::date is not distinct from v_start) then
      outcome := 'skipped'; start_precision := 'month'; start_quote := null;
      reason := 'withdrawn: this value was rejected earlier and is not admitted again (a person decides)';
      next_action := 'human_decision_required'; next_revisit_at := null;
      return next; outcome := null; continue;
    end if;
    -- decision §3: no more specific course-level date may contradict it (a full date of this month and year printed on the course page)
    select array_agg(distinct make_date(v_year, v_m, m[1]::int)) into v_page_dates
      from regexp_matches(coalesce(v_raw, ''), '\m(\d{1,2})(?:st|nd|rd|th)?\s+' || (array['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'])[v_m] || '[a-z]*,?\s+' || v_year || '\M', 'gi') m
     where m[1]::int between 1 and 28 or (m[1]::int <= extract(day from (make_date(v_year, v_m, 1) + interval '1 month - 1 day'))::int);  -- fixed: the last day of the month
    if v_page_dates is not null and (v_start is null or not (v_start = all (v_page_dates))) then
      outcome := 'skipped'; start_precision := 'month';
      reason := 'the course page gives its own start date for this intake (' || array_to_string(v_page_dates, ', ') || ')';
      next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := null; return next; outcome := null; continue;
    end if;
    -- direction 5 Nov 2026 15:50 §1, §2: the course page must offer this intake, and a month-only match needs a calendar that applies to the course
    reason := security.intake_course_applicability_v1(v_raw, v_m, v_year, v_cal, rule = 'calendar-v3-unique-month', case when rule <> 'calendar-v3-unique-month' then v_pers end, v_pq);
    if reason is not null then
      outcome := 'skipped'; start_precision := 'month'; periods := v_pers; start_quote := null;
      next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action);
      return next; outcome := null; continue;
    end if;
    start_precision := case when v_start is not null then 'day' else 'year' end;
    if cardinality(v_starts) > 1 then reason := 'two start days in this month: year only'; end if;
    -- the deadline of the matched period(s): one dated closing date before the start; one for international applicants first
    select bool_or(s.applies_to = 'international') into v_intl from jsonb_to_recordset(v_cal) s(kind text, period text, on_date date, applies_to text)
     where s.kind = 'deadline' and s.period = any (v_pers) and s.on_date is not null
       and s.on_date <= coalesce(v_start, make_date(v_year, v_m, 1)) and s.on_date >= coalesce(v_start, make_date(v_year, v_m, 1)) - v_max_before;
    select array_agg(distinct s.on_date), min(s.quote) into v_dl, v_dq
      from jsonb_to_recordset(v_cal) s(kind text, period text, on_date date, quote text, applies_to text)
     where s.kind = 'deadline' and s.period = any (v_pers) and s.on_date is not null
       and coalesce(s.applies_to, 'unstated') in ('international', 'all', 'unstated')
       and (not coalesce(v_intl, false) or s.applies_to = 'international')
       and s.on_date <= coalesce(v_start, make_date(v_year, v_m, 1)) and s.on_date >= coalesce(v_start, make_date(v_year, v_m, 1)) - v_max_before;
    select min(s.rolling_text) into v_roll from jsonb_to_recordset(v_cal) s(kind text, period text, rolling_text text) where s.kind = 'rolling' and s.period = any (v_pers);
    if cardinality(v_dl) = 1 then deadline_kind := 'date'; new_deadline := v_dl[1]; deadline_quote := v_dq;
    elsif v_roll is not null then deadline_kind := 'rolling'; deadline_text := v_roll; deadline_quote := v_roll;
    else deadline_kind := 'not_stated'; end if;
    new_year := case when r.intake_year is null then v_year end;
    new_start := case when r.start_date is null then v_start end;
    new_deadline := case when r.application_deadline is null then new_deadline end;
    outcome := case when new_year is not null or new_start is not null or new_deadline is not null then 'filled' else 'nothing_new' end;
    next_action := security.intake_next_action_v1(outcome, reason,
                     coalesce(r.intake_year, new_year) is not null and coalesce(r.start_date, new_start) is not null and coalesce(r.application_deadline, new_deadline) is not null);
    next_revisit_at := security.intake_revisit_at_v1(next_action);
    return next; outcome := null;
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION security.intake_page_date_v1(p_provider uuid, p_intake uuid, p_course uuid, p_evidence uuid, p_url text, p_month integer, p_intake_year integer, p_cal jsonb, p_today date, p_ahead integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_full text := (array['january','february','march','april','may','june','july','august','september','october','november','december'])[p_month];
  v_mon text := '(?:' || v_full || '|' || left(v_full, 3) || case when p_month = 9 then '|sept' else '' end || ')';
  v_label text := '\m(start dates?|starts?|starting|commenc\w*|intakes?|teaching periods?|study periods?|semester|trimester|term|session|key dates)\M';
  v_other text := '\m(deadlines?|clos(e|es|ing|ed)|apply by|applications? (close|due)|census|orientation|enrolments?|results?|exams?|examinations?|graduation|holidays?|break|recess)\M';
  v_dom text := '\m(domestic|local|australian|permanent residents?|onshore|new zealand|nz)\M';
  v_name text := initcap(v_full);
  v_pat text; v_ap_label boolean := false; v_ap_intl boolean := false; v_ap_note text;
  e text; sent text; m text[]; d date; v_y int; v_day int; v_last int; v_dates date[] := '{}'; v_range boolean := false;
  v_quote text; v_adapter boolean; v_lab boolean; v_q_adapter boolean := false; v_q_note text;
  v_p record; v_route text;
begin
  if p_month is null then return jsonb_build_object('admit', false); end if;
  -- the university's page adapter: its start-date pattern names the page section it reads (the section label of a stored "adapter pattern:" snippet) and,
  -- when it is anchored on international admissions, the audience of every date it returns
  select a.patterns->>'intakes' into v_pat from pipeline.uni_adapters a where a.provider_id = p_provider and a.enabled;
  if v_pat is not null then
    v_ap_intl := right(v_pat, 60) ~* 'international';
    v_ap_label := v_pat ~* v_label or v_ap_intl;
    v_ap_note := coalesce((regexp_match(v_pat, '(open for international admissions|international admissions)', 'i'))[1], (regexp_match(v_pat, v_label, 'i'))[1]);
  end if;
  -- 1 the full dates of the intake's month, with their year, in the stored snippets of the page (never in a sentence about a closing date, census or exam)
  for e in
    select x from (select x from pipeline.coverage_course_pages g,
                          jsonb_array_elements_text(case when jsonb_typeof(g.candidates->'intake_context') = 'array' then g.candidates->'intake_context' else '[]'::jsonb end) x
                    where g.course_id = p_course and (g.url = p_url or g.candidates->>'final_url' = p_url)
                   union
                   select f.quote from pipeline.field_enrich_items f
                    where f.course_id = p_course and f.field = 'intakes' and f.state = 'filled' and f.evidence_id = p_evidence and nullif(btrim(f.quote), '') is not null) z(x)
     order by 1
  loop
    v_adapter := e ~* '^\s*adapter pattern:';
    foreach sent in array regexp_split_to_array(e, '(\.\s+|;|\n)') loop
      continue when sent ~* v_other;
      for m in select x from regexp_matches(sent, '(?:(\d{1,2})(?:st|nd|rd|th)?\s*(?:-|–|—|to|until)\s*)?(\m(\d{1,2})(?:st|nd|rd|th)?\s+' || v_mon || '\.?,?\s+(20\d\d)\M)', 'gi') x loop
        if m[1] is not null then v_range := true; continue; end if;
        v_day := m[3]::int; v_y := m[4]::int;
        v_last := extract(day from (make_date(v_y, p_month, 1) + make_interval(months => 1) - make_interval(days => 1)))::int;
        continue when v_day not between 1 and v_last;
        d := make_date(v_y, p_month, v_day);
        if not d = any (v_dates) then v_dates := v_dates || d; end if;
        -- the quote: the first stored snippet that has the section label before the date (a page label, or the adapter's own for an "adapter pattern:" snippet)
        v_lab := left(e, greatest(position(m[2] in e) - 1, 0)) ~* v_label or (v_adapter and v_ap_label);
        if v_lab and (v_quote is null or (v_q_adapter and not v_adapter)) then
          v_quote := e; v_q_adapter := v_adapter and not (left(e, greatest(position(m[2] in e) - 1, 0)) ~* v_label);
        end if;
      end loop;
    end loop;
  end loop;
  if v_range then return jsonb_build_object('admit', false, 'skip', 'the course page prints a range of days for ' || v_name || ' (page date not admitted)'); end if;
  if cardinality(v_dates) = 0 then return jsonb_build_object('admit', false); end if;     -- no full date of this month: the calendar route decides as before
  if cardinality(v_dates) > 1 then
    return jsonb_build_object('admit', false, 'skip', 'the course page prints several different ' || v_name || ' dates (' || array_to_string(v_dates, ', ') || '): page date not admitted');
  end if;
  d := v_dates[1]; v_y := extract(year from d)::int;
  if p_intake_year is not null and p_intake_year <> v_y then
    return jsonb_build_object('admit', false, 'skip', 'the course page prints ' || d || ' but the intake is for ' || p_intake_year || ' (page date not admitted)');
  end if;
  if d < p_today then return jsonb_build_object('admit', false, 'skip', 'the course page prints ' || d || ', which is past (page date not admitted)'); end if;
  if make_date(v_y, p_month, 1) > (date_trunc('month', p_today) + make_interval(months => p_ahead))::date then
    return jsonb_build_object('admit', false, 'skip', 'the course page prints ' || d || ', more than ' || p_ahead || ' months away (page date not admitted)');
  end if;
  -- 2 a rejected value, or a value withdrawn from this intake, is never admitted again
  if exists (select 1 from pipeline.intake_date_rejections j where j.provider_id = p_provider and j.start_date = d) then
    return jsonb_build_object('admit', false, 'skip', 'the course page prints ' || d || ', a value recorded as rejected for this university (page date not admitted)');
  end if;
  if exists (select 1 from pipeline.course_intake_date_events w where w.intake_id = p_intake and w.outcome = 'withdrawn'
              and (w.before_value->>'year')::int is not distinct from v_y and (w.before_value->>'start_date')::date is not distinct from d) then
    return jsonb_build_object('admit', false, 'skip', 'withdrawn: this value was rejected earlier and is not admitted again (a person decides)');
  end if;
  -- 3 the quote carries its section label before the date
  if v_quote is null then
    return jsonb_build_object('admit', false, 'skip', 'the course page prints ' || d || ' without a section label (start dates, intake, semester ...) before it: page date not admitted');
  end if;
  -- 4 corroboration: P1 an approved main teaching calendar start on that day; P2 the audience is shown (the page names international students only, or the
  -- page adapter reads international admissions only); otherwise P3, page only, not admitted
  select (array_agg(distinct s.proposal_id::text))[1]::uuid proposal_id, array_agg(distinct s.period) periods, min(s.url) url, (array_agg(distinct s.evidence_id::text))[1]::uuid evidence_id into v_p
    from jsonb_to_recordset(p_cal) s(proposal_id uuid, kind text, period text, on_date date, url text, evidence_id uuid, year_ok boolean)
   where s.kind = 'start' and s.on_date = d and coalesce(s.year_ok, false) and s.period !~* '\m(pathway|foundation)\M'
     and not exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'central.calendar_excluded_words'), '[]'::jsonb)) w where lower(coalesce(s.url, '')) like '%' || lower(w) || '%');
  if v_p.proposal_id is not null then v_route := 'P1';
  elsif (v_quote ~* '^\s*adapter pattern:' and v_ap_intl) or (v_quote !~* '^\s*adapter pattern:' and v_quote ~* '\minternational\M' and v_quote !~* v_dom) then v_route := 'P2';
  else
    return jsonb_build_object('admit', false, 'skip', 'the course page prints ' || d || ' but no approved main calendar start is on that day and the page does not show the audience (page only): not admitted');
  end if;
  v_q_note := case when v_quote ~* '^\s*adapter pattern:' and v_ap_note is not null then ' [section label read by the university''s page adapter: ' || v_ap_note || ']' else '' end;
  -- the offering-evidence gate reads the page wording; the dates of an adapter snippet carry no word of their own ("15 February 2027"), so the adapter's section
  -- label is the statement: the one admitted date, labelled as the adapter reads it (a snippet with a label of its own on the page is read as printed)
  return jsonb_build_object('admit', true, 'date', d, 'quote', left(v_quote, 600) || v_q_note, 'route', v_route, 'proposal_id', v_p.proposal_id, 'periods', to_jsonb(v_p.periods),
                            'calendar_url', v_p.url, 'calendar_evidence_id', v_p.evidence_id,
                            'gate', case when v_q_adapter then 'intake dates read by the university''s page adapter (' || coalesce(v_ap_note, 'start dates') || '): ' || to_char(d, 'FMDD FMMonth YYYY') end);
end $function$;

do $c$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'security.intake_dates_plan_v3(uuid[],integer)'::regprocedure) <> '0d11bc5dfc4b0705f0722a1aa7905db6' then raise exception 'the plan was not restored byte for byte'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer)'::regprocedure) <> '80eb7b805fa1d68910623c46308c15da' then raise exception 'the page route was not restored byte for byte'; end if;
end $c$;
