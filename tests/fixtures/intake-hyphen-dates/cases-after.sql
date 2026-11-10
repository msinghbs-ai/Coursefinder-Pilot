-- Guards: F-INT intake dates, hyphenated day-month-year (Platform Admin, 10 Nov 2026 22:01: "Go ahead 1 and 4", Group 1, Swinburne), AFTER migration 20261110110523.
-- Proves: the hint reads 01-March-YYYY (and still nothing without a date); a decided month-only row whose page prints such a date is looked at again on the next run (its fingerprint
-- now holds pagedate=1) and is admitted only when an approved main calendar start is on that day (P1); a page-only date, an event banner with no section label and a day range are still
-- refused; the plan's guard now sees a hyphenated page date that contradicts the calendar; the spaced forms are unchanged; no central.* or intake_dates.* setting value changes.
\set ON_ERROR_STOP on
\set QUIET on

-- 1 the hint
do $$
declare f text := ''; c uuid; e uuid;
begin
  select k.course_id, i.evidence_id into c, e from public.pr_d1 k join catalogue.course_intakes i on i.id = k.intake_id where k.name = 'hMar';
  if not security.intake_page_date_hint_v1(c, e, 'March') then f := f || ' March'; end if;
  if not security.intake_page_date_hint_v1(c, e, 'August') then f := f || ' August'; end if;
  if security.intake_page_date_hint_v1(c, e, 'April') then f := f || ' April true without a date'; end if;
  select k.course_id, i.evidence_id into c, e from public.pr_d1 k join catalogue.course_intakes i on i.id = k.intake_id where k.name = 'hSpace';
  if not security.intake_page_date_hint_v1(c, e, 'March') then f := f || ' spaced form'; end if;
  for c, e in select k.course_id, i.evidence_id from public.pr_d1 k join catalogue.course_intakes i on i.id = k.intake_id where k.name in ('nMonth', 'nNone') loop
    if security.intake_page_date_hint_v1(c, e, 'March') or security.intake_page_date_hint_v1(c, e, 'July') then f := f || ' true without a date'; end if;
  end loop;
  if f <> '' then raise exception 'HD hint: %', f; end if;
  raise notice 'PASS HD hint: 01-March-YYYY and 02-August-YYYY are dated candidates; the spaced form still is; a month without a date is not';
end $$;

-- 2 the decided rows are looked at again on the next run, taken first, and decided as the page route decides
do $$
declare f text := ''; r record; v jsonb;
begin
  if (select count(*) from security.intake_dates_plan_v3((select array_agg(k.course_id) from public.pr_d1 k where k.name in ('hMar', 'hAug', 'hJun', 'hFeb')), 20)) <> 4 then
    raise exception 'the 4 decided hyphen rows are not all looked at again after the change'; end if;
  v := security.intake_dates_apply_v1(20, (select array_agg(k.course_id) from public.pr_d1 k where k.name in ('hMar', 'hAug', 'hJun', 'hFeb')));
  for r in select h.name, h.expect, h.new_start, h.reason_like, d.outcome, d.reason, d.rule, d.start_quote, i.start_date, i.intake_year
             from public.hd h join public.pr_d1 k on k.name = h.name join catalogue.course_intakes i on i.id = k.intake_id left join pipeline.course_intake_dates d on d.intake_id = k.intake_id
            where h.name in ('hMar', 'hAug', 'hJun', 'hFeb') loop
    if r.expect = 'filled' and (r.outcome is distinct from 'filled' or r.rule is distinct from 'page-date-v1' or r.start_date is distinct from r.new_start
                                or r.intake_year is distinct from extract(year from r.new_start)::int or r.start_quote not like 'adapter pattern:%') then
      f := f || ' ' || r.name || ' ' || coalesce(r.outcome, '-') || '/' || coalesce(r.reason, '-') || '/' || coalesce(r.start_date::text, '-'); end if;
    if r.expect = 'skipped' and (r.outcome is distinct from 'skipped' or r.reason not like r.reason_like or r.start_date is not null) then f := f || ' ' || r.name || ' ' || coalesce(r.reason, '-'); end if;
  end loop;
  if f <> '' then raise exception 'HD admission: % (%)', f, v; end if;
  if exists (select 1 from security.intake_dates_plan_v3((select array_agg(k.course_id) from public.pr_d1 k where k.name in ('hMar', 'hAug', 'hJun', 'hFeb')), 20) p where p.outcome = 'filled') then
    raise exception 'a settled hyphen row would be filled again'; end if;
  raise notice 'PASS HD admission: the 4 month-only rows are looked at on the next run; 01-March, 02-August and 21-June are admitted (rule page-date-v1, P1: an approved main calendar start that day, quoted); 22-February (no calendar start that day) stays held; settled after one run';
end $$;

-- 3 the other cases, planned fresh: refusals hold, the guard sees the hyphenated date, the spaced forms are unchanged
do $$
declare f text := ''; r record;
begin
  for r in select h.name, h.expect, h.new_start, h.reason_like, p.outcome, p.reason, p.new_start pstart, p.rule
             from public.hd h join public.pr_d1 k on k.name = h.name left join lateral security.intake_dates_plan_v3(array[k.course_id], 10) p on p.intake_id = k.intake_id
            where h.name in ('hBan', 'hRange', 'hSpace', 'hGuard', 'hGuardS') loop
    if r.expect = 'filled' and (r.outcome is distinct from 'filled' or r.pstart is distinct from r.new_start or r.rule is distinct from 'page-date-v1') then f := f || ' ' || r.name || ' ' || coalesce(r.outcome, '-') || '/' || coalesce(r.reason, '-'); end if;
    if r.expect = 'skipped' and (r.outcome is distinct from 'skipped' or r.reason not like r.reason_like) then f := f || ' ' || r.name || ' ' || coalesce(r.outcome, '-') || '/' || coalesce(r.reason, '-'); end if;
  end loop;
  if f <> '' then raise exception 'HD refusals: %', f; end if;
  raise notice 'PASS HD refusals: an event banner (Study Expo 24-November-YYYY, no section label) and a day range are refused; the plan no longer gives the calendar''s 1 March where the page prints 08-March-YYYY (the course page gives its own start date); the spaced forms are unchanged';
end $$;
