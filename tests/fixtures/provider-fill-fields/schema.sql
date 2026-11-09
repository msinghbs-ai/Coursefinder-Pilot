-- Guards: Fill fields (Platform Admin 9-10 Nov 2026) and G4 database-backed tests: the objects the Fill fields migration reads, as stubs on an isolated PostgreSQL (never a Supabase project).
-- Only the columns the migration's functions read are present. Stubs are marked "stub"; the facts function and the earlier page function are the live text, extracted from migration 20261109220000.
create extension if not exists pgcrypto;
create schema if not exists catalogue; create schema if not exists ref; create schema if not exists pipeline; create schema if not exists security; create schema if not exists auth;
create schema if not exists scholarship; create schema if not exists cron;
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;

create table ref.countries (id uuid primary key default gen_random_uuid(), iso_alpha2 char(2) not null unique, name text not null, default_currency_code char(3));
create table ref.subdivisions (id uuid primary key default gen_random_uuid(), code text not null, name text not null, subdivision_type text);
create table ref.provider_types (id uuid primary key default gen_random_uuid(), code text not null unique, name text not null);
create table catalogue.providers (
  id uuid primary key default gen_random_uuid(), stable_key text not null unique, canonical_name text not null, display_name text, country_id uuid not null references ref.countries(id),
  subdivision_id uuid, provider_type_id uuid, website text, description text, primary_city text, address_line1 text, phone text, email text, established_year smallint,
  lifecycle_status text not null default 'active', publication_status text not null default 'published', last_verified_at timestamptz, created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), provider_type_basis text);
create table catalogue.courses (id uuid primary key default gen_random_uuid(), provider_id uuid not null, lifecycle_status text default 'active');
create table catalogue.provider_registrations (id uuid primary key default gen_random_uuid(), provider_id uuid, registration_scheme text, registration_code text, status text, checked_at timestamptz, evidence_id uuid);
create table catalogue.provider_identifiers (id uuid primary key default gen_random_uuid(), provider_id uuid, evidence_id uuid);
create table scholarship.scholarships (id uuid primary key default gen_random_uuid(), provider_id uuid, publication_status text, lifecycle_status text);
create table pipeline.aer_provider_coverage (provider_id uuid primary key, disposition text, discovery_state text, extraction_state text, admission_state text, matrix_active int, course_req_active int, updated_at timestamptz);
create table pipeline.manual_locks (entity text, entity_id uuid, field text);
create table pipeline.evidence_artifacts (id uuid primary key default gen_random_uuid(), entity_id uuid);
create table pipeline.layer4_review_items (id uuid primary key default gen_random_uuid(), status text, decided_at timestamptz, field_code text);
create table pipeline.layer4_decisions (id uuid primary key default gen_random_uuid(), review_item_id uuid, layer2_state jsonb, created_at timestamptz default now());
create table pipeline.provider_description_reads (
  id uuid primary key default gen_random_uuid(), provider_id uuid not null, state text not null default 'queued', rule text, reason text, read_via text, tries int default 0, next_try_at timestamptz,
  evidence_id uuid, source_url text, review_item_id uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), consumer_checked_at timestamptz, consumer_checks jsonb,
  proposal jsonb, last_verified_at timestamptz, source_captured_at timestamptz, reserved_usd numeric, ai_calls int, cost_usd numeric, content_hash text);
create unique index on pipeline.provider_description_reads(provider_id) where state in ('queued', 'reading', 'proposed');
create table pipeline.provider_description_machine_admissions (id uuid primary key default gen_random_uuid(), provider_id uuid, tier text, created_at timestamptz default now(), evidence_id uuid, source_url text,
  outcome text, withdrawn_at timestamptz, after_description text, reason text, review_item_id uuid);
create table pipeline.website_sync_items (entity text, item_key text, removed_at timestamptz, item jsonb);
create table pipeline.zoho_sync_items (entity text, item_key text, removed_at timestamptz, item jsonb);
create table pipeline.provider_description_cohorts (
  id uuid primary key default gen_random_uuid(), requested_by uuid, selection jsonb, snapshot jsonb, state text not null default 'preview', expires_at timestamptz, reason text, prepared_at timestamptz,
  run_id uuid, request_key uuid default gen_random_uuid(), created_at timestamptz not null default now(), verified_at timestamptz, verification jsonb);
create table pipeline.provider_description_cohort_members (cohort_id uuid, provider_id uuid, evidence_id uuid, pick int, snapshot jsonb, read_id uuid);
create table pipeline.automation_catalogue (jobname text primary key, control_rank int);
create table cron.job (jobname text, active boolean);
create table pipeline.admin_jobs (id uuid primary key default gen_random_uuid(), kind text, lane text, state text, title text, args jsonb, result jsonb, error text, requested_by uuid, reason text,
  started_at timestamptz, finished_at timestamptz, scope text, outcome text, created_at timestamptz default now());
create table pipeline.admin_control_events (area text, action text, target text, detail jsonb, actor uuid, created_at timestamptz default now());
create table pipeline.ai_spend_ledger (lane text, source text, cost_usd numeric, calls int);
create table pipeline.central_ai_settings (id int primary key, model_identifier text);
create table pipeline.platform_toolset_settings (toolset_key text, key text, label text, help text, kind text, value jsonb, min_value numeric, max_value numeric, unit text, sort int, section text, used_by text, reason text, primary key (toolset_key, key));
create table pipeline.admin_table_columns (screen text, key text, grp text, label text, sort int, sort_key text, default_visible boolean, default_width int, min_width int, always_visible boolean, active boolean default true, primary key (screen, key));
create table pipeline.component_register (kind text, name text, layer text, purpose text, status text default 'active', replaces text[] default '{}', replaced_by text, retire_after date, introduced_in text, note text, unique (kind, name));
create table pipeline.ops_ai_diagnosis_requests (id bigint primary key);
create table pipeline.integration_issues (id bigint primary key);
create table pipeline.ops_root_causes (code text);

-- stub: the caller's identity and rank come from session settings (fx.uid, fx.rank)
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('fx.uid', true), '')::uuid $$;
create function security.current_role_rank() returns integer language sql stable as $$ select coalesce(nullif(current_setting('fx.rank', true), '')::int, 0) $$;
-- the live definition of security.pipeline_num_v1 (20261013012900)
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable security definer set search_path to '' as $$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $$;
-- stub
create function security.toolset_setting(p_toolset text, p_key text) returns jsonb language sql stable as $$ select (select s.value from pipeline.platform_toolset_settings s where s.toolset_key = p_toolset and s.key = p_key) $$;
create function security.ai_use_allowed_v1(p text) returns boolean language sql stable as $$ select true $$;
create function security.provider_description_scope_v1(p uuid) returns boolean language sql stable as $$ select true $$;
create function security.university_group_provider_ids(p text) returns setof uuid language sql stable as $$ select null::uuid where false $$;
create function security.provider_university_groups(p uuid) returns jsonb language sql stable as $$ select '[]'::jsonb $$;
create function security.provider_adapter_status_v1(p uuid) returns text language sql stable as $$ select 'none'::text $$;
-- stub: the feeds' candidate scans: a provider is served by a feed when it has an active course (fixture rule)
create function security.website_sync_candidates_v1(p_entity text) returns table(ref_id uuid) language sql stable as $$ select distinct c.provider_id from catalogue.courses c $$;
create function security.zoho_sync_candidates_v1(p_entity text) returns table(ref_id uuid) language sql stable as $$ select distinct c.provider_id from catalogue.courses c where c.lifecycle_status = 'active' $$;
-- stub: the existing consumer read wrapper (the Website and Zoho provider reads): a provider is served when the feed item exists
create function security.provider_description_consumer_read_v1(p_consumer text, p_key text) returns jsonb language sql stable as $$
  select coalesce((select jsonb_build_object('item', jsonb_build_object('provider_id', i.item_key, 'description', i.item->>'description'))
           from (select * from pipeline.website_sync_items where p_consumer = 'website' union all select * from pipeline.zoho_sync_items where p_consumer = 'zoho') i
          where i.entity = 'provider' and i.item_key = p_key and i.removed_at is null),
          -- the Website provider read answers NOT_FOUND for a provider it does not serve (website_v2_provider); the Zoho read answers no item
          case when p_consumer = 'website' then jsonb_build_object('error', jsonb_build_object('code', 'NOT_FOUND', 'message', 'provider not found')) else jsonb_build_object('item', null) end) $$;
-- stub: the governed selection (the live one is not edited by this change). Eligible unless the provider holds a manual lock; a fixture provider whose key ends '-current' is refused the way a current
-- admission would be (description_current), so the panel's honest refusal can be tested.
create function security.provider_description_selection_v1(p_args jsonb) returns jsonb language plpgsql stable as $$
declare v_id uuid := nullif(p_args->>'provider_id', '')::uuid; v_state text := coalesce(p_args->>'description_state', 'missing'); v_row jsonb;
begin
  select jsonb_build_object('provider_id', p.id, 'provider', coalesce(p.display_name, p.canonical_name), 'name', coalesce(p.display_name, p.canonical_name), 'stable_key', p.stable_key,
         'country', 'AU', 'type', null, 'active_course_count', 0, 'current_description', p.description, 'evidence_id', null, 'source_hash', null, 'last_read_id', null,
         'state', coalesce((select r.state from pipeline.provider_description_reads r where r.provider_id = p.id order by r.created_at desc limit 1), 'missing'),
         'eligible', not exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id) and not (v_state = 'stale' and p.stable_key like '%-current'),
         'eligibility_reason', case when exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id) then 'manual_lock'
                                    when v_state = 'stale' and p.stable_key like '%-current' then 'description_current' else 'eligible' end,
         'upgrade', coalesce((p_args->>'upgrade')::boolean, false))
    into v_row from catalogue.providers p
   where p.id = v_id and ((v_state = 'missing' and nullif(btrim(p.description), '') is null) or (v_state = 'stale' and nullif(btrim(p.description), '') is not null));
  return jsonb_build_object('providers', case when v_row is null then '[]'::jsonb else jsonb_build_array(v_row) end);
end $$;
create function security.provider_description_fire_v1() returns jsonb language sql as $$ select jsonb_build_object('sent', 1) $$;
create function security.provider_description_run_result_v1(p uuid) returns jsonb language sql stable as $$
  select jsonb_build_object('cohort_id', c.id, 'state', c.state, 'run_id', c.run_id, 'providers', coalesce((select jsonb_agg(m.snapshot) from pipeline.provider_description_cohort_members m where m.cohort_id = c.id), '[]'::jsonb))
    from pipeline.provider_description_cohorts c where c.id = p $$;
