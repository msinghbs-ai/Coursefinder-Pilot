-- Only what migration 20261112040000 reads or writes outside the two edited bodies (those are loaded from live/ with their bodies unchecked).
create schema if not exists security; create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists auth;
create table catalogue.providers (id uuid primary key default gen_random_uuid(), canonical_name text, display_name text, website text, lifecycle_status text default 'active');
create table catalogue.courses (id uuid primary key default gen_random_uuid(), provider_id uuid, lifecycle_status text default 'active');
create table pipeline.platform_toolset_settings (toolset_key text, key text, label text, help text, kind text, value jsonb, min_value numeric, max_value numeric, unit text, sort int,
  section text, used_by text, reason text, updated_at timestamptz, primary key (toolset_key, key));
create table pipeline.aer_source_discover_requests (id bigserial primary key, provider_id uuid, requested_at timestamptz default now(), outcome text, outcome_at timestamptz, credits numeric, detail jsonb default '{}'::jsonb);
create table pipeline.provider_central_search (provider_id uuid primary key, state text, requested_at timestamptz, searched_at timestamptz, attempts int default 0, updated_at timestamptz,
  leased_until timestamptz, evidence jsonb, found jsonb);
create table pipeline.entry_matrix_sources (id uuid primary key default gen_random_uuid(), provider_id uuid, url text, status text, read_at timestamptz, updated_at timestamptz default now());
create table pipeline.coverage_vendor_usage (id bigserial primary key, units numeric, purpose text, provider_id uuid, url text, at timestamptz default now());
create table pipeline.coverage_course_pages (course_id uuid, provider_id uuid, status text);
create table pipeline.component_register (kind text, name text, layer text, purpose text, status text, replaces text[], introduced_in text, primary key (kind, name));
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$ select coalesce((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = p_key), p_default) $$;
create function security.aer_eligible_v1() returns table(provider_id uuid, country text) language sql stable as $$ select id, 'AU'::text from catalogue.providers where lifecycle_status = 'active' $$;
create function security.third_party_host_v1(p text) returns boolean language sql immutable as $$ select p ~* 'directory\.example' $$;
create function security.fc_purpose_group_v1(p text) returns text language sql immutable as $$ select case when p like 'central%' then 'central' else 'other' end $$;
create function security.current_role_rank() returns int language sql stable as $$ select 7 $$;
create function auth.uid() returns uuid language sql stable as $$ select null::uuid $$;
create function auth.role() returns text language sql stable as $$ select null::text $$;
create role authenticated; create role anon;
create function security.aer_no_source_route_v1() returns table(provider_id uuid, route text, reason text, next_action text, parked boolean, courses_waiting integer, best_url text, best_score numeric)
  language sql stable as $$ select null::uuid, null::text, null::text, null::text, false, 0, null::text, null::numeric where false $$;  -- the daily route asks are not under test here
insert into pipeline.platform_toolset_settings(toolset_key, key, value) values ('pipeline', 'aer.source_discover_on', '1');
