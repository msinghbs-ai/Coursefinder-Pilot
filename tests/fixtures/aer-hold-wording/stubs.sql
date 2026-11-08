-- Minimal stand-ins (shape only) for what the two hold functions read before the Firecrawl hold; the Firecrawl budget functions are controlled by settings of this fixture.
\set ON_ERROR_STOP 1
create schema if not exists pipeline; create schema if not exists cron; create schema if not exists auth; create schema if not exists catalogue;
create table cron.job(jobname text, active boolean);
insert into cron.job values ('course-link-search-worker', true);
create table pipeline.enrichment_flags(entity text, entity_key text, reason_code text, state text, flagged_at timestamptz, next_check_at timestamptz);
create table pipeline.admin_jobs(kind text, state text, args jsonb);
create table pipeline.course_link_search_settings(id int primary key, enabled boolean, monthly_credit_cap numeric);
insert into pipeline.course_link_search_settings values (1, true, 100000);
create table pipeline.coverage_vendor_usage(purpose text, units numeric, at timestamptz);
create table pipeline.course_link_search(provider_id uuid, state text, requested_at timestamptz, sent_at timestamptz);
create table pipeline.firecrawl_target_cache(provider_id uuid, included boolean);
create table public.fx_settings(k text primary key, v numeric);
-- the two Firecrawl numbers this fixture controls: the credits left today (share) and the room above the floor (null = no floor / no fresh balance)
create function security.fc_budget_left_v1(p text) returns numeric language sql as $$ select least((select v from public.fx_settings where k = 'share_left'), coalesce((select v from public.fx_settings where k = 'room'), 1e12)) $$;
create function security.fc_priority_room_v1() returns numeric language sql as $$ select (select v from public.fx_settings where k = 'room') $$;
create function security.fc_setting_num_v1(p_key text, p_default numeric) returns numeric language sql as $$ select coalesce((select v from public.fx_settings where k = p_key), p_default) $$;
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql as $$ select p_default $$;
create function security.firecrawl_setting(p text) returns jsonb language sql as $$ select 'false'::jsonb $$;
create function security.enrich_focus_v1(p uuid) returns boolean language sql as $$ select true $$;
create function security.fc_search_stopped_v1() returns table(provider_id uuid) language sql as $$ select null::uuid where false $$;
create function security.current_role_rank() returns int language sql as $$ select 6 $$;
create function auth.uid() returns uuid language sql as $$ select 'c0ffee00-0000-4000-8000-000000000150'::uuid $$;
