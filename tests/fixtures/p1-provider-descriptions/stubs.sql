-- P1 provider descriptions: isolated fixture database (CF-247 missing-field enrichment, Platform Admin 2 Nov 2026 10:28).
-- The smallest set of schemas, tables and helper functions the migration 20261102050000 and the five live functions it edits need, with
-- the columns they use. Run on a scratch PostgreSQL only (never on a Supabase project): see run.sh. Nothing here is a copy of live data.
-- Helper functions that the change does not edit are simple stand-ins.
create schema if not exists extensions; create extension if not exists pgcrypto schema extensions;
create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists security; create schema if not exists search;
create schema if not exists ref; create schema if not exists auth; create schema if not exists scholarship; create schema if not exists cron; create schema if not exists net; create schema if not exists l4_api; create schema if not exists api;
do $$ begin create role anon; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated; exception when duplicate_object then null; end $$;
do $$ begin create role service_role; exception when duplicate_object then null; end $$;

-- who is calling: a fixture setting (fx.uid, fx.rank, fx.role)
create function auth.uid() returns uuid language sql stable as $f$ select nullif(current_setting('fx.uid', true), '')::uuid $f$;
create function auth.role() returns text language sql stable as $f$ select coalesce(nullif(current_setting('fx.role', true), ''), 'service_role') $f$;
create function security.current_role_rank() returns int language sql stable as $f$ select coalesce(nullif(current_setting('fx.rank', true), '')::int, 0) $f$;

create table pipeline.platform_toolset_settings(toolset_key text, key text, label text, help text, kind text, value jsonb, min_value numeric, max_value numeric,
  unit text, sort int, section text, used_by text, reason text, updated_at timestamptz default now(), primary key (toolset_key, key));
create function security.toolset_setting(p_toolset text, p_key text) returns jsonb language sql stable as
  $f$ select value from pipeline.platform_toolset_settings where toolset_key = p_toolset and key = p_key $f$;
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as
  $f$ select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $f$;
create table pipeline.component_register(kind text, name text, layer text, area text, purpose text, status text, replaces text[], introduced_in text, unique (kind, name));
create table pipeline.automation_catalogue(jobname text primary key, area text, sort int, label text, description text, control_rank int, batch_editable boolean, layer23_stage text);
create table pipeline.admin_control_events(id bigserial primary key, area text, action text, target text, detail jsonb, actor uuid, at timestamptz default now());

-- cron and net stand-ins: a schedule is recorded, never run
create table cron.job(jobid bigserial primary key, jobname text unique, schedule text, command text, active boolean default true);
create function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint language sql as
  $f$ insert into cron.job(jobname, schedule, command) values (p_name, p_schedule, p_command) on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command returning jobid $f$;
create function cron.alter_job(job_id bigint, active boolean) returns void language sql as $f$ update cron.job set active = alter_job.active where jobid = job_id $f$;
create table net._http_response(id bigint primary key);
create table pipeline.edge_request_log(id bigserial primary key, function_name text, mode text, request_id bigint, created_at timestamptz default now());
create function pipeline.svc_pilot_submit_nonce(p_function text, p_body jsonb) returns bigint language sql as
  $f$ insert into pipeline.edge_request_log(function_name, mode, request_id) values (p_function, p_body->>'mode', null) returning id $f$;

-- catalogue
create table ref.countries(id uuid primary key default gen_random_uuid(), iso_alpha2 text);
create table ref.provider_types(id uuid primary key default gen_random_uuid(), code text unique, name text);
create table catalogue.providers(id uuid primary key, stable_key text, canonical_name text, display_name text, website text, description text, country_id uuid,
  provider_type_id uuid, lifecycle_status text default 'active', publication_status text default 'published', updated_at timestamptz default now());
create table catalogue.courses(id uuid primary key, provider_id uuid, canonical_title text, display_title text, course_code text, lifecycle_status text default 'active');
create table pipeline.provider_extra_domains(provider_id uuid, domain text, state text default 'approved', primary key (provider_id, domain));
create table pipeline.manual_locks(entity text, entity_id uuid, field text, mode text default 'value');
create view security.provider_hidden_v1 as select p.id provider_id from catalogue.providers p where p.publication_status <> 'published';

-- evidence
create table pipeline.sources(id uuid primary key default gen_random_uuid(), source_type text, provider_id uuid, label text, url text);
create table pipeline.evidence_artifacts(id uuid primary key default gen_random_uuid(), entity_id uuid, source_id uuid, evidence_type text default 'page', source_url text,
  storage_path text, content_hash text, mime_type text, captured_at timestamptz default now(), metadata jsonb default '{}', created_at timestamptz default now());
create function security.coverage_sweep_source(p_provider_id uuid) returns uuid language plpgsql as $f$
declare v uuid;
begin
  select id into v from pipeline.sources where source_type = 'provider_course_page_sweep' and provider_id = p_provider_id limit 1;
  if v is null then insert into pipeline.sources(source_type, provider_id) values ('provider_course_page_sweep', p_provider_id) returning id into v; end if;
  return v;
end $f$;
create function public.svc_coursefacts_register_evidence(p_source uuid, p_url text, p_path text, p_sha text, p_mime text, p_meta jsonb) returns uuid language sql as
  $f$ insert into pipeline.evidence_artifacts(source_id, source_url, storage_path, content_hash, mime_type, metadata) values (p_source, p_url, p_path, p_sha, p_mime, p_meta) returning id $f$;

-- Layer 4
create table pipeline.layer3_interpretations(id uuid primary key default gen_random_uuid());
create table pipeline.layer4_review_items(id uuid primary key default gen_random_uuid(), entity_type text not null, entity_id uuid not null, field_code text not null,
  evidence_id uuid references pipeline.evidence_artifacts(id), layer3_interpretation_id uuid, before_value jsonb, proposed_value jsonb, layer2_state jsonb not null default '{}',
  layer3_state jsonb not null default '{}', status text not null default 'pending', assigned_to uuid, escalation_reason text, change_control_ref text not null default 'CF-CHG-20260825-038',
  created_at timestamptz not null default now(), decided_at timestamptz, claimed_at timestamptz);
create table pipeline.layer4_decisions(id uuid primary key default gen_random_uuid(), review_item_id uuid, action text, actor_id uuid, reason text, before_value jsonb, proposed_value jsonb,
  final_value jsonb, evidence_id uuid, layer2_state jsonb, layer3_state jsonb, scalar_resolution_id uuid, change_control_ref text, created_at timestamptz default now());
create table pipeline.search_refresh_signals(id uuid primary key default gen_random_uuid(), entity_type text, entity_id uuid, review_decision_id uuid, reason text, change_control_ref text);
create table pipeline.refresh_requests(id uuid primary key default gen_random_uuid(), requested_layer int, source_id uuid, entity_type text, entity_id uuid, evidence_id uuid,
  layer3_profile_id uuid, revalidation_ref text, reason text, trigger_type text, requested_by uuid, change_control_ref text);

-- AI spend: the description lane's daily guard reads the spend this change adds (stand-in: the guard setting against the lane's spend today)
create table pipeline.central_ai_settings(id int primary key, model_identifier text, model_code text);
insert into pipeline.central_ai_settings values (1, 'fixture/pinned-model', 'fixture');

-- the consumer API projection as it is live: website_v2_provider returns catalogue.providers.description for a published provider
create function public.website_v2_provider(p_provider_id text) returns jsonb language sql stable as $f$
  select case when p.id is null or p.publication_status <> 'published' then jsonb_build_object('contract_version', 'website-search-v2', 'error', jsonb_build_object('code', 'NOT_FOUND'))
              else jsonb_build_object('contract_version', 'website-search-v2', 'item', jsonb_build_object('provider_id', p.stable_key, 'description', p.description)) end
    from (select 1) one left join catalogue.providers p on lower(p.stable_key) = lower(btrim(p_provider_id)) $f$;

-- the AI stop as live (security.ai_use_allowed_v1 and security.ai_spend_today_v1 are the live definitions): its tables, empty
create table pipeline.platform_toolsets(key text primary key, enforcement text);
create table pipeline.layer3_openrouter_observations(kind text, remaining_usd numeric, observed_at timestamptz default now());
create table pipeline.scholarship_ai_extractions(id bigserial primary key, answer jsonb, at timestamptz, cost_usd numeric);
create table pipeline.uni_adapter_drafts(created_at timestamptz, cost_usd numeric);
create table pipeline.central_ai_queue(created_at timestamptz, cost_usd numeric);
create table pipeline.coverage_ai_match(decided_at timestamptz, created_at timestamptz, cost_usd numeric);
create table pipeline.field_enrich_items(updated_at timestamptz, cost_usd numeric);
create table pipeline.fee_reader_queue(finished_at timestamptz, created_at timestamptz, cost_usd numeric);
create table pipeline.entry_matrix_runs(updated_at timestamptz, cost_usd numeric);
-- the Layer 4 kinds the live decide function names (stand-ins; not called for a provider description)
create function security.aer_review_kinds_v1() returns text[] language sql immutable as $f$ select array['entry_matrix_first_run', 'entry_matrix_change', 'course_entry_first_read']::text[] $f$;

-- Layer 4 › Inbox as live (security.layer4_inbox_items_v1 and public.admin_layer4_inbox are the live definitions): the other sources it reads, empty
create table auth.users(id uuid primary key, email text);
create table scholarship.scholarships(id uuid primary key, provider_id uuid, name text);
create table pipeline.provider_onboarding(id uuid primary key default gen_random_uuid(), provider_id uuid, status text, stop_reason text, note text, created_at timestamptz default now(), updated_at timestamptz default now());
create table pipeline.adapter_builds(provider_id uuid, wave text);
create table pipeline.enrichment_flags(id bigserial primary key, entity text, entity_key text, provider_id uuid, state text, reason_code text, reason text, evidence jsonb, flagged_at timestamptz default now());
create table pipeline.scholarship_ai_reviews(id bigserial primary key, provider_id uuid, extraction_ids bigint[], url text, reason text, recheck jsonb, status text, created_at timestamptz default now());
create table pipeline.data_flags(id bigserial primary key, entity_type text, entity_id uuid, field_code text, detail jsonb, flag_code text, status text, created_at timestamptz default now());
create table pipeline.layer1_provider_departures(id bigserial primary key, provider_id uuid, courses_retired int, note text, status text, created_at timestamptz default now());
create function security.layer4_decision_outcome_v1(p_kind text, p_choice text, p_result jsonb) returns jsonb language sql stable as
  $f$ select jsonb_build_object('class', case when p_result->>'status' = 'rejected' then 'reconciled' else 'applied' end, 'status', p_result->>'status') $f$;
-- the live wrapper the Inbox calls (as live, md5 39491b87e50f554b8faaa2e0078c01f9)
CREATE OR REPLACE FUNCTION public.layer4_review_decide(p_review_item_id uuid, p_action text, p_reason text, p_final_value jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'security'
AS $function$ select security.layer4_review_decide_impl(p_review_item_id,p_action,p_reason,p_final_value) $function$;

-- central page finder suggestions (worker central_find), as live: one row a provider, found = suggested pages with kind and score
create table pipeline.provider_central_search(provider_id uuid primary key, found jsonb);
