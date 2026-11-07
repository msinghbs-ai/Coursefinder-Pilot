-- Fixture-only shapes of the live tables and functions the alert delivery lifecycle reads (copied from the live definitions, 7 Nov 2026).
do $$ begin if not exists (select 1 from pg_roles where rolname=$q$anon$q$) then create role anon; end if; if not exists (select 1 from pg_roles where rolname=$q$authenticated$q$) then create role authenticated; end if; end $$;
drop schema if exists pipeline cascade; drop schema if exists security cascade;
create schema pipeline; create schema security;
create table pipeline.platform_toolset_settings(toolset_key text, key text, label text, help text, kind text, value jsonb, min_value numeric, max_value numeric, unit text, sort int, section text, used_by text, reason text, primary key (toolset_key, key));
create table pipeline.component_register(kind text not null, name text not null, layer text not null default 'security', area text, purpose text, status text not null default 'active', replaces text[] not null default '{}', replaced_by text, introduced_in text, retire_after date, last_used_at timestamptz, usage jsonb not null default '{}', size_bytes bigint, note text, registered_at timestamptz not null default now(), updated_at timestamptz not null default now(), primary key (kind, name));
create table pipeline.platform_issues(id uuid primary key default gen_random_uuid(), check_key text, severity text, title text, resolved_at timestamptz, acknowledged_at timestamptz);
create table pipeline.platform_alerts(id bigserial primary key, issue_id uuid references pipeline.platform_issues(id) on delete set null, check_key text, kind text check (kind in ('raised','escalated','reminder','recovered','test')),
  severity text check (severity in ('critical','warning','info')), title text, body text, status text check (status in ('held','pending','sending','sent','failed')), attempts int not null default 0,
  next_attempt_at timestamptz not null default now(), lease_until timestamptz, sent_via text, sent_at timestamptz, net_request_id bigint, last_error text, dedupe_key text unique, created_at timestamptz not null default now());
create table pipeline.queue_watch(key text primary key);
create table pipeline.queue_watch_alerts(id bigserial primary key, key text references pipeline.queue_watch(key), state text, channel text check (channel in ('notify','report')), title text, body text, raised_at timestamptz not null default now(), sent_at timestamptz, sent_via text);
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $$;
insert into pipeline.platform_toolset_settings(toolset_key, key, value) values ('pipeline','alerts.max_attempts', to_jsonb(5)), ('pipeline','alerts.retry_minutes', to_jsonb(10));
insert into pipeline.component_register(kind, name) values ('function','security.platform_alerts_take_v1'),('function','security.platform_alerts_confirm_v1'),('function','security.queue_watch_alerts_take_v1');
