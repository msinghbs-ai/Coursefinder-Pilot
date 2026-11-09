-- Stand-ins for objects the production-shaped course-description fixture does not carry. Column lists and constraints read from production 10 Nov 2026 (fxcwkweaxjtknorudmwp). Every body is invented
-- except where a file under live/ says it is a byte-for-byte capture.
\set ON_ERROR_STOP 1
create schema if not exists auth;
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('g.uid', true), '')::uuid $$;
create or replace function security.current_role_rank() returns smallint language sql stable security definer as $$ select coalesce(nullif(current_setting('g.rank', true), '')::smallint, 0::smallint) $$;

-- pipeline.admin_jobs as production has it (the fixture carries only the key)
alter table pipeline.admin_jobs add column if not exists kind text not null default 'x', add column if not exists lane text not null default 'x', add column if not exists state text not null default 'queued',
  add column if not exists title text not null default '', add column if not exists args jsonb not null default '{}'::jsonb, add column if not exists cursor jsonb not null default '{}'::jsonb,
  add column if not exists progress jsonb not null default '{}'::jsonb, add column if not exists result jsonb not null default '{}'::jsonb, add column if not exists error text,
  add column if not exists cancel_requested boolean not null default false, add column if not exists pause_requested boolean not null default false, add column if not exists requested_by uuid,
  add column if not exists reason text not null default '', add column if not exists created_at timestamptz not null default now(), add column if not exists started_at timestamptz,
  add column if not exists updated_at timestamptz not null default now(), add column if not exists finished_at timestamptz, add column if not exists scope text, add column if not exists outcome text,
  add column if not exists outcome_detail jsonb;
alter table pipeline.admin_jobs alter column id set default gen_random_uuid();
alter table pipeline.admin_jobs alter column requested_by set not null;
create table if not exists pipeline.admin_job_events (id bigint generated always as identity primary key, job_id uuid not null, at timestamptz not null default now(), note text not null, detail jsonb);
create table if not exists pipeline.admin_control_events (id bigint generated always as identity primary key, area text not null, action text not null, target text, detail jsonb not null default '{}'::jsonb,
  actor uuid, created_at timestamptz not null default now());

-- flags as production has them
create table if not exists pipeline.enrichment_flags (id bigint generated always as identity primary key, entity text not null, entity_key text not null, provider_id uuid, field text not null default '',
  reason_code text not null, reason text not null, source text not null, flagged_at timestamptz not null default now(), cleared_at timestamptz, kind text not null check (kind in ('hard', 'soft')),
  state text not null check (state in ('counting', 'raised', 'released')), tries integer not null default 1, checks integer not null default 0, evidence jsonb not null default '{}'::jsonb,
  next_check_at timestamptz, input_mark text, raised_by_kind text not null check (raised_by_kind in ('auto', 'person')), released_at timestamptz, released_by text,
  release_kind text check (release_kind in ('auto', 'person')), release_reason text, updated_at timestamptz not null default now(), first_flagged_at timestamptz,
  unique (entity, entity_key, field, reason_code));
create table if not exists pipeline.enrichment_flag_events (id bigint generated always as identity primary key, flag_id bigint not null, action text not null, actor text, actor_kind text,
  reason text, evidence jsonb, at timestamptz not null default now());
create or replace function security.flag_requeue_v1(p_id bigint) returns text language sql stable as $$ select 'the next Enrich fields task includes it' $$;

-- the consumer feeds the verify action reads (read only), the hidden-provider view, absence memory, costs
create table if not exists pipeline.zoho_sync_items (entity text not null, item_key text not null, ref_id uuid, hash text, seq bigint, seq_at timestamptz, removed_at timestamptz, item jsonb, primary key (entity, item_key));
create table if not exists pipeline.g_hidden_providers (provider_id uuid primary key);
create or replace view security.provider_hidden_v1 as select h.provider_id from pipeline.g_hidden_providers h;
create table if not exists pipeline.g_absence (course_id uuid not null, evidence_id uuid not null);
create or replace function security.field_absence_unchanged_v1(p_course uuid, p_field text, p_ev uuid) returns boolean language sql stable as $$
  select p_ev is not null and exists (select 1 from pipeline.g_absence a where a.course_id = p_course and a.evidence_id = p_ev) $$;
create or replace function security.enrich_deadline_missing_v1(p_course uuid) returns boolean language sql stable as $$ select false $$;
create or replace function security.enrich_unit_costs_v1() returns jsonb language sql stable as $$ select jsonb_build_object('enrich_usd_per_item', 0.0031) $$;
create or replace function public.website_v2_course(p_identifier text) returns jsonb language plpgsql stable as $$
declare v_id uuid;
begin
  if p_identifier = 'boom' then raise exception 'simulated website read failure'; end if;
  select d.course_id into v_id from search.course_documents d where d.course_stable_key = p_identifier limit 1;
  if v_id is null then return jsonb_build_object('contract_version', 'website-search-v2', 'error', jsonb_build_object('code', 'NOT_FOUND')); end if;
  return jsonb_build_object('contract_version', 'website-search-v2', 'item', jsonb_build_object('course_id', v_id, 'description', (select c.description from catalogue.courses c where c.id = v_id)));
end $$;

-- the settings production holds (G2 labels and used_by as production has them)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, min_value, max_value, unit, sort, section, used_by) values
 ('pipeline', 'run_now.pilot_cap', 'Run now: most courses in a cohort', 'number', to_jsonb(20), 1, 200, 'courses', 1, 'Run now', 'security.run_now_cohort_create_v1; security.job_run_now_v1'),
 ('pipeline', 'gaps.recheck_days', 'Standing gap queue: look again after', 'number', to_jsonb(60), 1, 365, 'days', 2, 'Gaps', 'security.enrich_course_text_gaps_v1'),
 ('pipeline', 'zoho.sync_countries', 'Zoho: countries synced', 'list', '["AU"]'::jsonb, null, null, 'countries', 3, 'Zoho', 'security.zoho_sync_item_v1')
on conflict (toolset_key, key) do nothing;
update pipeline.platform_toolset_settings set used_by = 'security.enrich_course_text_gaps_v1; job field-gap-queue' where key = 'enrich.course_text_items_per_day' and used_by is null;
-- read by security.coverage_identity_allowed (a captured production function) for adapter proofs; empty here
create table if not exists pipeline.uni_adapters (provider_id uuid not null, enabled boolean not null default false, admit boolean not null default false, admit_fields text[] not null default '{}');
-- the proofs a country admits for each attribute (security.coverage_identity_allowed reads this); Australia and New Zealand admit an exact title for the description
create table if not exists pipeline.coverage_admission_countries (country_id uuid primary key, active boolean not null default true, identities jsonb not null default '{}'::jsonb);
insert into pipeline.coverage_admission_countries(country_id, identities) select id, '{"description": ["exact_title", "cricos_code"]}'::jsonb from ref.countries where iso_alpha2 in ('AU', 'NZ') on conflict do nothing;
-- the field list the unchanged part of public.admin_enrich_fields reads (an invented body; the real one is not under test)
create or replace function security.enrich_fields_v1() returns table (field text, label text, level text, sources text[], sort int) language sql stable as $$
  select * from (values ('description', 'Course description', 'course', array['ai_stored']::text[], 1), ('duration', 'Duration', 'course', array['ai_stored']::text[], 2)) v $$;

-- the Layer 4 back-pressure setting the standing queue reads (migration 20261108130000; ships 0 = off)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, min_value, max_value, unit, sort, section, used_by) values
 ('pipeline', 'enrich.course_description_pending_global_max', 'Course description: most waiting for a person before new readings pause', 'number', to_jsonb(0), 0, 20000, 'descriptions', 4, 'Enrich fields', 'security.enrich_course_text_gaps_v1')
on conflict (toolset_key, key) do nothing;
