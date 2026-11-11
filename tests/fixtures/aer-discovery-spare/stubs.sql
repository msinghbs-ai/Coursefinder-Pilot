-- CF-247 F-AER.04 D2 fixture: what public.svc_fc_spend's central path reads, beyond tests/fixtures/aer-discovery-campaign/stubs.sql (shapes as live, fewer columns)
alter table pipeline.coverage_vendor_usage add column if not exists acquisition_provider_id uuid, add column if not exists on_demand_run uuid;
alter table pipeline.entry_matrix_sources add column if not exists created_at timestamptz default now();
create table pipeline.enrich_plan_runs (id uuid primary key default gen_random_uuid(), provider_id uuid, mode text, state text);
create table pipeline.firecrawl_budget_refusals (day date, grp text, reason text, n int, last_at timestamptz, primary key (day, grp, reason));
create table pipeline.firecrawl_refusals_by_provider (day date, provider_id uuid, grp text, reason text, n int, last_at timestamptz, primary key (day, provider_id, grp, reason));
create table pipeline.layer2_acquisition_providers (id uuid primary key default gen_random_uuid(), provider_key text);
insert into pipeline.layer2_acquisition_providers(provider_key) values ('firecrawl');
create table pipeline.fx_vendor (room numeric);  -- the fixture's vendor balance above the floor (null: no fresh balance)
insert into pipeline.fx_vendor values (null);
create or replace function security.fc_purpose_group_v1(p text) returns text language sql immutable as $$ select case when p like 'central%' then 'central' when p = 'scrape' then 'reads' else 'other' end $$;
create function security.fc_setting_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$ select coalesce((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'firecrawl' and key = p_key), p_default) $$;
create function security.fc_day_start_v1() returns timestamptz language sql stable set search_path = '' as $$ select date_trunc('day', now() at time zone 'Australia/Melbourne') at time zone 'Australia/Melbourne' $$;
create function security.fc_billed_today_v1() returns numeric language sql stable as $$ select coalesce(sum(units), 0) from pipeline.coverage_vendor_usage where at >= security.fc_day_start_v1() $$;
create function security.fc_on_demand_today_v1() returns numeric language sql stable as $$ select coalesce(sum(units), 0) from pipeline.coverage_vendor_usage where at >= security.fc_day_start_v1() and on_demand_run is not null $$;
create function security.fc_priority_room_v1() returns numeric language sql stable as $$ select room from pipeline.fx_vendor $$;
create function security.fc_budget_left_v1(p_purpose text) returns numeric language sql stable as $$
  select case when security.fc_billed_today_v1() >= security.fc_setting_num_v1('daily_budget_total', 15000) then 0
              else greatest(0, security.fc_setting_num_v1('daily_share_' || security.fc_purpose_group_v1(p_purpose), 0)
                   - (select coalesce(sum(units), 0) from pipeline.coverage_vendor_usage where at >= security.fc_day_start_v1() and on_demand_run is null
                       and security.fc_purpose_group_v1(purpose) = security.fc_purpose_group_v1(p_purpose))) end $$;
create function security.fc_spend_host_v1(p text) returns text language sql immutable as $$ select null::text $$;
create function security.fc_month_refusal_v1(p numeric) returns text language sql stable as $$ select null::text $$;
create function security.ops_cost_fc_refusal_v1(a numeric, b text, c uuid, d text) returns text language sql stable as $$ select null::text $$;
create function security.fc_sch_eligible_v1(p uuid) returns boolean language sql stable as $$ select true $$;
create function security.fc_sch_cap_since_v1(p uuid) returns timestamptz language sql stable as $$ select now() $$;
create function security.search_stop_gate_v1(p uuid) returns text language sql stable as $$ select 'open'::text $$;
create table pipeline.provider_fact_sources (provider_id uuid, url text, status text, read_at timestamptz);
insert into pipeline.platform_toolset_settings(toolset_key, key, value) values
 ('firecrawl', 'daily_budget_on', 'true'), ('firecrawl', 'daily_budget_total', '100'), ('firecrawl', 'daily_share_central', '20'),
 ('firecrawl', 'daily_share_reads', '20'), ('firecrawl', 'daily_share_other', '10'), ('firecrawl', 'central_refresh_days', '30');
create schema if not exists scholarship;
create table scholarship.scholarships (id uuid primary key default gen_random_uuid(), provider_id uuid);
create table pipeline.scholarship_pages (scholarship_id uuid, url text, requested_at timestamptz);
