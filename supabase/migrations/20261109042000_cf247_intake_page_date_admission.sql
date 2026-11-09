-- CF-247 F-INT D1 (valid course intake dates; data population mandate 9 Nov 2026; coordinator instruction 9 Nov 2026): the date printed on the course page is admitted as
-- the intake's start date when it is corroborated, behind a switch that is OFF. Nothing is admitted until the Platform Admin switches it on.
-- Why (measured read-only on production, 9 Nov 2026): a course page often prints the start date of an intake ("Start dates: 1 March 2027") while the page
--   names no study period of the university's calendar, so the calendar route (rule calendar-v3) holds the intake month-only with "the course page names no
--   study period of the calendar". The dates are real course evidence, but a page alone does not say which audience a date is for (Macquarie, Western Sydney)
--   and a how-to-apply page is not the course's page (Adelaide).
-- What (existing architecture; no new job, table, engine or screen; the fill goes through security.intake_dates_apply_v1 and its events as today):
--   1 setting intake_dates.page_date_admit (G2): 0 off (default), 1 on. Label, range 0 to 1, unit on/off, section and used_by. Changed on Settings > Pipeline settings
--     with a reason. While it is 0 the plan behaves exactly as before (the fixture compares the plan result of every case before and after the switch).
--   2 security.intake_page_date_v1 (new, read-only): reads the stored snippets of the course's page (the text security.intake_page_wording_v1 joins: the page reader's
--     intake_context items and the filled intakes quotes of the same evidence) and admits a date only when ALL hold:
--       a the page is the course's own (E16 pass) and is not refused, the course is not locked by hand or held: all checked by the plan before this point;
--       b the snippets print exactly one distinct full date in the intake's month with its year (day, month, year), no range of days, outside any sentence about
--         a closing date, census, orientation, enrolment, results, exam, graduation or holiday; the year is the intake's own year when it holds one;
--       c the date is not past and is inside intake_dates.max_months_ahead;
--       d the quote is the verbatim stored snippet the date is printed in, with a section label (start dates, intake, semester, trimester, term, session, ...) before
--         the date, and is stored as start_quote. A snippet written by the university's page adapter ("adapter pattern: 15 February 2027 | 09 August 2027") carries no
--         label of its own: the label is the one the adapter's intakes pattern reads (pipeline.uni_adapters, enabled), appended in brackets to the quote;
--       e corroboration, one of
--           P1  the date equals a dated start (year proved) of the university's approved main teaching calendar (security.calendar_dated_periods_v2: already
--               without calendars set aside by address, by the reader's scope or as obsolete; central.calendar_excluded_words is read there), and the period is
--               not a pathway or foundation period;
--           P2  the audience is evidenced: the page snippet names international students and no domestic, local or other audience, or the snippet is the page
--               adapter's and the adapter's intakes pattern ends on international admissions (Canberra: "Open for international admissions");
--         a date with neither (P3: page only, audience unproven: Macquarie, Western Sydney) is NOT admitted and the intake is held with the reason;
--       f no rejected value (pipeline.intake_date_rejections of that university and date) and no value withdrawn from that intake;
--       g the course-specific offering gate, security.intake_course_applicability_v1, passes: it reads the page wording as stored, or, for the dates of an adapter
--         snippet that carry no offering word, the one admitted date labelled as the adapter reads it.
--   3 security.intake_dates_plan_v3 (md5-guarded edit, 2 additions): the switch is read once, and the check runs where the calendar route finds no named study
--     period of the calendar. A named period, a month-only match (intake_dates.month_unique_match: a page that is not admitted falls through to it), the horizon, the
--     withdrawn-value guard and every skip before this point (including a university with no valid calendar) are unchanged, so the calendar route and its proof rules
--     are untouched. A date printed with a day but no year is never admitted.
--   The fill is recorded as today: outcome filled, rule page-date-v1, start_precision day, the quote in start_quote, the corroborating calendar (P1) in proposal_id,
--   calendar_url and calendar_evidence_id (P2: the page and its evidence), one event row per decision, so gross fills, withdrawals and the net can be measured by
--   rule. A deadline is not taken from a page. Deakin 1 November 2028 cannot come back: it is outside the horizon, it is a rejected value, and a withdrawn value
--   stays withdrawn.
-- Consumer API: unchanged (G3). Only security.* functions and a setting are touched. central.auto_approve_calendar_dates and central.calendar_excluded_words
--   are not touched (the Platform Admin decides them).
-- Replaces: md5-guarded edit of security.intake_dates_plan_v3 (two additions)
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

-- 0 setting (G2) ----------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'intake_dates.page_date_admit', 'Intake dates: admit a start date printed on the course page when it is corroborated',
  'Off (0) by default. When on (1), a start date printed on the course page ("Start dates: 1 March 2027") fills the intake only when the page is the course''s own, the date is the only full date of the intake''s month with its year, it is within the months-ahead limit, the quote is stored, and either the approved main teaching calendar has a start on that day or the page shows the date is for international students. A page whose audience is not shown (page only) is never admitted. Rejected and withdrawn dates, locks and holds still stop it.',
  'number', to_jsonb(0), 0, 1, 'on/off', 1014, 'Intake dates',
  'security.intake_page_date_v1; security.intake_dates_plan_v3; job intake-dates-apply',
  'F-INT D1 (9 Nov 2026): a date printed on a course page is admitted only after a Platform Admin decision, and only with corroboration')
on conflict (toolset_key, key) do nothing;

-- 1 the check ---------------------------------------------------------------------------------------------------------------------------------
create or replace function security.intake_page_date_v1(p_provider uuid, p_intake uuid, p_course uuid, p_evidence uuid, p_url text, p_month integer, p_intake_year integer, p_cal jsonb, p_today date, p_ahead integer)
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
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
comment on function security.intake_page_date_v1(uuid, uuid, uuid, uuid, text, integer, integer, jsonb, date, integer) is 'CF-247 F-INT D1 (9 Nov 2026): reads the stored course page snippets (the text security.intake_page_wording_v1 reads) for the single full date of the intake''s month with its year, and admits it only when it is within the months-ahead limit, not rejected or withdrawn, quoted with its section label, and corroborated by an approved main teaching calendar start on that day (P1) or by the audience shown (P2: the page names international students only, or the university''s page adapter reads international admissions only). Page only (P3) is never admitted. Returns jsonb: admit, date, quote, route, proposal_id, periods, calendar_url, calendar_evidence_id, or skip with the reason. Used by security.intake_dates_plan_v3 only when intake_dates.page_date_admit is 1.';
revoke all on function security.intake_page_date_v1(uuid, uuid, uuid, uuid, text, integer, integer, jsonb, date, integer) from public, anon, authenticated;

-- 2 the plan (md5-guarded edit, two additions) ----------------------------------------------------------------------------------------------------
select pg_temp.edit('security.intake_dates_plan_v3(uuid[],integer)', '1c42216aec7113b5b628396edbe42386', 'intake_page_date_v1',
  array[$o$  r record; v_m int; v_year int;$o$,
        $o$    if v_named is null then
      if coalesce(v_raw, '') = '' then$o$],
  array[$n$  v_page_admit boolean := security.pipeline_num_v1('intake_dates.page_date_admit', 0) = 1;  -- F-INT D1: a date printed on the course page, default off
  v_pd jsonb;
  r record; v_m int; v_year int;$n$,
        $n$    -- F-INT D1 (setting intake_dates.page_date_admit, default off): where the calendar route finds no named study period, the single full date the course page
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
      if coalesce(v_raw, '') = '' then$n$],
  array[1, 1]);
comment on function security.intake_dates_plan_v3(uuid[], integer) is 'CF-247 intake dates plan v3 (decisions 5 Nov 2026; P0 IQ-00313, 8 Nov 2026; F-INT 9 Nov 2026): the horizon (intake_dates.max_months_ahead), calendar values listed in pipeline.intake_date_rejections are not used, a withdrawn value is not admitted again; a row held for evidence is looked at again from stored inputs and the inputs fingerprint holds the page wording; and, only while intake_dates.page_date_admit is 1, a corroborated date printed on the course page is admitted where the calendar route finds no named study period (rule page-date-v1).';
