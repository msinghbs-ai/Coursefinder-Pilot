-- CF-247 human-assisted recovery (migration 20261104450000): the other live shapes the change reads or writes, on top of the Layer 4 build of
-- ../l4-course-link (providers, courses, evidence, Layer 4 items, the Inbox functions) and workstream A's contract (../sch-coverage-recovery/
-- stub-ops-contract.sql). Columns are the ones the change uses, as live (read 4 Nov 2026 06:35-06:50 AEDT). Helpers the change only calls are
-- stand-ins. Fixture database only; nothing here is live data.

-- the controller's outcome codes and the integration queue (as live: fingerprint unique, status, events; upsert and close by contract)
create table if not exists pipeline.ops_outcome_codes(code text primary key, title text, counts_as_movement boolean);
insert into pipeline.ops_outcome_codes values ('succeeded_with_result', 'x', true), ('succeeded_no_movement', 'x', false), ('not_needed', 'x', false), ('deferred_dependency', 'x', false),
  ('blocked_policy', 'x', false), ('blocked_evidence', 'x', false), ('failed_retryable', 'x', false), ('failed_remediation', 'x', false) on conflict do nothing;
alter table pipeline.integration_issues add column if not exists status text default 'detected', add column if not exists title text, add column if not exists evidence jsonb,
  add column if not exists provider_ids uuid[] default '{}', add column if not exists closed_at timestamptz, add column if not exists verification_evidence jsonb,
  add column if not exists reopened int default 0;
create unique index if not exists integration_issues_fp_uq on pipeline.integration_issues(fingerprint);
create or replace function security.integration_issue_upsert_v1(p jsonb, p_actor text default 'integration-validate') returns jsonb language plpgsql as $f$
-- stand-in with the live contract: one row per fingerprint; a recurrence after Closed reopens the same row
declare r pipeline.integration_issues;
begin
  select * into r from pipeline.integration_issues where fingerprint = p->>'fingerprint';
  if not found then
    insert into pipeline.integration_issues(fingerprint, title, evidence, status) values (p->>'fingerprint', p->>'title', p->'evidence', 'detected') returning * into r;
    return jsonb_build_object('id', r.id, 'action', 'created');
  end if;
  update pipeline.integration_issues set title = p->>'title', evidence = p->'evidence', status = case when status = 'closed' then 'reopened' else status end,
         reopened = reopened + case when status = 'closed' then 1 else 0 end, closed_at = case when status = 'closed' then null else closed_at end where id = r.id;
  return jsonb_build_object('id', r.id, 'action', case when r.status = 'closed' then 'reopened' else 'observed' end);
end $f$;
create or replace function security.integration_issue_close_v1(p_issue bigint, p_actor text, p_verification jsonb) returns jsonb language plpgsql as $f$
begin
  if coalesce(p_verification->>'outcome', '') <> 'passed' or length(coalesce(p_verification->>'evidence', '')) < 20 then raise exception 'closing needs production verification evidence'; end if;
  update pipeline.integration_issues set status = 'closed', closed_at = now(), verification_evidence = p_verification where id = p_issue;
  return jsonb_build_object('id', p_issue, 'status', 'closed');
end $f$;
create table if not exists pipeline.ops_ai_diagnosis_requests(id bigserial primary key, issue_id bigint not null references pipeline.integration_issues(id), requested_at timestamptz not null default now(),
  state text not null default 'queued' check (state in ('queued', 'leased', 'answered', 'refused')), leased_until timestamptz, context jsonb not null, answer jsonb, model text, cost_usd numeric,
  answered_at timestamptz, note text);

-- provider sites and directory hosts (live security.url_on_provider_sites / security.third_party_host_v1; stand-ins answering from the provider's website and fx tables)
create table if not exists fx.directory_hosts(host text primary key);
create or replace function security.url_on_provider_sites(p_url text, p_provider_id uuid) returns boolean language sql stable as $f$
  select exists (select 1 from catalogue.providers p where p.id = p_provider_id and p.website is not null
                  and lower(substring(p_url from '^https?://(?:www\.)?([^/:?#]+)')) like '%' || lower(substring(p.website from '^https?://(?:www\.)?([^/:?#]+)')))
      or exists (select 1 from pipeline.provider_extra_domains d where d.provider_id = p_provider_id and lower(substring(p_url from '^https?://(?:www\.)?([^/:?#]+)')) like '%' || lower(d.domain)) $f$;
create or replace function security.third_party_host_v1(p_url text) returns boolean language sql stable as $f$
  select exists (select 1 from fx.directory_hosts h where lower(substring(p_url from '^https?://(?:www\.)?([^/:?#]+)')) = h.host) $f$;
create or replace function security.scholarship_url_norm(p_url text) returns text language sql immutable as $f$
  select lower(regexp_replace(regexp_replace(coalesce(p_url, ''), '^https?://(www\.)?', ''), '[/?#]+$', '')) $f$;
create table if not exists fx.policy_excluded(provider_id uuid primary key);
create or replace function security.scholarship_admission_provider_ok_v1(p_provider uuid) returns boolean language sql stable as $f$
  select not exists (select 1 from fx.policy_excluded x where x.provider_id = p_provider) $f$;

-- AER (as live: entry_matrix_sources with its checks, runs, the inventory of 20261104090000, the coverage ledger, schedule runs, admitted rows)
create table if not exists pipeline.entry_matrix_sources(id uuid primary key default gen_random_uuid(), provider_id uuid not null references catalogue.providers(id), url text not null check (url ~ '^https?://'),
  title text, rank int default 10, found_via text check (found_via in ('search', 'manual')),
  status text default 'found' check (status in ('found', 'reading', 'read', 'failed', 'robots_disallowed', 'pdf_step_b', 'inactive')),
  read_via text check (read_via in ('stored', 'direct', 'firecrawl')), http_status int, evidence_id uuid, content_hash text, attempts int default 0, read_at timestamptz, error text,
  created_at timestamptz default now(), updated_at timestamptz default now(), unique (provider_id, url));
alter table pipeline.entry_matrix_runs add column if not exists id uuid default gen_random_uuid(), add column if not exists provider_id uuid, add column if not exists source_id uuid,
  add column if not exists state text, add column if not exists error text, add column if not exists review_item_id uuid, add column if not exists created_at timestamptz default now();
create table if not exists pipeline.aer_source_inventory (id bigserial primary key, provider_id uuid not null references catalogue.providers(id), url text,
  role text not null, outcome text not null check (outcome in ('verified_attachable', 'verified_general_only', 'verified_rendered_only', 'unverified_link', 'blocked_site')),
  shape text not null, audience text, study_levels text[] not null default '{}', qualifications text[] not null default '{}', boundary text, evidence jsonb not null default '{}'::jsonb,
  attach boolean not null default false, verified_at timestamptz not null, recorded_at timestamptz not null default now());
create table if not exists pipeline.aer_provider_coverage(provider_id uuid primary key, eligible boolean, disposition text, discovery_state text, courses_eligible int default 0,
  sources int default 0, sources_read int default 0, sources_failed int default 0, runs_held int default 0, runs_failed int default 0, root_causes text[], held_scopes jsonb,
  evidence jsonb default '{}', last_run_id bigint, disposition_since timestamptz default now());
create table if not exists pipeline.aer_schedule_runs(id bigserial primary key, ran_at timestamptz default now(), detail jsonb);
create table if not exists catalogue.provider_entry_matrix(id uuid primary key default gen_random_uuid(), provider_id uuid, status text default 'proposed',
  created_at timestamptz default now(), updated_at timestamptz default now());
create table if not exists catalogue.course_entry_requirements(id uuid primary key default gen_random_uuid(), course_id uuid, status text default 'proposed',
  created_at timestamptz default now(), updated_at timestamptz default now());
create or replace function public.website_v2_provider(p_provider_id text) returns jsonb language sql stable as $f$
  select jsonb_build_object('item', jsonb_build_object('entry_matrix', coalesce((select jsonb_agg(m.id) from catalogue.provider_entry_matrix m join catalogue.providers p on p.id = m.provider_id
                                                                               where p.stable_key = p_provider_id and m.status = 'active'), '[]'::jsonb))) $f$;

-- scholarships (as live: listing pages and candidates with their checks; discovery rows); the coverage tables come from 20261104390000 §2
create table if not exists pipeline.scholarship_listing_pages(id bigserial primary key, provider_id uuid references catalogue.providers(id), url text, url_norm text,
  source text check (source in ('auto', 'suggested', 'manual')), active boolean default true, status text default 'waiting' check (status in ('waiting', 'read', 'failed', 'suggested')),
  read_at timestamptz, next_read_at timestamptz default now(), error text, added_by uuid, added_at timestamptz default now(), unique (provider_id, url_norm));
create table if not exists pipeline.scholarship_page_candidates(id bigserial primary key, provider_id uuid, url text, requested_at timestamptz, admitted_at timestamptz);
create table if not exists pipeline.scholarship_discovery_providers(provider_id uuid primary key, status text, attempts int default 0, next_discover_at timestamptz);

-- live catalogue.providers also carries short_name (read by the generators for the card subject)
alter table catalogue.providers add column if not exists short_name text;

-- AER held reads (E13 / D-R3): the gates, the corrected read and the matrix re-read are live functions this change only calls; stand-ins
-- answering from fx tables with the live contracts (course_entry_correction_v1 refuses a second request; a request leaves a supersession row)
alter table pipeline.field_enrich_items add column if not exists id bigserial, add column if not exists course_id uuid, add column if not exists field text,
  add column if not exists state text, add column if not exists value jsonb, add column if not exists job_id uuid, add column if not exists provider_id uuid;
alter table catalogue.course_entry_requirements add column if not exists provenance jsonb default '{}', add column if not exists quote text;
alter table catalogue.provider_entry_matrix add column if not exists run_id uuid, add column if not exists quote text;
create table if not exists pipeline.aer_read_supersessions(id uuid primary key default gen_random_uuid(), old_item_id uuid not null, course_id uuid not null, source_url text not null,
  old_evidence_id uuid, enrich_item_id bigint not null unique, job_id uuid, requested_by uuid, reason text not null,
  state text not null default 'requested' check (state in ('requested', 'superseded', 'refused')), new_item_id uuid, outcome text, diff jsonb, requested_at timestamptz not null default now());
create table if not exists fx.gates(item uuid primary key, result jsonb);
create or replace function security.course_entry_gate_v1(p_item uuid, p_exclude uuid[] default '{}') returns jsonb language sql stable as
  $f$ select coalesce((select g.result from fx.gates g where g.item = p_item), '{"complete": true, "reasons": []}'::jsonb) $f$;
create or replace function security.entry_matrix_gate_v1(p_run uuid, p_exclude uuid[] default '{}') returns jsonb language sql stable as
  $f$ select coalesce((select g.result from fx.gates g join pipeline.entry_matrix_runs r on r.review_item_id = g.item where r.id = p_run), '{"complete": true}'::jsonb) $f$;
create or replace function security.course_entry_correction_v1(p_item uuid, p_actor uuid, p_reason text) returns jsonb language plpgsql as $f$
declare o pipeline.layer4_review_items; v_e bigint;
begin
  select * into o from pipeline.layer4_review_items where id = p_item;
  if exists (select 1 from pipeline.aer_read_supersessions s where s.old_item_id = p_item and s.state = 'requested') then
    raise exception 'No corrected read (D-R2): a corrected read of this item is already asked for. Nothing was changed'; end if;
  insert into pipeline.field_enrich_items(course_id, field, state) values (o.entity_id, 'entry_requirements', 'queued') returning id into v_e;
  insert into pipeline.aer_read_supersessions(old_item_id, course_id, source_url, enrich_item_id, requested_by, reason)
  values (p_item, o.entity_id, coalesce((select g.url from pipeline.coverage_course_pages g where g.course_id = o.entity_id), 'https://x'), v_e, p_actor, p_reason);
  return jsonb_build_object('enrich_item_id', v_e, 'review_item_id', p_item);
end $f$;
create or replace function security.aer_reread_v1(p_source_id uuid, p_reason text, p_actor uuid default null) returns jsonb language sql as
  $f$ update pipeline.entry_matrix_runs set state = 'queued' where source_id = p_source_id returning jsonb_build_object('ok', true, 'runs', 1) $f$;
