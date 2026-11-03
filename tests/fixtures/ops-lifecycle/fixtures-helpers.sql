-- Fixture helpers (workstream D, job lifecycle): tasks, plans and items in the shapes seen live on 3 Nov 2026. Fixture data only.
set check_function_bodies = off;
-- the provider's missing values the plan builder reads (stand-in for security.enrich_provider_fields_v1, which is not edited)
create table fx.fields (provider_id uuid primary key, f jsonb);
create or replace function security.enrich_provider_fields_v1(p uuid) returns jsonb language sql stable as $$ select coalesce((select f from fx.fields where provider_id = p), '{}'::jsonb) $$;

create or replace function fx.reset3() returns void language plpgsql as $$
begin
  perform fx.reset2();
  truncate pipeline.field_enrich_items, pipeline.course_link_search, pipeline.jobs, fx.started, fx.priority, fx.fields, pipeline.enrich_plan_noop, fx.recorded,
           pipeline.coverage_course_pages, fx.block, pipeline.provider_contact_checks, pipeline.coverage_provider_discovery, pipeline.scholarship_ai_extractions;
  if to_regclass('pipeline.enrich_ai_answers') is not null then execute 'truncate pipeline.enrich_ai_answers, pipeline.enrich_plan_auto_runs, pipeline.admin_control_events'; end if;
  delete from fx.uid; delete from fx.record_fails;
end $$;

-- a task in a given state and result, with its plan reference when p_run is given
create or replace function fx.task3(p_kind text, p_state text, p_result jsonb, p_provider uuid default gen_random_uuid(), p_run uuid default null, p_error text default null,
                                    p_age interval default interval '2 hours') returns uuid language plpgsql as $$
declare v uuid := gen_random_uuid();
begin
  insert into pipeline.admin_jobs(id, kind, lane, state, args, result, error, created_at, started_at, updated_at, finished_at, scope)
  values (v, p_kind, p_kind || ':' || p_provider, p_state,
          jsonb_build_object('provider_id', p_provider, 'course_ids', '[]'::jsonb) || case when p_run is not null then jsonb_build_object('plan_run', p_run, 'plan_mode', 'auto') else '{}'::jsonb end,
          p_result, p_error, now() - p_age, now() - p_age, now() - p_age + interval '1 hour',
          case when p_state in ('done', 'failed', 'cancelled') then now() - p_age + interval '1 hour' end, p_provider::text);
  return v;
end $$;

-- field items of a task: p_filled filled, p_skipped skipped
create or replace function fx.items(p_job uuid, p_filled int, p_skipped int) returns void language sql as $$
  insert into pipeline.field_enrich_items(provider_id, job_id, state, updated_at, cost_usd, attempts, field)
  select null, p_job, case when g <= p_filled then 'filled' else 'skipped' end, now(), 0.001, 1, 'duration' from generate_series(1, p_filled + p_skipped) g $$;

-- a plan with the given steps (each step a jsonb), state and age
create or replace function fx.plan(p_provider uuid, p_state text, p_steps jsonb, p_age interval default interval '3 hours', p_mode text default 'auto', p_estimate jsonb default '{}'::jsonb)
returns uuid language plpgsql as $$
declare v uuid := gen_random_uuid();
begin
  insert into pipeline.enrich_plan_runs(id, provider_id, mode, state, steps, created_at, started_at, finished_at, updated_at, estimate, reason)
  values (v, p_provider, p_mode, p_state, p_steps, now() - p_age, now() - p_age, case when p_state in ('done', 'failed', 'cancelled') then now() - p_age + interval '1 hour' end, now(),
          p_estimate, 'fixture');
  return v;
end $$;

create or replace function fx.outcome(p uuid) returns text language sql as $$ select outcome from pipeline.admin_jobs where id = p $$;
create or replace function fx.plan_outcome(p uuid) returns text language sql as $$ select outcome from pipeline.enrich_plan_runs where id = p $$;
-- the row as history (state, steps, actual, result), to prove nothing but the outcome columns is written
create or replace function fx.plan_hist(p uuid) returns text language sql as $$ select md5(row(state, steps, actual, finished_at, fields_after, estimate)::text) from pipeline.enrich_plan_runs where id = p $$;
create or replace function fx.job_hist(p uuid) returns text language sql as $$ select md5(row(state, result, error, finished_at, progress, cursor)::text) from pipeline.admin_jobs where id = p $$;
create or replace function fx.set(p_key text, p_value text) returns void language sql as $$
  update pipeline.platform_toolset_settings set value = p_value::jsonb where toolset_key = 'pipeline' and key = p_key $$;

-- IQ-00064's shape: a university planned 7 hours ago whose Find course pages step ended failed (done with work unfinished) 6.5 hours ago
create or replace function fx.iq64(p_finished_ago interval default interval '6 hours 30 minutes') returns uuid language plpgsql as $$
declare v_p uuid := fx.provider(false, null); v_j uuid; v_r uuid;
begin
  insert into fx.priority(provider_id, missing) values (v_p, 1242);
  insert into fx.fields values (v_p, '{"official_url": {"missing": 173}}');
  v_j := fx.task3('course_page_find', 'done', '{"done": 62, "total": 173, "found": 8, "not_found": 54}', v_p, null, null, interval '7 hours');
  v_r := fx.plan(v_p, 'done', jsonb_build_array(jsonb_build_object('step', 'pages', 'group', 'course_search', 'status', 'failed', 'finished_at', now() - p_finished_ago,
           'note', 'ended done with 111 items unprocessed (IQ-00064)', 'ref', jsonb_build_object('kind', 'job', 'id', v_j))), interval '7 hours', 'auto',
           '{"missing": 1242, "fingerprint": "f-1141"}');
  return v_p;
end $$;
