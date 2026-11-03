-- Live shapes for the workstream B source recovery fixtures (CF-247 P0 autonomous operations, 3 Nov 2026). Only the columns the definitions under
-- test read or write; read-only from production on 3 Nov 2026 15:43 AEDT (information_schema). Never a Supabase project.
create extension if not exists pgcrypto;
create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists security; create schema if not exists cron;
do $$ begin if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; end $$;

create table pipeline.platform_toolset_settings (toolset_key text not null, key text not null, label text not null, help text not null default '', kind text not null, value jsonb not null,
  min_value numeric, max_value numeric, unit text, sort int not null default 100, reason text, updated_by uuid, updated_at timestamptz not null default now(),
  section text not null default 'Notices', used_by text, primary key (toolset_key, key));
create or replace function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable set search_path to '' as $$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $$;
create table pipeline.automation_catalogue (jobname text primary key, area text not null, sort int not null default 100, label text not null, description text not null,
  control_rank int not null default 5, batch_editable boolean not null default false, layer23_stage text);
create table pipeline.component_register (kind text not null, name text not null, layer text not null, area text, purpose text, status text not null default 'active',
  replaces text[] not null default '{}', replaced_by text, introduced_in text, retire_after date, primary key (kind, name));
create table cron.job (jobid bigint generated always as identity primary key, jobname text unique, schedule text, command text, active boolean default true);
create or replace function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint language sql as $$
  insert into cron.job(jobname, schedule, command) values (p_name, p_schedule, p_command) returning jobid $$;

create table catalogue.providers (id uuid primary key, canonical_name text, lifecycle_status text default 'active', website text);
create table catalogue.courses (id uuid primary key, provider_id uuid not null, canonical_title text, course_code text, lifecycle_status text default 'active', study_level_id uuid);
create view security.provider_hidden_v1 as select p.id provider_id from catalogue.providers p where p.lifecycle_status = 'hidden';
create or replace function security.coverage_country(p uuid) returns text language sql stable as $$ select 'AU' $$;

create table pipeline.evidence_artifacts (id uuid primary key default gen_random_uuid(), storage_path text, content_hash text);
create table pipeline.coverage_course_pages (course_id uuid primary key, provider_id uuid, url text, status text, read_status text, read_at timestamptz, read_attempts int default 0,
  identity_basis text, evidence_id uuid, candidates jsonb);
create table pipeline.course_page_proofs (course_id uuid primary key, page_key text, proven boolean not null, checked_at timestamptz not null default now());
create table pipeline.source_proof_requests (course_id uuid primary key, provider_id uuid not null,
  route text not null check (route in ('layer4', 'locked', 'reading', 'relink', 'search', 'no_route', 'exhausted')),
  state text not null check (state in ('queued', 'held', 'done')), fingerprint text, attempts int not null default 0, requested_at timestamptz, settled_at timestamptz,
  outcome text, considered_at timestamptz not null default now(), detail jsonb not null default '{}'::jsonb);
create table pipeline.source_proof_feed_runs (id bigserial primary key, run_at timestamptz not null default now(), outcome text not null check (outcome in ('done', 'held', 'idle')),
  hold_reason text, settled int not null default 0, routed jsonb not null default '{}'::jsonb, ms int);
create table pipeline.course_relink (course_id uuid primary key, provider_id uuid not null, old_url text, candidates jsonb not null default '[]', sources jsonb not null default '[]',
  pattern text, state text not null, reason text, result_url text, started_at timestamptz not null default now(), decided_at timestamptz, rule int);
create table pipeline.course_link_search (course_id uuid primary key, provider_id uuid, stage text, state text, query text, req_id bigint, attempts int not null default 0, results jsonb,
  candidates jsonb, cand_idx int, bound_url text, queued_at timestamptz, sent_at timestamptz, done_at timestamptz, requested_at timestamptz);
create table pipeline.course_link_recipes (provider_id uuid primary key, search_domain text, active boolean);
create table pipeline.provider_priority (provider_id uuid primary key, rank int);
create table pipeline.coverage_provider_urls (provider_id uuid, url text, title text, primary key (provider_id, url));
create table pipeline.provider_discovery_links (provider_id uuid, url text, anchor_text text, primary key (provider_id, url));
create table pipeline.course_page_blocks (course_id uuid, url text, reason text, created_at timestamptz default now());
create table pipeline.page_rejections (course_id uuid, url text, provider_id uuid, source text, reason text, rejected_at timestamptz default now());
create table pipeline.layer4_review_items (id uuid primary key default gen_random_uuid(), entity_id uuid, field_code text, status text default 'pending');
create table pipeline.manual_locks (entity text, entity_id uuid, field text);
create table pipeline.firecrawl_calls (id bigserial primary key, at timestamptz not null default now(), use_case text, endpoint text, course_id uuid, provider_id uuid, url text,
  credits_used numeric, outcome text);
create table pipeline.field_enrich_items (id bigserial primary key, course_id uuid, field text, state text, updated_at timestamptz default now());
create table pipeline.course_field_absence (course_id uuid not null, field text not null, absence_class text not null, evidence_id uuid, content_hash text, reader_version text,
  confidence numeric, reason text, next_eligible_at timestamptz, reeval_trigger text, item_id bigint, classified_at timestamptz not null default now(), resolved_at timestamptz,
  primary key (course_id, field));

-- live: security.course_page_key_v1 (md5 eed0e852..., read against) and the relink request check (097641b2...)
create or replace function security.course_page_key_v1(p_course uuid) returns text
language sql stable security definer set search_path to '' as $function$
  -- CF-247: the state of the course's page that its proof depends on (a new read, binding or identity changes the key)
  select md5(concat_ws('|', g.status, g.read_status, g.identity_basis, g.evidence_id, g.url, g.candidates->>'final_url', g.candidates->>'page_title', g.candidates->>'h1'))
    from pipeline.coverage_course_pages g where g.course_id = p_course
$function$;
create or replace function security.source_proof_relink_asked_v1(p_course uuid, p_since timestamptz) returns boolean
language sql stable security definer set search_path to '' as $function$
  -- CF-247 mandate 3 Nov 2026 12:04 §6: the source-proof lane asked course-relink to try this course again after its last relink decision
  select exists (select 1 from pipeline.source_proof_requests q where q.course_id = p_course and q.route = 'relink' and q.state = 'queued'
                    and q.requested_at > coalesce(p_since, '-infinity'::timestamptz))
$function$;
-- the binding a relink candidate gets (live: security.course_link_bind_v1 binds the page for the reader to read; not edited here)
create or replace function security.course_link_bind_v1(p_course uuid, p_provider uuid, p_url text, p_basis text) returns void language sql as $$
  update pipeline.coverage_course_pages set url = p_url, status = 'bound', read_status = null, identity_basis = null, evidence_id = null where course_id = p_course $$;
-- called by the live course_relink_tick_v1 (not edited here; settles page re-finds)
create or replace function security.page_refind_settle_v1() returns void language sql as $$ select $$;
