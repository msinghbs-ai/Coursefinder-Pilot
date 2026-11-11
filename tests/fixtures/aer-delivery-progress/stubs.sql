-- CF-247 F-AER.04 delivery item 6 fixture: what security.data_delivery_aer_progress_v1 reads (shapes as live, fewer columns)
create schema if not exists security; create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists auth;
create table pipeline.platform_toolset_settings (toolset_key text, key text, value jsonb, primary key (toolset_key, key));
create table pipeline.component_register (kind text, name text, layer text, purpose text, status text, replaces text[], introduced_in text, primary key (kind, name));
create table pipeline.aer_discovery_campaigns (id bigserial primary key, state text);
create table pipeline.aer_machine_admissions (id bigserial primary key, provider_id uuid, mode text, outcome text, withdrawn_at timestamptz, created_at timestamptz default now());
create table pipeline.aer_matrix_machine_admissions (id bigserial primary key, provider_id uuid, mode text, outcome text, reason text, withdrawn_at timestamptz, created_at timestamptz default now());
create table pipeline.aer_matrix_machine_validations (id bigserial primary key, passed boolean, validated_at timestamptz default now());
create table pipeline.aer_read_supersessions (id uuid primary key default gen_random_uuid(), state text, closed_at timestamptz);
create table catalogue.course_entry_requirements (id uuid primary key default gen_random_uuid(), status text, updated_at timestamptz default now());
create table catalogue.provider_entry_matrix (id uuid primary key default gen_random_uuid(), provider_id uuid, status text, updated_at timestamptz default now());
create table catalogue.provider_qualification_requirements (id uuid primary key default gen_random_uuid(), provider_id uuid, status text, updated_at timestamptz default now());
create table pipeline.entry_matrix_sources (id uuid primary key default gen_random_uuid(), status text, error text);
create table pipeline.entry_matrix_runs (id uuid primary key default gen_random_uuid(), state text);
create table pipeline.fx_caller (uid uuid, rank int);
insert into pipeline.fx_caller values ('00000000-0000-0000-0000-0000000000a1', 3);
create function auth.uid() returns uuid language sql stable as $$ select uid from pipeline.fx_caller $$;
create function security.current_role_rank() returns int language sql stable as $$ select rank from pipeline.fx_caller $$;
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$ select coalesce((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = p_key), p_default) $$;
create function security.aer_discovery_metrics_v1() returns jsonb language sql stable as $$
  select '{"providers_attempted": 105, "usable_sources": 17, "new_sources": 17, "not_found": 33, "open": 60, "credits": 331, "spare_credits_today": 54, "spare_credits_total": 54, "cost_per_usable_source": 19.5, "by_outcome": {"searching": 60}, "spare": {"room": 946, "why": "spare capacity"}}'::jsonb $$;
create role authenticated; create role anon;
