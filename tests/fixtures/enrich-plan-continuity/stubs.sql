-- Plan continuity (CF-247 3 Nov 2026, Workstream E): the tables and helpers the guarded functions use, cut to the columns they use (shapes as
-- live, 3 Nov 2026). public.admin_jobs and public.admin_provider_onboarding are cut to their cancel and stop paths (the role check and the state
-- change as live). Nothing here is a Supabase project.
create extension if not exists pgcrypto;
do $r$ begin if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; create role authenticated; create role service_role; end if; end $r$;
create schema if not exists security; create schema if not exists pipeline; create schema if not exists catalogue;
create schema if not exists ref; create schema if not exists auth; create schema if not exists ranking; create schema if not exists search;
-- Supabase auth: the claims a step sets (request.jwt.claims) first, else the signed-in person of the fixture (fx.uid)
create function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(nullif(current_setting('request.jwt.claims', true), '')::json->>'sub', ''), nullif(current_setting('fx.uid', true), ''))::uuid $$;
create function auth.role() returns text language sql stable as $$ select nullif(current_setting('fx.role', true), '') $$;
create table security.fx_ranks (uid uuid primary key, rank int);
create function security.current_role_rank() returns int language sql stable as $$ select (select rank from security.fx_ranks where uid = auth.uid()) $$;
create table pipeline.platform_toolset_settings (toolset_key text, key text, label text, help text, kind text, value jsonb, min_value text, max_value text,
  unit text, sort int, section text, used_by text, reason text, updated_at timestamptz default now(), primary key (toolset_key, key));
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $$;
insert into pipeline.platform_toolset_settings(toolset_key, key, value) values ('pipeline', 'plans.redo_days', '14'), ('pipeline', 'plans.auto_open_max', '40'),
  ('pipeline', 'plans.auto_per_run', '20'), ('pipeline', 'plans.priority_countries', '["NZ"]'), ('pipeline', 'hygiene.retire_after_days', '14');
create function security.fc_setting_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$ select p_default $$;
create function security.fc_on_demand_today_v1() returns numeric language sql stable as $$ select 0::numeric $$;
create function security.toolset_setting(p_toolset text, p_key text) returns jsonb language sql stable as $$ select '10'::jsonb $$;
create function security.fc_day_start_v1() returns timestamptz language sql stable as $$ select date_trunc('day', now()) $$;
create function security.fc_budget_left_v1(p text) returns numeric language sql stable as $$ select 1000::numeric $$;
create function security.fc_purpose_group_v1(p text) returns text language sql stable as $$ select 'other' $$;
create table ref.countries (id uuid primary key default gen_random_uuid(), iso_alpha2 text);
create table catalogue.providers (id uuid primary key default gen_random_uuid(), country_id uuid, canonical_name text, display_name text, website text,
  address_line1 text, lifecycle_status text default 'active', publication_status text default 'published');
create view security.provider_hidden_v1 as select id as provider_id from catalogue.providers p
  where p.publication_status is distinct from 'published' or p.lifecycle_status is distinct from 'active';
create table catalogue.courses (id uuid primary key default gen_random_uuid(), provider_id uuid, course_code text, canonical_title text, lifecycle_status text default 'active',
  duration_value numeric, duration_unit text, study_level_id uuid, delivery_mode text, primary_field_id uuid, open_to_international boolean);
create table catalogue.course_campuses (course_id uuid); create table catalogue.course_english_requirements (course_id uuid, status text);
create table catalogue.course_intakes (course_id uuid, status text);
create table catalogue.campuses (provider_id uuid, status text, subdivision_id uuid, city text);
create table ref.study_levels (id uuid primary key, name text);
create table pipeline.field_enrich_items (id bigserial primary key, job_id uuid, provider_id uuid, course_id uuid, field text, state text default 'queued', source text,
  value jsonb, quote text, reason text, evidence_id uuid, attempts int default 0, cost_usd numeric, created_at timestamptz default now(), updated_at timestamptz default now());
create unique index on pipeline.field_enrich_items (job_id, provider_id, course_id, field) nulls not distinct;
create table pipeline.admin_jobs (id uuid primary key default gen_random_uuid(), kind text, lane text, state text, title text, args jsonb default '{}', progress jsonb,
  result jsonb, requested_by uuid, reason text, scope text, cancel_requested boolean default false, created_at timestamptz default now(), finished_at timestamptz, updated_at timestamptz);
create table pipeline.admin_job_events (job_id uuid, note text, detail jsonb, at timestamptz default now());
create table pipeline.admin_control_events (id bigserial primary key, area text, action text, target text, detail jsonb, actor uuid, created_at timestamptz default now());
create table pipeline.component_register (kind text, name text, layer text, area text, purpose text, status text, replaces text[], replaced_by text,
  introduced_in text, retire_after date, note text, updated_at timestamptz, primary key (kind, name));
insert into pipeline.component_register(kind, name, status) values ('function', 'public.admin_enrich_plan', 'active'), ('function', 'security.enrich_plan_auto_v1', 'active');
create table pipeline.enrich_plan_control (id int primary key, auto_enabled boolean, owner uuid, reason text, updated_at timestamptz);
create table pipeline.enrich_plan_runs (id uuid primary key default gen_random_uuid(), provider_id uuid, mode text, state text default 'queued', steps jsonb, estimate jsonb,
  actual jsonb, fields_before jsonb, fields_after jsonb, requested_by uuid, reason text, created_at timestamptz default now(), started_at timestamptz, finished_at timestamptz,
  updated_at timestamptz, needs_person text);
create unique index enrich_plan_runs_one_open on pipeline.enrich_plan_runs (provider_id) where state in ('queued', 'running');
create table pipeline.provider_onboarding (id uuid primary key default gen_random_uuid(), provider_id uuid, status text, note text, created_at timestamptz default now(),
  finished_at timestamptz, updated_at timestamptz);
create table pipeline.course_attribute_coverage (provider_id uuid, course_id uuid, country_code text, attribute text, state text);
create table pipeline.field_register (field text, reader text);
create table ranking.observation_provider_links (provider_id uuid, observation_id uuid); create table ranking.observations (id uuid, rank_low int, rank_exact int);
create table pipeline.coverage_vendor_usage (purpose text, units numeric, provider_id uuid, at timestamptz);
create table pipeline.uni_adapter_drafts (provider_id uuid, cost_usd numeric, created_at timestamptz);
create table pipeline.scholarship_ai_extractions (provider_id uuid, cost_usd numeric, at timestamptz);
create table pipeline.coverage_course_pages (course_id uuid primary key, evidence_id uuid, candidates jsonb, read_status text, identity_basis text, read_at timestamptz);
create table pipeline.uni_adapter_results (course_id uuid, fields jsonb, at timestamptz);
create table pipeline.manual_locks (entity text, entity_id uuid, field text);
create table pipeline.field_crosscheck_findings (id bigserial, course_id uuid, provider_id uuid, field text, held_value jsonb, page_value jsonb, source text, quote text,
  evidence_id uuid, state text default 'open', decided_at timestamptz, note text, unique (course_id, field, page_value));
create table pipeline.sources (id uuid primary key, provider_id uuid);
create table pipeline.evidence_artifacts (id uuid primary key, source_id uuid, evidence_type text);
create table pipeline.city_regions (country_id uuid);
create table pipeline.field_source_rules (country_code text, field text);
-- readers the guarded functions call: simple, deterministic
create function security.enrich_fields_v1() returns table(field text, label text, level int, sources text[], sort int) language sql stable as $$
  select * from (values ('campus', 'Campus', 2, array['adapter'], 1), ('duration', 'Duration', 2, array['adapter'], 2), ('level', 'Level', 2, array['adapter'], 3),
    ('intakes', 'Intakes', 3, array['ai_stored'], 4), ('campus_region', 'Campus region', 3, array['ai_city'], 5), ('provider_address', 'Address', 2, array['scraper'], 6)) v $$;
create function security.catalogue_country_codes_v1() returns text[] language sql stable as $$ select array['AU', 'NZ'] $$;
create function security.campus_regions_apply_v1() returns int language sql as $$ select 0 $$;
create function security.enrich_parse_duration_v1(t text) returns jsonb language sql immutable as $$
  select case when t ~ '^\d+(\.\d+)? years?$' then jsonb_build_object('value', split_part(t, ' ', 1)::numeric, 'unit', 'years') end $$;
create function security.enrich_parse_level_v1(t text) returns uuid language sql immutable as $$ select case when t = 'Bachelor' then '00000000-0000-0000-0000-0000000000b1'::uuid end $$;
create function security.delivery_mode_read_v1(t text, p uuid) returns text language sql immutable as $$ select lower(t) $$;
-- the plan for a university: its steps (as live: label, group, estimate) and the open run
create table security.fx_plan_steps (provider_id uuid, steps jsonb);
create function security.enrich_plan_v1(p uuid) returns jsonb language sql stable as $$
  select jsonb_build_object('provider_id', p, 'name', 'U', 'country', 'AU', 'courses', 1, 'missing', 1, 'est_credits', 0, 'est_usd', 0,
    'steps', coalesce((select steps from security.fx_plan_steps where provider_id = p), '[]'::jsonb),
    'open_run', (select to_jsonb(r) from pipeline.enrich_plan_runs r where r.provider_id = p and r.state in ('queued', 'running'))) $$;
create function security.enrich_plan_tick_v1(p_run uuid default null) returns jsonb language sql as $$ select '{}'::jsonb $$;
-- public.admin_jobs, cut to the role check and the cancel path (live: a queued job is cancelled now, a running job when the runner next reaches it)
create function public.admin_jobs(p_action text, p_args jsonb default '{}') returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_rank int := security.current_role_rank(); v_j pipeline.admin_jobs%rowtype;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 4 then raise exception 'Operator or above required' using errcode = '42501'; end if;
  select * into v_j from pipeline.admin_jobs j where j.id = (p_args->>'id')::uuid;
  if v_j.id is null then raise exception 'unknown job'; end if;
  if v_rank < 5 and v_j.requested_by <> auth.uid() then raise exception 'only the person who started it, or an Operator, may change this job' using errcode = '42501'; end if;
  if p_action = 'cancel' then
    if v_j.state in ('done', 'failed', 'cancelled') then raise exception 'the job has already finished'; end if;
    if v_j.state in ('queued', 'paused') then update pipeline.admin_jobs set state = 'cancelled', finished_at = now(), cancel_requested = true where id = v_j.id;
    else update pipeline.admin_jobs set cancel_requested = true where id = v_j.id; end if;
    insert into pipeline.admin_job_events(job_id, note, detail) values (v_j.id, 'cancel by ' || auth.uid(), jsonb_build_object('reason', p_args->>'reason'));
  end if;
  return jsonb_build_object('ok', true);
end $$;
create function public.admin_provider_onboarding(p_action text default 'read', p_args jsonb default '{}') returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_action = 'stop' then
    update pipeline.provider_onboarding set status = 'cancelled', note = 'Stopped by a person: ' || (p_args->>'reason'), finished_at = now()
     where id = any (array(select x::uuid from jsonb_array_elements_text(p_args->'ids') x)) and status not in ('done', 'cancelled');
  end if;
  return '{}'::jsonb;
end $$;
-- the paste file's tables (shapes as live)
create table pipeline.refresh_policies (id uuid primary key, layer smallint, country_code text, enabled boolean, next_due_at timestamptz, updated_at timestamptz);
create table pipeline.refresh_requests (id uuid primary key default gen_random_uuid(), requested_layer smallint, country_code text, trigger_type text, status text,
  completed_at timestamptz, schedule_error text, created_at timestamptz default now(),
  check (status = any (array['queued', 'running', 'completed', 'cancelled', 'blocked', 'failed'])));
