-- IQ-00055 provider description picker: isolated fixture database. The smallest set of schemas, tables and helpers the three live functions
-- in live-before/ need, with the columns they use. Run on a scratch PostgreSQL only (never on a Supabase project): see run.sh. Nothing here
-- is a copy of live data. The helpers the page rule reads (provider_hosts_v1, provider_page_host_v1, provider_description_scope_v1) are in
-- live-before/ as their live text; the shared AI rule is a stand-in (always allowed).
create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists security; create schema if not exists ref; create schema if not exists auth;
do $$ begin create role anon; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated; exception when duplicate_object then null; end $$;
do $$ begin create role service_role; exception when duplicate_object then null; end $$;
create function auth.role() returns text language sql stable as $f$ select coalesce(nullif(current_setting('fx.role', true), ''), 'service_role') $f$;

create table pipeline.platform_toolset_settings(toolset_key text, key text, value jsonb, primary key (toolset_key, key));
CREATE OR REPLACE FUNCTION security.toolset_setting(p_toolset text, p_key text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select s.value from pipeline.platform_toolset_settings s where s.toolset_key = p_toolset and s.key = p_key
$function$;
CREATE OR REPLACE FUNCTION security.pipeline_num_v1(p_key text, p_default numeric)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default)
$function$;
create function security.ai_use_allowed_v1(p_use text) returns boolean language sql stable as $f$ select true $f$;

create table ref.countries(id uuid primary key default gen_random_uuid(), iso_alpha2 text);
create table ref.provider_types(id uuid primary key default gen_random_uuid(), code text unique);
create table catalogue.providers(id uuid primary key, stable_key text, canonical_name text, display_name text, website text, country_id uuid,
  provider_type_id uuid, lifecycle_status text default 'active');
create table pipeline.provider_extra_domains(provider_id uuid, domain text, state text default 'approved', primary key (provider_id, domain));
create table pipeline.sources(id uuid primary key default gen_random_uuid(), provider_id uuid);
create table pipeline.evidence_artifacts(id uuid primary key default gen_random_uuid(), source_id uuid, source_url text, storage_path text, mime_type text,
  captured_at timestamptz, created_at timestamptz not null default now());
-- the two indexes live reads a provider's copies through (evidence_source_idx, pipeline_sources_provider_idx)
create index evidence_source_idx on pipeline.evidence_artifacts(source_id);
create index pipeline_sources_provider_idx on pipeline.sources(provider_id);
create table pipeline.layer4_review_items(id uuid primary key default gen_random_uuid(), field_code text, status text);
create table pipeline.central_ai_settings(id int primary key, model_identifier text);
insert into pipeline.central_ai_settings values (1, 'fixture/pinned-model');
create table pipeline.ai_spend_ledger(id bigserial primary key, lane text, source text, cost_usd numeric);
create table pipeline.provider_central_search(provider_id uuid primary key, found jsonb);
create table pipeline.provider_description_reads(id uuid primary key default gen_random_uuid(), provider_id uuid not null, state text not null default 'queued',
  tries int not null default 0, next_try_at timestamptz not null default now(), leased_until timestamptz, firecrawl_reads int not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
