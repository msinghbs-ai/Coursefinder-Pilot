-- Stubs: the tables and helpers the AER read-now migration reads, in the shape live has them (live columns, read 10 Nov 2026; types simplified). Functions marked STUB stand in for live functions owned elsewhere: they do the smallest thing the scenarios need.
create schema if not exists security; create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists ref; create schema if not exists cron; create schema if not exists auth;
do $$ begin create role anon; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated; exception when duplicate_object then null; end $$;
create table ref.countries (id int primary key, iso_alpha2 text, name text);
create table ref.provider_types (id int primary key, code text);
create table catalogue.providers (id uuid primary key default gen_random_uuid(), canonical_name text, display_name text, short_name text, country_id int, provider_type_id int, website text, lifecycle_status text default 'active', publication_status text default 'published', enrols_international boolean default true);
create table catalogue.courses (id uuid primary key default gen_random_uuid(), provider_id uuid, canonical_title text, display_title text, lifecycle_status text default 'active', publication_status text default 'published', study_level_id int);
create table catalogue.provider_entry_matrix (id uuid primary key default gen_random_uuid(), provider_id uuid, course_id uuid, course_label text, matrix_kind text, level_label text, study_level_id int, country_id int, country_code text, qualification_name text, min_grade text, min_value numeric, grade_scale text,
  audience text, edition text, intake_year int, quote text, source_url text, source_id uuid, evidence_id uuid, run_id uuid, as_at date, status text, provenance jsonb default '{}', aer_level text);
create table catalogue.course_entry_requirements (id uuid primary key default gen_random_uuid(), course_id uuid, kind text, audience text, country_id int, description text, min_grade text, min_value numeric, grade_scale text, min_entry_score numeric, min_entry_score_basis text, quote text, source_url text, evidence_id uuid,
  as_at date, status text, provenance jsonb default '{}');
create table pipeline.platform_toolset_settings (toolset_key text, key text, value jsonb, primary key (toolset_key, key));
create table pipeline.evidence_artifacts (id uuid primary key default gen_random_uuid(), storage_path text, mime_type text, captured_at timestamptz default now());
create table pipeline.coverage_course_pages (course_id uuid primary key, provider_id uuid, url text, status text, identity_basis text, evidence_id uuid);
create table pipeline.coverage_provider_reconciliation (domain text, provider_id uuid, shortfall int);
create table pipeline.manual_locks (entity text, entity_id uuid, field text, mode text);
create table pipeline.entry_matrix_sources (id uuid primary key default gen_random_uuid(), provider_id uuid, url text, title text, rank int, found_via text, status text default 'found', read_via text, evidence_id uuid, content_hash text, attempts int default 0, read_at timestamptz, error text,
  created_at timestamptz default now(), updated_at timestamptz default now(), unique (provider_id, url));
create table pipeline.entry_matrix_runs (id uuid primary key default gen_random_uuid(), provider_id uuid, source_id uuid, content_hash text, state text, error text, result jsonb, review_item_id uuid, created_at timestamptz default now());
create table pipeline.layer4_review_items (id uuid primary key default gen_random_uuid(), entity_type text, entity_id uuid, field_code text, status text default 'pending', created_at timestamptz default now(), decided_at timestamptz);
create table pipeline.layer4_item_readiness (item_id uuid primary key, entity_type text, entity_id uuid, field_code text, item_status text, readiness text, reasons text[], route text, gate jsonb, classified_at timestamptz default now());
create table pipeline.field_enrich_items (id uuid primary key default gen_random_uuid(), provider_id uuid, course_id uuid, field text, state text, evidence_id uuid, updated_at timestamptz default now());
alter table pipeline.evidence_artifacts add column content_hash text;
alter table pipeline.field_enrich_items add column reason text;
alter table pipeline.entry_matrix_sources add column http_status int;
alter table pipeline.entry_matrix_runs add column rows_admitted int default 0, add column done_at timestamptz, add column updated_at timestamptz default now(), add column attempts int default 0;
create table pipeline.aer_replay_checks (item_id uuid primary key, checked_at timestamptz default now(), ok boolean);
create table pipeline.aer_read_supersessions (id bigserial primary key, old_item_id uuid, new_item_id uuid, reason text, requested_at timestamptz default now());
create table pipeline.aer_schedule_runs (id bigserial primary key, ran_at timestamptz default now(), course_reads int default 0, corrections int default 0, matrix_pages int default 0, layer4_waiting int, in_progress int, back_pressure boolean, used_before int, room int, refusal text, estimate_usd numeric, detail jsonb);
create table pipeline.admin_control_events (id bigserial primary key, area text, action text, target text, detail jsonb, actor uuid, created_at timestamptz default now());
create table pipeline.layer3_openrouter_observations (id bigserial primary key, kind text, remaining_usd numeric, observed_at timestamptz default now());
create table pipeline.aer_gap_findings (id bigserial primary key, fingerprint text unique, root_cause text, provider_id uuid, state text default 'open', evidence jsonb, last_seen timestamptz default now());
create table pipeline.aer_review_readiness (review_item_id uuid primary key, provider_id uuid, readiness text, root_cause text, settled_at timestamptz);
create table pipeline.aer_source_stored_find (provider_id uuid primary key, checked_at timestamptz default now(), outcome text, attached int default 0);
create table pipeline.aer_provider_coverage (provider_id uuid primary key, country text, eligible boolean default true, disposition text, sources int default 0, sources_read int default 0, matrix_active int default 0, course_req_active int default 0, course_req_proposed int default 0, layer4 jsonb default '{}', updated_at timestamptz default now());
create table pipeline.work_items (id bigserial primary key, lane text, entity text, work_kind text, provider_id uuid, stage text, failure_class text, first_blocked_at timestamptz default now(), unresolved_blocker jsonb);
create table pipeline.component_register (kind text not null check (kind in ('job', 'table', 'view', 'edge_function', 'screen', 'function')), name text not null, layer text not null, area text, purpose text, status text not null default 'active', replaces text[] not null default '{}', replaced_by text, introduced_in text, primary key (kind, name));
create table cron.job (jobid serial primary key, jobname text, schedule text, active boolean default true);
-- Data Delivery (the tables the live data_delivery_v1 reads)
create table pipeline.data_delivery_streams (stream text primary key, title text, sort int, lane text, unit text, net_unit text, consumer_unit text, what text, coverage_sql text, net_sql text, consumer_sql text, net_basis text, speed_basis text, primary_jobs text[] default '{}', queue_parts text[] default '{}', hold_parts text[] default '{}', not_measured jsonb default '{}', drill jsonb, added_in text);
create table pipeline.data_delivery_readings (stream text, measure text, measured_at timestamptz, rows jsonb, took_ms int, error text, failed_at timestamptz);
create table pipeline.data_delivery_job_runs (singleton boolean primary key default true, measured_at timestamptz, runs jsonb, took_ms int, error text, failed_at timestamptz);
create table pipeline.lane_funnel_lanes (lane text primary key, title text, sort int, what text, jobs text[], switch_keys text[] default '{}', setting_prefixes text[], budget_group text, review_kinds text[], issue_refs text[] default '{}', screen text, process_record text, added_in text);
create table pipeline.integration_issues (id bigserial primary key, issue_ref text, status text);
create table pipeline.ops_remedy_runs (id bigserial primary key, issue_id bigint, remedy_code text, started_at timestamptz default now(), result text);
-- helpers (the live definitions are owned elsewhere; these are the smallest equivalents)
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$ select coalesce((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = p_key), p_default) $$;
create function security.toolset_setting(p_tool text, p_key text) returns jsonb language sql stable as $$ select value from pipeline.platform_toolset_settings where toolset_key = p_tool and key = p_key $$;
create function security.aer_eligible_v1() returns table(provider_id uuid, country text) language sql stable as $$ select p.id, k.iso_alpha2 from catalogue.providers p join ref.countries k on k.id = p.country_id where p.lifecycle_status = 'active' and p.publication_status = 'published' and p.enrols_international is true $$;
create function security.coverage_identity_allowed(p_provider uuid, p_basis text, p_field text) returns boolean language sql stable as $$ select coalesce(p_basis, '') not in ('exact_title', 'title_level', 'degree_name', 'adapter_title', '') $$;
create table pipeline.fx_hidden (provider_id uuid);
create view security.provider_hidden_v1 as select provider_id from pipeline.fx_hidden;
create function security.aer_schedule_country_v1(p text) returns jsonb language sql stable as $$ select jsonb_build_object('on', coalesce(p, '') not in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'fx.countries_off'), '[]'::jsonb))), 'reason', 'switched off in the country setting') $$;
create function security.aer_review_kinds_v1() returns text[] language sql immutable as $$ select array['course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change'] $$;
create function security.cron_next_run_v1(p text, t timestamptz) returns timestamptz language sql immutable as $$ select t + interval '1 hour' $$;
create function security.course_entry_cost_v1() returns numeric language sql stable as $$ select 0.005::numeric $$;
create function security.ai_use_refusal_v1(p text) returns text language sql stable as $$ select (select value #>> '{}' from pipeline.platform_toolset_settings where toolset_key = 'fx' and key = 'ai_refusal_' || p) $$;
create function security.entry_matrix_enabled_v1(p uuid) returns boolean language sql stable as $$ select not coalesce((select (value #>> '{}')::boolean from pipeline.platform_toolset_settings where toolset_key = 'fx' and key = 'matrix_off'), false) $$;
create function security.current_role_rank() returns smallint language sql stable as $$ select coalesce(nullif(current_setting('fx.rank', true), ''), '0')::smallint $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('fx.uid', true), '')::uuid $$;
-- STUB: the parked-item lane view is loaded from migration 20261110160000 by run.sh (its real body)
-- STUB: the course reader's enqueue: records one waiting read, as the live function does for the item queue, and returns a job id
create function security.course_entry_read_enqueue_v1(p_course uuid, p_by uuid, p_reason text) returns uuid language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from catalogue.courses c where c.id = p_course) then raise exception 'no such course'; end if;
  insert into pipeline.field_enrich_items(provider_id, course_id, field, state) select c.provider_id, c.id, 'entry_requirements', 'queued' from catalogue.courses c where c.id = p_course;
  return gen_random_uuid();
end $$;
-- STUB: read again of one source: queues one run and returns the run, as the live function's result does
create function security.aer_reread_v1(p_source uuid, p_reason text, p_actor uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_run uuid := gen_random_uuid();
begin
  insert into pipeline.entry_matrix_runs(id, provider_id, source_id, state) select v_run, s.provider_id, s.id, 'queued' from pipeline.entry_matrix_sources s where s.id = p_source;
  update pipeline.entry_matrix_sources set status = 'found' where id = p_source;
  return jsonb_build_object('ok', true, 'runs', 1, 'run', v_run, 'rows_superseded', 0, 'items_superseded', 0);
end $$;
-- STUB: replay: a held read is replayable when fx_replayable lists it; applying supersedes it and writes a ready one, counted as the live replay counts (reason Replay of the stored read)
create table pipeline.fx_replayable (item_id uuid primary key);
create function security.aer_replay_plan_v1(p_item uuid) returns jsonb language sql stable as $$
  select case when exists (select 1 from pipeline.fx_replayable r where r.item_id = p_item) then jsonb_build_object('item', p_item, 'ok', true, 'rows', jsonb_build_array(), 'dropped', jsonb_build_array())
              else jsonb_build_object('item', p_item, 'ok', false, 'why', 'the waiting read keeps no row and no stored read exists') end $$;
create function security.aer_replay_apply_v1(p_item uuid, p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_new uuid := gen_random_uuid();
begin
  if not coalesce((p->>'ok')::boolean, false) then return jsonb_build_object('item', p_item, 'applied', false, 'why', p->>'why'); end if;
  update pipeline.layer4_review_items set status = 'superseded' where id = p_item;
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code) select v_new, entity_type, entity_id, field_code from pipeline.layer4_review_items where id = p_item;
  insert into pipeline.layer4_item_readiness(item_id, entity_type, entity_id, field_code, item_status, readiness, reasons, route, gate) select v_new, entity_type, entity_id, field_code, 'pending', 'judgement_ready', '{}', 'review', '{"complete": true}' from pipeline.layer4_review_items where id = v_new;
  insert into pipeline.aer_read_supersessions(old_item_id, new_item_id, reason) values (p_item, v_new, 'Replay of the stored read: ' || p_item);
  return jsonb_build_object('item', p_item, 'applied', true, 'new_item', v_new, 'state', 'superseded');
end $$;
-- STUB: the reviewer packet and the recovery detail that the card detail composes
create function security.aer_review_packet_v1(p uuid) returns jsonb language sql stable as $$
  select case when exists (select 1 from pipeline.layer4_review_items i where i.id = p) then jsonb_build_object('settlement', jsonb_build_object('settlement', 'ready'), 'provider', 'P', 'course', '{}'::jsonb, 'source', '{}'::jsonb, 'audiences', '[]'::jsonb, 'evidence', '{}'::jsonb,
    'recommended', 'approve', 'consequences', '{}'::jsonb, 'owner', '[]'::jsonb, 'queue', jsonb_build_object('position', 1, 'ready_at_university', 1), 'route', '{}'::jsonb, 'gate', jsonb_build_object('complete', true, 'source', 'stub'),
    'conflicts', '{}'::jsonb, 'exclude_row_ids', '[]'::jsonb, 'proposed', jsonb_build_object('count', 0, 'rows', '[]'::jsonb), 'active', jsonb_build_object('count', 0, 'rows', '[]'::jsonb), 'locks', '[]'::jsonb) end $$;
create function security.layer4_aer_recovery_detail_v1(p text) returns jsonb language sql stable as $$ select jsonb_build_object('sections', '[]'::jsonb, 'actions', '[]'::jsonb) $$;
-- STUBS for the other streams' sub-functions that the live data_delivery_v1 calls
create function security.data_delivery_meta_v1(a jsonb, b int) returns jsonb language sql as $$ select '{}'::jsonb $$;
create function security.data_delivery_net_v1(a jsonb, b int, c int, d text) returns jsonb language sql as $$ select jsonb_build_object('known', false, 'reason', 'stub') $$;
create function security.data_delivery_consumer_v1(a jsonb, b text, c int, d text) returns jsonb language sql as $$ select jsonb_build_object('known', false, 'reason', 'stub') $$;
create function security.data_delivery_parts_v1(a text, b text[], c int, d int) returns jsonb language sql as $$ select jsonb_build_object('known', false, 'reason', 'stub') $$;
create function security.data_delivery_pdesc_v1() returns jsonb language sql as $$ select '{}'::jsonb $$;
create function security.data_delivery_cdesc_stages_v1() returns jsonb language sql as $$ select '{}'::jsonb $$;
create function security.data_delivery_intake_v1() returns jsonb language sql as $$ select '{}'::jsonb $$;
create function security.admin_providers_page_v3(a jsonb) returns jsonb language sql as $$ select '{}'::jsonb $$;
