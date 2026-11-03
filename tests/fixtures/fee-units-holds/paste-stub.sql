-- Minimal stub of the live objects the IQ-00111 containment paste touches (shapes as live 3 Nov 2026).
create schema if not exists catalogue; create schema if not exists pipeline; create schema if not exists scholarship; create schema if not exists search;
create table catalogue.course_fees(id uuid primary key, course_id uuid, fee_year int, audience text, fee_type text, amount numeric, basis text, notes text,
  valid_to date, status text check (status in ('active','inactive','superseded','unverified')), updated_at timestamptz);
create table pipeline.manual_locks(entity text, entity_id uuid, field text);
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
