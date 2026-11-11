-- Stand-ins for the jobs-transient-retry fixture (scratch PostgreSQL only). The task runner is the LIVE text (live/); everything below is a stand-in with the columns the runner and the migration use.
\set ON_ERROR_STOP 1
do $r$ declare n text; begin foreach n in array array['anon', 'authenticated', 'service_role'] loop if not exists (select 1 from pg_roles where rolname = n) then execute format('create role %I nologin', n); end if; end loop; end $r$;
create schema if not exists security;
create schema if not exists pipeline;
create table pipeline.platform_toolset_settings(toolset_key text not null, key text not null, label text, help text, kind text, value jsonb, min_value text, max_value text, unit text, sort int, section text, used_by text, reason text, primary key (toolset_key, key));
insert into pipeline.platform_toolset_settings(toolset_key, key, value) values ('pipeline', 'jobs.per_lane_per_tick', '1000');
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$
  select coalesce((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = p_key), p_default) $$;
create table pipeline.admin_control_events(id bigserial primary key, area text, action text, target text, detail jsonb, actor uuid);
create table pipeline.admin_jobs(id uuid primary key, lane text not null, state text not null, cancel_requested boolean not null default false, pause_requested boolean not null default false,
  created_at timestamptz not null default now(), error text, finished_at timestamptz, updated_at timestamptz, started_at timestamptz, result jsonb);
create table pipeline.admin_job_events(id bigserial primary key, job_id uuid, note text, detail jsonb);
create table security.fx_closed(job_id uuid);
create function security.admin_job_close_v1(p_id uuid) returns void language sql as $$ insert into security.fx_closed values (p_id) $$;
-- the slice (stand-in): call n of a task takes the planned outcome n (counted by a sequence for each task, which a rolled-back slice does not undo): an SQLSTATE to raise, 'more' (not finished) or 'done';
-- it writes a work row first, so a rolled-back slice leaves none
create table security.fx_plan(job_id uuid, seq int, outcome text);
create table security.fx_work(job_id uuid, seq int);
create function security.admin_job_slice_v1(p_id uuid, p_items int) returns boolean language plpgsql as $$
declare v_n int := nextval(format('security.%I', 'fx_seq_' || replace(p_id::text, '-', ''))); v_o text;
begin
  select outcome into v_o from security.fx_plan where job_id = p_id and seq = v_n;
  if v_o is null then return true; end if;
  insert into security.fx_work values (p_id, v_n);
  if v_o = 'done' then return true; elsif v_o = 'more' then return false; end if;
  raise exception 'fixture error %', v_o using errcode = v_o;
end $$;
