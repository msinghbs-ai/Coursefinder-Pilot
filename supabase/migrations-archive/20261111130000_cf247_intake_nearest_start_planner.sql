-- CF-247 F-INT Rule B in the intake planner for listed providers only (Decision 271; Platform Admin 11 Nov 2026 10:16 AEDT: "Go ahead with Monash and give me
-- exact instructions how to lift the pause").
-- Evidence (production, read only, 11 Nov 2026 09:4x-10:1x AEDT): the Rule B shadow (20261111120000) gives Monash 502 dated rows (284 next start, 218 in month),
--   none ambiguous; the 40-row audit had Monash and RMIT 12 of 12 right. Monash's calendar (summary-dates, reader calendar-v2.3, column years) qualified and was
--   approved at 09:25 AEDT with Semester 1 = 1 Mar 2027 and Semester 2 = 26 Jul 2027.
-- Dry run (production, one transaction rolled back, 11 Nov 2026 10:3x AEDT): every edit applied exactly once; with Monash listed the plan of Monash's courses gave
--   381 filled by Rule B (calendar-v3-nearest-start), 85 filled by the named-period route (the calendar approved 09:25), 35 held by the course-level check (other
--   intake months such as November with no single main-teaching start), 9 research degrees, 32 with no start in or 35 days after the month, the rest held as before.
-- What:
--   1. security.intake_nearest_start_v1: Rule B for one intake (the rules of the shadow, plus the course-level check of the unique-month path): research degrees
--      and rolling wording give no date; only dated, year-proved starts of the approved calendars, on or after today, within intake_dates.max_months_ahead, not a
--      blocked period word and not an application, census, orientation or enrolment line; one start in the stated month, else one within
--      intake_dates.nearest_start_days after it; two or more keep the month; every other month the course offers must also map to one start, and never to the
--      same date (otherwise another academic calendar applies); a full date of the stated month on the course page that differs holds the row.
--   2. security.intake_dates_plan_v3, md5-guarded text edits (body 33e3fef045dbcfa8a0406c64402d4d29 -> ef496c19edb842c19a6aa1aef19e3644):
--      a. reads intake_dates.nearest_start_providers (list of provider ids) and intake_dates.nearest_start_days;
--      b. the inputs fingerprint of a LISTED provider's rows gains ';near=<days>', so only those rows are looked at again (nothing else re-plans);
--      c. where the course page names no study period, a listed provider's row takes Rule B (rule 'calendar-v3-nearest-start'): the withdrawn-value check and the
--         course offering check (security.intake_course_applicability_v1) apply as on the page-date route; otherwise it is held with the reason.
--   intake_dates.nearest_start_providers stays EMPTY: this change admits nothing until a Platform Admin lists a provider (Settings > Pipeline settings, with a
--   reason). intake_dates.month_unique_match stays 0 (P0 IQ-00313); listing a provider is the scoped lift of that containment for that provider only.
-- Guards: G1 (no job), G2 (list and window are settings), G3 (no consumer API object), G4 (cf-247-s531). A passing check switches nothing on.
-- Replaces: security.intake_dates_plan_v3 (same name; md5-guarded text edits, resulting md5 checked).
-- Retires: nothing.
-- Reversal: empty intake_dates.nearest_start_providers (stops all Rule B fills at once); withdraw filled rows through the governed withdrawal; restore the plan body
--   33e3fef045dbcfa8a0406c64402d4d29 by reversing the five edits.

do $g$
begin
  if to_regprocedure('security.intake_dates_plan_v3(uuid[],integer)') is null then raise exception 'required security.intake_dates_plan_v3 is missing'; end if;
  if to_regprocedure('security.intake_course_applicability_v1(text,integer,integer,jsonb,boolean,text[],text)') is null then raise exception 'required security.intake_course_applicability_v1 is missing'; end if;
end $g$;

create or replace function security.intake_nearest_start_v1(p_course uuid, p_intake uuid, p_month int, p_year int, p_raw text, p_cal jsonb, p_today date, p_ahead int, p_days int)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_names text[] := array['january','february','march','april','may','june','july','august','september','october','november','december'];
  v_words text[] := coalesce((select array(select jsonb_array_elements_text(s.value)) from pipeline.platform_toolset_settings s
                               where s.toolset_key = 'pipeline' and s.key = 'central.calendar_qualify_blocked_period_words'), '{}');
  v_y0 int; v_s1 date[]; v_s2 date[]; v_cand date; v_path text; o record; v_other date; v_bad text[] := '{}'; v_same text[] := '{}'; v_pd date[]; v_row record;
begin
  if exists (select 1 from catalogue.courses c join ref.study_levels l on l.id = c.study_level_id where c.id = p_course and l.code in ('doctorate', 'masters_research')) then
    return jsonb_build_object('admit', false, 'skip', 'a research degree is not dated from the coursework calendar (month only)');
  end if;
  if coalesce(p_raw, '') ~* '(rolling|flexible|continuous|any ?time|multiple intakes|throughout the year)' then
    return jsonb_build_object('admit', false, 'skip', 'rolling or flexible intakes: no calendar date (month only)');
  end if;
  -- the candidate start of one month: one start in the month, else one within p_days after the 1st
  for o in select x.m, coalesce(case when x.m = p_month then p_year end,
                                case when make_date(extract(year from p_today)::int, x.m, 1) >= date_trunc('month', p_today)::date
                                     then extract(year from p_today)::int else extract(year from p_today)::int + 1 end) as y
             from (select p_month as m union
                   select array_position(v_names, lower(btrim(i.intake_label))) from catalogue.course_intakes i
                    where i.course_id = p_course and i.status = 'active' and i.id <> p_intake and array_position(v_names, lower(btrim(i.intake_label))) is not null) x
            order by (x.m <> p_month), x.m loop
    select array_agg(distinct s.on_date order by s.on_date) filter (where s.on_date < (make_date(o.y, o.m, 1) + interval '1 month')::date),
           array_agg(distinct s.on_date order by s.on_date) filter (where s.on_date >= (make_date(o.y, o.m, 1) + interval '1 month')::date)
      into v_s1, v_s2
      from jsonb_to_recordset(p_cal) s(kind text, period text, on_date date, year_ok boolean, quote text)
     where s.kind = 'start' and s.year_ok and s.on_date is not null and s.on_date >= p_today
       and s.on_date < (p_today + make_interval(months => p_ahead))
       and s.on_date >= make_date(o.y, o.m, 1) and s.on_date <= make_date(o.y, o.m, 1) + p_days
       and not exists (select 1 from unnest(v_words) w where s.period ilike '%' || w || '%')
       and coalesce(s.quote, '') !~* '(applications?\s+(open|close)|census|orientation|o-?week|enrol)';
    if o.m = p_month then
      v_y0 := o.y;
      if cardinality(v_s1) > 1 or (v_s1 is null and cardinality(v_s2) > 1) then
        return jsonb_build_object('admit', false, 'skip', 'several study periods start in or just after this month (month only)');
      end if;
      v_cand := coalesce(v_s1[1], v_s2[1]); v_path := case when v_s1 is not null then 'in_month' else 'next_start' end;
      if v_cand is null then
        return jsonb_build_object('admit', false, 'skip', 'no main-teaching calendar start in this month or within ' || p_days || ' days after it (month only)');
      end if;
    else
      v_other := case when cardinality(v_s1) = 1 then v_s1[1] when v_s1 is null and cardinality(v_s2) = 1 then v_s2[1] end;
      if v_other is null then v_bad := v_bad || initcap(v_names[o.m]);
      elsif v_other = v_cand then v_same := v_same || initcap(v_names[o.m]); end if;
    end if;
  end loop;
  if cardinality(v_same) > 0 then
    return jsonb_build_object('admit', false, 'skip', 'two of the course''s intake months (' || initcap(v_names[p_month]) || ', ' || array_to_string(v_same, ', ') || ') would take the same calendar start (month only)');
  end if;
  if cardinality(v_bad) > 0 then
    return jsonb_build_object('admit', false, 'skip', 'the course''s other intakes (' || array_to_string(v_bad, ', ') || ') have no single main-teaching start: another academic calendar applies (month only)');
  end if;
  -- a full date of the stated month printed on the course page that differs holds the row
  select array_agg(distinct m[1]::int) into v_pd from regexp_matches(coalesce(p_raw, ''), '\m(\d{1,2})(?:st|nd|rd|th)?(?:\s+|-)' || left(v_names[p_month], 3) || '[a-z]*', 'gi') m;
  if v_pd is not null and not (extract(day from v_cand)::int = all (v_pd)) then
    return jsonb_build_object('admit', false, 'skip', 'the course page gives its own start date for this intake');
  end if;
  select s.period, s.quote, s.proposal_id, s.url, s.evidence_id into v_row
    from jsonb_to_recordset(p_cal) s(kind text, period text, on_date date, year_ok boolean, quote text, proposal_id uuid, url text, evidence_id uuid)
   where s.kind = 'start' and s.year_ok and s.on_date = v_cand
     and not exists (select 1 from unnest(v_words) w where s.period ilike '%' || w || '%')
     and coalesce(s.quote, '') !~* '(applications?\s+(open|close)|census|orientation|o-?week|enrol)'
   order by s.period limit 1;
  return jsonb_build_object('admit', true, 'date', v_cand, 'path', v_path, 'target_year', v_y0, 'period', v_row.period, 'quote', v_row.quote,
                            'proposal_id', v_row.proposal_id, 'calendar_url', v_row.url, 'calendar_evidence_id', v_row.evidence_id);
end
$function$;

revoke all on function security.intake_nearest_start_v1(uuid, uuid, int, int, text, jsonb, date, int, int) from public, anon, authenticated;
comment on function security.intake_nearest_start_v1(uuid, uuid, int, int, text, jsonb, date, int, int) is
  'CF-247 F-INT Rule B (Decision 271) for one intake: the one main-teaching calendar start in the stated month, else the one within intake_dates.nearest_start_days after it, with the course-level, research, rolling and page-date checks. Used by security.intake_dates_plan_v3 for providers in intake_dates.nearest_start_providers only.';

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then raise notice '%: already applied', p_sig; return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  raise notice '%: applied', p_sig;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_all('security.intake_dates_plan_v3(uuid[],integer)', '33e3fef045dbcfa8a0406c64402d4d29', 'ef496c19edb842c19a6aa1aef19e3644',
  array[
    $o$  v_settings text := $o$,
    $o$security.intake_inputs_fp_v1(sets.s, i.evidence_id, c.course_url, v_settings) fp$o$,
    $o$security.intake_inputs_fp_v1(sets.s, i.evidence_id, c.course_url, v_settings || ';wording='$o$,
    $o$security.intake_inputs_fp_v1(r.cal_set, r.evidence_id, r.course_url, v_settings || ';wording='$o$,
    $o$      if not v_unique then
        outcome := 'skipped'; start_precision := 'month'; reason := 'the course page names no study period of the calendar (month only)';$o$],
  array[
    $n$  -- Decision 271 (Rule B): providers listed here take the nearest main-teaching start (security.intake_nearest_start_v1); empty: none
  v_near uuid[] := coalesce((select array_agg(x::uuid) from pipeline.platform_toolset_settings s, jsonb_array_elements_text(s.value) x
                              where s.toolset_key = 'pipeline' and s.key = 'intake_dates.nearest_start_providers' and jsonb_typeof(s.value) = 'array'), '{}');
  v_near_days int := security.pipeline_num_v1('intake_dates.nearest_start_days', 35)::int;
  v_settings text := $n$,
    $n$security.intake_inputs_fp_v1(sets.s, i.evidence_id, c.course_url, v_settings || case when c.provider_id = any (v_near) then ';near=' || v_near_days else '' end) fp$n$,
    $n$security.intake_inputs_fp_v1(sets.s, i.evidence_id, c.course_url, v_settings || case when c.provider_id = any (v_near) then ';near=' || v_near_days else '' end || ';wording='$n$,
    $n$security.intake_inputs_fp_v1(r.cal_set, r.evidence_id, r.course_url, v_settings || case when r.provider_id = any (v_near) then ';near=' || v_near_days else '' end || ';wording='$n$,
    $n$      -- Decision 271 (Rule B), listed providers only (intake_dates.nearest_start_providers): the one main-teaching start in the stated month, else the one
      -- within intake_dates.nearest_start_days after it; the withdrawn-value and course offering checks apply as on the page-date route
      if r.provider_id = any (v_near) then
        v_pd := security.intake_nearest_start_v1(r.course_id, r.id, v_m, r.intake_year, v_raw, v_cal, v_today, v_ahead, v_near_days);
        if coalesce((v_pd->>'admit')::boolean, false) then
          v_start := (v_pd->>'date')::date; v_year := extract(year from v_start)::int;
          if exists (select 1 from pipeline.course_intake_date_events w where w.intake_id = r.id and w.outcome = 'withdrawn'
                        and (w.before_value->>'start_date')::date is not distinct from v_start) then
            outcome := 'skipped'; start_precision := 'month';
            reason := 'withdrawn: this value was rejected earlier and is not admitted again (a person decides)';
            next_action := 'human_decision_required'; next_revisit_at := null; return next; outcome := null; continue;
          end if;
          reason := security.intake_course_applicability_v1(v_raw, v_m, coalesce((v_pd->>'target_year')::int, v_year), v_cal, false, null, null);
          if reason is null then
            rule := 'calendar-v3-nearest-start'; start_precision := 'day'; start_quote := v_pd->>'quote'; deadline_kind := 'not_stated';
            periods := case when v_pd->>'period' is not null then array[v_pd->>'period'] end;
            proposal_id := nullif(v_pd->>'proposal_id', '')::uuid;
            calendar_url := v_pd->>'calendar_url'; calendar_evidence_id := nullif(v_pd->>'calendar_evidence_id', '')::uuid;
            new_year := case when r.intake_year is null then v_year end; new_start := v_start;
            outcome := 'filled';
            next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action);
            return next; outcome := null; continue;
          end if;
          outcome := 'skipped'; start_precision := 'month'; start_quote := null;
          next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action);
          return next; outcome := null; continue;
        end if;
        outcome := 'skipped'; start_precision := 'month'; reason := coalesce(v_pd->>'skip', 'the course page names no study period of the calendar (month only)');
        next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action);
        return next; outcome := null; continue;
      end if;
      if not v_unique then
        outcome := 'skipped'; start_precision := 'month'; reason := 'the course page names no study period of the calendar (month only)';$n$]);

do $post$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.intake_dates_plan_v3(uuid[],integer)'::regprocedure)) <> 'ef496c19edb842c19a6aa1aef19e3644' then
    raise exception 'post-check: security.intake_dates_plan_v3 does not have the recorded body'; end if;
  if (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'intake_dates.nearest_start_providers') <> '[]'::jsonb then
    raise exception 'post-check: this change lists no provider; a Platform Admin lists one with a reason'; end if;
  if security.pipeline_num_v1('intake_dates.month_unique_match', 0) <> 0 then raise exception 'post-check: intake_dates.month_unique_match must stay 0 (P0 IQ-00313)'; end if;
end $post$;
