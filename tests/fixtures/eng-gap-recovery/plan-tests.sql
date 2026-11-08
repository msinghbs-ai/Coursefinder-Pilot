-- Guards: Platform Admin 8 Nov 2026 14:06 (IQ-00072 zero-yield plans): the automatic planner does not pay again for "Find course pages" and "Build the adapter" of a university whose onboarding stopped
-- for a cause time does not clear and where nothing has changed; it proposes them again when something changes, after the quiet days, or when the setting is off; a person's Run now is never held.
-- Runs on plan-harness.sql with the live security.enrich_plan_v1 and migration 20261108122000. Invented rows only. Isolated local PostgreSQL only.
\set ON_ERROR_STOP on
create or replace function pg_temp.ok(c boolean, what text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL %', what; end if; raise notice 'PASS %', what; end $$;
create or replace function pg_temp.steps(p uuid) returns text language sql as $$ select coalesce((select string_agg(x->>'step', ',' order by x->>'step') from jsonb_array_elements(security.enrich_plan_v1(p)->'steps') x), '') $$;
create or replace function pg_temp.held(p uuid) returns text language sql as $$ select coalesce((select string_agg((x->>'step') || ':' || (x->>'code'), ',' order by x->>'step') from jsonb_array_elements(security.enrich_plan_v1(p)->'not_proposed') x), '') $$;
-- a university with 4 courses, no pages, a website and a phone, central pages searched 10 days ago, onboarding stopped 5 days ago for too few pages
insert into catalogue.providers(id, display_name, website, phone) values ('00000000-0000-0000-0000-00000000d001', 'Micro University', 'https://micro.example/', '123'), ('00000000-0000-0000-0000-00000000d002', 'Other University', 'https://other.example/', '123');
insert into catalogue.courses(id, provider_id, lifecycle_status, created_at, duration_value, study_level_id, delivery_mode, primary_field_id, open_to_international)
select gen_random_uuid(), pv, 'active', now() - interval '40 days', 1, gen_random_uuid(), 'on_campus', gen_random_uuid(), true from generate_series(1, 4) g, (values ('00000000-0000-0000-0000-00000000d001'::uuid), ('00000000-0000-0000-0000-00000000d002')) v(pv);
insert into pipeline.provider_central_search(provider_id, state, searched_at) select id, 'done', now() - interval '10 days' from catalogue.providers;
insert into pipeline.provider_onboarding(provider_id, status, stop_reason, created_at, updated_at, finished_at)
 values ('00000000-0000-0000-0000-00000000d001', 'stopped', 'too_few_pages', now() - interval '5 days', now() - interval '5 days', now() - interval '5 days'),
        ('00000000-0000-0000-0000-00000000d002', 'stopped', 'crashed: timeout', now() - interval '5 days', now() - interval '5 days', now() - interval '5 days');

-- 0 before the change is switched on for the test: both universities are offered every step (the hold is the only difference between the cases below)
select set_config('request.jwt.claim.sub', '', false);
select pg_temp.ok(security.pipeline_num_v1('plans.stalled_onboarding_hold', 1) = 1 and security.pipeline_num_v1('plans.stalled_onboarding_quiet_days', 30) = 30, 'the hold is on and the quiet period is 30 days by default');
select pg_temp.ok(security.plan_stalled_onboarding_v1('00000000-0000-0000-0000-00000000d001') is not null, 'a university whose onboarding stopped (too few pages) with nothing changed is stalled');
select pg_temp.ok(pg_temp.steps('00000000-0000-0000-0000-00000000d001') = 'fields,scholarships', 'the automatic planner is not offered Find course pages or Build the adapter');
select pg_temp.ok(pg_temp.held('00000000-0000-0000-0000-00000000d001') = 'adapter:onboarding_stalled,pages:onboarding_stalled', 'both are listed as not proposed, with the code onboarding_stalled');
select pg_temp.ok(security.enrich_plan_v1('00000000-0000-0000-0000-00000000d001')->'not_proposed'->0->>'reason' like 'onboarding stopped (too few pages) on %', 'the reason names the stop and says what brings it back');
select pg_temp.ok((security.enrich_plan_v1('00000000-0000-0000-0000-00000000d001')->>'est_credits')::numeric = 7, 'the estimate no longer counts the page search or the adapter (4 for fields, 3 for scholarships; 51 with every step)');
select pg_temp.ok(pg_temp.steps('00000000-0000-0000-0000-00000000d002') = 'adapter,fields,pages,scholarships', 'a stop for another cause (a crash) is not held: only a cause time does not clear is');

-- 1 a person's Run now is never held
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000ad', false);
select pg_temp.ok(pg_temp.steps('00000000-0000-0000-0000-00000000d001') = 'adapter,fields,pages,scholarships', 'a person behind the call sees every step');
select set_config('request.jwt.claim.sub', '', false);

-- 2 each change brings the steps back
insert into catalogue.courses(id, provider_id, lifecycle_status, duration_value, study_level_id, delivery_mode, primary_field_id, open_to_international) values ('00000000-0000-0000-0000-00000000d0c9', '00000000-0000-0000-0000-00000000d001', 'active', 1, gen_random_uuid(), 'on_campus', gen_random_uuid(), true);
select pg_temp.ok(pg_temp.steps('00000000-0000-0000-0000-00000000d001') = 'adapter,fields,pages,scholarships', 'a course added since the stop brings the steps back');
delete from catalogue.courses where id = '00000000-0000-0000-0000-00000000d0c9';
select pg_temp.ok(pg_temp.steps('00000000-0000-0000-0000-00000000d001') = 'fields,scholarships', 'held again once the change is gone (the test reads state, not a flag)');
insert into pipeline.coverage_course_pages(course_id, provider_id, status, read_status, read_at, evidence_id) select id, provider_id, 'bound', 'read', now() - interval '1 day', gen_random_uuid() from catalogue.courses where provider_id = '00000000-0000-0000-0000-00000000d001' limit 1;
select pg_temp.ok(pg_temp.steps('00000000-0000-0000-0000-00000000d001') like '%pages%' or pg_temp.steps('00000000-0000-0000-0000-00000000d001') like '%adapter%', 'a course page read and stored since the stop brings the steps back');
delete from pipeline.coverage_course_pages where provider_id = '00000000-0000-0000-0000-00000000d001';
update pipeline.provider_central_search set searched_at = now() - interval '1 day' where provider_id = '00000000-0000-0000-0000-00000000d001';
select pg_temp.ok(pg_temp.steps('00000000-0000-0000-0000-00000000d001') like '%adapter%', 'a central search finished since the stop brings the steps back');
update pipeline.provider_central_search set searched_at = now() - interval '10 days' where provider_id = '00000000-0000-0000-0000-00000000d001';
select pg_temp.ok(pg_temp.steps('00000000-0000-0000-0000-00000000d001') = 'fields,scholarships', 'a central search older than the stop does not');
update pipeline.provider_onboarding set created_at = now() - interval '40 days', updated_at = now() - interval '40 days', finished_at = now() - interval '40 days' where provider_id = '00000000-0000-0000-0000-00000000d001';
select pg_temp.ok(pg_temp.steps('00000000-0000-0000-0000-00000000d001') like '%adapter%', 'after the quiet days the steps come back by themselves');
update pipeline.provider_onboarding set created_at = now() - interval '5 days', updated_at = now() - interval '5 days', finished_at = now() - interval '5 days' where provider_id = '00000000-0000-0000-0000-00000000d001';
update pipeline.platform_toolset_settings set value = '0'::jsonb where key = 'plans.stalled_onboarding_hold' and toolset_key = 'pipeline';
select pg_temp.ok(security.plan_stalled_onboarding_v1('00000000-0000-0000-0000-00000000d001') is null and pg_temp.steps('00000000-0000-0000-0000-00000000d001') like '%adapter%', 'with the setting off the plan is as before');
select pg_temp.ok((security.enrich_plan_v1('00000000-0000-0000-0000-00000000d001')->>'est_credits')::numeric = 51, 'and the estimate is the full 51 credits again');
update pipeline.platform_toolset_settings set value = '1'::jsonb where key = 'plans.stalled_onboarding_hold' and toolset_key = 'pipeline';
select pg_temp.ok(security.plan_stalled_onboarding_v1('00000000-0000-0000-0000-00000000d001') is not null, 'and on again');

-- 3 a running or finished onboarding is not a stop
update pipeline.provider_onboarding set status = 'done' where provider_id = '00000000-0000-0000-0000-00000000d001';
select pg_temp.ok(security.plan_stalled_onboarding_v1('00000000-0000-0000-0000-00000000d001') is null, 'an onboarding that finished is not stalled');
select pg_temp.ok(not has_function_privilege('anon', 'security.plan_stalled_onboarding_v1(uuid)', 'execute') and not has_function_privilege('authenticated', 'security.plan_stalled_onboarding_v1(uuid)', 'execute'), 'the test is not callable by anon or authenticated');
