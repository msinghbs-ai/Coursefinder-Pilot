-- CF-247 AER review queue (migration 20261104490000) on isolated fixtures: the live shapes this change reads beyond ../aer-throughput (its
-- stubs and seed) and the Human-assisted recovery contract (20261104450000 §1-§5, §8-§11, §13b), which run.sh loads. Columns as live
-- (information_schema, read only, 4 Nov 2026 11:19 AEDT). Fixture database only; nothing here is live data.

-- the Inbox hook register (20261104440000 §2) with the aer_review extension row as live
create table if not exists pipeline.layer4_inbox_kind_hooks (kind text not null, mode text not null default 'kind' check (mode in ('kind', 'extend')),
  kind_fn text, counts_fn text, page_fn text, detail_fn text, decide_fn text, enabled boolean not null default true, owner text, note text,
  created_at timestamptz not null default now(), primary key (kind, mode));
insert into pipeline.layer4_inbox_kind_hooks(kind, mode, kind_fn, detail_fn, decide_fn, owner, note) values
 ('aer_review', 'extend', 'security.layer4_aer_recovery_kind_v1()', 'security.layer4_aer_recovery_detail_v1(text)', 'security.layer4_aer_recovery_decide_v1(text,text,text,text)',
  'human-assisted recovery (cf247-human-assisted-recovery)', 'AER recovery choices on E13-held reads') on conflict do nothing;

-- the ownership register (20261104260000)
create table if not exists pipeline.layer4_review_owners (id bigserial primary key, provider_id uuid not null references catalogue.providers(id), field_code text not null,
  owner text not null check (owner in ('claude', 'chatgpt', 'engineering')), scope text not null, basis text not null, since timestamptz not null default now(),
  closed_at timestamptz, note text);

-- reference and evidence (live columns used here)
create schema if not exists ref;
create table if not exists ref.countries(id uuid primary key, iso_alpha2 text);
create table if not exists ref.study_levels(id uuid primary key default gen_random_uuid(), code text, name text);
create table if not exists pipeline.evidence_artifacts(id uuid primary key, source_url text, captured_at timestamptz);
create table if not exists catalogue.provider_entry_matrix(id uuid primary key default gen_random_uuid(), provider_id uuid, run_id uuid, country_code text, level_label text,
  qualification_name text, min_grade text, grade_scale text, audience text, quote text, status text default 'proposed', created_at timestamptz default now());
alter table pipeline.entry_matrix_runs add column if not exists source_id uuid, add column if not exists review_item_id uuid, add column if not exists rows_admitted int,
  add column if not exists rows_dropped int, add column if not exists created_at timestamptz default now();
alter table pipeline.entry_matrix_sources add column if not exists url text;
alter table pipeline.field_enrich_items add column if not exists evidence_id uuid, add column if not exists reason text;
alter table pipeline.manual_locks add column if not exists mode text, add column if not exists set_at timestamptz default now();
alter table catalogue.course_entry_requirements add column if not exists min_grade text, add column if not exists min_value numeric, add column if not exists grade_scale text,
  add column if not exists confidence numeric, add column if not exists status_reason text, add column if not exists description text;
create or replace function security.entry_matrix_gate_v1(p_run uuid, p_ex uuid[]) returns jsonb language sql stable as
  $f$ select g from fx.gate f join pipeline.entry_matrix_runs m on m.review_item_id = f.item_id where m.id = p_run $f$;
-- the stand-ins Human-assisted recovery's helpers call (interfaces as live)
create or replace function security.url_on_provider_sites(p_url text, p_provider_id uuid) returns boolean language sql stable as $f$ select true $f$;
create or replace function security.third_party_host_v1(p_url text) returns boolean language sql stable as $f$ select false $f$;
create or replace function security.layer4_stored_copy_v1(p_url text) returns jsonb language sql stable as $f$ select null::jsonb $f$;
create or replace function security.aer_reread_v1(p_source uuid, p_reason text, p_by uuid) returns jsonb language sql as $f$ select '{}'::jsonb $f$;
create or replace function auth.role() returns text language sql stable as $f$ select 'authenticated'::text $f$;
create table if not exists auth.users(id uuid primary key, email text);
