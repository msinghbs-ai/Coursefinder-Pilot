-- CF-247 OPS/UI lane funnels: the minimum of the live schema (columns checked against project fxcwkweaxjtknorudmwp, 8 Nov 2026, read only) that
-- migration 20261108170000 reads. Stubs are marked STUB; pipeline_num_v1 and fc_purpose_group_v1 are the live definitions.
create schema if not exists auth; create schema if not exists security; create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists cron;
do $$ begin if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if; end $$;
-- STUB: the signed-in user and role rank are set per test with set_config('test.uid' / 'test.rank')
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid', true), '')::uuid $$;
create function security.current_role_rank() returns int language sql stable as $$ select coalesce(nullif(current_setting('test.rank', true), '')::int, 0) $$;

create table pipeline.platform_toolset_settings (toolset_key text not null, key text not null, label text, help text, kind text, value jsonb, min_value numeric, max_value numeric, unit text, sort int, reason text, updated_by uuid, updated_at timestamptz default now(), section text, used_by text, primary key (toolset_key, key));
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$ select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $$;
create table pipeline.automation_catalogue (jobname text primary key, area text, sort int, label text, description text, control_rank int, batch_editable boolean, layer23_stage text);
create table pipeline.component_register (kind text not null, name text not null, layer text, area text, purpose text, status text default 'active', replaces text[], replaced_by text, introduced_in text, primary key (kind, name));

-- STUB cron (pg_cron is not in the scratch database)
create table cron.job (jobid bigserial primary key, jobname text unique, schedule text, command text, active boolean default true);
create table cron.job_run_details (runid bigserial primary key, jobid bigint, start_time timestamptz, end_time timestamptz, status text, return_message text);
create function security.cron_next_run_v1(p_schedule text, p_after timestamptz) returns timestamptz language sql stable as $$ select case when p_schedule ~ ' ' then date_trunc('minute', p_after) + interval '1 minute' end $$;

create table pipeline.progress_transitions (key text primary key, chain text, step int, title text, producer_jobs text[], switch_keys text[], measured_at timestamptz, window_start timestamptz, input_eligible numeric, input_processed numeric, output_created numeric, output_rejected numeric, rejected_reasons jsonb, output_parked numeric, parked_next_actions jsonb, downstream_queued numeric, output_admitted numeric, output_published numeric, last_advanced_at timestamptz, zero_reason text, zero_detail text, stalled boolean not null default false, stalled_since timestamptz, issue_id bigint, measure_error text);
create table pipeline.release_job_verifications (id bigserial primary key, release text, jobname text, registered_at timestamptz default now(), expected_first_run timestamptz, first_run_at timestamptz, first_run_status text, actual_output numeric, status text, status_reason text, verified_at timestamptz);
create table pipeline.integration_issues (id bigserial primary key, issue_ref text, title text, severity text, status text, detected_at timestamptz default now(), closed_at timestamptz);

-- tables the stage SELECTs read
create table pipeline.course_intake_date_events (id bigserial primary key, run_at timestamptz default now(), outcome text, failure_class text);
create table pipeline.provider_fact_sources (id bigserial primary key, kind text, status text, created_at timestamptz default now());
create table pipeline.fee_reader_queue (id bigserial primary key, state text, created_at timestamptz default now());
create table pipeline.fee_reader_rows (id bigserial primary key, outcome text, created_at timestamptz default now());
create table pipeline.layer4_review_items (id uuid primary key default gen_random_uuid(), field_code text, status text, created_at timestamptz default now(), decided_at timestamptz);
create table pipeline.layer4_item_readiness (review_item_id uuid default gen_random_uuid(), field_code text, item_status text, readiness text, item_created_at timestamptz default now(), classified_at timestamptz default now());
create table pipeline.scholarship_coverage_items (provider_id uuid, item_key text, state text, present boolean default true, state_since timestamptz default now());
create table pipeline.course_link_search (id bigserial primary key, state text);
create table catalogue.courses (id uuid primary key default gen_random_uuid(), lifecycle_status text, description text, updated_at timestamptz default now());
create table catalogue.providers (id uuid primary key default gen_random_uuid(), lifecycle_status text, description text, updated_at timestamptz default now());
create table catalogue.course_fees (id uuid primary key default gen_random_uuid(), status text, created_at timestamptz default now(), updated_at timestamptz default now());
create table catalogue.course_english_requirements (id uuid primary key default gen_random_uuid(), course_id uuid, status text, last_verified_at timestamptz);
create table catalogue.course_entry_requirements (id uuid primary key default gen_random_uuid(), status text, updated_at timestamptz default now());
create table catalogue.course_links (id uuid primary key default gen_random_uuid(), created_at timestamptz default now());
create table catalogue.provider_rankings (id uuid primary key default gen_random_uuid(), verified_at timestamptz);

-- Firecrawl (STUBs of the Controller's functions, except fc_purpose_group_v1: live definition)
create table pipeline.layer2_acquisition_providers (id uuid primary key default gen_random_uuid(), provider_key text, billing_config jsonb);
create table pipeline.vendor_credit_observations (id bigserial primary key, provider_id uuid, remaining_units numeric, plan_units numeric, period_end timestamptz, observed_at timestamptz default now(), raw jsonb);
create table pipeline.coverage_vendor_usage (id bigserial primary key, acquisition_provider_id uuid, units numeric, purpose text, provider_id uuid, url text, at timestamptz default now(), on_demand_run uuid);
create function security.fc_purpose_group_v1(p text) returns text language sql immutable set search_path = '' as $$
  select case when p = 'course_link_search' then 'course_search' when p like 'sch\_%' then 'scholarships' when p in ('central_map', 'central_scrape') or p like 'provider\_facts%' then 'central'
              when p in ('scrape', 'fc_read', 'fc_probe', 'site_hint', 'adapter_builder', 'list_scrape') or p like 'fcx\_%' then 'reads' else 'other' end $$;
create function security.fc_day_start_v1() returns timestamptz language sql stable as $$ select date_trunc('day', now() at time zone 'Australia/Melbourne') at time zone 'Australia/Melbourne' $$;
create function security.fc_setting_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$ select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = p_key), p_default) $$;
create function security.fc_vendor_estimate_v1() returns numeric language sql stable as $$ select greatest(o.remaining_units - coalesce((select sum(u.units) from pipeline.coverage_vendor_usage u where u.at > o.observed_at), 0), 0) from pipeline.vendor_credit_observations o where o.observed_at > now() - interval '2 hours' order by o.observed_at desc limit 1 $$;
create function security.fc_priority_room_v1() returns numeric language sql stable as $$ select case when security.fc_setting_num_v1('priority_floor_course_search', 0) <= 0 then null else security.fc_vendor_estimate_v1() - security.fc_setting_num_v1('priority_floor_course_search', 0) end $$;
create function security.fc_budget_left_v1(p_purpose text) returns numeric language sql stable as $$ select greatest(0, security.fc_setting_num_v1('daily_share_' || security.fc_purpose_group_v1(p_purpose), 0) - coalesce((select sum(units) from pipeline.coverage_vendor_usage x where x.at >= security.fc_day_start_v1() and security.fc_purpose_group_v1(x.purpose) = security.fc_purpose_group_v1(p_purpose) and x.on_demand_run is null), 0)) $$;
create function security.fc_budget_status_v1() returns jsonb language sql stable as $$
  with g(grp, label, sort) as (values ('course_search', 'Finding course pages', 1), ('reads', 'Reading pages', 2), ('scholarships', 'Scholarships', 3), ('central', 'Central pages', 4), ('other', 'Other', 5)),
       u as (select security.fc_purpose_group_v1(x.purpose) grp, sum(x.units) used from pipeline.coverage_vendor_usage x where x.at >= security.fc_day_start_v1() group by 1)
  select jsonb_build_object('on', true, 'day_start', security.fc_day_start_v1(), 'total', security.fc_setting_num_v1('daily_budget_total', 15000), 'billed_today', 0, 'used_today', (select coalesce(sum(used), 0) from u),
    'groups', (select jsonb_agg(jsonb_build_object('group', g.grp, 'label', g.label, 'share', security.fc_setting_num_v1('daily_share_' || g.grp, 0), 'used', coalesce(u.used, 0), 'refused', 0) order by g.sort) from g left join u on u.grp = g.grp)) $$;
create function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint language sql as $$ insert into cron.job(jobname, schedule, command) values (p_name, p_schedule, p_command) on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command returning jobid $$;
create table if not exists pipeline.field_enrich_items (id uuid primary key default gen_random_uuid(), field text, state text, reason text, updated_at timestamptz default now());
