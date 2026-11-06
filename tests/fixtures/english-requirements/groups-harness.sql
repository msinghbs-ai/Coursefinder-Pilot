-- Guards: decision 19:14 §8 (Platform Admin 5 Nov 2026) for English requirements (Platform Admin 6 Nov 2026 09:44 §3-§4): the stand-ins the group migration needs on top of the
-- production-parity fixture. Everything here is a LOCAL STAND-IN for a production object that is not part of the captured English path (named in each comment); the captured tables
-- (proposals, fact sources, course_english_requirements with its keys and triggers, settings, catalogue, register, locks, central search) and the 48 captured functions are the real ones.
-- Isolated local PostgreSQL only.
create extension if not exists pg_trgm;  -- harmless; some captured definitions name extensions on the search path
-- pg_cron: the schedule table, alter_job and the run history, as far as the migration and the status read use them
create schema if not exists cron;
create table if not exists cron.job (jobid bigserial primary key, jobname text unique, schedule text, command text, active boolean default true);
create table if not exists cron.job_run_details (runid bigserial primary key, jobid bigint, start_time timestamptz, status text);
create or replace function cron.alter_job(job_id bigint, schedule text default null, command text default null, database text default null, username text default null, active boolean default null) returns void
language sql as $$ update cron.job set schedule = coalesce(alter_job.schedule, job.schedule), command = coalesce(alter_job.command, job.command), active = coalesce(alter_job.active, job.active) where jobid = job_id $$;
-- the live commands the migration replaces (md5 of the policy-add-tests command is guarded by the migration)
insert into cron.job(jobname, schedule, command) values
 ('policy-add-tests', '17 * * * *', $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'provider_facts_add_tests', 'limit', security.pipeline_num_v1('batch.policy_add_tests', 40)::int))$c$),
 ('central-attach', '48 * * * *', 'select security.central_pages_attach_v1()'),
 ('central-find', '2-59/5 * * * *', 'select 1');
-- security.roles / security.user_roles (read by the captured security.current_role_rank())
create schema if not exists security;
create table if not exists security.roles (code text primary key, rank smallint not null, status text not null default 'active');
create table if not exists security.user_roles (user_id uuid not null, role_code text not null references security.roles(code), expires_at timestamptz);
insert into security.roles values ('platform_admin', 6, 'active'), ('pipeline_operator', 4, 'active');
-- security.provider_hidden_v1: the production view (read 6 Nov 2026 from pg_get_viewdef)
-- catalogue.providers / catalogue.courses: the production fixture holds only their keys (referenced tables); the columns the English path reads, with production types
alter table catalogue.providers add column if not exists canonical_name text, add column if not exists display_name text, add column if not exists country_id uuid references ref.countries(id),
  add column if not exists provider_type_id uuid references ref.provider_types(id), add column if not exists website text, add column if not exists lifecycle_status text, add column if not exists publication_status text;
alter table catalogue.courses add column if not exists provider_id uuid references catalogue.providers(id), add column if not exists canonical_title text, add column if not exists study_level_id uuid references ref.study_levels(id),
  add column if not exists primary_field_id uuid references ref.fields_of_study(id), add column if not exists lifecycle_status text, add column if not exists open_to_international boolean;
create or replace view security.provider_hidden_v1 as select id as provider_id from catalogue.providers p where publication_status is distinct from 'published' or lifecycle_status is distinct from 'active';
-- pipeline.evidence_artifacts: the key only is captured; the policy route reads storage_path
alter table pipeline.evidence_artifacts add column if not exists storage_path text;
-- tables the replaced functions read that are outside the captured English path
create table if not exists pipeline.central_ai_settings (id int primary key, enabled boolean not null default true);
insert into pipeline.central_ai_settings values (1, true) on conflict do nothing;
create table if not exists pipeline.enrich_focus_providers (provider_id uuid primary key, in_focus boolean, rank int);
create table if not exists pipeline.enrichment_flags (entity text, entity_key text, provider_id uuid, field text, reason_code text, reason text, source text, flagged_at timestamptz default now(), cleared_at timestamptz, unique (entity, entity_key, field, reason_code));
create table if not exists pipeline.coverage_vendor_usage (id bigserial primary key, purpose text, units numeric, provider_id uuid, url text, at timestamptz default now());
create table if not exists pipeline.course_link_recipes (provider_id uuid, search_domain text, active boolean default true);
create schema if not exists search;
create table if not exists search.enrichment_source_gates (projection_code text, domain_code text, source_id uuid, gate_status text, approval_ref text, approved_at timestamptz, created_at timestamptz, updated_at timestamptz);
create or replace function search.refresh_course_enrichment_scoped_v1(p_ids uuid[], p_force boolean) returns void language sql as $$ select $$;
create or replace function security.coverage_sweep_source(p uuid) returns uuid language sql as $$ select p $$;
create or replace function security.tuition_chase_enabled(p uuid) returns boolean language sql as $$ select false $$;
-- STAND-IN for security.coverage_apply_course_v1(course, source, evidence, url, content_hash, payload): the real function runs the admission controls (tested by their own specs).
-- This one writes the payload's English rows into the REAL catalogue.course_english_requirements (its unique key, check constraints and triggers apply), reusing a withdrawn row.
create or replace function security.coverage_apply_course_v1(p_course uuid, p_source uuid, p_evidence uuid, p_url text, p_hash text, p_payload jsonb) returns jsonb language plpgsql as $$
declare q jsonb; t uuid;
begin
  for q in select e from jsonb_array_elements(p_payload->'english_requirements') e loop
    select id into t from ref.english_tests where code = q->>'test_code';
    insert into catalogue.course_english_requirements(course_id, english_test_id, overall_score, component_scores, notes, source_requirement_key, status, last_verified_at)
    values (p_course, t, (q->>'overall_score')::numeric, coalesce(q->'component_scores', '{}'::jsonb), q->>'notes', q->>'source_requirement_key', 'active', now())
    on conflict (course_id, english_test_id) do update set overall_score = excluded.overall_score, component_scores = excluded.component_scores, notes = excluded.notes,
      source_requirement_key = excluded.source_requirement_key, status = 'active', last_verified_at = now();
  end loop;
  return jsonb_build_object('ok', true);
end $$;
insert into pipeline.platform_toolsets(key) select 'pipeline' where not exists (select 1 from pipeline.platform_toolsets where key = 'pipeline');
-- STAND-IN for security.calendar_scope_v1(proposal, url, parser): the academic calendar branch belongs to the intake workstream and is outside the English path (no calendar proposal is used here)
create or replace function security.calendar_scope_v1(p jsonb, u text, parser text) returns text language sql as $$ select 'other'::text $$;
-- security.provider_english_flagged(jsonb): the production definition, read 6 Nov 2026 (read by provider_english_apply_v1; not in the captured path). The md5 below is the live one.
CREATE OR REPLACE FUNCTION security.provider_english_flagged(p_proposal jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce((p_proposal->>'flag_standard')::boolean, false)
      or coalesce(p_proposal->'caveats', '[]'::jsonb) ?| array['higher_unlisted', 'exceptions_unlisted', 'level_not_stated']
$function$;
do $$ begin
  if md5(pg_get_functiondef('security.provider_english_flagged(jsonb)'::regprocedure)) <> 'fb8eddcacadb800d771205f05226bc65' then raise exception 'security.provider_english_flagged differs from production'; end if;
end $$;
