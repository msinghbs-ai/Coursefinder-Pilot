-- Stand-ins for objects the course-description fixture does not carry. Signatures read from production 8 Nov 2026 (fxcwkweaxjtknorudmwp). Every body is invented.
\set ON_ERROR_STOP 1
create schema if not exists cron;
create schema if not exists auth;
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('g.uid', true), '')::uuid $$;
create or replace function security.current_role_rank() returns smallint language sql stable security definer as $$ select coalesce(nullif(current_setting('g.rank', true), '')::smallint, 0::smallint) $$;
create table if not exists pipeline.automation_catalogue (jobname text primary key, area text not null, sort int not null default 100, label text not null, description text not null,
  control_rank int not null default 5, batch_editable boolean not null default false, layer23_stage text);
create table if not exists cron.job (jobid bigint generated always as identity primary key, jobname text unique, schedule text, command text, active boolean default true);
create or replace function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint language sql as $$
  insert into cron.job(jobname, schedule, command) values (p_name, p_schedule, p_command) returning jobid $$;
create table if not exists pipeline.layer4_supersessions (
  id bigserial primary key, item_id uuid not null, field_code text not null, entity_type text not null, entity_id uuid not null,
  reason text not null check (reason in ('duplicate_pending', 'decided_before', 'covered_by_active', 'entity_retired')),
  covered_by_item uuid, evidence jsonb not null default '{}'::jsonb, mode text not null check (mode in ('arrival', 'reconcile')),
  at timestamptz not null default now(), reversed_at timestamptz, reversed_by uuid, reversed_note text);
alter table pipeline.admin_jobs add column if not exists args jsonb;
create or replace function security.enrich_deadline_missing_v1(p_course uuid) returns boolean language sql stable as $$ select p_course = '00000000-0000-4000-b100-000000000031'::uuid $$;
create or replace function security.enrich_item_held_v1(p_course uuid, p_field text) returns boolean language sql stable as $$ select false $$;
create or replace view security.provider_hidden_v1 as select p.id provider_id from catalogue.providers p where false;
-- the Layer 4 pace as production reports it for a kind with enough measured decisions
create or replace function security.layer4_pace_v1() returns jsonb language sql stable as $$
  select jsonb_build_object('course_description_first_read', jsonb_build_object('minutes', 2, 'measured', 9, 'basis', 'measured')) $$;
