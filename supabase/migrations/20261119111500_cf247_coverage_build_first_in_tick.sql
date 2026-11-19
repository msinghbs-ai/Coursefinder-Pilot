-- CF-247 s720 follow-up (S2-Build; Platform Admin 19 Nov 2026 08:17 and 10:50): the chunked coverage build runs first in its due ticks.
--
-- What was read after 20261119104500 went live (19 Nov 2026 11:03-11:12 AEDT, rolled-back read-backs through the dry-run workflow):
--   * rollup-scheduler and admission-rule-runner a, b and c: 8 runs each, no failure, no statement time-out.
--   * course-coverage-build: deferred on all 8 due ticks. security.rollup_tick_v1 estimates a target's time as its longest successful run in
--     rollup.keep_days (14 days), here 112 s from the full rebuild before 20261119104500; a target whose estimate passes
--     rollup.tick_finish_by_seconds (100) runs only when it is the first target of a tick, and course-coverage-build (priority 50) comes after
--     group A's every-minute priority 10 targets, so it never comes first. The chunked build takes about 5 s (789 courses, dry run).
-- What it changes (data only; no table, function or job; the dispatcher is not changed; the consumer API is not touched, G3 75/48):
--   course-coverage-build takes priority 5 in group A, so on its due minutes (every 3 minutes) it is the first target of the tick.
-- Replaces: priority 50 of course-coverage-build.
-- Retires: nothing.

update pipeline.rollup_targets
   set priority = 5, updated_at = now(),  -- fixed: the target's order in its group, as the target's own schedule
       note = coalesce(note, '') || ' | 19 Nov 2026 (20261119111500, s720): priority 5, first in its due ticks (the 14-day longest run of the full rebuild kept it deferred)'
 where target_code = 'course-coverage-build' and priority = 50 and schedule = '1-59/3 * * * *';

do $c$
declare v_p int;
begin
  select priority into v_p from pipeline.rollup_targets where target_code = 'course-coverage-build';
  if v_p is distinct from 5 then raise exception 'course-coverage-build priority is %, expected 5', v_p; end if;
  if exists (select 1 from pipeline.rollup_targets where rollup_group = 'A' and enabled and priority < 5 and target_code <> 'course-coverage-build') then
    raise exception 'another group A target already runs before priority 5';
  end if;
end $c$;
