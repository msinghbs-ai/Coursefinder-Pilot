-- Decision 5 E-7/E-8/E-9 budget enforcement and watchdog: isolated fixture database (Platform Admin 2 Nov 2026 10:56). Run on a scratch
-- PostgreSQL only (never on a Supabase project): see run.sh. The smallest set of schemas, tables and helpers that the live definitions in
-- live-defs.json and the 20261102070000 migration use, with the columns they use. Helpers whose answer the edited functions take as given
-- (purpose groups, directory hosts, eligibility, the stop gate) are simple stand-ins. Nothing here is live data.
create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists security; create schema if not exists auth;
create schema if not exists cron; create schema if not exists ref; create schema if not exists scholarship; create schema if not exists fx;
do $$ begin create role anon; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated; exception when duplicate_object then null; end $$;
do $$ begin create role supabase_read_only_user; exception when duplicate_object then null; end $$;
create function auth.role() returns text language sql stable as $f$ select 'service_role'::text $f$;
create function auth.uid() returns uuid language sql stable as $f$ select null::uuid $f$;

-- settings (G2)
create table pipeline.platform_toolset_settings(toolset_key text, key text, label text, help text, kind text, value jsonb, min_value numeric, max_value numeric,
  unit text, sort int, section text, used_by text, reason text, updated_at timestamptz default now(), primary key (toolset_key, key));
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as
  $f$ select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $f$;
create function security.toolset_setting(p_toolset text, p_key text) returns jsonb language sql stable as
  $f$ select value from pipeline.platform_toolset_settings where toolset_key = p_toolset and key = p_key $f$;
create function security.fc_setting_num_v1(p_key text, p_default numeric) returns numeric language sql stable as
  $f$ select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = p_key), p_default) $f$;
create table pipeline.platform_toolsets(key text primary key, enforcement text);
-- live values read 2 Nov 2026 (settings, enforcement)
insert into pipeline.platform_toolsets values ('openrouter', 'observe');
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value, label, help, used_by) values
  ('openrouter', 'credit_floor_usd', 'number', '5', 'Credit floor', 'old help', 'old'), ('openrouter', 'guard_scholarship_ai', 'number', '20', null, null, null),
  ('openrouter', 'guard_adapter_builder', 'number', '5', 'Daily guard: adapter proposals', 'old help', 'old'), ('openrouter', 'guard_central_ai', 'number', '5', null, null, null),
  ('openrouter', 'guard_course_match', 'number', '5', 'Daily guard: AI course-page matching', 'old help', 'old'), ('openrouter', 'guard_enrich_fields', 'number', '25', null, null, null),
  ('openrouter', 'guard_fee_ai', 'number', '5', null, null, null), ('openrouter', 'guard_entry_matrix', 'number', '2', null, null, null),
  ('pipeline', 'budgets.ai_daily_ceiling_usd', 'number', '14', 'AI spend: daily ceiling', 'old help', 'old'), ('pipeline', 'targets.ai_credit_min_usd', 'number', '10', null, null, null),
  ('pipeline', 'alerts.collect_within_minutes', 'number', '120', null, null, null), ('pipeline', 'alerts.delivery_enabled', 'flag', 'true', null, null, null),
  ('firecrawl', 'daily_budget_on', 'flag', 'true', null, null, null), ('firecrawl', 'daily_budget_total', 'number', '25000', null, null, null),
  ('firecrawl', 'daily_share_course_search', 'number', '13000', null, null, null), ('firecrawl', 'daily_share_reads', 'number', '5000', null, null, null),
  ('firecrawl', 'daily_share_scholarships', 'number', '3500', null, null, null), ('firecrawl', 'daily_share_central', 'number', '2500', null, null, null),
  ('firecrawl', 'daily_share_other', 'number', '1000', null, null, null), ('firecrawl', 'ondemand_credits_per_day', 'number', '2000', null, null, null);

-- OpenRouter balance and the AI cost tables (columns as live)
create table pipeline.layer3_openrouter_observations(id bigserial primary key, kind text, remaining_usd numeric, observed_at timestamptz default now());
create table pipeline.scholarship_ai_extractions(id bigserial primary key, cost_usd numeric, at timestamptz default now());
create table pipeline.scholarship_ai_reviews(id bigserial primary key, status text, recheck jsonb, created_at timestamptz default now());
create table pipeline.uni_adapter_drafts(id uuid primary key default gen_random_uuid(), provider_id uuid, status text default 'capturing', samples jsonb default '[]',
  captures jsonb default '[]', marks jsonb default '[]', comments text, proposals jsonb default '[]', model text, model_profile text, cost_usd numeric default 0,
  reason text, created_by uuid, created_at timestamptz default now(), updated_at timestamptz default now());
create table pipeline.central_ai_queue(id bigserial primary key, state text default 'queued', cost_usd numeric, created_at timestamptz default now(), done_at timestamptz);
create table pipeline.coverage_ai_match(id bigserial primary key, course_id uuid, provider_id uuid, attempt int default 1, state text default 'ready', candidates jsonb,
  chosen_url text, answer jsonb, model text, cost_usd numeric, leased_until timestamptz, created_at timestamptz default now(), decided_at timestamptz);
create table pipeline.field_enrich_items(id bigserial primary key, state text default 'queued', cost_usd numeric, created_at timestamptz default now(), updated_at timestamptz default now());
create table pipeline.fee_reader_queue(id bigserial primary key, state text default 'queued', cost_usd numeric, created_at timestamptz default now(), finished_at timestamptz);
create table pipeline.entry_matrix_runs(id uuid primary key default gen_random_uuid(), state text default 'queued', cost_usd numeric default 0, created_at timestamptz default now(),
  updated_at timestamptz default now());

-- course-page matching (public.svc_coverage_ai_match_next, public.svc_coverage_ai_match_record)
create table catalogue.providers(id uuid primary key, display_name text, canonical_name text);
create table catalogue.courses(id uuid primary key, provider_id uuid, canonical_title text, course_code text, study_level_id int);
create table ref.study_levels(id int primary key, name text);
create table pipeline.course_priority(course_id uuid primary key, sort int);
create table pipeline.provider_priority(provider_id uuid primary key, rank int);
create table fx.hidden(provider_id uuid primary key);
create view security.provider_hidden_v1 as select provider_id from fx.hidden;
create function security.coverage_country(p uuid) returns text language sql stable as $f$ select 'AU'::text $f$;
create table pipeline.coverage_course_pages(course_id uuid primary key, provider_id uuid, url text, score numeric, runner_up text, basis text, status text,
  bound_at timestamptz, next_read_at timestamptz, read_attempts int, read_status text, identity_basis text, leased_until timestamptz);

-- worker calls (pg_net through the nonce): recorded, never sent
create table fx.fired(id bigserial primary key, fn text, body jsonb, at timestamptz default now());
create function pipeline.svc_pilot_submit_nonce(p_function text, p_body jsonb) returns bigint language sql as
  $f$ insert into fx.fired(fn, body) values (p_function, p_body) returning id $f$;

-- adapter builder helpers (public.admin_adapter_builder skeleton, see builder-skeleton.sql)
create table pipeline.admin_control_events(id bigserial primary key, area text, action text, target text, detail jsonb, actor uuid, at timestamptz default now());
create function security.adapter_builder_budget() returns jsonb language sql stable as
  $f$ select jsonb_build_object('used_usd', 0, 'limit_usd', 5, 'proposals', 0, 'limit_proposals', 20) $f$;
create function security.adapter_builder_model_for_v1(p uuid) returns jsonb language sql stable as
  $f$ select jsonb_build_object('model', 'fixture/model', 'code', 'fixture') $f$;

-- Firecrawl (security.fc_budget_left_v1, public.svc_fc_spend, security.layer2_provider_budget_status)
create table pipeline.layer2_acquisition_providers(id uuid primary key, provider_key text unique, billing_config jsonb, request_template jsonb);
create table pipeline.layer2_provider_attempts(id bigserial primary key, acquisition_provider_id uuid, started_at timestamptz default now(), created_at timestamptz default now());
create table pipeline.vendor_credit_observations(id bigserial primary key, provider_id uuid, remaining_units numeric, observed_at timestamptz default now());
create table pipeline.coverage_vendor_usage(id bigserial primary key, acquisition_provider_id uuid, units numeric, purpose text, provider_id uuid, url text,
  on_demand_run uuid, at timestamptz not null default now());
create table pipeline.enrich_plan_runs(id uuid primary key default gen_random_uuid(), provider_id uuid, mode text, state text);
create table pipeline.firecrawl_budget_refusals(day date, grp text, reason text, n int, last_at timestamptz, primary key (day, grp, reason));
create table pipeline.firecrawl_refusals_by_provider(day date, provider_id uuid, grp text, reason text, n int, last_at timestamptz, primary key (day, provider_id, grp, reason));
create table pipeline.scholarship_pages(scholarship_id uuid, url text, requested_at timestamptz);
create table scholarship.scholarships(id uuid primary key, provider_id uuid);
create table pipeline.provider_fact_sources(provider_id uuid, url text, status text, read_at timestamptz);
create table pipeline.entry_matrix_sources(provider_id uuid, url text, status text, read_at timestamptz);
-- stand-ins: the purpose groups as live for the purposes used here; no directory hosts; every provider eligible; no stop gate
create function security.fc_purpose_group_v1(p text) returns text language sql immutable as $f$
  select case when p in ('search', 'cricos_search', 'link_search') then 'course_search' when p in ('scrape', 'fc_read', 'fc_probe', 'site_hint', 'adapter_builder', 'list_scrape') then 'reads'
              when p like 'sch\_%' then 'scholarships' when p like 'central%' then 'central' else 'other' end $f$;
create function security.fc_spend_host_v1(p_url text) returns text language sql immutable as $f$ select substring(p_url from '^https?://([^/]+)') $f$;
create function security.third_party_host_v1(p_url text) returns boolean language sql immutable as $f$ select p_url like '%directory.example%' $f$;
create function security.fc_sch_eligible_v1(p uuid) returns boolean language sql stable as $f$ select true $f$;
create function security.fc_sch_cap_since_v1(p uuid) returns timestamptz language sql stable as $f$ select '-infinity'::timestamptz $f$;
create function security.search_stop_gate_v1(p uuid) returns text language sql stable as $f$ select null::text $f$;
create function security.fc_day_start_v1() returns timestamptz language sql stable as
  $f$ select date_trunc('day', now() at time zone 'Australia/Melbourne') at time zone 'Australia/Melbourne' $f$;
create function security.fc_billed_today_v1() returns numeric language sql stable as
  $f$ select coalesce(sum(units), 0) from pipeline.coverage_vendor_usage where at >= security.fc_day_start_v1() $f$;
create function security.fc_on_demand_today_v1() returns numeric language sql stable as
  $f$ select coalesce(sum(units), 0) from pipeline.coverage_vendor_usage where at >= security.fc_day_start_v1() and on_demand_run is not null $f$;
-- the Firecrawl provider as live (billing_config key fields only; id as live)
insert into pipeline.layer2_acquisition_providers values ('6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88', 'firecrawl',
  '{"monthly_vendor_units_limit": 500000, "stop_at_vendor_units_remaining": 2000, "no_silent_paid_fallback": true, "plan_note": "Growth plan, 500,000 credits a month as reported by Firecrawl (period 2 Oct to 2 Nov 2026)"}', '{}');

-- scheduler and alerts (security.platform_watchdog_v1)
create table cron.job(jobid bigserial primary key, jobname text unique, schedule text, command text, active boolean not null default true);
create table cron.job_run_details(runid bigserial primary key, jobid bigint, status text, start_time timestamptz, end_time timestamptz);
create table pipeline.platform_alerts(id bigserial primary key, kind text, severity text, title text, status text default 'pending', created_at timestamptz default now(),
  sent_at timestamptz, next_attempt_at timestamptz default now());
