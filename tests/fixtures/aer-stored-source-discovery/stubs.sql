-- AER source discovery from stored evidence: the tables and helpers migration 20261107150000 reads, as live has them (columns and behaviour, not data).
do $r$ begin if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if; if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; end $r$;
-- Scratch PostgreSQL only (never a Supabase project): see run.sh. Nothing here is a copy of live data.
create schema if not exists security; create schema if not exists catalogue; create schema if not exists pipeline; create schema if not exists ref; create schema if not exists cron;
create table ref.countries(id uuid primary key default gen_random_uuid(), iso_alpha2 text unique);
insert into ref.countries(iso_alpha2) values ('AU'), ('NZ'), ('CA');
create table catalogue.providers(id uuid primary key, canonical_name text, website text, country_id uuid, lifecycle_status text default 'active',
  publication_status text default 'published', enrols_international boolean default true);
create table catalogue.courses(id uuid primary key default gen_random_uuid(), provider_id uuid, lifecycle_status text default 'active');
create table security.provider_hidden_v1(provider_id uuid);
create table pipeline.platform_toolset_settings(toolset_key text, key text, label text, help text, kind text, value jsonb, min_value numeric, max_value numeric, unit text,
  sort int, section text, used_by text, reason text, primary key (toolset_key, key));
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable security definer set search_path = '' as
  $f$ select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $f$;
create function security.toolset_setting(p_toolset text, p_key text) returns jsonb language sql stable security definer set search_path = '' as
  $f$ select s.value from pipeline.platform_toolset_settings s where s.toolset_key = p_toolset and s.key = p_key $f$;
-- live security.site_host_v1 (same body, line endings aside)
create function security.site_host_v1(p_url text) returns text language sql immutable set search_path = '' as
  $f$ select nullif(lower(regexp_replace(substring(btrim(coalesce(p_url, '')) from '^(?:https?://)?([^/:?#\s]+)'), '^www\.', '')), '') $f$;
create table pipeline.important_links(domain text, enabled boolean default true, retired_at timestamptz, uses text[], authority_category text);
create function security.third_party_host_v1(p_url text) returns boolean language sql stable security definer set search_path = '' as
  $f$ select coalesce((select bool_or(h = l.domain or h like '%.' || l.domain) from pipeline.important_links l, (select security.site_host_v1(p_url) h) x
                        where x.h is not null and l.enabled and l.retired_at is null and l.domain is not null and 'not_provider_site' = any(l.uses)
                          and l.authority_category in ('third_party_directory', 'general_web', 'ranking_publisher')), false) $f$;
-- cron: the jobs table and the two calls the migration makes
create table cron.job(jobid serial primary key, jobname text unique, schedule text, command text, active boolean default true);
create function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint language sql as
  $f$ insert into cron.job(jobname, schedule, command) values (p_name, p_schedule, p_command) returning jobid $f$;
create function cron.alter_job(p_id bigint, active boolean default null) returns void language sql as $f$ update cron.job set active = coalesce(alter_job.active, job.active) where jobid = p_id $f$;
-- live security.aer_eligible_v1 and aer_schedule_active_v1 (bodies unchanged); the per-country switch is a fixture setting
create function security.aer_eligible_v1() returns table(provider_id uuid, country text) language sql stable security definer set search_path to '' as $function$
  select p.id, k.iso_alpha2::text
    from catalogue.providers p join ref.countries k on k.id = p.country_id
   where k.iso_alpha2::text in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'aer.eligible_countries'), '[]'::jsonb)))
     and p.lifecycle_status = 'active' and p.publication_status = 'published' and p.enrols_international is true
$function$;
create function security.aer_schedule_active_v1() returns boolean language sql stable security definer set search_path to '' as
  $f$ select exists (select 1 from cron.job j where j.jobname = 'aer-scheduled-read' and j.active) $f$;
create function security.aer_schedule_country_v1(p_country text) returns jsonb language sql stable as
  $f$ select jsonb_build_object('on', not coalesce((security.toolset_setting('pipeline', 'fixture.countries_off') ? p_country), false), 'country', p_country) $f$;
-- the entry matrix tables as step A created them (columns the migration and the live attach read)
create table pipeline.entry_matrix_sources(id uuid primary key default gen_random_uuid(), provider_id uuid not null references catalogue.providers(id), url text not null check (url ~ '^https?://'),
  title text, rank int not null default 1, found_via text not null check (found_via in ('search', 'manual')),
  status text not null default 'found' check (status in ('found', 'reading', 'read', 'failed', 'robots_disallowed', 'pdf_step_b', 'inactive')),
  read_at timestamptz, content_hash text, unique (provider_id, url));
create table pipeline.provider_central_search(provider_id uuid primary key, state text, found jsonb, updated_at timestamptz default now());
create table pipeline.coverage_provider_urls(provider_id uuid, url text, title text, tokens text[], title_tokens text[], source text, first_seen_at timestamptz default now(), last_seen_at timestamptz default now(), primary key (provider_id, url));
create table pipeline.provider_discovery_links(provider_id uuid, url text, anchor_text text, pages int, evidence_id uuid, first_seen_at timestamptz default now(), last_seen_at timestamptz default now(), score_text text, primary key (provider_id, url));
create table pipeline.automation_catalogue(jobname text primary key, area text not null, sort int not null, label text not null, description text not null, control_rank int not null, batch_editable boolean not null, layer23_stage text);
create table pipeline.component_register(kind text not null, name text not null, layer text not null, area text, purpose text, status text not null default 'active', replaces text[] not null default '{}',
  replaced_by text, introduced_in text, retire_after date, note text, updated_at timestamptz not null default now(), primary key (kind, name));
insert into pipeline.component_register(kind, name, layer, purpose) values ('function', 'security.entry_matrix_attach_v1', 'Layer 2', 'fixture');
