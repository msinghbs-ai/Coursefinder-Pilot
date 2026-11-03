-- CF-247 IQ-00067 (coverage admission lock isolation) on isolated fixtures: the live shapes the admission path reads or writes, beyond the
-- integration queue stubs (../integration-queue/stubs.sql) and workstream A's contract (stub-ops-contract.sql). Columns as live (read-only,
-- 3 Nov 2026 15:55-16:05 AEDT). The plan, the writers and the search refresh are stubs: the plan returns the rows in fx.plan, the record
-- writer refuses a course listed in fx.refuse. Scratch PostgreSQL only (never a Supabase project). Nothing here is live data.
create schema if not exists ref;

-- tasks (live columns; state check as live), before workstream A's contract adds outcome and outcome_detail
create table pipeline.admin_jobs(id uuid primary key default gen_random_uuid(), kind text not null, lane text, state text not null default 'queued'
  check (state = any (array['queued', 'running', 'paused', 'done', 'failed', 'cancelled'])), title text, args jsonb not null default '{}', cursor jsonb,
  progress jsonb, result jsonb, error text, cancel_requested boolean not null default false, pause_requested boolean not null default false, requested_by uuid,
  reason text, created_at timestamptz not null default now(), started_at timestamptz, updated_at timestamptz not null default now(), finished_at timestamptz, scope text);

create table pipeline.manual_locks(entity text not null, entity_id uuid not null, field text not null, mode text, set_by uuid, set_at timestamptz not null default now(),
  primary key (entity, entity_id, field));
create table pipeline.layer4_decisions(id uuid primary key default gen_random_uuid(), review_item_id uuid, action text, actor_id uuid, reason text, before_value jsonb,
  proposed_value jsonb, final_value jsonb, evidence_id uuid, layer2_state jsonb, layer3_state jsonb, scalar_resolution_id uuid, change_control_ref text, created_at timestamptz not null default now());
create table pipeline.job_input_marks(job_key text primary key, last_input_at timestamptz, last_full_at timestamptz, last_run_at timestamptz, last_result jsonb,
  runs_done int not null default 0, runs_skipped int not null default 0, started_at timestamptz not null default now());
create table pipeline.sources(id uuid primary key default gen_random_uuid(), source_type text, country_id uuid, status text default 'active');
create table pipeline.course_fact_source_qualifications(source_id uuid, country_id uuid, source_key text, source_class text, authority_name text, provider_cricos text,
  admitted_domains text[], mapping_strategy text, evidence_strategy text, qualification_status text, notes text, metadata jsonb, created_at timestamptz not null default now());
create table search.enrichment_source_gates(projection_code text, domain_code text, source_id uuid, gate_status text, approval_ref text, approved_at timestamptz,
  created_at timestamptz, updated_at timestamptz);
create table pipeline.consumer_api_baselines(id bigserial primary key, label text, captured_at timestamptz not null default now(), snapshot jsonb);
create table catalogue.course_links(id uuid primary key default gen_random_uuid(), course_id uuid not null, link_type text not null, url text not null, audience text, label text,
  is_primary boolean, status text, source_id uuid, evidence_id uuid, confidence numeric, last_verified_at timestamptz, updated_at timestamptz, unique (course_id, link_type, url));

-- fixture controls
create table fx.plan(course_id uuid, provider_id uuid, provider_cricos text, course_cricos text, evidence_id uuid, content_hash text, page_url text, attribute text,
  action text, proposed jsonb, current jsonb, ord serial);
create table fx.applied(course_id uuid, payload jsonb, at timestamptz not null default now());
create table fx.refuse(course_id uuid primary key);

create function security.coverage_admission_plan_v1(p_extractor text default 'coverage-sweep-v0.5.3')
returns table(course_id uuid, provider_id uuid, provider_cricos text, course_cricos text, evidence_id uuid, content_hash text, page_url text, attribute text, action text,
              proposed jsonb, current jsonb)
language sql stable as $f$ select course_id, provider_id, provider_cricos, course_cricos, evidence_id, content_hash, page_url, attribute, action, proposed, current
                            from fx.plan order by ord $f$;
create function security.admit_input_mark_v1() returns timestamptz language sql stable as $f$ select now() $f$;
create function security.coverage_sweep_source(p uuid) returns uuid language sql stable as $f$ select 'aaaaaaaa-0000-4000-8000-000000000001'::uuid $f$;
create function security.uni_adapter_excluded(p_course uuid, p_attr text) returns boolean language sql stable as $f$ select false $f$;
create function security.consumer_api_snapshot_v1() returns jsonb language sql stable as $f$ select '{}'::jsonb $f$;
create function search.refresh_course_enrichment_scoped_v1(p uuid[], p_b boolean) returns void language sql as $f$ select $f$;
create function security.reference_url_has_use(p_url text, p_use text) returns boolean language sql stable as $f$ select false $f$;
create function security.course_link_hold_basis_v1(p_course uuid, p_link_type text, p_url text, p_source uuid) returns jsonb language sql stable as $f$ select null::jsonb $f$;
create function security.coverage_apply_course_v1(p_course uuid, p_src uuid, p_ev uuid, p_url text, p_hash text, p_payload jsonb) returns void language plpgsql as $f$
begin
  if exists (select 1 from fx.refuse r where r.course_id = p_course) then raise exception 'fixture: the record writer refused this course'; end if;
  insert into fx.applied(course_id, payload) values (p_course, p_payload);
end $f$;
create function public.svc_coursefacts_apply_record(p_src uuid, p_ev uuid, p_pc text, p_cc text, p_key text, p_url text, p_hash text, p_payload jsonb, p_b boolean)
returns jsonb language plpgsql as $f$
begin
  perform security.coverage_apply_course_v1(substring(p_key from 10)::uuid, p_src, p_ev, p_url, p_hash, p_payload);
  return '{}'::jsonb;
end $f$;

insert into pipeline.sources(id, source_type) values ('aaaaaaaa-0000-4000-8000-000000000001', 'coverage_sweep'), ('aaaaaaaa-0000-4000-8000-000000000002', 'layer4_human_review');
