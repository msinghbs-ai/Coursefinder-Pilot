-- Minimal stub of the live objects the IQ-00111 containment paste touches (shapes as live 3 Nov 2026).
create schema if not exists catalogue; create schema if not exists pipeline; create schema if not exists scholarship; create schema if not exists search; create schema if not exists security;
create table catalogue.course_fees(id uuid primary key default gen_random_uuid(), course_id uuid, fee_year int, audience text, fee_type text, amount numeric, basis text, notes text,
  valid_to date, status text check (status in ('active','inactive','superseded','unverified')), updated_at timestamptz,
  currency_code text, source_id uuid, evidence_id uuid, confidence numeric, source_fee_key text, last_verified_at timestamptz, created_at timestamptz default now());
create table pipeline.manual_locks(entity text, entity_id uuid, field text, mode text, set_by uuid, set_at timestamptz default now());
create table pipeline.admin_control_events(id bigserial, area text, action text, target text, detail jsonb default '{}', actor uuid, created_at timestamptz default now());
create table scholarship.course_financial_calculations(mapping_id uuid primary key, course_id uuid, course_fee_id uuid, scholarship_saving_amount numeric);
create table search.refresh_requests(id bigserial, requested_at timestamptz default now(), requested_by text);
-- stand-in for the live recompute: picks the active provider fee, else marks the CRICOS estimate (no withdrawn fee id)
create function scholarship.refresh_course_financial_calculations(p_course_id uuid, p_s uuid) returns jsonb language sql as $$
  update scholarship.course_financial_calculations fc set course_fee_id = (select f.id from catalogue.course_fees f where f.course_id = fc.course_id
     and f.fee_type = 'provider_current_tuition' and f.status not in ('inactive','retired','superseded') limit 1) where fc.course_id = p_course_id
  returning jsonb_build_object('refreshed', 1) $$;
create table pipeline.platform_toolset_settings(toolset_key text, key text, value jsonb, updated_at timestamptz, updated_by text, reason text);
insert into pipeline.platform_toolset_settings values ('pipeline','fees.course_pages','1',now(),null,null);
-- for the correction paste (live columns used)
create table pipeline.sources(id uuid primary key default gen_random_uuid(), source_type text);
insert into pipeline.sources(source_type) values ('manual_entry');
create table pipeline.evidence_artifacts(id uuid primary key, source_url text, storage_path text);
insert into pipeline.evidence_artifacts values ('a58f1c88-e3de-4561-b4f9-0c415b960da0', 'https://www.murdoch.edu.au/course/postgraduate/g1104', 'layer2/AU/x.html.gz');
create table pipeline.enrichment_flags(id bigint primary key, entity_key text, reason_code text, state text, released_at timestamptz, cleared_at timestamptz, released_by text,
  release_kind text, release_reason text, updated_at timestamptz);
insert into pipeline.enrichment_flags(id, entity_key, reason_code, state) values (6619496, 'd9dc5bb8-025b-46ca-ac24-7ca13157599f', 'fee_crosscheck', 'raised');
-- stand-in for the live release (state, actor and reason; the live one also logs an event and requeues the course)
create function security.flag_release_v1(p_id bigint, p_actor text, p_kind text, p_reason text, p_ev jsonb, p_keep boolean) returns jsonb language sql as $$
  update pipeline.enrichment_flags set state = 'released', released_at = now(), cleared_at = now(), released_by = p_actor, release_kind = p_kind, release_reason = p_reason
   where id = p_id and state <> 'released' returning jsonb_build_object('id', id, 'state', 'released') $$;
