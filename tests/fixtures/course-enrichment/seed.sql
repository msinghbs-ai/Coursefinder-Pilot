-- CF-247 Release B: the live rows this change reads or changes (3 Nov 2026): the starting source rules of the course fields, the field register,
-- the central model, the standing queue switched on, job field-gap-queue as it runs today (schedule 23 */6 * * *) and its catalogue row
insert into ref.countries(id, iso_alpha2, name) values ('00000000-0000-0000-0000-0000000000a1', 'AU', 'Australia'), ('00000000-0000-0000-0000-0000000000a2', 'NZ', 'New Zealand'),
  ('00000000-0000-0000-0000-0000000000a3', 'CA', 'Canada');
insert into pipeline.field_source_rules(country_code, field, sources, reason, updated_at) values
 ('ALL', 'campus', array['adapter', 'ai_stored'], 'live', now()), ('ALL', 'duration', array['adapter', 'ai_stored'], 'live', now()),
 ('ALL', 'delivery', array['adapter', 'ai_stored'], 'live', now()), ('ALL', 'international', array['institution_rule', 'adapter', 'ai_stored'], 'live', now()),
 ('ALL', 'english', array['ai_stored'], 'live', now()), ('ALL', 'intakes', array['ai_stored'], 'live', now()),
 ('ALL', 'description', array['ai_stored'], 'live', now()), ('ALL', 'deadline', array['ai_stored'], 'live', now()),
 ('ALL', 'level', array['adapter', 'ai_title'], 'live', now());
insert into pipeline.field_register(field, level, label, grp, sort, reader, active) values
 ('delivery', 'course', 'Delivery mode', 'Course page', 1, 'enrich', true), ('duration', 'course', 'Duration', 'Course page', 2, 'enrich', true),
 ('english', 'course', 'English', 'Entry', 3, 'enrich', true), ('description', 'course', 'Course description', 'Course page', 4, 'enrich', true);
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by) values
 ('pipeline', 'gaps.recheck_days', 'r', 'h', 'number', '60', 7, 365, 'days', 104, 'Re-read and retry', 'security.field_gap_queue_tick_v1'),
 ('pipeline', 'enrich.course_text_items_per_day', 'c', 'h', 'number', '500', 0, 20000, 'items', 1101, 'Course description and deadline', 'security.enrich_course_text_gaps_v1 (job field-gap-queue)'),
 ('pipeline', 'binding.identity_check', 'b', 'h', 'number', '1', 0, 1, 'on/off', 319, 'Course pages', 'x');
insert into pipeline.field_gap_queue_control values (1, true, null, 'standing');
insert into pipeline.field_gap_queue_checkpoint(id) values (1);
insert into pipeline.central_ai_settings values (1, 'openai/gpt-4.1-mini', 'mini');
insert into cron.job(jobname, schedule, command) values ('field-gap-queue', '23 */6 * * *', 'select security.field_gap_queue_run_v1()');
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('field-gap-queue', 'Course pages', 30, 'Fill the gaps (standing queue) and cross-check', 'Every 6 hours: cross-checks held duration, level and delivery against the latest course page reading. Runs through security.field_gap_queue_run_v1: the gaps are found in bounded slices.', 6, false);
