-- CF-247 P0 Layer 4 readiness and admission throughput (migration 20261104120000) on isolated fixtures: the live shapes this change reads or
-- writes beyond ../integration-queue/stubs.sql, the integration queue (20261102120000), ../ops-controller/stubs-extra.sql and workstream A's
-- migration (20261104010000), which run.sh loads first. Columns read from information_schema on production (read-only, 3 Nov 2026 18:16-18:24
-- AEDT). Run on a scratch PostgreSQL only (never on a Supabase project): see run.sh. Nothing here is live data.

-- the Layer 4 status check (live) and the existing BEFORE INSERT reroute trigger (a stand-in that marks the row, so the order is visible)
alter table pipeline.layer4_review_items add constraint layer4_review_items_status_check
  check (status = any (array['pending', 'approved', 'edited_approved', 'rejected', 'more_evidence', 'returned_layer2', 'returned_layer3', 'superseded']));
create index if not exists layer4_review_items_entity_field_iq_idx on pipeline.layer4_review_items (entity_id, field_code, status);
create table fx.trigger_order(id bigserial primary key, item_id uuid, trg text, status_seen text);
create function security.layer4_reroute_trg_v1() returns trigger language plpgsql as $f$
begin insert into fx.trigger_order(item_id, trg, status_seen) values (new.id, 'reroute', new.status); return new; end $f$;
create trigger layer4_review_items_reroute before insert on pipeline.layer4_review_items for each row execute function security.layer4_reroute_trg_v1();

-- the live list-setting reader (repository migration 20261103140000; live md5 c33c2152bbadc8d01625ced9bf2c9bda, read 3 Nov 2026 18:27)
create or replace function security.pipeline_list_v1(p_key text, p_default jsonb default '[]'::jsonb) returns text[]
language sql stable security definer set search_path to '' as $function$
  select array(select jsonb_array_elements_text(coalesce(
           (select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key and jsonb_typeof(s.value) = 'array'),
           case when jsonb_typeof(p_default) = 'array' then p_default else '[]'::jsonb end)))
$function$;

-- stored pages (live columns)
create table pipeline.evidence_artifacts(id uuid primary key default gen_random_uuid(), entity_id uuid, source_id uuid, job_id uuid, evidence_type text, source_url text,
  storage_path text, content_hash text, mime_type text, captured_at timestamptz default now(), valid_from timestamptz, valid_to timestamptz, supersedes_evidence_id uuid,
  metadata jsonb, created_at timestamptz not null default now(), source_profile_version_id uuid, retention_class text, retain_until timestamptz, review_state text,
  capture_version int, evidence_group_key text);

-- catalogue values the checks read (live columns)
create table catalogue.course_links(id uuid primary key default gen_random_uuid(), course_id uuid not null, link_type text not null, url text not null, audience text, locale text,
  label text, is_primary boolean not null default false, status text not null default 'active', valid_from date, valid_to date, source_id uuid, evidence_id uuid, confidence numeric,
  last_verified_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (course_id, link_type, url));
create table catalogue.course_fees(id uuid primary key default gen_random_uuid(), course_id uuid not null, fee_year int, audience text, fee_type text, amount numeric, currency_code character(3),
  basis text, load_basis text, is_csp boolean, notes text, valid_from date, valid_to date, source_id uuid, evidence_id uuid, confidence numeric, created_at timestamptz not null default now(),
  campus_id uuid, source_fee_key text, status text, last_verified_at timestamptz, updated_at timestamptz not null default now(), source_snapshot_at timestamptz);
create table catalogue.course_entry_requirements(id uuid primary key default gen_random_uuid(), course_id uuid not null, kind text, audience text, country_id uuid, description text,
  min_grade text, min_value numeric, grade_scale text, min_entry_score numeric, min_entry_score_basis text, benchmark_band text, quote text, source_url text, evidence_id uuid,
  confidence numeric, as_at date, status text, status_reason text, provenance jsonb not null default '{}', created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table catalogue.provider_entry_matrix(id uuid primary key default gen_random_uuid(), provider_id uuid not null, run_id uuid, status text, status_reason text, quote text, provenance jsonb not null default '{}',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table pipeline.no_page_trust(provider_id uuid not null, kind text not null, state text, sample int, confirmed int, parent_url text, review_item_id uuid, decided_at timestamptz,
  created_at timestamptz not null default now(), primary key (provider_id, kind));
alter table pipeline.provider_description_reads add column if not exists review_item_id uuid;

-- the reference list the course-link apply refuses (live: security.reference_url_has_use; stand-in with the same answer for the hosts used here)
create table fx.reference_hosts(host text primary key, use text not null);
insert into fx.reference_hosts values ('facebook.com', 'not_course_page'), ('www.facebook.com', 'not_course_page');
create function security.reference_url_has_use(p_url text, p_use text) returns boolean language sql stable as
  $f$ select exists (select 1 from fx.reference_hosts h where h.use = p_use and h.host = lower(substring(p_url from '^https?://([^/]+)'))) $f$;

-- the E13 / D-R3 gates (live: security.course_entry_gate_v1 4fc06c08…, security.entry_matrix_gate_v1 78ca8d1f…; stand-ins answering from a table)
create table fx.gate(item uuid primary key, complete boolean, reason text);
create table fx.gate_calls(id bigserial primary key, item uuid, at timestamptz default clock_timestamp());
create function security.course_entry_gate_v1(p_item uuid, p_exclude uuid[] default '{}') returns jsonb language plpgsql as $f$
begin
  insert into fx.gate_calls(item) values (p_item);
  return (select jsonb_build_object('rule', 'E13', 'complete', coalesce(g.complete, true), 'reasons', case when g.complete is false then jsonb_build_array(g.reason) else '[]'::jsonb end)
            from (select 1) one left join fx.gate g on g.item = p_item);
end $f$;
create function security.entry_matrix_gate_v1(p_run uuid, p_exclude uuid[] default '{}') returns jsonb language plpgsql as $f$
begin
  insert into fx.gate_calls(item) values (p_run);
  return (select jsonb_build_object('rule', 'D-R3', 'complete', coalesce(g.complete, true), 'reasons', case when g.complete is false then jsonb_build_array(g.reason) else '[]'::jsonb end)
            from (select 1) one left join fx.gate g on g.item = p_run);
end $f$;
