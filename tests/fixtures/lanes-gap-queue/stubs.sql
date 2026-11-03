-- Live shapes for the lanes and gap queue fixtures (CF-247 P0 mandate 3 Nov 2026 10:44 §3 Agent C, §6). Only the columns the definitions
set check_function_bodies = off;
-- under test read or write; read-only from production on 3 Nov 2026 (information_schema). Never a Supabase project.
create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists security; create schema if not exists scholarship;
create schema if not exists cron; create schema if not exists auth; create schema if not exists ref;
create or replace function auth.role() returns text language sql as $$ select nullif(current_setting('request.jwt.claim.role', true), '') $$;
create or replace function auth.uid() returns uuid language sql as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
do $$ begin if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if; end $$;

create table pipeline.platform_toolset_settings (toolset_key text not null, key text not null, label text not null, help text not null default '', kind text not null, value jsonb not null,
  min_value numeric, max_value numeric, unit text, sort int not null default 100, reason text, updated_by uuid, updated_at timestamptz not null default now(),
  section text not null default 'Notices', used_by text, primary key (toolset_key, key));
create table pipeline.platform_toolsets (key text primary key, enforcement text);
create table pipeline.mode_outcome_ledger (id bigint generated always as identity primary key, run_at timestamptz not null default now(), mode text, status int, ms int, items int, ok int,
  failed int, wait_ms int, landed jsonb, worker text, detail jsonb, outcome text check (outcome = any (array['succeeded', 'idle', 'zero_work_error', 'failed'])));
create table pipeline.automation_catalogue (jobname text primary key, area text not null, sort int not null default 100, label text not null, description text not null,
  control_rank int not null default 5, batch_editable boolean not null default false, layer23_stage text);
create table pipeline.component_register (kind text not null, name text not null, layer text not null, area text, purpose text, status text not null default 'active',
  replaces text[] not null default '{}', replaced_by text, introduced_in text, retire_after date, primary key (kind, name));
create table cron.job (jobid bigint generated always as identity primary key, jobname text unique, schedule text, command text, active boolean default true);
create or replace function cron.alter_job(job_id bigint, schedule text default null, command text default null, database text default null, username text default null, active boolean default null)
returns void language sql as $$ update cron.job set schedule = coalesce(alter_job.schedule, job.schedule), command = coalesce(alter_job.command, job.command), active = coalesce(alter_job.active, job.active) where jobid = job_id $$;
create table pipeline.submitted (id bigint generated always as identity, fn text, body jsonb);
create or replace function pipeline.svc_pilot_submit_nonce(p_fn text, p_body jsonb) returns bigint language sql as $$ insert into pipeline.submitted(fn, body) values (p_fn, p_body) returning id $$;

-- settings readers (live text for pipeline_num_v1; the others are the same rule on their toolset)
create or replace function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable set search_path to '' as $$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $$;
create or replace function security.fc_setting_num_v1(p_key text, p_default numeric) returns numeric language sql stable set search_path to '' as $$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = p_key), p_default) $$;
create or replace function security.toolset_setting(p_toolset text, p_key text) returns jsonb language sql stable set search_path to '' as $$
  select s.value from pipeline.platform_toolset_settings s where s.toolset_key = p_toolset and s.key = p_key $$;
create or replace function security.current_role_rank() returns smallint language sql stable as $$ select nullif(current_setting('request.rank', true), '')::smallint $$;

-- Firecrawl spend helpers the live budget functions read (fixture: today's billed use is the usage table's own sum)
create table pipeline.coverage_vendor_usage (id bigint generated always as identity primary key, acquisition_provider_id uuid not null default gen_random_uuid(), units numeric not null,
  purpose text not null, provider_id uuid, url text, at timestamptz not null default now(), on_demand_run uuid);
create table pipeline.layer2_acquisition_providers (id uuid primary key default gen_random_uuid(), provider_key text, billing_config jsonb default '{}', request_template jsonb default '{}');
create table pipeline.vendor_credit_observations (provider_id uuid, remaining_units numeric, observed_at timestamptz);
create table pipeline.layer2_provider_attempts (acquisition_provider_id uuid, started_at timestamptz);
create or replace function security.layer2_provider_budget_status(p uuid, u numeric) returns jsonb language sql as $$ select '{"allowed": true}'::jsonb $$;
create or replace function security.fc_billed_today_v1() returns numeric language sql stable set search_path to '' as $$ select coalesce(sum(units), 0) from pipeline.coverage_vendor_usage where at >= security.fc_day_start_v1() $$;
create or replace function security.fc_on_demand_today_v1() returns numeric language sql stable set search_path to '' as $$ select coalesce(sum(units), 0) from pipeline.coverage_vendor_usage where at >= security.fc_day_start_v1() and on_demand_run is not null $$;
-- AI refusal helpers
create table pipeline.layer3_openrouter_observations (kind text, remaining_usd numeric, observed_at timestamptz);
create table pipeline.ai_spend_ledger (id bigint generated always as identity primary key, at timestamptz not null default now(), lane text not null, source text not null default 'call', source_id text, cost_usd numeric not null, calls int not null default 1);
create or replace function security.ai_spend_today_v1() returns table(use text, spent numeric, guard numeric) language sql stable set search_path to '' as $$
  select l.lane, sum(l.cost_usd), 0::numeric from pipeline.ai_spend_ledger l where l.at >= date_trunc('day', now()) group by 1 $$;

-- catalogue and pipeline rows the gap queue reads
create table catalogue.providers (id uuid primary key default gen_random_uuid(), canonical_name text, display_name text, address_line1 text, lifecycle_status text default 'active', website text);
create table catalogue.courses (id uuid primary key, provider_id uuid not null, canonical_title text, lifecycle_status text default 'active', duration_value numeric, study_level_id uuid,
  delivery_mode text, primary_field_id uuid, open_to_international boolean, description text);
create table catalogue.course_campuses (course_id uuid, campus_id uuid);
create table catalogue.course_english_requirements (course_id uuid, status text);
create table catalogue.course_intakes (course_id uuid, status text);
create table catalogue.campuses (id uuid primary key default gen_random_uuid(), provider_id uuid, status text, subdivision_id uuid, city text);
create view security.provider_hidden_v1 as select p.id provider_id from catalogue.providers p where p.lifecycle_status = 'hidden';
create table pipeline.manual_locks (entity text, entity_id uuid, field text, mode text, set_by uuid, set_at timestamptz default now());
create table pipeline.coverage_course_pages (course_id uuid primary key, provider_id uuid, url text, status text default 'bound', read_at timestamptz, next_read_at timestamptz, read_attempts int default 0, leased_until timestamptz,
  read_status text, identity_basis text, evidence_id uuid, candidates jsonb);
create table pipeline.field_enrich_items (id bigint generated always as identity primary key, job_id uuid not null, provider_id uuid not null, course_id uuid, field text not null,
  state text not null default 'queued', source text, reason text, storage_path text, attempts int not null default 0, leased_until timestamptz, cost_usd numeric,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique nulls not distinct (job_id, provider_id, course_id, field));
create index field_enrich_items_course_field_idx on pipeline.field_enrich_items (course_id, field);
create table pipeline.field_gap_queue_control (id int primary key default 1, enabled boolean not null default true, owner uuid not null, reason text not null, updated_at timestamptz not null default now());
create table pipeline.admin_jobs (id uuid primary key default gen_random_uuid(), kind text not null, lane text not null default 'adapters', state text not null default 'queued', title text not null,
  args jsonb not null default '{}', progress jsonb not null default '{}', requested_by uuid not null, reason text not null, scope text, created_at timestamptz not null default now());
create table pipeline.admin_job_events (id bigint generated always as identity primary key, job_id uuid, at timestamptz default now(), note text, detail jsonb);
create table pipeline.fields_in_scope (field text primary key, sort int, sources text[] not null default array['ai_stored']);
create or replace function security.enrich_fields_v1() returns table(field text, label text, level text, sources text[], sort int) language sql immutable as $$
  select f.field, f.field, 'course', f.sources, f.sort from pipeline.fields_in_scope f order by f.sort $$;
create or replace function security.field_crosscheck_v1() returns jsonb language sql as $$ select '{"checked": 0}'::jsonb $$;
create or replace function security.campus_regions_apply_v1() returns int language sql as $$ select 0 $$;
create or replace function security.enrich_item_held_v1(p_course uuid, p_field text) returns boolean language sql stable as $$ select false $$;
create or replace function security.catalogue_country_codes_v1() returns text[] language sql stable as $$ select array['AU', 'NZ', 'CA'] $$;
create or replace function security.enrich_course_text_gaps_v1(p_fields text[]) returns table(provider_id uuid, course_id uuid, field text, pri int) language sql as $$ select null::uuid, null::uuid, null::text, null::int where false $$;

-- scholarship queues
create table pipeline.evidence_artifacts (id uuid primary key default gen_random_uuid(), storage_path text);
create table scholarship.scholarships (id uuid primary key default gen_random_uuid(), evidence_id uuid, provider_id uuid);
create table pipeline.scholarship_pages (scholarship_id uuid primary key, evidence_id uuid);
create table pipeline.scholarship_page_candidates (id bigint generated always as identity primary key, storage_path text, content_hash text, evidence_id uuid);
create table pipeline.scholarship_ai_models (code text primary key, model_identifier text);
create table pipeline.scholarship_ai_prompts (version int primary key, text text);
create table pipeline.scholarship_ai_queue (id bigint generated always as identity primary key, model_code text not null, prompt_version int not null, run_kind text not null, job_id uuid, sample_id int,
  candidate_id bigint, scholarship_id uuid, provider_id uuid, url text not null, state text not null default 'queued', attempts int not null default 0, leased_until timestamptz,
  next_try_at timestamptz not null default now(), created_at timestamptz not null default now(), done_at timestamptz, extraction_id bigint, step int not null default 1, storage_path text, root_id bigint, skip_reason text);
create table pipeline.scholarship_ai_extractions (id bigint generated always as identity primary key, url text, storage_path text, content_hash text, evidence_id uuid, error text, at timestamptz default now(), answer jsonb);
create table pipeline.scholarship_ai_extract_settings (id int primary key, chain text[]);
create table pipeline.scholarship_ai_reviews (id bigint generated always as identity primary key, provider_id uuid, url text not null, storage_path text, extraction_ids bigint[] not null default '{}',
  reason text not null default 'held', status text not null default 'pending', recheck jsonb);
create or replace function scholarship.provider_currency(p uuid) returns text language sql as $$ select 'AUD' $$;
create or replace function security.third_party_host_v1(p_url text) returns boolean language sql stable as $$ select coalesce(p_url, '') like '%directory.example%' $$;
create or replace function security.provider_sch_search_off_v1(p uuid) returns boolean language sql stable as $$ select false $$;
create or replace function security.coverage_country(p uuid) returns text language sql stable as $$ select 'AU' $$;

-- the other queues the lane status counts
create table pipeline.course_link_search (course_id uuid primary key, provider_id uuid, state text, sent_at timestamptz);
create table pipeline.course_link_search_settings (id int primary key, enabled boolean, monthly_credit_cap numeric);
create table pipeline.provider_central_search (provider_id uuid primary key, state text);
create table pipeline.scholarship_listing_pages (id bigint generated always as identity primary key, provider_id uuid, url text, active boolean, source text, next_read_at timestamptz);
create table pipeline.fee_reader_queue (id bigint generated always as identity primary key, state text);
create table pipeline.central_ai_queue (id bigint generated always as identity primary key, state text);
create table pipeline.provider_description_reads (id bigint generated always as identity primary key, state text);
create table pipeline.layer4_review_items (id uuid primary key default gen_random_uuid(), status text not null default 'pending', decided_at timestamptz);
create or replace function security.pipeline_yield_v1(p_hours int) returns jsonb language sql stable as $$ select jsonb_build_object('window_hours', coalesce(p_hours, 24), 'lanes', '[]'::jsonb) $$;
create or replace function security.worker_call_work_v1(p_content text) returns numeric language plpgsql immutable set search_path to '' as $function$
declare j jsonb;
begin
  begin j := p_content::jsonb; exception when others then return null; end;
  if jsonb_typeof(j) <> 'object' then return null; end if;
  return (select coalesce(sum(case when jsonb_typeof(v) = 'number' then (v #>> '{}')::numeric when jsonb_typeof(v) = 'array' then jsonb_array_length(v) else 0 end), 0)
            from jsonb_each(j) e(k, v) where k in ('providers', 'items', 'rows', 'found', 'read', 'searched', 'pages', 'picked', 'discover', 'applied', 'done', 'checked'));
end $function$;

-- the idle flag recheck (IQ-00060): flags, the edge log and responses it reads, and the release that switches a job on (flag_requeue_v1's rule)
create schema if not exists net;
create table net._http_response (id bigint primary key, status_code int, content text);
create table pipeline.edge_request_log (request_id bigint, function_name text, mode text, created_at timestamptz default now());
create table pipeline.enrichment_flags (id bigint generated always as identity primary key, entity text, entity_key text, provider_id uuid, field text default '', reason_code text, reason text,
  source text, flagged_at timestamptz default now(), cleared_at timestamptz, kind text, state text default 'raised', tries int default 0, checks int default 0, evidence jsonb,
  next_check_at timestamptz, released_at timestamptz, released_by text, release_reason text, unique (entity, entity_key, field, reason_code));
create or replace function security.flag_list_num_v1(p_key text, p_n int) returns numeric language sql stable as $$ select null::numeric $$;
create or replace function security.worker_mode_waiting_v1(p_mode text) returns boolean language sql stable as $$ select false $$;
create or replace function security.flag_raise_v1(p_entity text, p_key text, p_provider_id uuid, p_field text, p_code text, p_reason text, p_kind text, p_actor text, p_actor_kind text,
  p_evidence jsonb, p_input_mark text, p_next_check timestamptz) returns bigint language sql as $$
  insert into pipeline.enrichment_flags(entity, entity_key, field, reason_code, reason, state, next_check_at) values (p_entity, p_key, p_field, p_code, p_reason, 'raised', p_next_check)
  on conflict (entity, entity_key, field, reason_code) do update set state = 'raised', reason = excluded.reason, next_check_at = excluded.next_check_at returning id $$;
create or replace function security.flag_release_v1(p_id bigint, p_actor text, p_actor_kind text, p_reason text, p_evidence jsonb, p_keep_checks boolean) returns jsonb language plpgsql as $$
declare f pipeline.enrichment_flags;
begin
  update pipeline.enrichment_flags set state = 'released', released_at = now(), released_by = p_actor, release_reason = p_reason, checks = checks + 1, next_check_at = null where id = p_id returning * into f;
  if f.entity = 'job' and f.reason_code = 'idle_paused' then perform cron.alter_job((select jobid from cron.job where jobname = f.entity_key), active := true); end if;  -- security.flag_requeue_v1
  return jsonb_build_object('id', f.id, 'state', 'released');
end $$;

-- the course page check (E16): a fixture page whose address contains "refuse" is refused
create or replace function security.course_page_check_v1(p_course uuid, p_url text, p_title text, p_identity text) returns jsonb language sql stable as $$
  select jsonb_build_object('verdict', case when coalesce(p_url, '') like '%refuse%' then 'refuse' else 'pass' end) $$;
