-- Course link fill respects Layer 4: the tables and helpers security.course_url_fill_v1 reads, cut to the columns it uses (shapes as live,
-- 2 Nov 2026). Nothing here is a Supabase project.
create extension if not exists pgcrypto;
create schema if not exists security; create schema if not exists pipeline; create schema if not exists catalogue;
create schema if not exists ref; create schema if not exists search; create schema if not exists cron;
create table pipeline.platform_toolset_settings (toolset_key text, key text, label text, help text, kind text, value jsonb, min_value text, max_value text,
  unit text, sort int, section text, used_by text, reason text, updated_at timestamptz default now(), primary key (toolset_key, key));
insert into pipeline.platform_toolset_settings(toolset_key, key, value) values
  ('pipeline', 'course_url.fill_enabled', '1'), ('pipeline', 'course_url.max_retraction_pct', '5'), ('pipeline', 'batch.course_url_fill', '2000'),
  ('pipeline', 'course_url.fill_countries', '["NZ","AU","CA"]');
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $$;
create table pipeline.fx_rate (filled int, retraction_pct numeric, max_pct numeric);
insert into pipeline.fx_rate values (0, 0, 5);
create function security.course_url_retraction_30d_v1() returns jsonb language sql stable as $$
  select jsonb_build_object('filled', filled, 'retraction_pct', retraction_pct, 'max_pct', max_pct) from pipeline.fx_rate $$;
create function security.coverage_identity_allowed(p_provider uuid, p_basis text, p_field text) returns boolean language sql stable as $$ select p_basis <> 'refused_basis' $$;
create table ref.countries (id uuid primary key default gen_random_uuid(), iso_alpha2 text);
create table catalogue.providers (id uuid primary key default gen_random_uuid(), country_id uuid);
create table catalogue.courses (id uuid primary key default gen_random_uuid(), provider_id uuid, lifecycle_status text default 'active', course_url text, updated_at timestamptz);
create table pipeline.coverage_course_pages (course_id uuid primary key, provider_id uuid, url text, candidates jsonb default '{}', status text, identity_basis text,
  read_status text, evidence_id uuid);
create table pipeline.course_url_fills (course_id uuid primary key, url text not null, evidence_id uuid not null, identity_basis text not null,
  filled_at timestamptz not null default now(), retracted_at timestamptz, retract_reason text);
create table pipeline.manual_locks (entity text, entity_id uuid, field text, mode text);
create table pipeline.admin_control_events (id bigserial, area text, action text, target text, detail jsonb, actor uuid, created_at timestamptz default now());
create table search.refresh_requests (id bigserial, requested_by text);
create table pipeline.layer4_review_items (id uuid primary key default gen_random_uuid(), entity_type text, entity_id uuid, field_code text, status text,
  proposed_value jsonb, created_at timestamptz default now());
create table pipeline.automation_catalogue (jobname text primary key, description text);
insert into pipeline.automation_catalogue values ('course-url-fill', 'Daily at 02:23 UTC: for courses with no official link in Official link: countries filled, writes the address of the course''s proven own page (bound, proof on the page, stored copy) into course_url; takes a link back when the page is no longer bound or its copy changed, and fills again from the new binding. Never touches a locked or person-set link. Pauses itself when more than Official link: most taken back of the last 30 days'' fills were taken back. Handles Official link: links filled a run courses a run.');
create table pipeline.component_register (kind text, name text, status text, note text, updated_at timestamptz, primary key (kind, name));
insert into pipeline.component_register values ('function', 'security.course_url_fill_v1', 'active', null, now());
