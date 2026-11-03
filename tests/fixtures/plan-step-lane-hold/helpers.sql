-- Fixture helpers (IQ-00064): a running Find course pages task of a plan step, the lane's idle calls, and readers. Fixture data only.
create or replace function fx.reset() returns void language plpgsql as $$
begin
  truncate pipeline.admin_job_events, pipeline.admin_jobs cascade;
  truncate pipeline.course_link_search, pipeline.enrich_plan_runs, pipeline.enrichment_flags, pipeline.edge_request_log, net._http_response, fx.block, fx.waiting, cron.job;
  insert into cron.job(jobname, schedule, command, active) values
    ('course-link-search-worker', '* * * * *', 'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'', ''link_search''))', true);
  -- 30 answered calls in a row with nothing done (what the budget-held lane answered from 00:55 UTC)
  insert into net._http_response(id, status_code, content) select g, 200, '{"items":0}' from generate_series(1, 30) g;
  insert into pipeline.edge_request_log(function_name, mode, created_at, request_id)
    select 'coverage-sweep', 'link_search', now() - make_interval(mins => 3 + g), g from generate_series(1, 30) g;
end $$;

-- a running course_page_find task with p_total courses, p_searched of them searched; nothing moved for p_stall; its plan run and running step
create or replace function fx.task(p_total int, p_searched int, p_stall interval, p_block jsonb default null, p_step_age interval default interval '1 hour')
returns uuid language plpgsql as $$
declare v_job uuid := gen_random_uuid(); v_run uuid := gen_random_uuid(); v_prov uuid := gen_random_uuid(); v_ids uuid[];
begin
  v_ids := array(select gen_random_uuid() from generate_series(1, p_total));
  insert into pipeline.admin_jobs(id, kind, lane, state, args, cursor, created_at, started_at)
    values (v_job, 'course_page_find', 'providers:course_page_find:' || v_prov, 'running',
            jsonb_build_object('provider_id', v_prov, 'course_ids', to_jsonb(v_ids), 'plan_run', v_run, 'plan_mode', 'auto'),
            jsonb_build_object('last_done', p_searched, 'last_change_at', now() - p_stall), now() - p_step_age, now() - p_step_age);
  insert into pipeline.course_link_search(course_id, provider_id, state, requested_at, queued_at)
    select c, v_prov, case when o <= p_searched then 'none' else 'queued' end, now() - p_step_age, now() - p_step_age + interval '1 minute'
      from unnest(v_ids) with ordinality u(c, o);
  insert into pipeline.enrich_plan_runs(id, provider_id, mode, state, started_at, created_at, steps) values (v_run, v_prov, 'auto', 'running', now() - p_step_age, now() - p_step_age,
    jsonb_build_array(jsonb_build_object('step', 'pages', 'group', 'course_search', 'status', 'running', 'ref', jsonb_build_object('kind', 'job', 'id', v_job),
                                         'started_at', now() - p_step_age)));
  delete from fx.block;
  if p_block is not null then insert into fx.block(id, block) values (1, p_block); end if;
  return v_job;
end $$;

create or replace function fx.job(p uuid) returns pipeline.admin_jobs language sql as $$ select * from pipeline.admin_jobs where id = p $$;
create or replace function fx.step(p uuid) returns jsonb language sql as $$
  select r.steps->0 from pipeline.enrich_plan_runs r where r.id = (select (args->>'plan_run')::uuid from pipeline.admin_jobs where id = p) $$;
create or replace function fx.run_state(p uuid) returns text language sql as $$
  select r.state from pipeline.enrich_plan_runs r where r.id = (select (args->>'plan_run')::uuid from pipeline.admin_jobs where id = p) $$;
create or replace function fx.lane_active() returns boolean language sql as $$ select active from cron.job where jobname = 'course-link-search-worker' $$;
create or replace function fx.ok(p_cond boolean, p_what text) returns void language plpgsql as $$
begin
  if p_cond is distinct from true then raise exception 'FAILED: %', p_what; end if;
  raise notice 'ok %', p_what;
end $$;
-- the gates link_search_block_v1 names (as live words)
create or replace function fx.day_budget() returns jsonb language sql as $$
  select jsonb_build_object('code', 'day_budget', 'words', 'Today''s Firecrawl share for course search is used', 'fix', 'Waits for tomorrow''s share') $$;
create or replace function fx.idle_paused() returns jsonb language sql as $$
  select jsonb_build_object('code', 'lane_idle_paused', 'words', 'The course page search lane is paused by the idle guard until 12:45', 'fix', 'It wakes by itself when work waits; nothing to do') $$;
create or replace function fx.no_site() returns jsonb language sql as $$
  select jsonb_build_object('code', 'no_site', 'words', 'No website is recorded to search', 'fix', 'Adapter builder step 1: the website') $$;
