-- Live shapes for the scholarship coverage recovery fixtures (CF-247, 4 Nov 2026). Columns as read from production on 4 Nov 2026 05:10-05:45 AEDT
-- (information_schema, read only); only the tables and helpers the definitions under test read or write. Helpers marked "live" carry the live text;
-- the others keep the live semantics the cases need. Never a Supabase project.
set check_function_bodies = off;
create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists security; create schema if not exists scholarship;
create schema if not exists ref; create schema if not exists auth; create schema if not exists api; create schema if not exists cron;
create or replace function auth.role() returns text language sql as $$ select nullif(current_setting('request.jwt.claim.role', true), '') $$;
do $$ begin if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if; end $$;

create table pipeline.platform_toolset_settings (toolset_key text not null, key text not null, label text not null, help text not null default '', kind text not null, value jsonb not null,
  min_value numeric, max_value numeric, unit text, sort int not null default 100, reason text, updated_by uuid, updated_at timestamptz not null default now(),
  section text not null default 'Notices', used_by text, primary key (toolset_key, key));
create or replace function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable set search_path to '' as $$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $$;
create or replace function security.toolset_setting(p_toolset text, p_key text) returns jsonb language sql stable set search_path to '' as $$
  select s.value from pipeline.platform_toolset_settings s where s.toolset_key = p_toolset and s.key = p_key $$;
create or replace function security.scholarship_flag_v1(p_key text, p_default boolean) returns boolean language sql stable security definer set search_path to '' as $function$
  select coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default)
$function$;
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value) values
  ('pipeline', 'scholarship.non_university_admission', 'Non-university admission', 'boolean', 'true'),
  ('pipeline', 'scholarship.pilot_only', 'Pilot only', 'boolean', 'true'),
  ('pipeline', 'scholarship.non_university_types', 'Non-university types', 'list', '["university_college","higher_education_institute","tafe_polytechnic","private_vet","wananga"]'),
  ('pipeline', 'coverage.provider_level_types', 'Provider-level types', 'list', '["university","university_college","tafe_polytechnic","wananga"]');
create table pipeline.automation_catalogue (jobname text primary key, area text, sort int, label text, description text, control_rank int, batch_editable boolean, layer23_stage text);
create table pipeline.component_register (kind text not null, name text not null, layer text, area text, purpose text, status text, replaces text[], introduced_in text, primary key (kind, name));
create table cron.job (jobid bigint generated always as identity primary key, jobname text unique, schedule text, command text, active boolean default true);
create or replace function cron.schedule(p_name text, p_sched text, p_cmd text) returns bigint language sql as $$
  insert into cron.job(jobname, schedule, command) values (p_name, p_sched, p_cmd) returning jobid $$;

create table ref.countries (id uuid primary key default gen_random_uuid(), iso_alpha2 text, scholarship_ingestion_enabled boolean not null default true);
create table ref.provider_types (id uuid primary key default gen_random_uuid(), code text, status text default 'active');
create table ref.study_levels (id uuid primary key default gen_random_uuid(), code text);
create table catalogue.providers (id uuid primary key default gen_random_uuid(), canonical_name text, display_name text, short_name text, country_id uuid, provider_type_id uuid,
  provider_type_basis text, lifecycle_status text default 'active', publication_status text default 'published', website text, enrols_international boolean default true);
create view security.provider_hidden_v1 as select p.id provider_id from catalogue.providers p where p.publication_status is distinct from 'published' or p.lifecycle_status is distinct from 'active';
create table pipeline.scholarship_pilot_members (provider_id uuid primary key);
create or replace function security.scholarship_pilot_member_v1(p uuid) returns boolean language sql stable as $$ select exists (select 1 from pipeline.scholarship_pilot_members m where m.provider_id = p) $$;
create or replace function security.scholarship_pilot_scope_v1(p_provider_id uuid) returns boolean language sql stable security definer set search_path to '' as $function$
  select not security.scholarship_flag_v1('scholarship.pilot_only', true) or security.scholarship_pilot_member_v1(p_provider_id)
$function$;
create table pipeline.provider_university_groups (provider_id uuid, grp text);
create or replace function security.provider_university_groups(p uuid) returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(grp), '[]'::jsonb) from pipeline.provider_university_groups where provider_id = p $$;
-- live (md5 4525429ae4085b67d9851ed2899329cb)
CREATE OR REPLACE FUNCTION security.australian_university(p_provider_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'ref', 'security'
AS $function$
  select exists (select 1 from catalogue.providers p join ref.countries c on c.id=p.country_id
     where p.id=p_provider_id and c.iso_alpha2='AU' and p.lifecycle_status='active'
       and (jsonb_array_length(coalesce(security.provider_university_groups(p.id),'[]'))>0
            or (p.canonical_name ~* '\muniversity\M' and p.canonical_name !~* '(college|pathways?|language cent|senior|theology|divinity)')))
$function$;
create or replace function security.site_host_v1(p_url text) returns text language sql immutable as $$ select lower(substring(p_url from '^[a-z]+://(?:www\.)?([^/:?#]+)')) $$;
create or replace function security.third_party_host_v1(p_url text) returns boolean language sql stable as $$
  select coalesce(security.site_host_v1(p_url), '') in ('coursesearch.studymelbourne.vic.gov.au', 'search.studyqueensland.qld.gov.au') $$;
create or replace function security.scholarship_url_norm(p text) returns text language sql immutable as $$
  select lower(regexp_replace(regexp_replace(coalesce(p, ''), '^https?://(www\.)?', ''), '/+$', '')) $$;
create or replace function security.url_on_provider_site(p_url text, p_site text) returns boolean language sql immutable as $$
  select p_site is not null and (security.site_host_v1(p_url) = security.site_host_v1(case when p_site ~ '^[a-z]+://' then p_site else 'https://' || p_site end)
         or security.site_host_v1(p_url) like '%.' || security.site_host_v1(case when p_site ~ '^[a-z]+://' then p_site else 'https://' || p_site end)) $$;
create table pipeline.scholarship_discovery_providers(provider_id uuid primary key, website text, site_origin text, priority int, reason text, status text, method text,
  url_count int, kept_count int, matched_count int, attempts int not null default 0, leased_until timestamptz, discovered_at timestamptz, last_error text,
  updated_at timestamptz default now(), allowed_hosts text[], tier smallint, next_discover_at timestamptz, sources_mapped jsonb, settled_at timestamptz, settled_from text, settle_reason text);
-- live text
create or replace function security.url_on_provider_sites(p_url text, p_provider_id uuid) returns boolean language sql stable security definer
  set search_path to 'pg_catalog', 'pipeline', 'security' as $function$
  select coalesce((select security.url_on_provider_site(p_url, coalesce(d.site_origin,d.website)) or security.url_on_provider_site(p_url, d.website)
                          or exists (select 1 from unnest(d.allowed_hosts) h where security.url_on_provider_site(p_url, h))
                     from pipeline.scholarship_discovery_providers d where d.provider_id=p_provider_id), false)
$function$;
create table pipeline.fx_held (provider_id uuid primary key);
create or replace function security.fc_sch_held_v1(p uuid, p_strict boolean) returns boolean language sql stable as $$ select exists (select 1 from pipeline.fx_held h where h.provider_id = p) $$;
-- live (md5 269f74a985acbc37f1f3b8615efa6254)
CREATE OR REPLACE FUNCTION security.scholarship_admission_provider_ok_v1(p_provider_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select security.scholarship_university(p_provider_id)
      or (security.scholarship_flag_v1('scholarship.non_university_admission', false)
          -- CF-247 scholarships beyond universities (decision 3 Nov 2026 08:44 §4): the pilot providers only while scholarship.pilot_only is on
          and security.scholarship_pilot_scope_v1(p_provider_id)
          and exists (select 1 from catalogue.providers p join ref.provider_types t on t.id = p.provider_type_id join ref.countries k on k.id = p.country_id
                       where p.id = p_provider_id and p.lifecycle_status = 'active' and k.scholarship_ingestion_enabled
                         and t.status = 'active' and p.provider_type_basis is not null
                         and t.code in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'scholarship.non_university_types'), '[]'::jsonb)))
                         and nullif(btrim(coalesce(p.website, '')), '') is not null and not security.third_party_host_v1(p.website)))
$function$;
create or replace function security.coverage_kv_v1(p_key text) returns table(k text, v text) language sql stable as $$
  select split_part(x, '=', 1), split_part(x, '=', 2) from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', p_key), '[]'::jsonb)) x $$;

create table pipeline.scholarship_listing_pages(id bigint generated always as identity primary key, provider_id uuid, url text, url_norm text,
  source text check (source in ('auto', 'suggested', 'manual')), active boolean default true, status text check (status in ('waiting', 'read', 'failed', 'suggested')),
  http_status int, read_at timestamptz, next_read_at timestamptz, items jsonb, item_hash text, error text, added_by uuid, added_at timestamptz,
  page_state text check (page_state in ('single', 'complete', 'partial', 'failed')), pages_read int, total_stated int, next_url text, paging jsonb, completed_at timestamptz,
  unique (provider_id, url_norm));
create table pipeline.scholarship_listing_members(listing_id bigint, provider_id uuid, item_key text, name text, url text, code text, kind text, candidate_id bigint,
  held_scholarship_id uuid, first_seen timestamptz default now(), last_seen timestamptz default now(), present boolean default true, primary key (listing_id, item_key));
create table pipeline.scholarship_page_candidates(id bigint generated always as identity primary key, provider_id uuid, url text, url_norm text, title text,
  source text check (source in ('sitemap', 'map', 'search', 'register')), found_at timestamptz default now(), matched_scholarship_id uuid, match_basis text, matched_at timestamptz,
  read_status text, http_status int, fetched_via text, final_url text, read_at timestamptz, attempts int default 0, leased_until timestamptz, next_read_at timestamptz,
  storage_path text, content_hash text, facts jsonb, admit_status text, admit_reasons text[], admitted_scholarship_id uuid, admitted_at timestamptz, requested_at timestamptz,
  evidence_id uuid, unique (provider_id, url_norm));
create table pipeline.scholarship_ai_models (code text primary key, model_identifier text, status text default 'active');
insert into pipeline.scholarship_ai_models values ('qwen3-30b', 'qwen/qwen3-30b-a3b-instruct-2507', 'active');
create or replace function security.scholarship_ai_active_v1() returns table(model_code text, prompt_version int) language sql stable as $$
  select code, 2 from pipeline.scholarship_ai_models where status = 'active' and nullif(current_setting('fx.no_model', true), '') is null limit 1 $$;
create table pipeline.scholarship_ai_queue (id bigint generated always as identity primary key, model_code text not null references pipeline.scholarship_ai_models(code), prompt_version int not null,
  run_kind text not null check (run_kind = any (array['qualify', 'admit', 'reread', 'test'])), job_id uuid, sample_id int, candidate_id bigint, scholarship_id uuid, provider_id uuid, url text not null,
  state text not null default 'queued' check (state = any (array['queued', 'leased', 'done', 'failed'])), attempts int not null default 0, leased_until timestamptz,
  next_try_at timestamptz not null default now(), created_at timestamptz not null default now(), done_at timestamptz, extraction_id bigint, step int not null default 1, storage_path text,
  root_id bigint, skip_reason text, fresh_read boolean not null default false, read_request_id bigint);
create table pipeline.scholarship_ai_extractions (id bigint generated always as identity primary key, queue_id bigint, model_code text, model_identifier text, prompt_version int, run_kind text,
  job_id uuid, sample_id int, candidate_id bigint, scholarship_id uuid, provider_id uuid, url text, storage_path text, content_hash text, evidence_id uuid, answer jsonb, checks jsonb,
  verdict text, applied jsonb, cost_usd numeric, tokens_in int, tokens_out int, seconds numeric, error text, at timestamptz not null default now());
create table pipeline.scholarship_ai_reviews (id bigint generated always as identity primary key, candidate_id bigint, scholarship_id uuid, provider_id uuid, url text not null, storage_path text,
  extraction_ids bigint[] not null default '{}', reason text not null, status text not null default 'pending', decided_by uuid, decided_at timestamptz, note text, decision jsonb,
  created_at timestamptz not null default now(), recheck jsonb);
create table pipeline.scholarship_owner_proposals (id bigint generated always as identity primary key, review_id bigint unique, candidate_id bigint, holder_provider_id uuid, url text, host text,
  finding text check (finding = 'directory_page'), named text, owner_candidates jsonb, proposed_action text check (proposed_action = 'refuse_from_holder'), evidence jsonb,
  state text check (state in ('proposed', 'decided')), created_at timestamptz default now(), decided_at timestamptz, decision jsonb);
create table scholarship.register_listings(register_code text, listing_id text, country_code character(2), url text, name text, provider_ref text, provider_name text,
  provider_cricos text, provider_id uuid, level_text text, award_text text, closing_text text, nationality_text text, website_url text, content_hash text,
  scholarship_id uuid, match_basis text, candidate_id bigint, handoff_status text, detail_hash text, detail_read_at timestamptz, detail_error text,
  detail_evidence_id uuid, evidence_id uuid, first_seen_at timestamptz default now(), last_seen_at timestamptz default now(), departed_at timestamptz, last_run_id uuid);
create table scholarship.scholarships(id uuid primary key default gen_random_uuid(), provider_id uuid, name text, audience text, award_value_text text, application_open_date date,
  application_close_date date, source_url text, lifecycle_status text default 'active', publication_status text default 'published', award_value_type text, award_percentage numeric,
  award_amount numeric, nationalities text[], updated_at timestamptz default now());
create table scholarship.scopes(id uuid primary key default gen_random_uuid(), scholarship_id uuid, study_level_id uuid, include_exclude text);
create table scholarship.criteria(id uuid primary key default gen_random_uuid(), scholarship_id uuid, criterion_type text, status text);
create table scholarship.award_tiers(id uuid primary key default gen_random_uuid(), scholarship_id uuid);
create table scholarship.application_windows(id uuid primary key default gen_random_uuid(), scholarship_id uuid, opens_at timestamptz, closes_at timestamptz);
create table pipeline.scholarship_publication_holds(scholarship_id uuid, reason text, held_by text, held_at timestamptz default now(), released_at timestamptz, release_note text);
create table pipeline.layer4_review_items(id uuid primary key default gen_random_uuid(), entity_type text, entity_id uuid, status text);
create table pipeline.scholarship_round_states(scholarship_id uuid primary key, state text, basis text, open_date date, close_date date, evidence jsonb, decided_at timestamptz);
create table pipeline.scholarship_pages(scholarship_id uuid primary key, url text, url_source text, final_url text, read_status text, read_at timestamptz, next_read_at timestamptz,
  leased_until timestamptz, attempts int not null default 0, requested_at timestamptz);
create or replace function scholarship.provider_currency(p uuid) returns text language sql as $$ select 'AUD' $$;
create or replace function security.provider_name_list(p uuid) returns jsonb language sql as $$ select '[]'::jsonb $$;
-- the consumer API, read only: a published, active scholarship is returned (as live: api.website_v2_scholarship_item returns null otherwise);
-- fx.consumer_missing names one the fixture makes the consumer API miss
create or replace function api.website_v2_scholarship_item(p_id uuid) returns jsonb language sql stable as $$
  select jsonb_build_object('id', s.id, 'name', s.name) from scholarship.scholarships s
   where s.id = p_id and s.lifecycle_status = 'active' and s.publication_status = 'published' and s.id::text is distinct from nullif(current_setting('fx.consumer_missing', true), '') $$;

create table pipeline.integration_issues(id bigint generated always as identity primary key, issue_ref text, fingerprint text unique, title text, provider_ids uuid[] default '{}',
  status text default 'triaged', severity text, diagnosis jsonb);
create table pipeline.coverage_provider_reconciliation(domain text, provider_id uuid, country text, provider_name text, provider_type text, disposition text, measures jsonb,
  categories jsonb, gaps text[], shortfall int, issue_fingerprint text, first_seen timestamptz default now(), disposition_since timestamptz, previous_disposition text,
  computed_at timestamptz default now(), primary key (domain, provider_id));
create table pipeline.ops_outcome_codes(code text primary key, title text, counts_as_movement boolean);
insert into pipeline.ops_outcome_codes values ('succeeded_with_result', 'x', true), ('succeeded_no_movement', 'x', false), ('not_needed', 'x', false), ('deferred_dependency', 'x', false),
  ('blocked_policy', 'x', false), ('blocked_evidence', 'x', false), ('failed_retryable', 'x', false), ('failed_remediation', 'x', false);
