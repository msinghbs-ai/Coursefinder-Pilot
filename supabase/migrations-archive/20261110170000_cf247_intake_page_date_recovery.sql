-- CF-247 F-INT (Platform Admin directive 10 Nov 2026 14:02: admit verified EXACT intake dates faster, reuse stored sources, never invent a day, month, year or deadline).
-- ROOT CAUSES (live, project fxcwkweaxjtknorudmwp, SELECT only, 10 Nov 2026 03:00 to 04:00 UTC; the skipped counts are the latest decision of each intake in the 24 h to 03:08 UTC):
--   1,068 intakes were skipped in 24 h (1,091 events). Genuinely month only (the stored page prints no day for the month): 838. Identity (E16): 77. No stored reading of the page: 55. Page prints one
--   future date but no calendar start shares it and the audience is not shown (P3, protected D1 decision): 39. Calendar period not dated in that month or year: 26. Page date past: 19. Calendar set aside: 6.
--   Several dates: 5. Page route admits it now but the row was decided before the D1 switch and waits for its revisit: 3.
--   The 24 h skipped list is NOT where the exact dates are. THE STOCK is: 600 undated intakes at 5 providers (Torrens 243, Canberra 147, Toi Ohomai 75, Federation 72, TAFE Queensland 63) pass today
--   every check of the D1 page route (E16 pass, no lock, no hold, not refused, month not excluded, corroborated by an approved main calendar start, P1, or by the audience, P2, the offering gate passes). They were
--   decided "the course page names no study period (month only)" BEFORE the D1 switch went on (9 Nov 09:30 UTC) and sit on the 14-day revisit that the D3 backfill gave them (next_revisit_at spread to 24 Nov,
--   about 640 a day for all 9,030 rows): the plan skips a row whose inputs fingerprint is unchanged until its revisit time, and the fingerprint holds neither the D1 switch nor whether the page prints a date.
--   Only 34 have filled since the switch went on. They convert at about 43 a day by the clock instead of in the next hourly runs.
--   A second cause of missed exact dates is extraction. security.intake_page_date_v1 reads only "D Month YYYY". Measured on the stored wording: "Month D, YYYY" (NorthTec, Melbourne Polytechnic), a year heading
--   with days and months under it ("2027: 11 Jan, 1 Mar", Stanley College, "Semester 1 2027: 1 March", University of Otago), and a page that lists the month for two years (a past date and the next one, which
--   the route refused as "several different dates"). It also has a correctness defect: "16 Nov 2027:" in "2026: ..., 16 Nov 2027: 11 Jan, ..." is the heading of the next list, not the year of 16 November;
--   the route read it as 16 November 2027 (live events: "the course page prints 2027-11-16 / 2027-11-22 / 2027-11-30 but no approved main calendar start ..."), so a calendar start on such a day would have admitted a wrong date.
--   Third: a row that already holds its exact start date and whose page names no period is overwritten by the calendar route as "skipped: names no study period", which erases the stored quote and rule of an
--   admitted date (the catalogue date stays) the next time the row is planned (a new approved calendar for the provider changes the fingerprint of every row it has).
-- WHAT THIS CHANGES (no new job, table, setting or screen; the fill still goes through security.intake_dates_apply_v1 and its events; md5-guarded; nothing is switched on or off):
--   1 security.intake_page_date_hint_v1(course, evidence, intake label) NEW, read-only: true when the stored wording of the course prints a dated candidate for the intake's month (day month year, month day year, or a year heading
--     with days and months), the same snippets security.intake_page_date_v1 reads. It is a superset test, cheap, and decides nothing.
--   2 security.intake_dates_plan_v3: while intake_dates.page_date_admit is 1, an undated intake whose wording passes the hint carries ';pagedate=1' in its inputs fingerprint (so a decision taken before the page route existed is no
--     longer the same input and the row is looked at now, not at its revisit time; a row the page route has already filled keeps the suffix, so the fill itself does not change its fingerprint) and is taken first in the batch (its own tier, fair by university within it, the batch size unchanged: batch.intake_dates_apply). Nothing else changes
--     while the switch is 0: no row carries the suffix and the order is the one of today. A row that already holds its start date and year and whose page names no period is kept as nothing_new with its stored rule and quote.
--   3 security.intake_page_date_v1: the extraction above. A year followed by a colon is a heading, never the year of the date before it. Month day year and year-heading lists are read. Of the dates a page prints for the month,
--     only those of the intake's own year (when it holds one), still to come and inside intake_dates.max_months_ahead count; one is admitted when corroborated (P1 or P2, unchanged), two are ambiguous (unchanged). A day without a year is never
--     admitted. The label, closing-date, census, range, rejection, withdrawal, audience (P3 never admits) and offering rules are unchanged. central.auto_approve_calendar_dates and intake_dates.month_unique_match are not touched.
-- EXPECTED GAIN (measured by calling the live functions read only on live data, not an estimate): 600 exact start dates at 5 providers within the next 3 hourly runs after release (200 a run); at most 30 more from the extraction fixes
--   (Stanley College 3, University of Otago up to 28, four "Month D, YYYY" pages), each only if corroborated. Withdrawals of an admitted date (the existing governed path) are not forecast. No deadline is gained: the page route does not read
--   deadlines, the approved calendars hold 54 dated deadlines (all already used) and 13 course pages print a deadline sentence, 7 for international students (a separate decision, not taken here).
-- Live definitions this change edits (pg_proc.prosrc md5, read 10 Nov 2026), before -> after:
--   security.intake_dates_plan_v3(uuid[],integer) 0d11bc5dfc4b0705f0722a1aa7905db6 -> 06255497ef431b0ae0d9fca6460c6cb5
--   security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer) 80eb7b805fa1d68910623c46308c15da -> 52bad9ded722b889b97c746b7209e63a
--   security.intake_page_date_hint_v1(uuid,uuid,text) (new) -> 6adf9102074633735e9f30ffe529072c
-- The edits are guarded: the migration stops, and nothing is applied, if a live body is neither the one it replaces nor the one it writes; applying it twice changes nothing. The text before is kept in
-- supabase/held/intake_page_date_recovery_forward_recovery.sql. Depends on 20261109042000 (the page route as it leaves it) and 20261109040000 (the fingerprint that holds the wording).
-- Consumer API (G3): not touched; only security.* functions of the intake plan are edited, and nothing the Website or Zoho read changes shape: the existing job writes the same catalogue columns as today.
-- No operational value is written into code (G2): the horizon is intake_dates.max_months_ahead, the batch is batch.intake_dates_apply, the switch is intake_dates.page_date_admit; the only constants are the section words and
--   the format patterns of a date, which are text rules, not operating values. No job is added (G1). No setting, ledger row, read or admission is written; no setting value changes.
-- Replaces: security.intake_dates_plan_v3 and security.intake_page_date_v1 are edited in place (md5-guarded); the earlier text is kept in supabase/held/intake_page_date_recovery_forward_recovery.sql; otherwise nothing
-- Retires: nothing
-- Nothing is dropped, deleted or renamed by this migration.

do $g$
declare r record;
begin
  for r in select * from (values ('security.intake_dates_plan_v3(uuid[],integer)'), ('security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer)'), ('security.pipeline_num_v1(text,numeric)'),
                                 ('security.intake_inputs_fp_v1(text,uuid,text,text)'), ('security.intake_wording_fp_v1(uuid,uuid)'), ('security.intake_next_action_v1(text,text,boolean)'), ('security.intake_revisit_at_v1(text)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  if to_regclass('pipeline.coverage_course_pages') is null or to_regclass('pipeline.field_enrich_items') is null or to_regclass('pipeline.course_intake_dates') is null then raise exception 'a table this change reads is missing'; end if;
end $g$;

-- ----------------------------------------------------------------------------------------------------------------------------------------- 1 the hint (read only; applying again writes the same text)
create or replace function security.intake_page_date_hint_v1(p_course uuid, p_evidence uuid, p_label text) returns boolean
language plpgsql stable security definer set search_path to ''
as $function$
-- intake-page-date-hint-v1
declare v_m int := array_position(array['january','february','march','april','may','june','july','august','september','october','november','december'], lower(btrim(p_label)));
        v_full text; v_mon text;
begin
  if v_m is null then return false; end if;
  v_full := (array['january','february','march','april','may','june','july','august','september','october','november','december'])[v_m];
  v_mon := '(?:' || v_full || '|' || left(v_full, 3) || case when v_m = 9 then '|sept' else '' end || ')';
  -- the snippets security.intake_page_wording_v1 joins: the page reader's intake_context items of the course and the filled intakes quotes of the evidence
  return exists (
    select 1 from (select x from pipeline.coverage_course_pages g,
                          jsonb_array_elements_text(case when jsonb_typeof(g.candidates->'intake_context') = 'array' then g.candidates->'intake_context' else '[]'::jsonb end) x
                    where g.course_id = p_course
                   union all
                   select f.quote from pipeline.field_enrich_items f
                    where f.course_id = p_course and f.field = 'intakes' and f.state = 'filled' and f.evidence_id = p_evidence and nullif(btrim(f.quote), '') is not null) z(x)
     where z.x ~* ('\m\d{1,2}(?:st|nd|rd|th)?\s+' || v_mon || '\.?,?\s+20\d\d\M')
        or z.x ~* ('\m' || v_mon || '\.?\s+\d{1,2}(?:st|nd|rd|th)?,?\s+20\d\d\M')
        or (z.x ~ '\m20\d\d\s*:' and z.x ~* ('\m\d{1,2}(?:st|nd|rd|th)?\s+' || v_mon || '\M')));
end
$function$;
comment on function security.intake_page_date_hint_v1(uuid, uuid, text) is 'CF-247 F-INT (10 Nov 2026): true when the stored wording of a course (the intake_context snippets of its page and the filled intakes quotes of the evidence, the text security.intake_page_date_v1 reads) prints a dated candidate for the intake month: day month year, month day year, or a year heading with days and months under it. A superset test: it decides nothing and admits nothing. Used by security.intake_dates_plan_v3 only while intake_dates.page_date_admit is 1, to look at such an intake now and to take it first.';
revoke all on function security.intake_page_date_hint_v1(uuid, uuid, text) from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- 2 the page route (md5-guarded replacement)
do $pd$
declare v_src text; v_sig regprocedure := to_regprocedure('security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer)');
begin
  v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
  -- fixed: the guard is the md5 of the live function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = '52bad9ded722b889b97c746b7209e63a' then return; end if;                           -- already applied
  if md5(v_src) <> '80eb7b805fa1d68910623c46308c15da' then raise exception 'live security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer) differs from the definition this change edits (body md5 %)', md5(v_src); end if;
  execute $ex$
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
  e text; sent text; m record; d date; v_y int; v_day int; v_last int; v_dates date[] := '{}'; v_range boolean := false;
  v_quote text; v_adapter boolean; v_own boolean; v_q_adapter boolean := false; v_q_note text;
  v_p record; v_route text; v_hits jsonb := '[]'::jsonb; h jsonb; v_cand date[]; v_fut date[]; v_pos int;
  v_f1 text := '(?:(\d{1,2})(?:st|nd|rd|th)?\s*(?:-|–|—|to|until)\s*)?(\m(\d{1,2})(?:st|nd|rd|th)?\s+' || v_mon || '\.?,?\s+(20\d\d)\M(?!\s*:))';  -- day month year; a year followed by a colon is the heading of a list ("2027: 11 Jan, 1 Mar"), not the year of the date before it
  v_f2 text := '(\m' || v_mon || '\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(20\d\d)\M(?!\s*:))';                                       -- month day, year ("March 1, 2027", "February 1st 2027")
  v_f3 text := '(20\d\d)\s*:\s*((?:\d{1,2}(?:st|nd|rd|th)?\s+[A-Za-z]{3,9}\.?\s*[,|]?\s*)+)';                                       -- a year heading and the days and months listed under it ("2027: 11 Jan, 1 Mar")
  v_f3t text := '(\d{1,2})(?:st|nd|rd|th)?\s+' || v_mon || '\M';
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
      for m in
        select 'dmy' f, x[3] dd, x[4] yy, x[2] txt, x[1] rg from regexp_matches(sent, v_f1, 'gi') x
        union all select 'mdy', x[2], x[3], x[1], null from regexp_matches(sent, v_f2, 'gi') x
        union all select 'yh', t[1], b[1], b[2], null from regexp_matches(sent, v_f3, 'g') b, regexp_matches(b[2], v_f3t, 'gi') t
      loop
        if m.rg is not null then v_range := true; continue; end if;
        v_day := m.dd::int; v_y := m.yy::int;
        v_last := extract(day from (make_date(v_y, p_month, 1) + make_interval(months => 1) - make_interval(days => 1)))::int;
        continue when v_day not between 1 and v_last;
        d := make_date(v_y, p_month, v_day);
        -- the section label before the date (a page label, or the adapter's own for an "adapter pattern:" snippet)
        v_pos := greatest(position(m.txt in e) - 1, 0);
        v_own := left(e, v_pos) ~* v_label;
        v_hits := v_hits || jsonb_build_object('d', d, 'e', e, 'ad', v_adapter, 'own', v_own, 'lab', v_own or (v_adapter and v_ap_label));
      end loop;
    end loop;
  end loop;
  if v_range then return jsonb_build_object('admit', false, 'skip', 'the course page prints a range of days for ' || v_name || ' (page date not admitted)'); end if;
  select coalesce(array_agg(distinct (z->>'d')::date), '{}') into v_dates from jsonb_array_elements(v_hits) z;
  if cardinality(v_dates) = 0 then return jsonb_build_object('admit', false); end if;     -- no full date of this month: the calendar route decides as before
  -- the dates of the intake's own year when it holds one (a date of another year is not its date)
  v_cand := case when p_intake_year is null then v_dates else coalesce((select array_agg(x order by x) from unnest(v_dates) x where extract(year from x)::int = p_intake_year), '{}') end;
  if cardinality(v_cand) = 0 then
    return jsonb_build_object('admit', false, 'skip', 'the course page prints ' || v_dates[1] || ' but the intake is for ' || p_intake_year || ' (page date not admitted)');
  end if;
  -- the dates still to come inside the horizon: a page that lists this month for several years (a past date and the next one) names one upcoming date, as the calendar route reads it; two upcoming dates are ambiguous
  v_fut := coalesce((select array_agg(x order by x) from unnest(v_cand) x where x >= p_today and make_date(extract(year from x)::int, p_month, 1) <= (date_trunc('month', p_today) + make_interval(months => p_ahead))::date), '{}');
  if cardinality(v_fut) = 0 then
    d := v_cand[cardinality(v_cand)];
    if d < p_today then return jsonb_build_object('admit', false, 'skip', 'the course page prints ' || d || ', which is past (page date not admitted)'); end if;
    return jsonb_build_object('admit', false, 'skip', 'the course page prints ' || d || ', more than ' || p_ahead || ' months away (page date not admitted)');
  end if;
  if cardinality(v_fut) > 1 then
    return jsonb_build_object('admit', false, 'skip', 'the course page prints several different ' || v_name || ' dates (' || array_to_string(v_fut, ', ') || '): page date not admitted');
  end if;
  d := v_fut[1]; v_y := extract(year from d)::int;
  -- the quote: the first stored snippet that prints this date with a section label before it; a snippet whose only label is the adapter's gives way to a page snippet that has one
  for h in select z from jsonb_array_elements(v_hits) z where (z->>'d')::date = d loop
    if (h->>'lab')::boolean and (v_quote is null or (v_q_adapter and not (h->>'ad')::boolean)) then
      v_quote := h->>'e'; v_q_adapter := (h->>'ad')::boolean and not (h->>'own')::boolean;
    end if;
  end loop;
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
end $function$
  $ex$;
  v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
  if md5(v_src) <> '52bad9ded722b889b97c746b7209e63a' then raise exception 'security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer) after the edit has body md5 %, expected 52bad9ded722b889b97c746b7209e63a', md5(v_src); end if;
end $pd$;
comment on function security.intake_page_date_v1(uuid, uuid, uuid, uuid, text, integer, integer, jsonb, date, integer) is 'CF-247 F-INT D1 (9 Nov 2026), extraction extended 10 Nov 2026: reads the stored course page snippets (the text security.intake_page_wording_v1 reads) for the dates printed for the intake month (day month year; month day year; the days and months listed under a year heading; a year followed by a colon is a heading, never the year of the date before it). Of those, only the dates of the intake own year (when it holds one), still to come and inside the months-ahead limit count; exactly one is admitted, and only when it is not rejected or withdrawn, is quoted with its section label, and is corroborated by an approved main teaching calendar start on that day (P1) or by the audience shown (P2). Page only (P3) is never admitted, a day without a year is never admitted. Returns jsonb: admit, date, quote, route, proposal_id, periods, calendar_url, calendar_evidence_id, or skip with the reason. Used by security.intake_dates_plan_v3 only when intake_dates.page_date_admit is 1.';

-- ----------------------------------------------------------------------------------------------------------------------------------------- 3 the plan (md5-guarded edit, six additions)
create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  -- fixed: line endings are normalised, so the edit applies the same however the text arrives
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_all('security.intake_dates_plan_v3(uuid[],integer)', '0d11bc5dfc4b0705f0722a1aa7905db6', '06255497ef431b0ae0d9fca6460c6cb5',
  array[$o1$           security.intake_inputs_fp_v1(sets.s, i.evidence_id, c.course_url, v_settings) fp,
           ceil(row_number() over (partition by c.provider_id order by i.course_id, i.id)::numeric / v_share) rnd, sets.served, f.rank frank, c.provider_id = any (v_pilot) pilot
      from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id join sets on sets.provider_id = c.provider_id
$o1$,
        $o2$                          and d.inputs_fp is not distinct from security.intake_inputs_fp_v1(sets.s, i.evidence_id, c.course_url, v_settings || ';wording=' || security.intake_wording_fp_v1(i.course_id, i.evidence_id))$o2$,
        $o3$    select q.id, q.course_id, q.provider_id, q.intake_label, q.intake_year, q.start_date, q.application_deadline, q.evidence_id, q.course_url, q.cal_set, q.fp from ($o3$,
        $o4$     order by case when q.pilot and q.pilot_seq <= v_pilot_rows then 0 when not q.pilot then 1 else 2 end,$o4$,
        $o5$calendar_set := r.cal_set; inputs_fp := security.intake_inputs_fp_v1(r.cal_set, r.evidence_id, r.course_url, v_settings || ';wording=' || security.intake_wording_fp_v1(r.course_id, r.evidence_id));$o5$,
        $o6$    if v_named is null then
      if coalesce(v_raw, '') = '' then$o6$],
  array[$n1$           security.intake_inputs_fp_v1(sets.s, i.evidence_id, c.course_url, v_settings) fp, pd.ready pdready, pd.sfx pdsfx,
           ceil(row_number() over (partition by c.provider_id, pd.ready order by i.course_id, i.id)::numeric / v_share) rnd, sets.served, f.rank frank, c.provider_id = any (v_pilot) pilot
      from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id join sets on sets.provider_id = c.provider_id
      -- F-INT (10 Nov 2026): while intake_dates.page_date_admit is 1, an undated intake whose stored wording prints a dated candidate for its month is looked at now and taken first
      -- (a row the page route has already filled keeps the suffix, so its fingerprint is the same before and after the fill and it is not looked at again for that)
      cross join lateral (select r0.ready, r0.ready or (v_page_admit and i.start_date is not null and exists (select 1 from pipeline.course_intake_dates k0 where k0.intake_id = i.id and k0.rule = 'page-date-v1')) as sfx
                            from (select case when v_page_admit and i.start_date is null then security.intake_page_date_hint_v1(i.course_id, i.evidence_id, i.intake_label) else false end as ready) r0) pd
$n1$,
        $n2$                          and d.inputs_fp is not distinct from security.intake_inputs_fp_v1(sets.s, i.evidence_id, c.course_url, v_settings || ';wording=' || security.intake_wording_fp_v1(i.course_id, i.evidence_id) || case when pd.sfx then ';pagedate=1' else '' end)$n2$,
        $n3$    select q.id, q.course_id, q.provider_id, q.intake_label, q.intake_year, q.start_date, q.application_deadline, q.evidence_id, q.course_url, q.cal_set, q.fp, q.pdready, q.pdsfx from ($n3$,
        $n4$     order by case when q.pdready then 0 when q.pilot and q.pilot_seq <= v_pilot_rows then 1 when not q.pilot then 2 else 3 end,$n4$,
        $n5$calendar_set := r.cal_set; inputs_fp := security.intake_inputs_fp_v1(r.cal_set, r.evidence_id, r.course_url, v_settings || ';wording=' || security.intake_wording_fp_v1(r.course_id, r.evidence_id) || case when r.pdsfx then ';pagedate=1' else '' end);$n5$,
        $n6$    -- F-INT (10 Nov 2026): a row that already holds its start date and year (admitted from the course page or the calendar) and whose page names no period has nothing new to add; it is kept
    -- as nothing_new with the rule, quote and source it was admitted with, not overwritten as skipped (that erased the quote of an admitted date the next time its fingerprint changed)
    if v_named is null and r.start_date is not null and r.intake_year is not null then
      select d.rule, d.start_quote, d.proposal_id, d.calendar_url, d.calendar_evidence_id, d.periods into rule, start_quote, proposal_id, calendar_url, calendar_evidence_id, periods
        from pipeline.course_intake_dates d where d.intake_id = r.id and d.outcome in ('filled', 'nothing_new');
      rule := coalesce(rule, 'calendar-v3'); outcome := 'nothing_new'; start_precision := 'day'; deadline_kind := 'not_stated';
      next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := null;   -- nothing to look at again until an input changes (the fingerprint)
      return next; outcome := null; continue;
    end if;
    if v_named is null then
      if coalesce(v_raw, '') = '' then$n6$]);
comment on function security.intake_dates_plan_v3(uuid[], integer) is 'CF-247 intake dates plan v3 (decisions 5 Nov 2026; P0 IQ-00313, 8 Nov 2026; F-INT 9 and 10 Nov 2026): the horizon (intake_dates.max_months_ahead), calendar values listed in pipeline.intake_date_rejections are not used, a withdrawn value is not admitted again; a row held for evidence is looked at again from stored inputs and the inputs fingerprint holds the page wording; while intake_dates.page_date_admit is 1 a corroborated date printed on the course page is admitted where the calendar route finds no named study period (rule page-date-v1), an undated intake whose stored wording prints a dated candidate for its month is looked at now (its fingerprint holds pagedate=1) and taken first in the batch, and a row that already holds its start date and year and whose page names no period is kept as nothing_new with its stored rule and quote.';

-- ----------------------------------------------------------------------------------------------------------------------------------------- register, post-check
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.intake_page_date_hint_v1', 'Platform', 'F-INT: true when the stored wording of a course prints a dated candidate for the intake month; the intake plan looks at such an intake now and takes it first (read only)', 'active', '{}', '20261110170000')
on conflict do nothing;

do $post$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.intake_page_date_hint_v1(uuid,uuid,text)'::regprocedure)) <> '6adf9102074633735e9f30ffe529072c' then raise exception 'post-check: security.intake_page_date_hint_v1 does not have the recorded body md5'; end if;
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer)'::regprocedure)) <> '52bad9ded722b889b97c746b7209e63a' then raise exception 'post-check: security.intake_page_date_v1 does not have the recorded body md5'; end if;
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.intake_dates_plan_v3(uuid[],integer)'::regprocedure)) <> '06255497ef431b0ae0d9fca6460c6cb5' then raise exception 'post-check: security.intake_dates_plan_v3 does not have the recorded body md5'; end if;
end $post$;
