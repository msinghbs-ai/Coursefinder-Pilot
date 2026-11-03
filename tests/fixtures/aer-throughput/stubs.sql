-- CF-247 AER throughput (migration 20261104470000) on isolated fixtures: the live shapes this change reads, writes or calls beyond
-- ../integration-queue/stubs.sql and the work-continuity contract (20261104170000 §1-§5, 20261104320000 §1-§3), which run.sh loads first.
-- Columns are the live ones (information_schema on production, read only, 4 Nov 2026 08:20 AEDT). Helpers the change only calls are stand-ins;
-- the gate is a stand-in that answers from fx.gate (the gate is not changed by this change). Fixture database only; nothing here is live data.

-- Layer 4 (live columns used here)
create table if not exists pipeline.layer4_item_readiness(item_id uuid primary key, entity_type text, entity_id uuid, field_code text, item_created_at timestamptz,
  item_status text, readiness text, reasons text[], route text, resolution jsonb, blockers jsonb, est_minutes numeric, gate jsonb, gate_checked_at timestamptz,
  classified_at timestamptz, rule text);
create table if not exists pipeline.layer4_readiness_runs(id bigserial primary key, at timestamptz default now(), ms int, result jsonb);
create table if not exists pipeline.layer4_decisions(id uuid primary key default gen_random_uuid(), review_item_id uuid, action text, created_at timestamptz default now());
create table if not exists pipeline.layer4_admission_checks(decision_id uuid primary key, field_code text, result text, reason text, entity_id uuid, decided_at timestamptz, checked_at timestamptz);
alter table pipeline.integration_issues add column if not exists condition_cleared_at timestamptz, add column if not exists status text default 'detected';
create table if not exists pipeline.integration_issue_events(id bigserial primary key, issue_id bigint, kind text, from_status text, to_status text, actor text, note text);
create table if not exists pipeline.manual_locks(entity text, entity_id uuid, field text);

-- AER (live columns used here)
create table if not exists pipeline.coverage_course_pages(course_id uuid primary key, provider_id uuid, url text, evidence_id uuid, status text, read_status text);
create table if not exists pipeline.aer_read_supersessions(id uuid primary key default gen_random_uuid(), old_item_id uuid not null, course_id uuid, source_url text,
  old_evidence_id uuid, enrich_item_id bigint, job_id uuid, requested_by uuid, reason text, state text not null default 'requested', new_item_id uuid, outcome text, diff jsonb,
  requested_at timestamptz not null default now(), closed_at timestamptz);
alter table pipeline.field_enrich_items add column if not exists job_id uuid, add column if not exists field text, add column if not exists value jsonb,
  add column if not exists updated_at timestamptz default now(), add column if not exists attempts int default 0;
create unique index if not exists field_enrich_items_job_course_field_uq on pipeline.field_enrich_items(job_id, course_id, field);
create table if not exists pipeline.admin_jobs(id uuid primary key default gen_random_uuid(), kind text, lane text, state text, title text, args jsonb, progress jsonb,
  requested_by uuid, reason text, scope text, created_at timestamptz default now());
create table if not exists pipeline.enrichment_flags(entity text, entity_key text, field text, reason_code text, state text, released_at timestamptz, released_by uuid,
  release_kind text, release_reason text, updated_at timestamptz);
create table if not exists catalogue.course_entry_requirements(id uuid primary key default gen_random_uuid(), course_id uuid, kind text, audience text, quote text,
  min_entry_score numeric, min_entry_score_basis text, status text default 'proposed', provenance jsonb default '{}', created_at timestamptz default now(), updated_at timestamptz default now());
create table if not exists pipeline.aer_schedule_runs(id bigserial primary key, ran_at timestamptz default now(), course_reads int default 0, corrections int default 0,
  matrix_pages int default 0, layer4_waiting int, in_progress int, back_pressure boolean, used_before int, room int, refusal text, estimate_usd numeric, detail jsonb);
create table if not exists pipeline.aer_schedule_checks(item_id uuid primary key, checked_at timestamptz, outcome text);
create table if not exists pipeline.entry_matrix_sources(id uuid primary key default gen_random_uuid(), provider_id uuid, status text, read_via text, read_at timestamptz);
create table if not exists pipeline.field_gap_queue_control(id int primary key, owner uuid);
create table if not exists security.roles(code text primary key, rank int, status text);
create table if not exists security.user_roles(user_id uuid, role_code text, expires_at timestamptz);
create table if not exists pipeline.layer3_openrouter_observations(id bigserial primary key, kind text, remaining_usd numeric, observed_at timestamptz default now());

-- the gate and the readiness helpers: stand-ins (the gate answers from fx.gate; it is read, never changed, by this change)
create table if not exists fx.gate(item_id uuid primary key, g jsonb not null);
create table if not exists fx.gate_calls(id bigserial primary key, item_id uuid, at timestamptz default clock_timestamp());
create or replace function security.course_entry_gate_v1(p_item uuid, p_exclude uuid[] default '{}'::uuid[]) returns jsonb language plpgsql as $f$
begin
  if not exists (select 1 from pipeline.layer4_review_items r where r.id = p_item and r.field_code = 'course_entry_first_read') then return null; end if;
  insert into fx.gate_calls(item_id) values (p_item);
  return (select g from fx.gate where item_id = p_item);
end $f$;
create or replace function security.layer4_blockers_v1(p_item uuid, p_gate boolean) returns jsonb language plpgsql as $f$
declare g jsonb;
begin
  if p_gate then
    if (select field_code from pipeline.layer4_review_items where id = p_item) = 'course_entry_first_read' then g := security.course_entry_gate_v1(p_item);
    else insert into fx.gate_calls(item_id) values (p_item); g := (select x.g from fx.gate x where x.item_id = p_item); end if;
  end if;
  if g is not null and not coalesce((g->>'complete')::boolean, true) then
    return jsonb_build_object('blockers', jsonb_build_array(jsonb_build_object('code', 'completeness_gate', 'why', g->'reasons'->>0)), 'route', 'repair:completeness_gate', 'gate', g);
  end if;
  return jsonb_build_object('blockers', '[]'::jsonb, 'route', 'review', 'gate', g);
end $f$;
create or replace function security.layer4_resolution_v1(p_item uuid) returns jsonb language sql stable as $f$ select null::jsonb $f$;
create or replace function security.layer4_pace_v1() returns jsonb language sql stable as $f$ select '{}'::jsonb $f$;
create or replace function security.pipeline_list_v1(p_key text, p_default jsonb) returns text[] language sql stable as $f$ select '{}'::text[] $f$;
create or replace function security.layer4_reconcile_v1(p_kind text, p_limit int) returns jsonb language sql as $f$ select '{}'::jsonb $f$;
create or replace function security.layer4_admission_record_v1(p_decision uuid) returns void language sql as $f$ select $f$;

-- AI lane and balance (live interfaces): fx.ai_stop says whether enrich_fields is stopped
create table if not exists fx.ai_stop(lane text primary key, why text);
create or replace function security.ai_use_refusal_v1(p_lane text) returns text language sql stable as $f$ select why from fx.ai_stop where lane = p_lane $f$;
create or replace function security.course_entry_cost_v1() returns numeric language sql stable as $f$ select 0.00609::numeric $f$;
create or replace function security.course_entry_read_check_v1(p_rows jsonb, p_dropped jsonb) returns jsonb language sql stable as
  $f$ select '{"drops_uncovered": [], "not_requirement": [], "audience": []}'::jsonb $f$;
create or replace function security.course_entry_shared_page_v1(p_course uuid) returns jsonb language sql stable as $f$ select '[]'::jsonb $f$;

-- the fixture's own reading of a gate result (independent of the change's security.aer_e13_class_v1)
create or replace function fx.cls(g jsonb) returns text language sql immutable as $f$
  select case when g is null then null when (g->>'complete')::boolean then 'complete' when (g->>'rows_cut')::int > 0 then 'row_limit'
              when jsonb_array_length(g->'shared_page') > 0 then 'shared_page' when jsonb_array_length(g->'drops_uncovered') > 0 then 'drops_uncovered' else 'row_level' end $f$;
