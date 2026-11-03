-- Workstream D (job lifecycle and self-healing, CF-247, 3 Nov 2026): the live shapes the edited and new definitions read, cut to the columns
-- used (information_schema, production, read-only, 3 Nov 2026 15:43-15:58 AEDT), added to the Release A stubs (../plan-step-lane-hold) and
-- the v2.15.426 stubs (../orchestration-followups/stubs-extra.sql). Stand-ins the fixture sets are in schema fx. Never a Supabase project.
set check_function_bodies = off;
-- the task close mirrors each ended task into pipeline.jobs (live definition in live/; the Release A stub is replaced)
create table pipeline.jobs (id bigint generated always as identity primary key, job_type text, domain text, status text, provider_id uuid, requested_by uuid,
  started_at timestamptz, completed_at timestamptz, attempt_count int, payload jsonb, result jsonb, error_text text);
drop function security.admin_job_close_v1(uuid);
-- the catalogue and the scheduler as live
alter table pipeline.automation_catalogue add column if not exists area text, add column if not exists sort int, add column if not exists label text,
  add column if not exists control_rank int, add column if not exists batch_editable boolean, add column if not exists layer23_stage text;
create or replace function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint language sql as $$
  insert into cron.job(jobname, schedule, command, active) values (p_name, p_schedule, p_command, true) returning jobid $$;
-- field items, course searches, scholarship AI reads (live columns used)
alter table pipeline.field_enrich_items add column course_id uuid, add column field text, add column attempts int not null default 0, add column leased_until timestamptz,
  add column reason text, add column evidence_id uuid, add column storage_path text, add column created_at timestamptz default now();
alter table pipeline.course_link_search add column done_at timestamptz;
alter table pipeline.scholarship_ai_extractions add column job_id uuid, add column verdict text, add column applied jsonb;
-- the automatic planner (live: one open plan per provider by index enrich_plan_runs_one_open)
alter table pipeline.enrich_plan_runs add column estimate jsonb, add column requested_by uuid, add column reason text;
create unique index enrich_plan_runs_one_open on pipeline.enrich_plan_runs (provider_id) where state in ('queued', 'running');
create table pipeline.enrich_plan_control (id int primary key, auto_enabled boolean, owner uuid, reason text, updated_at timestamptz);
insert into pipeline.enrich_plan_control values (1, true, gen_random_uuid(), 'Platform Admin: automatic plans on', now());
create table pipeline.enrich_plan_noop (provider_id uuid primary key, fingerprint text, at timestamptz);
create table fx.priority (provider_id uuid primary key, missing bigint, country text default 'AU', best_rank int);
create or replace function security.enrich_plan_priority_v1() returns table(provider_id uuid, name text, country text, courses bigint, missing bigint, best_rank integer)
language sql stable as $$ select p.provider_id, 'Fixture university', p.country, 10::bigint, p.missing, p.best_rank from fx.priority p $$;
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value) values
 ('pipeline', 'plans.replan_per_hour', 'number', '5'), ('pipeline', 'plans.replan_min_days', 'number', '2'), ('pipeline', 'plans.replan_on_evidence', 'number', '1'),
 ('pipeline', 'plans.fair_order', 'number', '1'), ('pipeline', 'plans.redo_days', 'number', '14'), ('pipeline', 'plans.auto_open_max', 'number', '40'),
 ('pipeline', 'plans.auto_per_run', 'number', '20'), ('pipeline', 'plans.step_wait_hours', 'number', '48'), ('pipeline', 'plans.replan_min_new_gaps', 'number', '5')
on conflict (toolset_key, key) do update set value = excluded.value;
update pipeline.platform_toolset_settings set value = '["too_few_pages", "nothing_ready", "no_website", "not a search target", "no website is recorded", "already has a read page", "Needs a website first", "needs_source_discovery"]'
 where key = 'plans.retry_waits_for_change';
-- the step starter: a stand-in that records which step started and returns a task reference (the real one starts a task as the run's person)
create table fx.started (run uuid, step text, at timestamptz default clock_timestamp());
create or replace function security.enrich_plan_start_step_v1(p_run uuid, p_step text) returns jsonb language plpgsql as $$
begin insert into fx.started(run, step) values (p_run, p_step); return jsonb_build_object('kind', 'none'); end $$;
-- who is calling: null for the scheduled planner, a person for Run now and the plan screen
create table fx.uid (id int primary key default 1, uid uuid);
create or replace function auth.uid() returns uuid language sql stable as $$ select (select uid from fx.uid where id = 1) $$;
-- the recorder (Release B owns it): records each answer, or raises the live statement time-out when fx.record_fails is set
create table fx.record_fails (id int primary key default 1, fails boolean);
create table fx.recorded (item_id bigint, at timestamptz default clock_timestamp());
create or replace function public.svc_enrich_ai_record(p_results jsonb) returns jsonb language plpgsql as $$
begin
  if coalesce((select fails from fx.record_fails where id = 1), false) then raise exception 'canceling statement due to statement timeout'; end if;
  insert into fx.recorded(item_id) select (x->>'item_id')::bigint from jsonb_array_elements(p_results) x;
  update pipeline.field_enrich_items e set state = case when x->'value' is not null and x->'value' <> 'null'::jsonb then 'filled' else 'skipped' end,
         leased_until = null, updated_at = now(), cost_usd = coalesce(e.cost_usd, 0) + coalesce((x->>'cost')::numeric, 0)
    from jsonb_array_elements(p_results) x where e.id = (x->>'item_id')::bigint;
  return jsonb_build_object('recorded', jsonb_array_length(p_results));
end $$;
