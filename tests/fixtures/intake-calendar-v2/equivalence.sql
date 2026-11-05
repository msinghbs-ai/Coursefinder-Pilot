-- Guards: Platform Admin decision 5 Nov 2026 §3: plan v3 changes nothing the named-period rule already decided; it adds only unique-month fills.
\set ON_ERROR_STOP on
begin;
delete from pipeline.course_intake_dates;
create temp table v2 as select * from security.intake_dates_plan_v2(null, 100000);
create temp table v3 as select * from security.intake_dates_plan_v3(null, 100000);
do $$ declare n2 int := (select count(*) from v2); n3 int := (select count(*) from v3); bad int; added int;
begin
  if n2 <> n3 or n2 = 0 then raise exception 'row counts differ: v2 % v3 %', n2, n3; end if;
  select count(*) into bad from v2 join v3 using (intake_id)
   where (v2.outcome, v2.reason, v2.new_year, v2.new_start, v2.new_deadline) is distinct from (v3.outcome, v3.reason, v3.new_year, v3.new_start, v3.new_deadline)
     and not (v2.reason = 'the course page names no study period of the calendar (month only)' and v3.rule = 'calendar-v3-unique-month');
  select count(*) into added from v2 join v3 using (intake_id) where v2.outcome = 'skipped' and v3.rule = 'calendar-v3-unique-month' and v3.outcome = 'filled';
  if bad <> 0 then raise exception '% rows decided differently by plan v3 outside the unique-month rule', bad; end if;
  if exists (select 1 from v3 where next_action is null or inputs_fp is null or calendar_set is null) then raise exception 'a v3 row without next action, fingerprint or calendar set'; end if;
  raise notice 'PASS equivalence: % rows; plan v3 decides exactly as plan v2 except % month-only rows the unique-month rule fills; every row has a next action', n3, added;
end $$;
rollback;
