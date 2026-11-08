-- CF-247 SCH/DISC fixtures: the live shapes this change calls that the shared coverage stubs do not carry. Live text where it is short and stable; otherwise a
-- stub of the live behaviour named in its comment.
create table if not exists pipeline.provider_scholarship_search (provider_id uuid primary key, enabled boolean not null, auto boolean not null default false, reason text, set_by uuid, set_at timestamptz default now());
-- live (8 Nov 2026), verbatim
create or replace function security.provider_sch_search_off_v1(p_provider uuid) returns boolean language sql stable security definer set search_path to '' as $function$
  select exists (select 1 from pipeline.provider_scholarship_search f where f.provider_id = p_provider and not f.enabled)
$function$;
-- security.pipeline_list_v1(text, jsonb): a setting holding a JSON array of text, else the default (live behaviour)
create or replace function security.pipeline_list_v1(p_key text, p_default jsonb) returns text[] language sql stable security definer set search_path to '' as $function$
  select coalesce((select array_agg(e) from jsonb_array_elements_text(coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key and jsonb_typeof(s.value) = 'array'), p_default)) e), '{}'::text[])
$function$;
-- security.lane_paid_hold_v1(purpose): the reason a paid lane is held by its Firecrawl share or reserve, else null; here driven by a one-row table
create table if not exists pipeline.fx_lane_hold (purpose text primary key, reason text);
create or replace function security.lane_paid_hold_v1(p_purpose text) returns text language sql stable security definer set search_path to '' as $function$
  select (select h.reason from pipeline.fx_lane_hold h where h.purpose = p_purpose)
$function$;
-- security.fc_sch_eligible_v1(provider): live rule outside the pilot proposals: not Australian, or at least scholarship_min_courses (30) active courses; here a table lists the ineligible
create table if not exists pipeline.fx_sch_ineligible (provider_id uuid primary key);
create or replace function security.fc_sch_eligible_v1(p_provider_id uuid) returns boolean language sql stable security definer set search_path to '' as $function$
  select not exists (select 1 from pipeline.fx_sch_ineligible x where x.provider_id = p_provider_id)
$function$;
-- pipeline.layer4_interventions: the columns security.scholarship_coverage_items_v1 reads (human-assisted recovery, live)
create table if not exists pipeline.layer4_interventions (id bigint generated always as identity primary key, lane text, entity text, missing_fact text, status text);
