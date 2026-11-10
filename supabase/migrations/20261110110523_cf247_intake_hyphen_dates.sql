-- CF-247 F-INT intake dates: read a day-month-year date written with hyphens ("01-March-2027") (Platform Admin, 10 Nov 2026 22:01: "Go ahead 1 and 4", Group 1, Swinburne).
-- ROOT CAUSE (live, project fxcwkweaxjtknorudmwp, SELECT only, 10 Nov 2026 AEDT): Swinburne's page adapter stores its start dates as "01-March-2027 | 02-August-2027". The page route
--   (intake_dates.page_date_admit = 1, 20261109042000 and 20261110170000), its hint and the plan's "the course page gives its own start date" guard read a day month year only when the parts
--   are separated by spaces ("1 March 2027"). So 303 Swinburne intakes whose page prints the exact date were decided "the course page names no study period (month only)" and their hint was
--   false, so they were never looked at again. Only Swinburne stores this form (303 of 15,342 decision rows, measured on the stored page quotes).
-- WHAT THIS CHANGES (no new job, table, setting or screen; the fill still goes through security.intake_dates_apply_v1 and its events; md5-guarded; nothing is switched on or off):
--   1 security.intake_page_date_hint_v1: day month year may be separated by spaces or by one hyphen. A Swinburne intake whose wording prints such a date is now "ready", so its inputs
--     fingerprint carries ';pagedate=1' and it is looked at on the next run and taken first (the mechanism of 20261110170000; no other provider's fingerprint changes).
--   2 security.intake_page_date_v1: the same in the day-month-year pattern (v_f1). The capture groups are unchanged. A range of days ("1-5 March 2027") is still a range. Corroboration is
--     unchanged: a page date is admitted only when an approved main calendar start falls on that day (P1) or the audience is shown (P2); page only (P3) is never admitted; the label,
--     closing-date, rejection, withdrawal and offering rules are unchanged.
--   3 security.intake_dates_plan_v3: the same in the guard that refuses a calendar date when the course page prints its own date for that month and year.
--   central.* settings, intake_dates.month_unique_match and the calendar qualifier are not touched.
-- RESULT ON PILOT: first applied 10 Nov 2026 11:05 UTC (ledger version 20261110110523, in a first, apply-once form of the same three edits: statement md5 c796aa325a5825cf01d16f2c91852f3f).
--   A run limited to Swinburne's courses then admitted 265 exact start dates at 148 courses (1 Mar 129, 2 Aug 120, 21 Jun 10, 5 Jul 5, 1 Feb 1), each a start of Swinburne's approved
--   2027 higher education calendar on the same day (P1); 36 page-only dates, 11 identity refusals and 2 past dates stayed held. This file is the re-runnable form: on Pilot it is a no-op.
-- Live definitions this change edits (pg_proc.prosrc md5, read 10 Nov 2026), before -> after:
--   security.intake_page_date_hint_v1(uuid,uuid,text) 6adf9102074633735e9f30ffe529072c -> 7e008fa7981cf32ab89765829b7a3439
--   security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer) 52bad9ded722b889b97c746b7209e63a -> de956842ab53e842c7b4baaf578ff0f0
--   security.intake_dates_plan_v3(uuid[],integer) 06255497ef431b0ae0d9fca6460c6cb5 -> 33e3fef045dbcfa8a0406c64402d4d29
-- The edits are guarded: the migration stops, and nothing is applied, if a live body is neither the one it replaces nor the one it writes; applying it twice changes nothing. The text before is
-- restored by supabase/held/intake_hyphen_dates_forward_recovery.sql. Depends on 20261110170000 (the before bodies are the bodies it writes).
-- Consumer API (G3): not touched; only security.* functions of the intake plan are edited, and nothing the Website or Zoho read changes shape.
-- No operational value is written into code (G2); no job is added (G1). No setting, ledger row, read or admission is written; no setting value changes.
-- Tested: tests/fixtures/intake-hyphen-dates/run.sh (isolated PostgreSQL; never a Supabase project).
-- Replaces: the three bodies above are edited in place (md5-guarded); otherwise nothing
-- Retires: nothing
-- Nothing is dropped, deleted or renamed by this migration.

do $g$
declare r record;
begin
  for r in select * from (values ('security.intake_page_date_hint_v1(uuid,uuid,text)'), ('security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer)'),
                                 ('security.intake_dates_plan_v3(uuid[],integer)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
end $g$;

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

-- 1 the hint
select pg_temp.edit_all('security.intake_page_date_hint_v1(uuid,uuid,text)', '6adf9102074633735e9f30ffe529072c', '7e008fa7981cf32ab89765829b7a3439',
  array[$o$(?:st|nd|rd|th)?\s+' || v_mon || '\.?,?\s+20\d\d\M')$o$],
  array[$n$(?:st|nd|rd|th)?(?:\s+|-)' || v_mon || '\.?(?:,?\s+|-)20\d\d\M')$n$]);

-- 2 the page route (v_f1, day month year)
select pg_temp.edit_all('security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer)', '52bad9ded722b889b97c746b7209e63a', 'de956842ab53e842c7b4baaf578ff0f0',
  array[$o$(?:st|nd|rd|th)?\s+' || v_mon || '\.?,?\s+(20\d\d)\M(?!\s*:))'$o$],
  array[$n$(?:st|nd|rd|th)?(?:\s+|-)' || v_mon || '\.?(?:,?\s+|-)(20\d\d)\M(?!\s*:))'$n$]);

-- 3 the plan (the course page's own date for the month and year)
select pg_temp.edit_all('security.intake_dates_plan_v3(uuid[],integer)', '06255497ef431b0ae0d9fca6460c6cb5', '33e3fef045dbcfa8a0406c64402d4d29',
  array[$o$(?:st|nd|rd|th)?\s+' || (array['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'])[v_m] || '[a-z]*,?\s+' || v_year || '\M'$o$],
  array[$n$(?:st|nd|rd|th)?(?:\s+|-)' || (array['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'])[v_m] || '[a-z]*(?:,?\s+|-)' || v_year || '\M'$n$]);

do $post$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.intake_page_date_hint_v1(uuid,uuid,text)'::regprocedure)) <> '7e008fa7981cf32ab89765829b7a3439' then raise exception 'post-check: security.intake_page_date_hint_v1 does not have the recorded body md5'; end if;
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer)'::regprocedure)) <> 'de956842ab53e842c7b4baaf578ff0f0' then raise exception 'post-check: security.intake_page_date_v1 does not have the recorded body md5'; end if;
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.intake_dates_plan_v3(uuid[],integer)'::regprocedure)) <> '33e3fef045dbcfa8a0406c64402d4d29' then raise exception 'post-check: security.intake_dates_plan_v3 does not have the recorded body md5'; end if;
end $post$;
