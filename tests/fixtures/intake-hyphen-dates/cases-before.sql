-- Guards: F-INT intake dates, hyphenated day-month-year (Platform Admin, 10 Nov 2026 22:01: "Go ahead 1 and 4", Group 1, Swinburne): the setup and the baseline BEFORE migration
--   20261110110523, on the code 20261110170000 leaves (production before that migration: hint 6adf9102..., page route 52bad9de..., plan 06255497...).
-- A Swinburne-shaped university (measured read-only on production, 10 Nov 2026): an approved main calendar with semester 1, semester 2 and a winter term; a page adapter whose start-date
-- pattern reads "Start dates" and returns dates written "01-March-2027"; not anchored on international admissions (P1 only). Every date is relative to the clock, so the cases do not age.
-- Nothing here touches central.* settings. The helpers public.pr_d1_prov and public.pr_d1_course are those of tests/fixtures/intake-page-date-recovery/cases-before.sql.
\set ON_ERROR_STOP on
\set QUIET on

-- settings as production (10 Nov 2026): the page route on, named-period lists on, the unique-month path off, the job on
update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key in ('intake_dates.page_date_admit', 'intake_dates.name_period_lists');
update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'intake_dates.month_unique_match';
update pipeline.platform_toolset_settings set value = to_jsonb(true) where toolset_key = 'pipeline' and key = 'intake_dates.apply_enabled';

create table public.hd (name text primary key, label text, expect text, new_start date, reason_like text);

do $$
declare
  y1 int := public.pr_dy(3, 1); y2 int := public.pr_dy(8, 2); yJ int := public.pr_dy(6, 21); yF int := public.pr_dy(2, 22); yO int := public.pr_dy(10, 18); yN int := public.pr_dy(11, 24);
  v_swin text := 'Start dates ([0-9]{1,2}-[A-Z][a-z]{2,8}-20[0-9]{2})';
  s_main text := 'adapter pattern: 01-March-' || y1 || ' | 02-August-' || y2;
  s_tri text := 'adapter pattern: 22-February-' || yF || ' | 21-June-' || yJ || ' | 18-October-' || yO;
begin
  perform public.pr_d1_prov('Swinburne', 'https://www.fixture-hdswin.example/student-administration/calendar/', jsonb_build_array(
    jsonb_build_object('period', 'semester 1', 'y', y1, 'm', 3, 'd', 1), jsonb_build_object('period', 'semester 2', 'y', y2, 'm', 8, 'd', 2),
    jsonb_build_object('period', 'winter term', 'y', yJ, 'm', 6, 'd', 21)), v_swin);
  -- admitted after the change (P1: an approved main calendar start on the page's day)
  perform public.pr_d1_course('hMar', 'Swinburne', 'March', array[s_main], 'filled', make_date(y1, 3, 1));
  insert into public.hd values ('hMar', 'March', 'filled', make_date(y1, 3, 1), null);
  perform public.pr_d1_course('hAug', 'Swinburne', 'August', array[s_main], 'filled', make_date(y2, 8, 2));
  insert into public.hd values ('hAug', 'August', 'filled', make_date(y2, 8, 2), null);
  perform public.pr_d1_course('hJun', 'Swinburne', 'June', array[s_tri], 'filled', make_date(yJ, 6, 21));
  insert into public.hd values ('hJun', 'June', 'filled', make_date(yJ, 6, 21), null);
  -- still refused after the change
  perform public.pr_d1_course('hFeb', 'Swinburne', 'February', array[s_tri], 'skipped');                                                   -- 22 February: no calendar start that day (P3)
  insert into public.hd values ('hFeb', 'February', 'skipped', null, '%no approved main calendar start is on that day%');
  perform public.pr_d1_course('hBan', 'Swinburne', 'November', array['Upcoming events Swinburne Study Expo 24-November-' || yN], 'skipped');   -- an event banner: no section label
  insert into public.hd values ('hBan', 'November', 'skipped', null, '%without a section label%');
  perform public.pr_d1_course('hRange', 'Swinburne', 'March', array['Start dates 1-5 March ' || y1], 'skipped');                          -- a range of days stays a range
  insert into public.hd values ('hRange', 'March', 'skipped', null, '%range of days%');
  perform public.pr_d1_course('hSpace', 'Swinburne', 'March', array['adapter pattern: 01 March ' || y1], 'filled', make_date(y1, 3, 1)); -- the spaced form, unchanged
  insert into public.hd values ('hSpace', 'March', 'filled', make_date(y1, 3, 1), null);
  -- the plan's guard: the page names semester 1 (calendar 1 March) and prints its own date for that month, 8 March
  perform public.pr_d1_course('hGuard', 'Swinburne', 'March', array['Semester 1 Start dates 08-March-' || y1], 'skipped');
  insert into public.hd values ('hGuard', 'March', 'skipped', null, '%gives its own start date%');
  perform public.pr_d1_course('hGuardS', 'Swinburne', 'March', array['Semester 1 Start dates 08 March ' || y1], 'skipped');               -- the spaced form of the same, unchanged
  insert into public.hd values ('hGuardS', 'March', 'skipped', null, '%gives its own start date%');
  perform search.refresh_course_enrichment_scoped_v1((select array_agg(k.course_id) from public.pr_d1 k join public.hd h on h.name = k.name), true);
end $$;

-- the plan on the code before the change (no decision row yet, so every case is planned)
create table public.hd_before as
select h.name, p.outcome, p.reason, p.new_start, p.rule from public.hd h join public.pr_d1 k on k.name = h.name left join lateral security.intake_dates_plan_v3(array[k.course_id], 10) p on p.intake_id = k.intake_id;
do $$
declare f text := ''; r record;
begin
  for r in select * from public.hd_before order by name loop
    -- the defects: a hyphenated date is not read, so the page route finds nothing and the row is month only; the guard does not see the page's own date
    if r.name in ('hMar', 'hAug', 'hJun', 'hFeb') and (r.outcome is distinct from 'skipped' or r.reason not like '%names no study period%') then f := f || ' ' || r.name || ' ' || coalesce(r.outcome, '-') || '/' || coalesce(r.reason, '-'); end if;
    if r.name = 'hGuard' and (r.outcome is distinct from 'filled' or r.new_start is distinct from make_date(public.pr_dy(3, 1), 3, 1)) then f := f || ' hGuard ' || coalesce(r.outcome, '-') || '/' || coalesce(r.reason, '-'); end if;
    -- unchanged by the change
    if r.name = 'hSpace' and (r.outcome is distinct from 'filled' or r.new_start is distinct from make_date(public.pr_dy(3, 1), 3, 1) or r.rule is distinct from 'page-date-v1') then f := f || ' hSpace ' || coalesce(r.outcome, '-') || '/' || coalesce(r.reason, '-'); end if;
    if r.name = 'hRange' and (r.outcome is distinct from 'skipped' or r.reason not like '%range of days%') then f := f || ' hRange ' || coalesce(r.reason, '-'); end if;
    if r.name = 'hGuardS' and (r.outcome is distinct from 'skipped' or r.reason not like '%gives its own start date%') then f := f || ' hGuardS ' || coalesce(r.outcome, '-') || '/' || coalesce(r.reason, '-'); end if;
  end loop;
  if f <> '' then raise exception 'HD baseline: %', f; end if;
  raise notice 'PASS HD baseline (code before 20261110110523): a page date written 01-March-YYYY is not read (4 intakes month only), the plan admits the calendar''s 1 March where the page prints 08-March-YYYY; the spaced forms (01 March YYYY, 08 March YYYY) and a day range are read as before';
end $$;

-- the hourly decision on the code before the change, for the rows the page route would admit: month only, and the hint is false, so the fingerprint stays and the row is not looked at again
do $$
declare v jsonb; c uuid; e uuid;
begin
  v := security.intake_dates_apply_v1(20, (select array_agg(k.course_id) from public.pr_d1 k where k.name in ('hMar', 'hAug', 'hJun', 'hFeb')));
  if exists (select 1 from catalogue.course_intakes i join public.pr_d1 k on k.intake_id = i.id where k.name in ('hMar', 'hAug', 'hJun', 'hFeb') and i.start_date is not null) then raise exception 'a hyphen case is filled before the change: %', v; end if;
  select k.course_id, i.evidence_id into c, e from public.pr_d1 k join catalogue.course_intakes i on i.id = k.intake_id where k.name = 'hMar';
  if security.intake_page_date_hint_v1(c, e, 'March') then raise exception 'the hint already reads 01-March-YYYY before the change'; end if;
  if exists (select 1 from security.intake_dates_plan_v3((select array_agg(k.course_id) from public.pr_d1 k where k.name in ('hMar', 'hAug', 'hJun', 'hFeb')), 20)) then
    raise exception 'the decided hyphen rows are planned again before the change (their fingerprint should be unchanged)'; end if;
  raise notice 'PASS HD baseline gate: the 4 decided rows are month only, the hint is false for 01-March-YYYY, and the next run does not look at them again (the production stock: 303 Swinburne rows on 10 Nov 2026)';
end $$;
