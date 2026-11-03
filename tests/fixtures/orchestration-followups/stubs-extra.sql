-- Orchestration follow-ups (IQ-00066, IQ-00053 residual, IQ-00063; CF-247, 3 Nov 2026): the live shapes the seven edited definitions read, cut
-- to the columns used, added to the Release A stubs (../plan-step-lane-hold/stubs.sql). The reader gates the scholarship scan check calls
-- (security.fc_sch_held_v1, fc_sch_eligible_v1, provider_sch_search_off_v1, third_party_host_v1) are not edited here: they are stand-ins
-- the fixture sets per provider (fx.sch_gate). pdesc_words_v1 and pdesc_similarity_v1 are the live definitions (md5 checked in run.sh).
alter table pipeline.admin_jobs alter column scope type text using scope #>> '{}';
insert into pipeline.automation_catalogue values ('enrich-plan-auto', 'Automatic enrichment plans.'), ('enrich-plan-run', 'Enrichment plan runner.'),
  ('provider-onboarding', 'Provider onboarding.') on conflict do nothing;
-- (plans.retry_waits_for_change, as live, and tasks.stall_seconds come from the Release A stubs) tasks.lane_hold_on as live (on)
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value) values ('pipeline', 'tasks.lane_hold_on', 'number', '1') on conflict (toolset_key, key) do update set value = excluded.value;

-- providers, courses and what the plan builder reads
alter table catalogue.providers add column display_name text, add column canonical_name text, add column lifecycle_status text default 'active';
alter table catalogue.courses add column duration_value numeric, add column study_level_id uuid, add column delivery_mode text, add column primary_field_id uuid,
  add column open_to_international boolean, add column description text, add column updated_at timestamptz default now();
create table catalogue.course_campuses (course_id uuid);
create table pipeline.uni_adapters (provider_id uuid primary key, enabled boolean, admit boolean, admit_fields text[]);
alter table pipeline.provider_onboarding add column provider_id uuid, add column created_at timestamptz default now(), add column job_id uuid, add column note text,
  add column step_started_at timestamptz, add column updated_at timestamptz default now(), add column attempts int default 0, add column result jsonb default '{}',
  add column priority int default 0, add column started_at timestamptz, add column requested_by uuid, add column source text default 'backfill';
alter table pipeline.provider_central_search add column searched_at timestamptz;
alter table pipeline.coverage_course_pages add column course_id uuid, add column evidence_id uuid, add column read_at timestamptz;
alter table pipeline.coverage_provider_discovery add column website text;
create or replace function security.coverage_country(p uuid) returns text language sql stable as $$ select 'AU'::text $$;
create or replace function security.enrich_unit_costs_v1() returns jsonb language sql stable as $$
  select '{"site_credits": 5, "search_credits_per_course": 2, "adapter_credits": 10, "adapter_usd": 0.5, "enrich_usd_per_item": 0.001, "scholarship_credits": 20, "scholarship_usd": 0.1}'::jsonb $$;
create or replace function security.enrich_item_held_v1(p_course uuid, p_field text) returns boolean language sql stable as $$ select false $$;

-- the scholarship reader's discovery, candidates and listing pages (live columns used)
alter table pipeline.scholarship_discovery_providers add column next_discover_at timestamptz, add column discovered_at timestamptz, add column kept_count int,
  add column website text, add column leased_until timestamptz, add column priority int, add column reason text, add column updated_at timestamptz;
alter table pipeline.scholarship_page_candidates add column read_status text;
create table pipeline.scholarship_listing_pages (provider_id uuid, url text, active boolean, source text, next_read_at timestamptz);
-- security.fc_sch_held_v1 and provider_sch_search_off_v1 are the live definitions (live/); what they read: the Firecrawl day-budget switch and
-- the scholarship cap (settings), the usage, the cap period start and the eligibility rule (stand-in: fx.ineligible lists the providers below
-- scholarship_min_courses), and the per-provider search switch
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value) values ('firecrawl', 'daily_budget_on', 'boolean', 'true'), ('firecrawl', 'scholarship_cap_per_uni', 'number', '150');
create table fx.ineligible (provider_id uuid primary key);
create or replace function security.fc_sch_eligible_v1(p uuid) returns boolean language sql stable as $$ select not exists (select 1 from fx.ineligible where provider_id = p) $$;
create or replace function security.fc_sch_cap_since_v1(p uuid) returns timestamptz language sql stable as $$ select now() - interval '30 days' $$;
create table pipeline.provider_scholarship_search (provider_id uuid primary key, enabled boolean);
create or replace function security.third_party_host_v1(p text) returns boolean language sql immutable as $$ select coalesce(p, '') ~* 'studyabroad-directory' $$;

-- onboarding tick (live shapes; the step itself is a stand-in that records it was called)
create table pipeline.provider_onboarding_settings (id int primary key, enabled boolean, max_active int, run_as uuid);
insert into pipeline.provider_onboarding_settings values (1, true, 5, gen_random_uuid());
create or replace function security.adapter_builder_budget() returns jsonb language sql stable as $$ select '{"used_usd": 0, "limit_usd": 1, "proposals": 0, "limit_proposals": 5}'::jsonb $$;
create table pipeline.provider_policy_proposals (provider_id uuid, status text, decided_at timestamptz);
create table fx.stepped (id uuid, at timestamptz default clock_timestamp());
create or replace function security.provider_onboarding_step_v1(p_id uuid) returns void language plpgsql as $$
begin insert into fx.stepped(id) values (p_id); end $$;

-- Pipeline yield (the parts it joins are stand-ins)
create or replace function auth.uid() returns uuid language sql stable as $$ select '00000000-0000-0000-0000-000000000001'::uuid $$;
create or replace function security.current_role_rank() returns int language sql stable as $$ select 9 $$;
create or replace function security.pipeline_yield_v1(p int) returns jsonb language sql stable as $$ select '{"stages": []}'::jsonb $$;
create or replace function security.lane_status_v1() returns jsonb language sql stable as $$ select '{"lanes": []}'::jsonb $$;
create or replace function security.field_backlog_v1(p text) returns jsonb language sql stable as $$ select '{"fields": []}'::jsonb $$;

-- the course description check (the checks before the duplicate scan are stand-ins that pass; pdesc words and similarity are live)
create or replace function security.toolset_setting(p_toolset text, p_key text) returns jsonb language sql stable as $$
  select s.value from pipeline.platform_toolset_settings s where s.toolset_key = p_toolset and s.key = p_key $$;
create or replace function security.pdesc_has_term_v1(p_text text, p_term text) returns boolean language sql immutable as $$ select false $$;
create or replace function security.pdesc_support_v1(p_text text, p_quote text) returns numeric language sql immutable as $$ select 1::numeric $$;
create table pipeline.layer4_review_items (id bigint generated always as identity, entity_type text, entity_id uuid, field_code text, status text, proposed_value jsonb, created_at timestamptz default now());
