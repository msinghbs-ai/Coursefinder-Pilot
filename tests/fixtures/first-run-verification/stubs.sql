-- Live shapes for the first-run verification fixtures (CF-247, 4 Nov 2026). Columns as read from production on 4 Nov 2026 08:20-08:23 AEDT
-- (information_schema, read only); only the tables and columns the change reads. Loaded after the integration queue, workstream A's migration and
-- the reopen rule, so tables those stubs already create gain the live columns here. Never a Supabase project.
set check_function_bodies = off;
create schema if not exists scholarship; create schema if not exists api;

-- the controller-era columns of the queue are created by 20261104010000; the remediation columns are this change's own

-- scholarship chain
create table if not exists pipeline.scholarship_coverage_state_codes (code text primary key, title text not null, resolved boolean not null, owner text not null,
  existing_status text not null, escalate_when text not null, work_event text not null, sort int not null);
insert into pipeline.scholarship_coverage_state_codes values
 ('source_not_discovered', 'Source not discovered', false, 'o', 's', 'after_hours', 'dependency', 10), ('source_found_unread', 'Source found but unread', false, 'o', 's', 'after_hours', 'dependency', 20),
 ('traversal_incomplete', 'Listing traversal incomplete', false, 'o', 's', 'recovery_failed', 'dependency', 30), ('rejected_incorrectly', 'Candidate rejected incorrectly', false, 'o', 's', 'recovery_failed', 'dependency', 40),
 ('international_unresolved', 'International eligibility unresolved', false, 'o', 's', 'always', 'ambiguity', 50), ('ownership_conflict', 'Provider ownership conflict', false, 'o', 's', 'always', 'identity', 60),
 ('awaiting_layer4', 'Awaiting Layer 4', false, 'o', 's', 'never', 'review', 70), ('admitted_not_published', 'Admitted but not published', false, 'o', 's', 'after_hours', 'dependency', 80),
 ('rejected_correctly', 'Candidate rejected correctly', true, 'o', 's', 'never', 'succeeded', 90), ('domestic_only', 'Domestic-only scholarship', true, 'o', 's', 'never', 'succeeded', 100),
 ('expired', 'Expired scholarship', true, 'o', 's', 'never', 'succeeded', 110), ('published_verified', 'Published and consumer-verified', true, 'o', 's', 'never', 'succeeded', 120),
 ('evidence_backed_none', 'Evidence-backed no eligible scholarships', true, 'o', 's', 'never', 'succeeded', 130);
create table if not exists pipeline.scholarship_coverage_items (provider_id uuid not null, item_key text not null, state text not null references pipeline.scholarship_coverage_state_codes(code),
  reason text, evidence jsonb not null default '{}'::jsonb, recovery text, owner text, next_recovery_at timestamptz, escalation jsonb, present boolean not null default true,
  first_seen timestamptz not null default now(), state_since timestamptz not null default now(), classified_at timestamptz not null default now(), primary key (provider_id, item_key));
create table if not exists pipeline.scholarship_coverage_providers (provider_id uuid primary key, provider_state text not null, states jsonb not null default '{}'::jsonb,
  unresolved int not null default 0, published_verified int not null default 0, reported jsonb not null default '{}'::jsonb, classified_at timestamptz not null default now());
create table if not exists pipeline.scholarship_coverage_recoveries (id bigint generated always as identity primary key, provider_id uuid not null, item_key text not null,
  action text not null, state_before text not null, detail jsonb not null default '{}'::jsonb, at timestamptz not null default now(), outcome text, outcome_at timestamptz,
  unique (item_key, action));
create table if not exists pipeline.scholarship_listing_pages (id bigserial primary key, provider_id uuid, url text, url_norm text, source text, active boolean, status text,
  http_status int, read_at timestamptz, next_read_at timestamptz, items jsonb, item_hash text, error text, added_by uuid, added_at timestamptz, page_state text, pages_read int,
  total_stated int, next_url text, paging jsonb, completed_at timestamptz);
create table if not exists pipeline.scholarship_listing_members (listing_id bigint, provider_id uuid, item_key text, name text, url text, code text, kind text, candidate_id bigint,
  held_scholarship_id uuid, first_seen timestamptz, last_seen timestamptz, present boolean);
create table if not exists pipeline.scholarship_page_candidates (id bigserial primary key, provider_id uuid, url text, url_norm text, title text, source text, found_at timestamptz,
  matched_scholarship_id uuid, match_basis text, matched_at timestamptz, read_status text, http_status int, fetched_via text, final_url text, read_at timestamptz, attempts int,
  leased_until timestamptz, next_read_at timestamptz, storage_path text, content_hash text, facts jsonb, admit_status text, admit_reasons text[], admitted_scholarship_id uuid,
  admitted_at timestamptz, requested_at timestamptz, evidence_id uuid);
create table if not exists pipeline.scholarship_admission_log (id bigserial primary key, candidate_id bigint, scholarship_id uuid, provider_id uuid, action text, detail jsonb,
  at timestamptz not null default now());
create table if not exists pipeline.scholarship_ai_reviews (id bigserial primary key, candidate_id bigint, scholarship_id uuid, provider_id uuid, url text, storage_path text,
  extraction_ids bigint[], reason text, status text, decided_by uuid, decided_at timestamptz, note text, decision jsonb, created_at timestamptz not null default now(), recheck jsonb);
alter table scholarship.scholarships add column if not exists created_at timestamptz not null default now();
alter table scholarship.scholarships add column if not exists updated_at timestamptz not null default now();

-- AER chain
create table if not exists pipeline.aer_gap_findings (id bigserial primary key, fingerprint text, root_cause text, provider_id uuid, source_id uuid, scope_kind text, scope_key text,
  scope_label text, study_level text, severity text, state text, evidence jsonb, owner_role text, next_action text, first_seen timestamptz, last_seen timestamptz, resolved_at timestamptz,
  closure_evidence jsonb, reopen_count int, last_run_id bigint);
create table if not exists pipeline.aer_source_inventory (id bigserial primary key, provider_id uuid, url text, role text, outcome text, shape text, audience text, study_levels text[],
  qualifications text[], boundary text, evidence jsonb, attach boolean, verified_at timestamptz, recorded_at timestamptz not null default now(), url_key text);
create table if not exists pipeline.entry_matrix_sources (id uuid primary key default gen_random_uuid(), provider_id uuid, url text, title text, rank int, found_via text, status text,
  read_via text, http_status int, evidence_id uuid, content_hash text, attempts int, read_at timestamptz, error text, created_at timestamptz not null default now(), updated_at timestamptz);
alter table pipeline.entry_matrix_runs add column if not exists created_at timestamptz not null default now();
alter table pipeline.entry_matrix_runs add column if not exists done_at timestamptz;
alter table pipeline.entry_matrix_runs add column if not exists error text;
alter table pipeline.entry_matrix_runs add column if not exists rows_admitted int;
alter table pipeline.entry_matrix_runs add column if not exists rows_dropped int;
create table if not exists pipeline.aer_schedule_runs (id bigserial primary key, ran_at timestamptz not null default now(), course_reads int, corrections int, matrix_pages int,
  layer4_waiting int, in_progress int, back_pressure boolean, used_before int, room int, refusal text, estimate_usd numeric, detail jsonb);
create table if not exists catalogue.course_entry_requirements (id uuid primary key default gen_random_uuid(), course_id uuid, kind text, audience text, status text, status_reason text,
  provenance jsonb, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table if not exists pipeline.work_items (id bigserial primary key, lane text not null, entity text not null, work_kind text not null, provider_id uuid, field text, owner text,
  stage text not null, attempts int not null default 0, total_attempts int not null default 0, failure_class text, failure_fingerprint text, repeat_count int not null default 0,
  evidence jsonb not null default '[]'::jsonb, first_blocked_at timestamptz, last_attempt_at timestamptz, next_eligible_at timestamptz, recover_by timestamptz, lease_until timestamptz,
  escalation jsonb, dependency_refs jsonb, lock_refs jsonb, review_ref text, review_category text, evidence_version text, outcome text, unresolved_blocker jsonb,
  recovered_at timestamptz, last_recovery_minutes numeric, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
alter table pipeline.layer4_review_items add column if not exists decided_at timestamptz;
