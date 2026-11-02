-- Scheduled AER reading fixtures (CF-247, Platform Admin direction 3 Nov 2026 09:32): what the D-R2/D-R3 fixture database
-- (../e13-completeness-gate/stubs.sql, ../aer-dr2-dr3/stubs.sql, the rebuilt reader and the 20261103070000 migration) lacks for the scheduled
-- reading: the columns and tables it reads, as live has them, and live helpers it calls (their behaviour, not their code; they are not changed
-- here). Run on a scratch PostgreSQL only (never on a Supabase project): see run.sh. Nothing here is a copy of live data.
create schema if not exists ref; create schema if not exists cron; create schema if not exists net;
alter table catalogue.courses add column if not exists lifecycle_status text not null default 'active';
create table ref.countries(id uuid primary key default gen_random_uuid(), iso_alpha2 text unique);
insert into ref.countries(iso_alpha2) values ('AU'), ('NZ'), ('CA');
create table ref.provider_types(id uuid primary key default gen_random_uuid(), code text unique);
insert into ref.provider_types(code) values ('university'), ('private_vet');
create table catalogue.providers(id uuid primary key, canonical_name text, display_name text, short_name text, country_id uuid, provider_type_id uuid,
  lifecycle_status text default 'active', publication_status text default 'published', enrols_international boolean default true);
create table security.provider_hidden_v1(provider_id uuid);
alter table pipeline.evidence_artifacts add column if not exists storage_path text default 'stored/x', add column if not exists source_url text,
  add column if not exists mime_type text, add column if not exists created_at timestamptz default now();
alter table pipeline.field_enrich_items add column if not exists cost_usd numeric, add column if not exists created_at timestamptz default now();
create table pipeline.enrichment_flags(id bigserial primary key, entity text, entity_key text, provider_id uuid, field text, reason_code text, state text,
  released_at timestamptz, released_by text, release_kind text, release_reason text, updated_at timestamptz default now());
alter table pipeline.admin_jobs add column if not exists kind text, add column if not exists lane text, add column if not exists state text,
  add column if not exists title text, add column if not exists args jsonb, add column if not exists progress jsonb, add column if not exists requested_by uuid not null,
  add column if not exists reason text not null, add column if not exists scope text, add column if not exists created_at timestamptz default now();
create table pipeline.field_gap_queue_control(id int primary key, owner uuid not null);
insert into pipeline.field_gap_queue_control values (1, '63ba56cb-0000-4000-8000-000000000000');
create table pipeline.layer3_openrouter_observations(kind text, remaining_usd numeric, observed_at timestamptz default now());
insert into pipeline.layer3_openrouter_observations values ('credits', 85.7, now());
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value) values
  ('openrouter', 'credit_floor_usd', 'number', '5'), ('pipeline', 'aer.eligible_countries', 'list', '["AU", "NZ"]'),
  ('pipeline', 'aer.priority_provider_types', 'list', '["university"]'), ('pipeline', 'entry.matrix_enabled', 'number', '1'),
  ('pipeline', 'entry.countries', 'list', '["AU", "NZ"]'), ('pipeline', 'entry.matrix_refresh_days', 'number', '30'),
  ('pipeline', 'entry.providers', 'list', '["d2000000-0000-4000-8000-000000000003"]'), ('pipeline', 'fixture.ai_stopped', 'text', '""'),
  ('pipeline', 'hygiene.retire_after_days', 'number', '14')
on conflict do nothing;
-- the AI rule (one rule for every lane, security.ai_use_refusal_v1): a fixture setting stops it
create function security.ai_use_refusal_v1(p_use text) returns text language sql stable as
  $f$ select nullif(security.toolset_setting('pipeline', 'fixture.ai_stopped') #>> '{}', '') $f$;
create function security.ai_use_allowed_v1(p_use text) returns boolean language sql stable as $f$ select security.ai_use_refusal_v1(p_use) is null $f$;
-- the item gate: a course listed in a fixture setting is held
create function security.enrich_item_held_v1(p_course uuid, p_field text) returns boolean language sql stable as
  $f$ select coalesce(security.toolset_setting('pipeline', 'fixture.item_held'), '[]'::jsonb) ? p_course::text $f$;
-- identity: a 'weak' basis admits no entry requirements
create or replace function security.coverage_identity_allowed(p_provider uuid, p_basis text, p_field text) returns boolean language sql stable as $f$ select p_basis <> 'weak' $f$;
create function security.catalogue_country_codes_v1() returns text[] language sql stable as $f$ select array['AU', 'CA', 'NZ'] $f$;
create function auth.role() returns text language sql stable as $f$ select case when exists (select 1 from auth.session) then 'authenticated' end $f$;
-- live security.aer_eligible_v1 (3 Nov 2026), its body unchanged
create function security.aer_eligible_v1() returns table(provider_id uuid, country text) language sql stable security definer set search_path to '' as $function$
  -- Phase A baseline §1.1: country in aer.eligible_countries, active, published, enrols international students
  select p.id, k.iso_alpha2::text
    from catalogue.providers p join ref.countries k on k.id = p.country_id
   where k.iso_alpha2::text in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'aer.eligible_countries'), '[]'::jsonb)))
     and p.lifecycle_status = 'active' and p.publication_status = 'published' and p.enrols_international is true
$function$;
-- entry matrices: the columns the fire and the refresh read, and the steps the fire calls (counted, not run)
alter table pipeline.entry_matrix_sources add column if not exists read_via text, add column if not exists read_at timestamptz, add column if not exists attempts int default 0,
  add column if not exists evidence_id uuid, add column if not exists error text, add column if not exists updated_at timestamptz default now();
alter table pipeline.entry_matrix_runs add column if not exists attempts int default 0, add column if not exists leased_until timestamptz, add column if not exists error text,
  add column if not exists updated_at timestamptz default now();
create function security.entry_matrix_attach_v1() returns int language sql as $f$ select 0 $f$;
create function security.entry_matrix_use_stored_v1() returns int language sql as $f$ select 0 $f$;
create function security.entry_matrix_enqueue_v1() returns int language sql as $f$ select 0 $f$;
create table pipeline.edge_request_log(function_name text, mode text, created_at timestamptz, request_id bigint);
create table net._http_response(id bigint);
create table pipeline.fixture_submits(body jsonb);
create function pipeline.svc_pilot_submit_nonce(p_fn text, p_body jsonb) returns void language sql as $f$ insert into pipeline.fixture_submits values (p_body) $f$;
-- the scheduler
create table cron.job(jobid bigserial primary key, jobname text unique, schedule text, command text, active boolean default true);
create function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint language sql as
  $f$ insert into cron.job(jobname, schedule, command) values (p_name, p_schedule, p_command) returning jobid $f$;
create function cron.alter_job(job_id bigint, schedule text default null, command text default null, database text default null, username text default null, active boolean default null)
  returns void language sql as $f$ update cron.job set active = coalesce(alter_job.active, job.active) where jobid = job_id $f$;
-- governance tables
create table pipeline.automation_catalogue(jobname text primary key, area text, sort int, label text, description text, control_rank int, batch_editable boolean, layer23_stage text);
create table pipeline.component_register(kind text, name text, layer text, area text, purpose text, status text, replaces text[], replaced_by text, introduced_in text,
  retire_after date, updated_at timestamptz, primary key (kind, name));
create table pipeline.integration_issues(id bigserial primary key, fingerprint text unique, payload jsonb, actor text);
-- the integration queue writer (its behaviour: one issue by fingerprint; the live function is not changed here)
create function security.integration_issue_upsert_v1(p jsonb, p_actor text default 'integration-validate') returns jsonb language sql as
  $f$ insert into pipeline.integration_issues(fingerprint, payload, actor) values (p->>'fingerprint', p, p_actor)
      on conflict (fingerprint) do update set payload = excluded.payload returning jsonb_build_object('id', id) $f$;
