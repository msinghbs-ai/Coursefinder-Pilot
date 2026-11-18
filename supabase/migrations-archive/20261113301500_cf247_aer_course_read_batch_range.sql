-- CF-247 AER: the hourly course-read run queues as many reads as the reader finishes in an hour (Platform Admin 13 Nov 2026 09:30: "Use available vendor
-- capacity and safe bounded concurrency rather than artificially maintaining the scheduled rate"; "fix the shared cause through the normal engineering release
-- process"; "Do not create new scheduler machinery").
-- Evidence (13 Nov 2026 11:40 AEDT): with 30 task starts a minute and 16 AI calls at once (09:40), course reads finish at 600 to 1,200 an hour, but the hourly
--   job aer-scheduled-read queues at most batch.aer_schedule_courses (range maximum 200) a run, so the reader waits empty for most of each hour; about 10,000
--   eligible reads remain. The Layer 4 back-pressure (aer.schedule_layer4_max), the daily cap (15,000), the credit floor and every admission rule still apply.
-- What: batch.aer_schedule_courses range 1..200 -> 1..1,000; value 200 -> 800 (about one hour of reading at the measured rate). No job, schedule or code change.
-- Guards: G1 (no new job), G2 (the batch stays a setting, changed with the Platform Admin's reason), G3 (no consumer API object), Decision 260.
-- Reversal without code: set the value back on Settings › Pipeline settings, with a reason.
-- Replaces: nothing. Retires: nothing.

update pipeline.platform_toolset_settings
   set max_value = 1000, value = to_jsonb(800), updated_at = now(),
       reason = 'Platform Admin 13 Nov 2026 09:30: the hourly course-read run queues about an hour of reading (measured 600 to 1,200 reads an hour)'
 where toolset_key = 'pipeline' and key = 'batch.aer_schedule_courses' and (value #>> '{}')::numeric = 200;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('toolsets', 'setting_change', 'pipeline.batch.aer_schedule_courses',
        jsonb_build_object('from', 200, 'to', 800, 'max_value', 1000, 'reason', 'Platform Admin 13 Nov 2026 09:30: on-demand AER backlog, reader capacity'), null);
