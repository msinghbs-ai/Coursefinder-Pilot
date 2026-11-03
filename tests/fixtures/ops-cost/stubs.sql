-- CF-247 workstream F (cost and yield, 3 Nov 2026): the shapes the two edited live definitions and the new ops_cost_* functions read or
-- write, cut to the columns used (information_schema, production, read-only, 3 Nov 2026 15:43 AEDT). Helpers they only call are small
-- fixture-settable stand-ins (fx.*); the flag unit's raise and hold functions are the repository definitions. Never a Supabase project.
set check_function_bodies = off;
create extension if not exists pgcrypto;
create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists security; create schema if not exists auth;
create schema if not exists scholarship; create schema if not exists fx;
create or replace function auth.role() returns text language sql as $$ select 'service_role'::text $$;
do $$ begin if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; end $$;

create table pipeline.platform_toolset_settings (toolset_key text not null, key text not null, label text not null default '', help text not null default '', kind text not null, value jsonb not null,
  min_value numeric, max_value numeric, unit text, sort int not null default 100, reason text, updated_at timestamptz not null default now(),
  section text not null default 'Notices', used_by text, primary key (toolset_key, key));
create or replace function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable set search_path to '' as $$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $$;
create or replace function security.fc_setting_num_v1(p_key text, p_default numeric) returns numeric language sql stable set search_path to '' as $$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = p_key), p_default) $$;
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value) values
 ('firecrawl', 'daily_budget_on', 'boolean', 'true'), ('firecrawl', 'daily_budget_total', 'number', '25000'), ('pipeline', 'waste.retry_max_attempts', 'number', '3'),
 ('pipeline', 'waste.retry_min_yield_pct', 'number', '15'), ('pipeline', 'gaps.recheck_days', 'number', '60'), ('pipeline', 'flag.soft_tries', 'number', '2'),
 ('pipeline', 'search.skip_providers', 'list', '["provider:skip:1"]'), ('pipeline', 'budgets.ai_daily_ceiling_usd', 'number', '14');
create table pipeline.automation_catalogue (jobname text primary key, description text not null);
insert into pipeline.automation_catalogue values ('waste-guard', 'Waste rules: idle jobs, flip-flops, flags.');
create table pipeline.component_register (kind text not null, name text not null, layer text not null, purpose text, status text not null default 'active',
  replaces text[] not null default '{}', introduced_in text, primary key (kind, name));

-- catalogue
create table catalogue.providers (id uuid primary key default gen_random_uuid(), stable_key text, lifecycle_status text default 'active', publication_status text default 'published');
create table catalogue.courses (id uuid primary key default gen_random_uuid(), provider_id uuid, lifecycle_status text default 'active');
create table scholarship.scholarships (id uuid primary key default gen_random_uuid(), provider_id uuid);

-- spend and evidence
create table pipeline.layer2_acquisition_providers (id uuid primary key default gen_random_uuid(), provider_key text);
insert into pipeline.layer2_acquisition_providers(provider_key) values ('firecrawl');
create table pipeline.coverage_vendor_usage (id bigint generated always as identity primary key, acquisition_provider_id uuid, units numeric, purpose text, provider_id uuid, url text,
  at timestamptz not null default now(), on_demand_run uuid);
create table pipeline.firecrawl_budget_refusals (day date, grp text, reason text, n int, last_at timestamptz, primary key (day, grp, reason));
create table pipeline.firecrawl_refusals_by_provider (day date, provider_id uuid, grp text, reason text, n int, last_at timestamptz, primary key (day, provider_id, grp, reason));
create table pipeline.evidence_artifacts (id uuid primary key default gen_random_uuid(), source_url text, content_hash text, captured_at timestamptz default now());
create table pipeline.ai_spend_ledger (id bigint generated always as identity primary key, at timestamptz not null default now(), lane text, source text, source_id text, cost_usd numeric, calls int);
create table pipeline.layer3_openrouter_observations (id uuid primary key default gen_random_uuid(), kind text, remaining_usd numeric, observed_at timestamptz default now());
create table pipeline.enrich_plan_runs (id uuid primary key default gen_random_uuid(), provider_id uuid, mode text default 'auto', state text default 'done', steps jsonb default '[]',
  actual jsonb, created_at timestamptz default now());
create table pipeline.scholarship_pages (scholarship_id uuid, url text, requested_at timestamptz);
create table pipeline.provider_fact_sources (provider_id uuid, url text, status text, read_at timestamptz);
create table pipeline.entry_matrix_sources (provider_id uuid, url text, status text, read_at timestamptz);
create table pipeline.mode_outcome_ledger (id bigint generated always as identity primary key, run_at timestamptz default now(), mode text, ok int, failed int);

-- lanes
create table pipeline.field_enrich_items (id bigint generated always as identity primary key, job_id uuid, provider_id uuid, course_id uuid, field text, state text, source text,
  reason text, evidence_id uuid, attempts int default 1, cost_usd numeric, created_at timestamptz default now(), updated_at timestamptz default now());
create table pipeline.scholarship_ai_queue (id bigint generated always as identity primary key, provider_id uuid, state text, step int, attempts int default 0, created_at timestamptz default now(), done_at timestamptz);
create table pipeline.scholarship_ai_extractions (id bigint generated always as identity primary key, queue_id bigint, model_code text, prompt_version int, run_kind text,
  provider_id uuid, url text, content_hash text, cost_usd numeric, error text, at timestamptz default now());
create table pipeline.coverage_ai_match (id bigint generated always as identity primary key, course_id uuid, provider_id uuid, attempt int, state text, chosen_url text,
  cost_usd numeric, created_at timestamptz default now(), decided_at timestamptz);
create table pipeline.coverage_course_pages (course_id uuid primary key, provider_id uuid, url text, status text, read_at timestamptz, read_attempts int default 0, evidence_id uuid);
create table pipeline.course_link_search (course_id uuid primary key, provider_id uuid, state text, query text, attempts int default 0, done_at timestamptz);
create table pipeline.course_page_proofs (course_id uuid, page_key text, proven boolean, checked_at timestamptz default now());
create table pipeline.course_attribute_coverage (course_id uuid, provider_id uuid, attribute text, state text);
create table pipeline.scholarship_page_candidates (id bigint generated always as identity primary key, provider_id uuid, admit_status text, admitted_at timestamptz, read_at timestamptz,
  next_read_at timestamptz, storage_path text);
create table pipeline.scholarship_discovery_providers (provider_id uuid primary key, next_discover_at timestamptz);
create table pipeline.coverage_provider_urls (provider_id uuid, url text);
create table pipeline.admin_jobs (id uuid primary key default gen_random_uuid(), kind text, state text, args jsonb default '{}');
create table pipeline.enrich_value_retractions (item_id bigint, retracted_at timestamptz default now());
create table pipeline.course_url_fills (course_id uuid, filled_at timestamptz default now(), retracted_at timestamptz);
create table pipeline.fee_reader_queue (id uuid primary key default gen_random_uuid(), rows_found int, finished_at timestamptz);

-- flags (the flag unit's live shape, cut) and the raise and hold functions as the repository defines them
create table pipeline.enrichment_flags (id bigint generated always as identity primary key, entity text not null, entity_key text not null, provider_id uuid, field text not null default '',
  reason_code text not null, reason text, source text, flagged_at timestamptz not null default now(), cleared_at timestamptz, kind text, state text, tries int default 0, checks int default 0,
  evidence jsonb, next_check_at timestamptz, input_mark text, raised_by_kind text, released_at timestamptz, unique (entity, entity_key, field, reason_code));
create table pipeline.enrichment_flag_events (id bigint generated always as identity primary key, flag_id bigint, action text, actor text, actor_kind text, reason text, evidence jsonb, at timestamptz default now());
CREATE OR REPLACE FUNCTION security.flag_raise_v1(p_entity text, p_key text, p_provider_id uuid, p_field text, p_code text, p_reason text, p_kind text,
                                                 p_actor text, p_actor_kind text, p_evidence jsonb, p_input_mark text, p_next_check timestamptz)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f pipeline.enrichment_flags; v_state text; v_action text; v_tries int; v_soft int := security.pipeline_num_v1('flag.soft_tries', 2)::int;
begin
  perform set_config('cf.flag_fn', '1', true);
  select * into f from pipeline.enrichment_flags x where x.entity = p_entity and x.entity_key = p_key and x.field = coalesce(p_field, '') and x.reason_code = p_code for update;
  if not found then
    v_state := case when p_kind = 'hard' or v_soft <= 1 then 'raised' else 'counting' end;
    insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source, kind, state, tries, evidence, next_check_at, input_mark, raised_by_kind, cleared_at)
    values (p_entity, p_key, p_provider_id, coalesce(p_field, ''), p_code, p_reason, p_actor, p_kind, v_state, 1, coalesce(p_evidence, '{}'::jsonb), p_next_check, p_input_mark, p_actor_kind,
            case when v_state = 'raised' then null else now() end)
    returning * into f;
    v_action := case v_state when 'raised' then 'raised' else 'counted' end;
  elsif f.state = 'raised' then
    update pipeline.enrichment_flags set reason = p_reason, evidence = coalesce(p_evidence, evidence), input_mark = coalesce(p_input_mark, input_mark),
           next_check_at = coalesce(p_next_check, next_check_at) where id = f.id;
    v_state := 'raised';  -- already held: evidence refreshed, no new history line
  else
    v_tries := case when f.state = 'counting' then f.tries + 1 else 1 end;
    v_state := case when p_kind = 'hard' or v_tries >= v_soft then 'raised' else 'counting' end;
    update pipeline.enrichment_flags set reason = p_reason, source = p_actor, kind = p_kind, state = v_state, tries = v_tries, evidence = coalesce(p_evidence, '{}'::jsonb),
           next_check_at = p_next_check, input_mark = coalesce(p_input_mark, input_mark), raised_by_kind = p_actor_kind, flagged_at = now(),
           cleared_at = case when v_state = 'raised' then null else coalesce(cleared_at, now()) end,
           released_at = case when v_state = 'raised' then null else released_at end
     where id = f.id;
    v_action := case when v_state = 'counting' then 'counted' when f.state = 'released' then 're_raised' else 'raised' end;
  end if;
  if v_action is not null then
    insert into pipeline.enrichment_flag_events(flag_id, action, actor, actor_kind, reason, evidence) values (f.id, v_action, p_actor, p_actor_kind, p_reason, coalesce(p_evidence, '{}'::jsonb));
  end if;
  perform set_config('cf.flag_fn', '', true);
  return jsonb_build_object('id', f.id, 'state', v_state);
end $function$;

create or replace function security.enrich_item_held_v1(p_course uuid, p_field text)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select exists (select 1 from pipeline.enrichment_flags f
                  where f.entity = 'course' and f.entity_key = p_course::text and f.field in (p_field, '')
                    and ((f.state = 'raised' and f.reason_code in ('enrich_no_value', 'manual_hold'))
                         or (f.state = 'counting' and f.reason_code = 'enrich_no_value'
                             and f.flagged_at > now() - make_interval(days => security.pipeline_num_v1('gaps.recheck_days', 60)::int)
                             and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = p_course and g.evidence_id is not null
                                               and g.evidence_id::text is distinct from f.input_mark and g.read_at > f.flagged_at))))
$function$;

-- integration queue (the live upsert opens or re-observes one issue by fingerprint; cut to that)
create table pipeline.integration_issues (id bigint generated always as identity primary key, fingerprint text unique, title text, status text default 'detected', severity text,
  failure text, evidence jsonb, provider_ids jsonb, condition_cleared_at timestamptz, observed int default 1);
create or replace function security.integration_issue_upsert_v1(p jsonb, p_actor text default 'integration-validate') returns jsonb language plpgsql as $$
declare v_id bigint;
begin
  insert into pipeline.integration_issues(fingerprint, title, severity, failure, evidence, provider_ids) values (p->>'fingerprint', p->>'title', p->>'severity', p->>'failure', p->'evidence', p->'provider_ids')
  on conflict (fingerprint) do update set observed = pipeline.integration_issues.observed + 1, condition_cleared_at = null, failure = excluded.failure, evidence = excluded.evidence
  returning id into v_id;
  return jsonb_build_object('id', v_id);
end $$;

-- helpers the definitions only call: fixture-settable stand-ins
create table fx.knobs (k text primary key, v text);
create or replace function fx.knob(p text) returns text language sql stable as $$ select v from fx.knobs where k = p $$;
create or replace function security.fc_purpose_group_v1(p text) returns text language sql immutable set search_path = '' as $function$
  select case when p = 'course_link_search' then 'course_search'
              when p like 'sch\_%' then 'scholarships'
              when p in ('central_map', 'central_scrape') or p like 'provider\_facts%' then 'central'
              when p in ('scrape', 'fc_read', 'fc_probe', 'site_hint', 'adapter_builder', 'list_scrape') or p like 'fcx\_%' then 'reads'
              else 'other' end
$function$;
create or replace function security.fc_spend_host_v1(p text) returns text language sql stable as $$ select null::text $$;
create or replace function security.third_party_host_v1(p text) returns boolean language sql stable as $$ select false $$;
create or replace function security.fc_month_refusal_v1(p numeric) returns text language sql stable as $$ select fx.knob('month_refusal') $$;
create or replace function security.fc_on_demand_today_v1() returns numeric language sql stable as $$ select 0::numeric $$;
create or replace function security.fc_billed_today_v1() returns numeric language sql stable as $$ select 0::numeric $$;
create or replace function security.fc_budget_left_v1(p text) returns numeric language sql stable as $$ select coalesce(fx.knob('budget_left')::numeric, 100000) $$;
create or replace function security.fc_sch_cap_since_v1(p uuid) returns timestamptz language sql stable as $$ select now() - interval '30 days' $$;
create table fx.ineligible (provider_id uuid primary key);
create or replace function security.fc_sch_eligible_v1(p uuid) returns boolean language sql stable as $$ select not exists (select 1 from fx.ineligible where provider_id = p) $$;
create table fx.stopped (provider_id uuid primary key);
create or replace function security.fc_search_stopped_v1() returns table(provider_id uuid) language sql stable as $$ select provider_id from fx.stopped $$;
create or replace function security.search_stop_gate_v1(p uuid) returns text language sql stable as $$ select case when exists (select 1 from fx.stopped s where s.provider_id = p) then 'search_stopped' end $$;
create or replace function security.waste_idle_guard_v1() returns jsonb language sql as $$ select '{"paused": 0}'::jsonb $$;
create or replace function security.waste_flipflop_guard_v1() returns jsonb language sql as $$ select '{"frozen": 0}'::jsonb $$;
create or replace function security.enrichment_flags_refresh_v1() returns jsonb language sql as $$ select '{"outside_focus": 0}'::jsonb $$;
create or replace function security.ai_spend_today_v1() returns table(use text, label text, spent numeric, guard numeric, calls bigint) language sql stable as $$
  select l.lane, l.lane, sum(l.cost_usd), 0::numeric, sum(l.calls)::bigint from pipeline.ai_spend_ledger l where l.at >= date_trunc('day', now()) group by 1 $$;
-- the plan builder's unit costs: the live definition (read 3 Nov 2026 15:42 AEDT, md5 9ffc69020b6f84c3b4b0af11650b634f), cut to the keys used
create or replace function security.enrich_unit_costs_v1() returns jsonb language sql stable set search_path to '' as $$
  select jsonb_build_object('site_credits', 12.0, 'search_credits_per_course', 2.0, 'adapter_credits', 30.0, 'scholarship_credits', 40.0) $$;
