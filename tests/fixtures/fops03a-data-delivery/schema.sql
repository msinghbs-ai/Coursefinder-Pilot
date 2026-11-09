-- CF-247 F-OPS.03A Data Delivery: the minimum of the live schema (columns checked against project fxcwkweaxjtknorudmwp, 9 Nov 2026, read only) that migration
-- 20261110000100 reads, added to the lane funnel fixture schema (tests/fixtures/lane-funnels/schema.sql, applied first, then migration 20261108170000). Stubs are marked STUB.
create schema if not exists ref; create schema if not exists scholarship;
create table ref.countries (id uuid primary key default gen_random_uuid(), iso_alpha2 text unique);
alter table catalogue.providers add column if not exists stable_key text, add column if not exists country_id uuid;
alter table catalogue.courses add column if not exists stable_key text, add column if not exists provider_id uuid;
alter table catalogue.course_fees add column if not exists course_id uuid;
alter table catalogue.course_entry_requirements add column if not exists course_id uuid, add column if not exists created_at timestamptz default now();
alter table catalogue.course_links add column if not exists course_id uuid, add column if not exists status text, add column if not exists link_type text, add column if not exists updated_at timestamptz default now();
create table catalogue.course_intakes (id uuid primary key default gen_random_uuid(), course_id uuid, status text, start_date date);
create table scholarship.scholarships (id uuid primary key default gen_random_uuid(), stable_key text, provider_id uuid, lifecycle_status text, publication_status text);
create table pipeline.scholarship_admission_log (id bigserial primary key, provider_id uuid, action text, at timestamptz default now());
create table pipeline.provider_description_machine_admissions (id bigserial primary key, provider_id uuid, outcome text, created_at timestamptz default now(), withdrawn_at timestamptz, review_item_id uuid);
create table pipeline.provider_description_reads (id uuid primary key default gen_random_uuid(), provider_id uuid, state text, reason text, updated_at timestamptz default now());
alter table pipeline.layer4_review_items add column if not exists entity_id uuid;
alter table pipeline.course_intake_date_events add column if not exists provider_id uuid;
alter table pipeline.field_enrich_items add column if not exists provider_id uuid;
alter table pipeline.fee_reader_rows add column if not exists provider_id uuid;
create table pipeline.website_sync_items (entity text, item_key text, item jsonb, removed_at timestamptz);
create table pipeline.zoho_sync_items (entity text, item_key text, item jsonb, removed_at timestamptz);
-- STUB: the served set. The live functions read the Website and Zoho candidate scans; here the served ids are a table the fixtures fill.
create table pipeline.fx_served (feed text, entity text, ref_id uuid);
create function security.website_sync_candidates_v1(p_entity text) returns table(ref_id uuid) language sql stable as $$ select s.ref_id from pipeline.fx_served s where s.feed = 'w' and s.entity = p_entity $$;
create function security.zoho_sync_candidates_v1(p_entity text) returns table(ref_id uuid) language sql stable as $$ select s.ref_id from pipeline.fx_served s where s.feed = 'z' and s.entity = p_entity $$;
create table pipeline.ops_remedy_runs (id bigserial primary key, issue_id bigint, remedy_code text, started_at timestamptz default now(), result text);
-- STUB: the live public.admin_layer23 is far longer; its gate lines and the line the migration edits are the live text (rank 3 and above)
create function public.admin_layer23(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_rank int; v_out jsonb; v_list jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  v_rank := security.current_role_rank();
  if coalesce(v_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_action = 'universities_page' then
    return jsonb_build_object('stub', 'universities_page');
  end if;
  raise exception 'unknown action %', p_action;
end $f$;
