-- Live shapes (4 Nov 2026, read 06:55-07:20 and 11:09-11:10 AEDT, fxcwkweaxjtknorudmwp, read only) of what the SS-020 follow-up migration touches
create schema if not exists pipeline; create schema if not exists security; create schema if not exists auth;
create table auth.fixture_actor (uid uuid, rank int);
insert into auth.fixture_actor values ('00000000-0000-4000-8000-000000000006', 6);
create function auth.uid() returns uuid language sql stable as $$ select uid from auth.fixture_actor limit 1 $$;
create function security.current_role_rank() returns int language sql stable as $$ select rank from auth.fixture_actor limit 1 $$;
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql as $$ select p_default $$;
create table pipeline.sources (id uuid primary key, url text);
create table pipeline.refresh_policies (id uuid primary key default gen_random_uuid(), country_code text, layer smallint not null, source_profile_id uuid,
  entity_type text, entity_id uuid, freshness_class text not null, cadence_interval interval, next_due_at timestamptz, hash_sensitive boolean not null default true,
  important_date_sensitive boolean not null default false, enabled boolean not null default true, change_control_ref text not null, updated_at timestamptz not null default now(),
  source_id uuid references pipeline.sources(id), created_by uuid, created_by_display_snapshot text, created_by_email_snapshot text, owner_user_id uuid, owner_display_snapshot text,
  check (source_id is not null or source_profile_id is not null or entity_id is not null or (layer = 4 and freshness_class = 'event-driven')),
  check (freshness_class = any (array['critical','weekly','monthly','term-cycle','annual','event-driven'])), check (layer between 1 and 4));
create table pipeline.refresh_requests (id uuid primary key default gen_random_uuid(), requested_layer smallint, country_code text, source_id uuid, source_profile_id uuid,
  entity_type text, entity_id uuid, evidence_id uuid, layer3_profile_id uuid, revalidation_ref text, reason text, trigger_type text, important_date_id uuid,
  requested_by uuid, change_control_ref text, status text not null default 'queued', created_at timestamptz default now());
create table pipeline.important_dates (id uuid primary key default gen_random_uuid(), status text, refresh_layer smallint, starts_at timestamptz, starts_on date, ends_at timestamptz,
  ends_on date, timezone text, warning_window interval, source_id uuid, source_profile_id uuid, entity_type text, entity_id uuid, country_code text, title text,
  change_control_ref text, expires_at timestamptz, updated_at timestamptz);
create table pipeline.layer3_interpretations (id uuid primary key default gen_random_uuid(), status text, interpretation_expires_at timestamptz, entity_type text, entity_id uuid,
  evidence_id uuid, profile_id uuid, change_control_ref text);
create table pipeline.layer1_source_operations (source_id uuid primary key, authority_name text not null default 'x', authority_domains text[] not null default '{x}',
  expected_format text not null default 'csv', active boolean not null default true, paused boolean not null default false,
  verification_cadence_days integer not null default 1, ingestion_cadence_days integer, next_verification_at timestamptz, auto_ingest boolean not null default false,
  change_reason text not null default 'initial baseline', updated_by uuid, updated_at timestamptz not null default now());
create table pipeline.admin_control_events (id bigint generated always as identity primary key, area text not null, action text not null, target text,
  detail jsonb not null default '{}', actor uuid, created_at timestamptz not null default now());
create table pipeline.component_register (kind text not null check (kind in ('job','table','view','edge_function','screen','function')), name text not null, layer text not null,
  area text, purpose text, status text not null default 'active' check (status in ('active','retiring','retired')), replaces text[] default '{}', replaced_by text, retire_after date,
  introduced_in text, note text, updated_at timestamptz default now(), primary key (kind, name));
create table pipeline.refresh_policy_action_events (id uuid primary key default gen_random_uuid(), policy_id uuid not null references pipeline.refresh_policies(id) on delete restrict,
  action text not null check (action in ('edit_schedule','run_on_demand')), reason text not null check (length(trim(reason)) >= 5), actor_id uuid not null,
  change_control_ref text not null default 'CF-CHG-20260910-092', before_state jsonb not null default '{}', after_state jsonb not null default '{}',
  refresh_request_id uuid references pipeline.refresh_requests(id) on delete set null, outcome text not null default 'applied' check (outcome in ('applied','queued','existing_active')),
  created_at timestamptz not null default now(), actor_display_snapshot text, actor_email_snapshot text);
-- live functions this change edits, as deployed (their md5 is checked against the live md5 read on 4 Nov 2026)
\i live/admin_layer1_schedule.sql
\i live/refresh_scheduler_tick_impl.sql
-- the legacy Refresh schedules controls whose role, reason and audit rules Layer 1 › Sources now uses (Option A, 4 Nov 2026 10:00 §8)
\i live/scheduler_policy_edit_v1_browser_bridge.sql
\i live/scheduler_policy_run_now_v1_browser_bridge.sql
