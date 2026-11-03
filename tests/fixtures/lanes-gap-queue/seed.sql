-- Seed: settings as live (3 Nov 2026), the jobs the change edits with their live commands, the gap queue switch.
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value) values
 ('firecrawl', 'daily_budget_on', 'Daily budget on', 'boolean', 'true'), ('firecrawl', 'daily_budget_total', 'Daily total', 'number', '25000'),
 ('firecrawl', 'daily_share_scholarships', 'Scholarships share', 'number', '100'), ('firecrawl', 'daily_share_course_search', 'Course search share', 'number', '100'),
 ('firecrawl', 'daily_share_reads', 'Reads share', 'number', '100'), ('firecrawl', 'daily_share_central', 'Central share', 'number', '100'), ('firecrawl', 'daily_share_other', 'Other share', 'number', '100'),
 ('pipeline', 'gaps.items_per_run', 'Gap items per run', 'number', '30000'), ('pipeline', 'gaps.recheck_days', 'Recheck days', 'number', '60'),
 ('pipeline', 'search.daily_picked_cap', 'Daily picked cap', 'number', '200');
insert into pipeline.platform_toolsets(key, enforcement) values ('openrouter', 'stop');
insert into pipeline.field_gap_queue_control(id, enabled, owner, reason) values (1, true, gen_random_uuid(), 'standing');
insert into pipeline.course_link_search_settings values (1, true, 200000);
insert into pipeline.scholarship_ai_models values ('m1', 'openai/gpt-4.1-mini');
insert into pipeline.scholarship_ai_prompts values (1, 'prompt');
insert into pipeline.scholarship_ai_extract_settings values (1, array['m1']);
insert into pipeline.fields_in_scope values ('duration', 1), ('level', 2), ('intakes', 3), ('provider_address', 4);
insert into cron.job(jobname, schedule, command, active) values
 ('field-gap-queue', '23 */6 * * *', 'select security.field_gap_queue_tick_v1()', true),
 ('course-link-search-worker', '* * * * *', $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'link_search', 'limit', security.pipeline_num_v1('batch.link_search_worker', 120)::int))$c$, true),
 ('central-find', '2-59/5 * * * *', $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'central_find', 'limit', security.pipeline_num_v1('batch.central_find', 4)::int))$c$, true),
 ('coverage-discover', '* * * * *', $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'discover', 'limit', security.pipeline_num_v1('batch.coverage_discover', 20)::int))$c$, false),
 ('coverage-discover-2', '* * * * *', $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'discover', 'limit', security.pipeline_num_v1('batch.coverage_discover_2', 8)::int))$c$, false),
 ('scholarship-listing', '7-59/15 * * * *', $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode','scholarship_listing','limit',security.scholarship_setting('listing_limit',6)::int))$c$, true),
 ('scholarship-read', '*/5 * * * *', $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode','scholarship_read','limit',security.scholarship_setting('read_limit',20)::int))$c$, true);
insert into pipeline.automation_catalogue(jobname, area, label, description) select jobname, 'pipeline', jobname, 'Job ' || jobname || '.' from cron.job;
