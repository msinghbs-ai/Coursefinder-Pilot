-- Added to ../aer-qualification-first/stubs.sql (the entry-matrix tables and the decision path as live after 20261112060000): what rule aer-matrix-machine-v1 and the
-- course machine job it is stepped from read or write.
alter table catalogue.providers add column website text, add column lifecycle_status text default 'active';
alter table pipeline.entry_matrix_sources add column content_hash text;
alter table pipeline.layer4_review_items add column created_at timestamptz default now(), add column decided_at timestamptz, add column claimed_at timestamptz, add column assigned_to uuid;
create table pipeline.evidence_artifacts (id uuid primary key default gen_random_uuid(), storage_path text);
create table pipeline.manual_locks (entity text, entity_id uuid, field text, mode text, set_by uuid, set_at timestamptz default now());
create table pipeline.layer4_decisions (id uuid primary key default gen_random_uuid(), review_item_id uuid, action text, actor_id uuid, reason text, before_value jsonb, proposed_value jsonb,
  final_value jsonb, evidence_id uuid, layer2_state jsonb, layer3_state jsonb, change_control_ref text, created_at timestamptz default now());
create table pipeline.admin_control_events (id bigserial primary key, area text, action text, target text, detail jsonb, actor uuid, created_at timestamptz default now());
create table pipeline.search_refresh_signals (id bigserial primary key, entity_type text, entity_id uuid, review_decision_id uuid, reason text, change_control_ref text, status text default 'queued');
-- the course machine job's own reads (its body is loaded from live/)
create table pipeline.aer_machine_admissions (id bigserial primary key, review_item_id uuid, mode text, outcome text, created_at timestamptz default now(), updated_at timestamptz default now());
create table pipeline.aer_machine_validations (id bigserial primary key, passed boolean, validated_at timestamptz default now());
create table pipeline.layer4_item_readiness (item_id uuid primary key, gate jsonb, gate_checked_at timestamptz);
create function security.aer_machine_suspend_check_v1() returns jsonb language sql as $$ select '{}'::jsonb $$;
create function security.aer_machine_admit_v1(p uuid, v text) returns jsonb language sql as $$ select '{"outcome":"would_admit"}'::jsonb $$;
create function security.site_host_v1(p text) returns text language sql immutable as $$ select nullif(lower(regexp_replace(substring(p from '^https?://([^/?#]+)'), '^www\.', '')), '') $$;
create function security.system_actor_id() returns uuid language sql immutable as $$ select '00000000-0000-0000-0000-00000000005e'::uuid $$;
