-- CF-247 s720 follow-up (S2-Build; Platform Admin 19 Nov 2026 08:17 and 10:50: "< 8 s (< 10 s target)").
--
-- What was read (19 Nov 2026 11:36-11:52 AEDT, live rollup runs, read back through the dry-run workflow): the chunked coverage build runs on
-- every due tick since 20261119111500 and its daily counts equal the table (530,137; Australia 385,545), but 800 courses take 11.7 to 16.0 s live
-- (5.4 s in the rolled-back dry run): above the target.
-- What it changes (settings value and one rollup target's schedule; no table, function or job; G3 75/48):
--   batch.course_coverage_courses 800 -> 400 and course-coverage-build every 2 minutes, so a run takes about 6 to 8 s and the whole table
--   (36,031 courses) is rebuilt about every 3 hours.
-- Replaces: batch.course_coverage_courses 800 and the 3-minute schedule of course-coverage-build.
-- Retires: nothing.

update pipeline.platform_toolset_settings
   set value = to_jsonb(400), updated_at = now(),
       reason = reason || ' | 19 Nov 2026 11:55 (20261119115000): 400 courses every 2 minutes; 800 took 11.7 to 16.0 s live'
 where toolset_key = 'pipeline' and key = 'batch.course_coverage_courses' and value = to_jsonb(800);

update pipeline.rollup_targets
   set schedule = '0-58/2 * * * *', expected_ms = 7000, updated_at = now(),  -- fixed: the target's own schedule; batch size is the setting
       note = coalesce(note, '') || ' | 19 Nov 2026 (20261119115000, s720): 400 courses every 2 minutes, the whole table about every 3 hours'
 where target_code = 'course-coverage-build' and schedule = '1-59/3 * * * *';

do $c$
begin
  if security.pipeline_num_v1('batch.course_coverage_courses', 0) <> 400 then raise exception 'batch.course_coverage_courses is not 400'; end if;
  if (select schedule from pipeline.rollup_targets where target_code = 'course-coverage-build') <> '0-58/2 * * * *' then
    raise exception 'course-coverage-build schedule not changed';
  end if;
end $c$;
