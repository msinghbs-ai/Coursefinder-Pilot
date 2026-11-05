-- Guards: decision 19:14 §8: the tool's round trip is proven on a local stand-in for production that carries the shapes the intake releases missed.
-- A local stand-in for production (never production): the admin_jobs outcome foreign key to a code table, the manual_locks mode check and
-- composite primary key, an enum, a sequence, a trigger, RLS with policies, table and function grants, a role time-out and a code table
-- carrying a personal-data column (which the tool must refuse to copy). Column names follow the live tables; the rows are invented codes.
create schema if not exists pipeline;
create schema if not exists catalogue;
create schema if not exists security;
do $r$ begin create role anon nologin; exception when duplicate_object then null; end $r$;
do $r$ begin create role authenticated nologin; exception when duplicate_object then null; end $r$;
do $r$ begin create role service_role nologin; exception when duplicate_object then null; end $r$;
do $r$ begin execute format('alter role authenticated in database %I set statement_timeout = %L', current_database(), '8s'); end $r$;

create type pipeline.pp_lock_mode as enum ('hold', 'override');
create table pipeline.ops_outcome_codes (code text primary key, title text not null, counts_as_movement boolean not null default false);
insert into pipeline.ops_outcome_codes values ('done', 'Done', true), ('failed', 'Failed', false), ('run_now_queued', 'Queued by Run now', false);
create table pipeline.pp_operators (id uuid primary key, email text not null);
insert into pipeline.pp_operators values ('00000000-0000-0000-0000-000000000001', 'someone@example.invalid');

create sequence pipeline.admin_jobs_seq;
create table pipeline.admin_jobs (
  id bigint primary key default nextval('pipeline.admin_jobs_seq'),
  kind text not null check (kind <> ''),
  outcome text references pipeline.ops_outcome_codes(code),
  requested_by uuid references pipeline.pp_operators(id),
  created_at timestamptz not null default now(),
  attempts int not null default 0 constraint admin_jobs_attempts_ck check (attempts between 0 and 20));
create index admin_jobs_kind_idx on pipeline.admin_jobs (kind, created_at desc);

create table pipeline.manual_locks (
  entity text not null, entity_id uuid not null, field text not null, mode pipeline.pp_lock_mode not null default 'hold',
  value jsonb, locked_at timestamptz not null default now(),
  primary key (entity, entity_id, field),
  constraint manual_locks_mode_ck check (mode in ('hold', 'override')));

create or replace function security.pp_touch() returns trigger language plpgsql set search_path to '' as $f$
begin new.locked_at := now(); return new; end $f$;
create or replace function security.pp_guard_active() returns boolean language sql stable set search_path to '' as $f$ select false $f$;
create trigger manual_locks_touch before update on pipeline.manual_locks for each row when (security.pp_guard_active() is false) execute function security.pp_touch();

create or replace function security.pp_job_count(p_kind text) returns bigint language sql stable security definer set search_path to '' as $f$
  select count(*) from pipeline.admin_jobs where kind = p_kind $f$;
revoke all on function security.pp_job_count(text) from public;
grant execute on function security.pp_job_count(text) to authenticated, service_role;

alter table pipeline.admin_jobs enable row level security;
create policy admin_jobs_read on pipeline.admin_jobs for select to authenticated using (kind <> 'secret');
alter table pipeline.manual_locks enable row level security;
alter table pipeline.manual_locks force row level security;
create policy manual_locks_write on pipeline.manual_locks as restrictive for insert to authenticated with check (mode = 'hold');
grant usage on schema pipeline, catalogue to authenticated, service_role;
grant usage on schema security to authenticated, service_role, anon;
revoke all on pipeline.admin_jobs, pipeline.manual_locks from public, anon, authenticated, service_role;
grant select on pipeline.admin_jobs to authenticated;
grant select, insert, update on pipeline.manual_locks to service_role;
grant select on pipeline.manual_locks to authenticated with grant option;
