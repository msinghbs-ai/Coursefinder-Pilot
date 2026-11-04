-- Live shapes added to ../sch-coverage-recovery/stubs.sql for the scholarship hand-off fixtures (CF-247 IQ-00264, 4 Nov 2026). Columns as read
-- from production on 4 Nov 2026 11:10-11:16 AEDT (information_schema, read only). Never a Supabase project.
set check_function_bodies = off;
alter table scholarship.scholarships add column if not exists evidence_id uuid, add column if not exists award_currency_code character(3), add column if not exists description text,
  add column if not exists created_at timestamptz default now();
alter table scholarship.award_tiers add column if not exists tier_code text;
alter table scholarship.criteria add column if not exists value_json jsonb, add column if not exists value_codes text[];
alter table pipeline.scholarship_pages add column if not exists facts jsonb, add column if not exists evidence_id uuid, add column if not exists candidate_id bigint,
  add column if not exists name_check jsonb, add column if not exists http_status int;
create table if not exists scholarship.course_mappings (scholarship_id uuid, course_id uuid, mapping_state text, mapping_basis text);
create table if not exists catalogue.courses (id uuid primary key default gen_random_uuid(), provider_id uuid, study_level_id uuid, lifecycle_status text default 'active');
create table if not exists pipeline.evidence_artifacts (id uuid primary key default gen_random_uuid(), captured_at timestamptz default now());
create or replace function security.scholarship_series_key_v1(p text) returns text language sql immutable as $$ select lower(btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g'))) $$;
-- the Curator edit route's helpers (live semantics: one lock per field; the caller's role from the session)
create table if not exists pipeline.manual_locks (entity text, entity_id uuid, field text, mode text, set_by uuid, set_at timestamptz default now(), primary key (entity, entity_id, field));
create table if not exists pipeline.manual_edit_log (id bigint generated always as identity primary key, entity text, entity_id uuid, field text, action text, before jsonb, after jsonb,
  reason text, actor uuid, at timestamptz default now());
create table if not exists ref.nationality_terms (code text primary key);
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create or replace function security.current_role_rank() returns int language sql stable as $$ select coalesce(nullif(current_setting('fx.rank', true), '')::int, 0) $$;
create or replace function security.manual_lock_set(p_entity text, p_id uuid, p_field text, p_mode text) returns void language sql as $$
  insert into pipeline.manual_locks(entity, entity_id, field, mode, set_by) values (p_entity, p_id, p_field, p_mode, auth.uid())
  on conflict (entity, entity_id, field) do update set mode = excluded.mode, set_by = excluded.set_by, set_at = now() $$;
create or replace function scholarship.value_label(p uuid) returns text language sql stable as $$
  select case s.award_value_type when 'fixed_amount' then s.award_amount::text when 'percentage' then s.award_percentage::text || '%' else s.award_value_text end
    from scholarship.scholarships s where s.id = p $$;
create or replace function security.integration_issue_close_v1(p_issue bigint, p_actor text, p jsonb) returns jsonb language sql as $$ select '{}'::jsonb $$;
-- the hourly publishing run, as live (security.scholarship_auto_publish_v1 publishes every active scholarship that passes every check)
create or replace function public.fx_auto_publish() returns int language sql as $$
  with p as (update scholarship.scholarships s set publication_status = 'published', updated_at = now()
               from security.scholarship_publishability_for_v1(null) x where x.scholarship_id = s.id and x.publishable and s.publication_status <> 'published' returning s.id)
  select count(*)::int from p $$;
-- the audit names the actor from auth.users (security.har_event_v1)
create table if not exists auth.users (id uuid primary key, email text);
insert into auth.users values ('63ba56cb-48d4-4169-98c2-7c4d1f72925b', 'reviewer@example.invalid') on conflict do nothing;
-- the stored copy of an address, when one is held (live: Layer 4 evidence lookup); the fixture holds none
create or replace function security.layer4_stored_copy_v1(p_url text) returns uuid language sql stable as $$ select null::uuid $$;
