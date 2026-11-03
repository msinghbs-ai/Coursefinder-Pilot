-- Plan lifecycle (CF-247 3 Nov 2026, Agent A): additions to ../enrich-plan-continuity/stubs.sql for the tick, the step starter, the inputs and
-- the orphan check (shapes as live, 3 Nov 2026, cut to the columns used). Nothing here is a Supabase project.
alter table pipeline.coverage_course_pages add column provider_id uuid, add column bound_at timestamptz;
alter table pipeline.coverage_vendor_usage add column on_demand_run uuid;
alter table pipeline.provider_onboarding add column stop_reason text;
create table pipeline.provider_central_search (provider_id uuid primary key, state text, searched_at timestamptz);
create schema if not exists cron;
create table cron.job (jobid bigserial primary key, jobname text unique, schedule text, command text, active boolean default true);
create function cron.alter_job(job_id bigint, schedule text default null, command text default null, database text default null, username text default null, active boolean default null)
  returns void language sql as $$ update cron.job set command = coalesce(alter_job.command, cron.job.command) where jobid = job_id $$;
insert into cron.job(jobname, schedule, command) values ('integration-validate', '21,51 * * * *', 'select security.integration_validate_v1(), security.integration_yield_checks_v1()');
create table pipeline.automation_catalogue (jobname text primary key, description text);
insert into pipeline.automation_catalogue values ('integration-validate', 'Integration checks.');
create table pipeline.integration_issues (id bigserial primary key, fingerprint text unique, status text default 'detected', severity text, workstream text,
  condition_cleared_at timestamptz, evidence jsonb, retry_count int default 0);
create table pipeline.integration_issue_events (issue_id bigint, kind text, from_status text, to_status text, actor text, note text);
create table security.fx_alerts (issue_id bigint, observed boolean);
-- the integration queue upsert, cut to create-or-observe by fingerprint (live: 20261102120000)
create function security.integration_issue_upsert_v1(p jsonb, p_actor text default 'integration-validate') returns jsonb language plpgsql as $$
begin
  insert into pipeline.integration_issues(fingerprint, severity, workstream, evidence) values (p->>'fingerprint', p->>'severity', p->>'workstream', p->'evidence')
  on conflict (fingerprint) do update set retry_count = pipeline.integration_issues.retry_count + 1, condition_cleared_at = null, evidence = excluded.evidence;
  return '{}'::jsonb;
end $$;
create function security.integration_alert_sync_v1(p_issue bigint, p_observed boolean, p_actor text default 'integration-validate') returns void language sql as $$
  insert into security.fx_alerts values (p_issue, p_observed) $$;
-- what the tick calls when a run finishes
create function security.enrich_provider_fields_v1(p uuid) returns jsonb language sql stable as $$ select '{}'::jsonb $$;
create function security.enrich_plan_needs_person_v1(p uuid) returns text language sql stable as $$ select null::text $$;
create table search.refresh_requests (requested_by text);
-- the Firecrawl share left, per purpose (fixture-settable; live reads the vendor ledger)
create table security.fx_budget (purpose text primary key, left_credits numeric);
create or replace function security.fc_budget_left_v1(p text) returns numeric language sql stable as $$ select coalesce((select left_credits from security.fx_budget where purpose = p), 1000) $$;
create or replace function security.fc_setting_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$
  select case when p_key like 'daily_share_%' then 100 else p_default end $$;
-- public.admin_jobs: the start path the plan steps use (live: a queued task of the kind, as the signed-in person)
create or replace function public.admin_jobs(p_action text, p_args jsonb default '{}') returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_rank int := security.current_role_rank(); v_j pipeline.admin_jobs%rowtype; v_id uuid;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 4 then raise exception 'Operator or above required' using errcode = '42501'; end if;
  if p_action = 'start' then
    insert into pipeline.admin_jobs(kind, state, args, requested_by, reason) values (p_args->>'kind', 'queued', coalesce(p_args->'args', '{}'), auth.uid(), p_args->>'from') returning id into v_id;
    return jsonb_build_object('id', v_id);
  end if;
  select * into v_j from pipeline.admin_jobs j where j.id = (p_args->>'id')::uuid;
  if v_j.id is null then raise exception 'unknown job'; end if;
  if v_rank < 5 and v_j.requested_by <> auth.uid() then raise exception 'only the person who started it, or an Operator, may change this job' using errcode = '42501'; end if;
  if p_action = 'cancel' then
    if v_j.state in ('done', 'failed', 'cancelled') then raise exception 'the job has already finished'; end if;
    if v_j.state in ('queued', 'paused') then update pipeline.admin_jobs set state = 'cancelled', finished_at = now(), cancel_requested = true where id = v_j.id;
    else update pipeline.admin_jobs set cancel_requested = true where id = v_j.id; end if;
  end if;
  return jsonb_build_object('ok', true);
end $$;
