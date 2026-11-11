-- CF-247 F-CDESC (Layer 4 build-up; Platform Admin 11 Nov 2026 15:21 AEDT "set it"): review-capacity back-pressure for course descriptions switched on.
--
-- Evidence (project fxcwkweaxjtknorudmwp, SELECT only, 11 Nov 2026 14:50 AEDT): enrich.course_text_items_per_day was raised to 20,000 by the
-- Platform Admin at 14:43 ("Layer 4 Cleanup 11/11"); enrich.course_description_pending_global_max was still 0 (off, shipped off 8 Nov "the
-- Platform Admin or Controller sets it from the capacity numbers"). Layer 4 held 5,500 pending items, about 2,300 of them course descriptions; the
-- machine rule settles about 450 an hour and every reading it declines waits for a person.
-- What this changes: enrich.course_description_pending_global_max 0 -> 1,500 (range 0 to 20,000 unchanged). While 1,500 or more course descriptions
-- wait in Layer 4, the standing gap queue and Fill / Recheck description add no new description readings (readings already queued finish); they
-- resume on their own below it. No function, job, schedule, Layer 4 item, reading or consumer object (G3) changes. Nothing dropped or deleted.
-- Forward recovery: the same update with 0 (Settings > Pipeline settings > Course description and deadline).
-- Replaces: the value 0 of enrich.course_description_pending_global_max
-- Retires: nothing

update pipeline.platform_toolset_settings set value = '1500'::jsonb, updated_at = now(),
       reason = 'CF-247 Layer 4 build-up (20261111220000), Platform Admin 11 Nov 15:21 "set it": new description readings pause while 1,500 wait for a person'
 where toolset_key = 'pipeline' and key = 'enrich.course_description_pending_global_max';

do $post$
begin
  if security.pipeline_num_v1('enrich.course_description_pending_global_max', 0) <> 1500 then raise exception 'post-check: enrich.course_description_pending_global_max'; end if;
end $post$;
