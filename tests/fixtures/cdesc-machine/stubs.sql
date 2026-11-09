-- Guards: F-CDESC (Platform Admin decision 10 Nov 2026): stand-ins for the objects the course-description fixture does not carry, with the shapes read from production on 10 Nov 2026 (project fxcwkweaxjtknorudmwp).
-- Every body is invented, except where a live definition is loaded from live/ (checked against its live md5 by run.sh). Scratch database only.
\set ON_ERROR_STOP 1
create schema if not exists storage;
create table if not exists storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text not null, name text not null, metadata jsonb);
create unique index if not exists storage_objects_bucket_name_uq on storage.objects (bucket_id, name);

-- production shape: ONE search refresh signal for each decision (UNIQUE review_decision_id)
create table if not exists pipeline.search_refresh_signals (
  id uuid primary key default gen_random_uuid(), entity_type text not null, entity_id uuid not null,
  review_decision_id uuid not null references pipeline.layer4_decisions(id) on delete cascade,
  reason text not null, status text not null default 'queued' check (status in ('queued', 'processing', 'done', 'failed')),
  change_control_ref text not null, created_at timestamptz not null default now(), completed_at timestamptz,
  constraint search_refresh_signals_review_decision_id_key unique (review_decision_id));
create table if not exists pipeline.admin_control_events (id bigserial primary key, area text not null, action text not null, target text, detail jsonb not null default '{}'::jsonb, actor uuid, created_at timestamptz not null default now());
create table if not exists pipeline.enrichment_flags (id bigserial primary key, entity text not null, entity_key text not null, provider_id uuid, field text not null default '', reason_code text not null, reason text not null default '',
  source text not null default 'x', flagged_at timestamptz not null default now(), kind text not null default 'soft', state text not null default 'raised', tries int not null default 0, checks int not null default 0,
  evidence jsonb not null default '{}'::jsonb, raised_by_kind text not null default 'auto', updated_at timestamptz not null default now());
alter table pipeline.enrichment_flags add column if not exists input_mark text; -- read by the live security.enrich_item_held_v1 loaded from live/
create or replace function security.provider_lifecycle_held_v1(p_provider uuid) returns boolean language sql stable as $$ select false $$;
-- the hidden-provider view reads a scratch table so a scenario can hide a provider
create table if not exists pipeline.cdm_hidden (provider_id uuid primary key);
create or replace view security.provider_hidden_v1 as select provider_id from pipeline.cdm_hidden;
create table if not exists pipeline.cdm_not_in_feed (course_id uuid primary key);
-- production has the control class column since 20261110080000 (F-OPS.05); the fixture carries the column only, not that migration
alter table pipeline.platform_toolset_settings add column if not exists control_class text check (control_class in ('human', 'automatic', 'retiring'));
-- the consumer function the read-back calls: a stand-in that reads the catalogue like the live one reads the description column. The GUC cdm.consumer simulates lag, a different text, or an error.
create or replace function public.website_v2_course(p_identifier text) returns jsonb language plpgsql stable as $$
declare v_id uuid; v_mode text := coalesce(current_setting('cdm.consumer', true), '');
begin
  if v_mode = 'error' then raise exception 'consumer function failed'; end if;
  -- live answers for a course whatever its publication status (it reads the search documents, which carry unpublished courses too); only a course missing from the feed is NOT_FOUND
  select c.id into v_id from catalogue.courses c where c.stable_key = p_identifier and not exists (select 1 from pipeline.cdm_not_in_feed n where n.course_id = c.id);
  if v_id is null then return jsonb_build_object('contract_version', 'website-search-v2', 'error', jsonb_build_object('code', 'NOT_FOUND')); end if;
  return jsonb_build_object('contract_version', 'website-search-v2', 'item', jsonb_build_object('course_id', v_id,
    'description', case v_mode when 'lag' then null when 'mismatch' then 'Some other text that the feed holds for this course.' else (select c.description from catalogue.courses c where c.id = v_id) end));
end $$;
