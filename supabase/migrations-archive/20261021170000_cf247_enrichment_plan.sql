-- CF-247 (21 Oct 2026). Platform Admin 12:03: "feature: build a functionality to tackle end to end data enrichment for universities or steps
-- if its achievable right now. idea is automation is gated by toolset configurable limits but manual should decide on screen of required
-- toolset usage but can do it on demand." Choices: "Own on-demand allowance (Recommended)", "All, most missing first (Recommended)",
-- "Universities row + plan tab (Recommended)".
-- Every step already exists on its own; this joins them per university, in order, with the toolset cost shown first.
--   1 security.enrich_plan_v1(provider): the university's plan from its own gaps, in order: 1 Website, contacts and central pages (task
--     provider_fill); 2 Find course pages (course_page_find); 3 Build the adapter (onboarding: start, or retry when stopped); 4 Admit (a
--     person, Layer 2/3 › Universities); 5 Fill missing fields (an Enrich fields task for this university, AI on, new reads allowed);
--     6 Scholarships (scholarship_provider_scan). Each step says why it is needed, which fields it fills and its estimate in Firecrawl
--     credits and AI US$, from what the same step actually used in the last 30 days (security.enrich_unit_costs_v1).
--   2 pipeline.enrich_plan_runs: a run of chosen steps for one university, manual (Run now) or automatic. job enrich-plan-run (every 5
--     minutes) starts each step in turn with the existing task or onboarding call and moves on when it has finished; it records what each
--     step used (Firecrawl credits, AI US$) and the fields gained.
--   3 Manual runs use their own allowance: while a university has a manual run, its Firecrawl spends are charged to the on-demand allowance
--     (firecrawl.ondemand_credits_per_day, 2,000) instead of the daily shares and per-university caps (a directory site is still never
--     paid for); the shares and the day's budget left for automation leave on-demand spends out. Run now is refused when the plan's
--     estimate is more than what is left today of the on-demand credits or AI (openrouter.ondemand_usd_per_day, US$10). (One branch added to
--     public.svc_fc_spend, two lines in security.fc_budget_left_v1; md5-guarded. Column coverage_vendor_usage.on_demand_run.)
--   4 Automatic plans (job enrich-plan-auto, hourly, while switched on): universities with gaps, most missing values first (then world
--     ranking), plans.auto_open_max (20) open at once, plans.auto_per_run (10) started an hour; a university is planned again after
--     plans.redo_days (14). An automatic step starts only when its toolset share has room for its estimate today, and waits otherwise
--     (skipped after plans.step_wait_hours, 48). Switched on and off on Layer 2/3 › Enrichment plan by the Platform Admin, with a reason.
--   5 public.admin_enrich_plan: list (priority), plan, run (Pipeline Operator), cancel, runs, control (Platform Admin).
-- Steps started on a person's behalf run as that person (manual: who pressed Run now; automatic: the Platform Admin who switched
-- automation on), with the same role checks as from their own screens.
-- Replaces: public.svc_fc_spend (on-demand branch added); security.fc_budget_left_v1 (on-demand spends left out)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

do $guard$
declare v_expected jsonb := '{"public.svc_fc_spend(numeric,text,uuid,text)": "61769c033f9f51f3521dc3c53a210735",
                              "security.fc_budget_left_v1(text)": "2441df624ddce7880a8d19451aeac767"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(pg_get_functiondef(v_sig::regprocedure)) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- Settings -----------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('firecrawl', 'ondemand_credits_per_day', 'On-demand allowance (Run now)', 'Firecrawl credits a day for runs a person starts with Run now on Layer 2/3 › Enrichment plan. Kept apart from the daily shares, so manual and automatic work do not use up each other''s credits.', 'number', to_jsonb(2000), 0, 20000, 'credits', 90, 'CF-247, Platform Admin 21 Oct 2026 "Own on-demand allowance (Recommended)"', 'Daily budget', 'svc_fc_spend; Layer 2/3 › Enrichment plan › Run now'),
 ('openrouter', 'ondemand_usd_per_day', 'On-demand allowance (Run now)', 'AI US$ a day for runs a person starts with Run now on Layer 2/3 › Enrichment plan; Run now is refused when the plan''s estimate is more than what is left today.', 'number', to_jsonb(10), 0, 200, 'US$ a day', 90, 'CF-247, Platform Admin 21 Oct 2026 "Own on-demand allowance (Recommended)"', 'Daily guards', 'Layer 2/3 › Enrichment plan › Run now'),
 ('pipeline', 'plans.auto_open_max', 'Automatic enrichment plans open at once', 'The most automatic university plans running at the same time.', 'number', to_jsonb(20), 0, 500, 'universities', 120, 'CF-247, Platform Admin 21 Oct 2026 "All, most missing first (Recommended)"', 'Onboarding', 'job enrich-plan-auto'),
 ('pipeline', 'plans.auto_per_run', 'Automatic enrichment plans started an hour', 'University plans the hourly planner starts, most missing values first.', 'number', to_jsonb(10), 0, 200, 'universities', 121, 'CF-247, Platform Admin 21 Oct 2026 "All, most missing first (Recommended)"', 'Onboarding', 'job enrich-plan-auto'),
 ('pipeline', 'plans.redo_days', 'Plan a university again after', 'Days after an automatic plan finished before the same university is planned again.', 'number', to_jsonb(14), 1, 180, 'days', 122, 'CF-247, Platform Admin 21 Oct 2026', 'Onboarding', 'job enrich-plan-auto'),
 ('pipeline', 'plans.step_wait_hours', 'Skip an automatic step waiting for budget after', 'An automatic step waits for room in its toolset share; after this many hours it is skipped and the plan moves on.', 'number', to_jsonb(48), 1, 336, 'hours', 123, 'CF-247, Platform Admin 21 Oct 2026', 'Onboarding', 'job enrich-plan-run'),
 ('pipeline', 'plans.step_max_hours', 'An enrichment plan step finishes within', 'A step still running after this many hours is marked as timed out and the plan moves on (its task keeps running).', 'number', to_jsonb(24), 1, 336, 'hours', 124, 'CF-247, Platform Admin 21 Oct 2026', 'Onboarding', 'job enrich-plan-run')
on conflict (toolset_key, key) do nothing;

-- Tables --------------------------------------------------------------------------------------------------------------------------------
alter table pipeline.coverage_vendor_usage add column if not exists on_demand_run uuid;
comment on column pipeline.coverage_vendor_usage.on_demand_run is 'CF-247 21 Oct 2026: the manual enrichment plan run this spend was charged to (on-demand allowance); null for automatic spends, which count against the daily shares.';
create index if not exists idx_coverage_vendor_usage_on_demand on pipeline.coverage_vendor_usage(at) where on_demand_run is not null;

create table if not exists pipeline.enrich_plan_runs (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  mode text not null check (mode in ('manual', 'auto')),
  state text not null default 'queued' check (state in ('queued', 'running', 'done', 'failed', 'cancelled')),
  steps jsonb not null,                 -- [{step, label, status, ref, started_at, finished_at, est_credits, est_usd, note}]
  estimate jsonb not null default '{}'::jsonb,
  actual jsonb not null default '{}'::jsonb,
  fields_before jsonb,
  fields_after jsonb,
  requested_by uuid not null,
  reason text not null,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  updated_at timestamptz not null default now());
alter table pipeline.enrich_plan_runs enable row level security;
create unique index if not exists enrich_plan_runs_one_open on pipeline.enrich_plan_runs(provider_id) where state in ('queued', 'running');
comment on table pipeline.enrich_plan_runs is 'CF-247 21 Oct 2026: a run of a university''s enrichment plan (manual Run now or automatic): its steps in order, each step''s task or onboarding reference, status, estimate and what it used; the fields before and after. One open run per university.';

create table if not exists pipeline.enrich_plan_control (
  id int primary key default 1 check (id = 1),
  auto_enabled boolean not null default true,
  owner uuid not null,
  reason text not null,
  updated_at timestamptz not null default now());
alter table pipeline.enrich_plan_control enable row level security;
comment on table pipeline.enrich_plan_control is 'CF-247 21 Oct 2026: automatic enrichment plans on or off and who switched them (automatic steps run as that Platform Admin). Changed on Layer 2/3 › Enrichment plan with a reason.';
insert into pipeline.enrich_plan_control(id, auto_enabled, owner, reason)
select 1, true, ur.user_id, 'CF-247 21 Oct 2026: Platform Admin "All, most missing first (Recommended)"'
  from security.user_roles ur join security.roles r on r.code = ur.role_code
 where r.rank = 6 and r.status = 'active' and (ur.expires_at is null or ur.expires_at > now()) order by ur.user_id limit 1
on conflict (id) do nothing;

-- On-demand Firecrawl -------------------------------------------------------------------------------------------------------------------
create or replace function security.fc_on_demand_today_v1()
 returns numeric
 language sql
 stable security definer
 set search_path to ''
as $function$
  select coalesce(sum(x.units), 0) from pipeline.coverage_vendor_usage x where x.on_demand_run is not null and x.at >= security.fc_day_start_v1()
$function$;
revoke execute on function security.fc_on_demand_today_v1() from public, anon, authenticated;

select pg_temp.edit_once('security.fc_budget_left_v1(text)', '2441df624ddce7880a8d19451aeac767', array[
  array[$x$  if security.fc_billed_today_v1() >= security.fc_setting_num_v1('daily_budget_total', 15000) then return 0; end if;$x$,
        $x$  -- CF-247 21 Oct 2026: on-demand spends (manual enrichment plan runs) have their own allowance and do not use up the automatic budget
  if security.fc_billed_today_v1() - security.fc_on_demand_today_v1() >= security.fc_setting_num_v1('daily_budget_total', 15000) then return 0; end if;$x$],
  array[$x$where x.at >= security.fc_day_start_v1() and security.fc_purpose_group_v1(x.purpose) = v_grp;$x$,
        $x$where x.at >= security.fc_day_start_v1() and security.fc_purpose_group_v1(x.purpose) = v_grp and x.on_demand_run is null;$x$]]);

select pg_temp.edit_once('public.svc_fc_spend(numeric,text,uuid,text)', '61769c033f9f51f3521dc3c53a210735', array[
  array[$x$declare v_grp text := security.fc_purpose_group_v1(p_purpose); v_why text; v_host text := security.fc_spend_host_v1(p_url);$x$,
        $x$declare v_grp text := security.fc_purpose_group_v1(p_purpose); v_why text; v_host text := security.fc_spend_host_v1(p_url);
  -- CF-247 21 Oct 2026: a university with a manual enrichment plan run spends from the on-demand allowance
  v_od uuid := case when p_provider_id is null then null else (select r.id from pipeline.enrich_plan_runs r where r.provider_id = p_provider_id and r.mode = 'manual' and r.state = 'running' limit 1) end;$x$],
  array[$x$  elsif p_provider_id is not null and p_purpose in ('sch_map', 'sch_search') and not security.fc_sch_eligible_v1(p_provider_id) then$x$,
        $x$  elsif v_od is not null then
    -- on demand: the person saw the estimate and chose to run it; the daily shares and per-university caps do not apply, the allowance does
    perform pg_advisory_xact_lock(hashtext('fc_spend:on_demand'));
    if security.fc_on_demand_today_v1() + p_units > security.fc_setting_num_v1('ondemand_credits_per_day', 2000) then v_why := 'on_demand_allowance'; end if;
  elsif p_provider_id is not null and p_purpose in ('sch_map', 'sch_search') and not security.fc_sch_eligible_v1(p_provider_id) then$x$],
  array[$x$  insert into pipeline.coverage_vendor_usage(acquisition_provider_id, units, purpose, provider_id, url)
  select id, p_units, p_purpose, p_provider_id, left(p_url, 500) from pipeline.layer2_acquisition_providers where provider_key = 'firecrawl';$x$,
        $x$  insert into pipeline.coverage_vendor_usage(acquisition_provider_id, units, purpose, provider_id, url, on_demand_run)
  select id, p_units, p_purpose, p_provider_id, left(p_url, 500), v_od from pipeline.layer2_acquisition_providers where provider_key = 'firecrawl';$x$]]);

-- Unit costs and the plan ------------------------------------------------------------------------------------------------------------
create or replace function security.enrich_unit_costs_v1()
 returns jsonb
 language sql
 stable security definer
 set search_path to ''
as $function$
  -- what each kind of step actually used, last 30 days (estimates follow the platform, nothing is typed in)
  with u as (select security.fc_purpose_group_v1(x.purpose) g, x.purpose, x.units, x.provider_id from pipeline.coverage_vendor_usage x where x.at > now() - interval '30 days')  -- fixed: estimate window
  select jsonb_build_object(
    'site_credits', round(coalesce((select sum(units) / nullif(count(distinct provider_id), 0) from u where g in ('other', 'central')), 0), 1),
    'search_credits_per_course', round(coalesce((select sum(units) / nullif(count(*), 0) from u where purpose = 'course_link_search'), 0), 2),
    'adapter_credits', round(coalesce((select sum(units) / nullif(count(distinct provider_id), 0) from u where g = 'reads'), 0), 1),
    'scholarship_credits', round(coalesce((select sum(units) / nullif(count(distinct provider_id), 0) from u where g = 'scholarships'), 0), 1),
    'enrich_usd_per_item', coalesce((select round(avg(coalesce(e.cost_usd, 0)), 5) from pipeline.field_enrich_items e where e.updated_at > now() - interval '30 days' and e.state in ('filled', 'skipped', 'review', 'failed')), 0),
    'adapter_usd', coalesce((select round(sum(d.cost_usd) / nullif(count(distinct d.provider_id), 0), 4) from pipeline.uni_adapter_drafts d where d.created_at > now() - interval '30 days'), 0),
    'scholarship_usd', coalesce((select round(sum(s.cost_usd) / nullif(count(distinct s.provider_id), 0), 4) from pipeline.scholarship_ai_extractions s where s.at > now() - interval '30 days'), 0))
$function$;
revoke execute on function security.enrich_unit_costs_v1() from public, anon, authenticated;

create or replace function security.enrich_provider_fields_v1(p_provider uuid)
 returns jsonb
 language sql
 stable security definer
 set search_path to ''
as $function$
  -- filled and missing values per field for one university (the hourly coverage build), fields with a reader only
  select coalesce(jsonb_object_agg(a.attribute, jsonb_build_object('filled', a.f, 'missing', a.m)), '{}'::jsonb)
    from (select x.attribute, count(*) filter (where x.state = 'admitted') f, count(*) filter (where x.state <> 'admitted') m
            from pipeline.course_attribute_coverage x join pipeline.field_register r on r.field = x.attribute and r.reader in ('coverage', 'enrich')
           where x.provider_id = p_provider group by 1) a
$function$;
revoke execute on function security.enrich_provider_fields_v1(uuid) from public, anon, authenticated;

create or replace function security.enrich_plan_v1(p_provider uuid)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare p record; c jsonb := security.enrich_unit_costs_v1(); f jsonb := security.enrich_provider_fields_v1(p_provider); v_steps jsonb := '[]'::jsonb;
        v_courses int; v_site boolean; v_contact boolean; v_central timestamptz; v_url_missing int; v_onb record; v_ad record; v_items int; v_nopage int;
        v_sch int; v_sch_scan timestamptz;
begin
  select pr.id, coalesce(pr.display_name, pr.canonical_name) name, security.coverage_country(pr.id) cc, nullif(btrim(pr.website), '') website,
         nullif(btrim(pr.phone), '') is not null or nullif(btrim(pr.email), '') is not null has_contact
    into p from catalogue.providers pr where pr.id = p_provider;
  if p.id is null then return null; end if;
  select count(*) into v_courses from catalogue.courses c2 where c2.provider_id = p_provider and c2.lifecycle_status = 'active';
  select s.searched_at into v_central from pipeline.provider_central_search s where s.provider_id = p_provider and s.state = 'done';
  -- 1 website, contacts and central pages
  if p.website is null or not p.has_contact or v_central is null or v_central < now() - interval '30 days' then  -- fixed: the central-page refresh interval (central_refresh_days) is 30
    v_steps := v_steps || jsonb_build_object('step', 'site', 'label', 'Website, contacts and central pages',
      'why', case when p.website is null then 'No website known' when v_central is null then 'Central pages (fees, English, calendar) never searched'
                  when v_central < now() - interval '30 days' then 'Central pages last searched ' || to_char(v_central, 'DD Mon YYYY') else 'No public phone or email' end,
      'fields', jsonb_build_array('p_website', 'p_contact', 'provider_tuition', 'english', 'intakes'), 'est_credits', c->'site_credits', 'est_usd', 0, 'group', 'other');
  end if;
  -- 2 course pages
  v_url_missing := coalesce((f->'official_url'->>'missing')::int, 0);
  if v_url_missing > 0 then
    v_steps := v_steps || jsonb_build_object('step', 'pages', 'label', 'Find course pages',
      'why', v_url_missing || ' of ' || v_courses || ' courses have no course page', 'fields', jsonb_build_array('official_url'),
      'est_credits', round(v_url_missing * (c->>'search_credits_per_course')::numeric, 0), 'est_usd', 0, 'group', 'course_search',
      'blocked', case when p.website is null then 'Needs a website first (step 1)' end);
  end if;
  -- 3 adapter (onboarding) and 4 admit
  select a.enabled, a.admit, coalesce(jsonb_array_length(to_jsonb(a.admit_fields)), 0) n into v_ad from pipeline.uni_adapters a where a.provider_id = p_provider;
  select o.status, o.stop_reason into v_onb from pipeline.provider_onboarding o where o.provider_id = p_provider order by o.created_at desc limit 1;
  if not coalesce(v_ad.admit, false) then
    if v_onb.status = 'waiting_admit' then
      v_steps := v_steps || jsonb_build_object('step', 'admit', 'label', 'Admit the adapter', 'why', 'The adapter passed; a person admits it on Layer 2/3 › Universities',
        'fields', jsonb_build_array('provider_tuition', 'english', 'intakes', 'duration'), 'est_credits', 0, 'est_usd', 0, 'group', 'none', 'person', true);
    else
      v_steps := v_steps || jsonb_build_object('step', 'adapter', 'label', 'Build the adapter (onboarding)',
        'why', case when v_onb.status is null then 'No adapter yet' when v_onb.status = 'stopped' then 'Onboarding stopped: ' || replace(coalesce(v_onb.stop_reason, 'unknown'), '_', ' ')
                    when v_onb.status in ('done', 'cancelled') then 'No admitting adapter' else 'Onboarding running: ' || v_onb.status end,
        'fields', jsonb_build_array('provider_tuition', 'english', 'intakes', 'duration', 'campus'), 'est_credits', c->'adapter_credits', 'est_usd', c->'adapter_usd', 'group', 'reads',
        'running', v_onb.status is not null and v_onb.status not in ('done', 'cancelled', 'stopped', 'waiting_admit'),
        'blocked', case when p.website is null then 'Needs a website first (step 1)' end);
    end if;
  end if;
  -- 5 fields Enrich fields fills
  select count(*) into v_items from (
    select 1 from catalogue.courses c3 cross join unnest(array['campus', 'duration', 'level', 'delivery', 'field_of_study', 'international']) x(fld)
     where c3.provider_id = p_provider and c3.lifecycle_status = 'active'
       and case x.fld when 'campus' then not exists (select 1 from catalogue.course_campuses k where k.course_id = c3.id)
                      when 'duration' then c3.duration_value is null when 'level' then c3.study_level_id is null
                      when 'delivery' then nullif(btrim(c3.delivery_mode), '') is null when 'field_of_study' then c3.primary_field_id is null
                      else c3.open_to_international is null end
       and not security.enrich_item_held_v1(c3.id, x.fld)) z;  -- held: tried on the same page already (until the page changes or gaps.recheck_days)
  if v_items > 0 then
    select count(*) into v_nopage from catalogue.courses c4 where c4.provider_id = p_provider and c4.lifecycle_status = 'active'
       and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c4.id and g.evidence_id is not null);
    v_steps := v_steps || jsonb_build_object('step', 'fields', 'label', 'Fill missing fields (stored pages, AI, new reads)',
      'why', v_items || ' missing values in duration, delivery, campus, level, field of study or international not yet tried on the current page',
      'fields', jsonb_build_array('duration', 'delivery', 'campus', 'campus_city', 'level', 'field_of_study', 'international'),
      'est_credits', least(v_nopage, v_items), 'est_usd', round(v_items * (c->>'enrich_usd_per_item')::numeric, 3), 'group', 'reads');
  end if;
  -- 6 scholarships
  select count(*) into v_sch from scholarship.scholarships s where s.provider_id = p_provider and s.lifecycle_status = 'active';
  select max(j.created_at) into v_sch_scan from pipeline.admin_jobs j where j.kind = 'scholarship_provider_scan' and j.scope = p_provider::text;
  if v_sch = 0 and (v_sch_scan is null or v_sch_scan < now() - interval '30 days') then  -- fixed: the scholarship cap period is 30 days
    v_steps := v_steps || jsonb_build_object('step', 'scholarships', 'label', 'Find and read scholarships',
      'why', case when v_sch_scan is null then 'No scholarships and never searched' else 'No scholarships; last searched ' || to_char(v_sch_scan, 'DD Mon YYYY') end,
      'fields', jsonb_build_array('p_scholarships'), 'est_credits', c->'scholarship_credits', 'est_usd', c->'scholarship_usd', 'group', 'scholarships',
      'blocked', case when p.website is null then 'Needs a website first (step 1)' end);
  end if;
  return jsonb_build_object('provider_id', p.id, 'name', p.name, 'country', p.cc, 'website', p.website,
    'courses', (select count(*) from catalogue.courses c5 where c5.provider_id = p_provider and c5.lifecycle_status = 'active'),
    'fields', f, 'missing', (select coalesce(sum((v->>'missing')::int), 0) from jsonb_each(f) e(k, v)),
    'steps', v_steps,
    'est_credits', (select coalesce(sum((x->>'est_credits')::numeric), 0) from jsonb_array_elements(v_steps) x),
    'est_usd', (select coalesce(round(sum((x->>'est_usd')::numeric), 3), 0) from jsonb_array_elements(v_steps) x),
    'unit_costs', c,
    'open_run', (select to_jsonb(r) - 'steps' || jsonb_build_object('steps', r.steps) from pipeline.enrich_plan_runs r where r.provider_id = p_provider and r.state in ('queued', 'running')));
end $function$;
revoke execute on function security.enrich_plan_v1(uuid) from public, anon, authenticated;

-- The runner -------------------------------------------------------------------------------------------------------------------------
create or replace function security.enrich_plan_start_step_v1(p_run uuid, p_step text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare r pipeline.enrich_plan_runs%rowtype; v jsonb; v_o record; v_fields jsonb;
begin
  select * into r from pipeline.enrich_plan_runs where id = p_run;
  -- the step runs as the person behind the run, with that person's role checks
  perform set_config('request.jwt.claims', json_build_object('sub', r.requested_by, 'role', 'authenticated')::text, true);
  if p_step = 'site' then
    v := public.admin_jobs('start', jsonb_build_object('kind', 'provider_fill', 'from', 'Enrichment plan', 'args', jsonb_build_object('provider_id', r.provider_id)));
    return jsonb_build_object('kind', 'job', 'id', v->>'id');
  elsif p_step = 'pages' then
    v := public.admin_jobs('start', jsonb_build_object('kind', 'course_page_find', 'from', 'Enrichment plan', 'args', jsonb_build_object('provider_id', r.provider_id)));
    return jsonb_build_object('kind', 'job', 'id', v->>'id');
  elsif p_step = 'scholarships' then
    v := public.admin_jobs('start', jsonb_build_object('kind', 'scholarship_provider_scan', 'from', 'Enrichment plan', 'args', jsonb_build_object('provider_ids', jsonb_build_array(r.provider_id))));
    return jsonb_build_object('kind', 'job', 'id', v->>'id');
  elsif p_step = 'fields' then
    v := public.admin_enrich_fields('start', jsonb_build_object('provider_ids', jsonb_build_array(r.provider_id), 'fields', to_jsonb(array(select e.field from security.enrich_fields_v1() e where e.field <> 'provider_address')),
                                    'ai', true, 'scraper', true, 'reason', 'Enrichment plan (' || r.mode || '): ' || r.reason));
    return jsonb_build_object('kind', 'job', 'id', v->>'job_id', 'items', v->'items');
  elsif p_step = 'adapter' then
    select o.id, o.status into v_o from pipeline.provider_onboarding o where o.provider_id = r.provider_id order by o.created_at desc limit 1;
    if v_o.status = 'stopped' then
      v := public.admin_provider_onboarding('retry', jsonb_build_object('ids', jsonb_build_array(v_o.id), 'reason', 'Enrichment plan (' || r.mode || '): ' || r.reason));
    elsif v_o.status is null or v_o.status in ('done', 'cancelled') then
      v := public.admin_provider_onboarding('start', jsonb_build_object('provider_ids', jsonb_build_array(r.provider_id), 'reason', 'Enrichment plan (' || r.mode || '): ' || r.reason));
    end if;
    return jsonb_build_object('kind', 'onboarding', 'id', (select o.id from pipeline.provider_onboarding o where o.provider_id = r.provider_id order by o.created_at desc limit 1));
  end if;
  raise exception 'unknown step %', p_step;
end $function$;
revoke execute on function security.enrich_plan_start_step_v1(uuid, text) from public, anon, authenticated;

create or replace function security.enrich_plan_tick_v1(p_run uuid default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare r pipeline.enrich_plan_runs%rowtype; s jsonb; i int; v_ref jsonb; v_state text; v_done int := 0; v_started int := 0; v_room numeric; v_note text;
        v_wait int := security.pipeline_num_v1('plans.step_wait_hours', 48)::int; v_max int := security.pipeline_num_v1('plans.step_max_hours', 24)::int;
begin
  for r in select * from pipeline.enrich_plan_runs where state in ('queued', 'running') and (p_run is null or id = p_run) order by created_at for update skip locked loop
    if r.state = 'queued' then
      update pipeline.enrich_plan_runs set state = 'running', started_at = now(), updated_at = now(), fields_before = security.enrich_provider_fields_v1(r.provider_id) where id = r.id;
      r.state := 'running';
    end if;
    -- the first step not finished
    i := (select min(o - 1) from jsonb_array_elements(r.steps) with ordinality e(x, o) where x->>'status' in ('pending', 'waiting', 'running'));
    if i is null then
      update pipeline.enrich_plan_runs set state = 'done', finished_at = now(), updated_at = now(), fields_after = security.enrich_provider_fields_v1(r.provider_id),
             actual = jsonb_build_object(
               'credits', (select coalesce(sum(x.units), 0) from pipeline.coverage_vendor_usage x where x.provider_id = r.provider_id and x.at between r.started_at and now()),
               'credits_on_demand', (select coalesce(sum(x.units), 0) from pipeline.coverage_vendor_usage x where x.on_demand_run = r.id),
               'usd', round(coalesce((select sum(e.cost_usd) from pipeline.field_enrich_items e where e.provider_id = r.provider_id and e.updated_at between r.started_at and now()), 0)
                          + coalesce((select sum(d.cost_usd) from pipeline.uni_adapter_drafts d where d.provider_id = r.provider_id and d.created_at between r.started_at and now()), 0)
                          + coalesce((select sum(x.cost_usd) from pipeline.scholarship_ai_extractions x where x.provider_id = r.provider_id and x.at between r.started_at and now()), 0), 4))
       where id = r.id;
      insert into search.refresh_requests(requested_by) values ('enrichment plan ' || left(r.id::text, 8) || ' finished');
      v_done := v_done + 1; continue;
    end if;
    s := r.steps->i;
    if s->>'status' in ('pending', 'waiting') then
      v_note := null;
      if (s->>'person')::boolean then
        v_state := 'person';  -- a person's step: shown, not waited for
      elsif nullif(s->>'blocked', '') is not null and exists (select 1 from catalogue.providers p where p.id = r.provider_id and nullif(btrim(p.website), '') is null) then
        v_state := 'skipped'; v_note := s->>'blocked';
      elsif r.mode = 'auto' and s->>'group' not in ('none') and coalesce((s->>'est_credits')::numeric, 0) > 0
            and security.fc_budget_left_v1(case s->>'group' when 'course_search' then 'course_link_search' when 'scholarships' then 'sch_scrape' when 'reads' then 'scrape' when 'central' then 'central_map' else 'other' end)
                < least((s->>'est_credits')::numeric, security.fc_setting_num_v1('daily_share_' || (s->>'group'), 0)) then
        -- automatic: wait for room in the toolset share
        v_state := case when coalesce((s->>'waiting_since')::timestamptz, now()) < now() - make_interval(hours => v_wait) then 'skipped' else 'waiting' end;
        v_note := case when v_state = 'skipped' then 'no room in the ' || (s->>'group') || ' share for ' || v_wait || ' hours' else 'waiting for room in the ' || (s->>'group') || ' share' end;
      else
        begin
          v_ref := security.enrich_plan_start_step_v1(r.id, s->>'step');
          v_state := 'running'; v_started := v_started + 1;
        exception when others then
          v_state := 'failed'; v_note := left(sqlerrm, 300);
        end;
      end if;
      update pipeline.enrich_plan_runs set updated_at = now(),
             steps = jsonb_set(steps, array[i::text], (steps->i) || jsonb_build_object('status', v_state, 'note', v_note)
                       || case when v_state = 'running' then jsonb_build_object('ref', v_ref, 'started_at', now()) else '{}'::jsonb end
                       || case when v_state = 'waiting' and not (steps->i ? 'waiting_since') then jsonb_build_object('waiting_since', now()) else '{}'::jsonb end
                       || case when v_state in ('person', 'skipped', 'failed') then jsonb_build_object('finished_at', now()) else '{}'::jsonb end)
       where id = r.id;
    elsif s->>'status' = 'running' then
      v_state := case
        when s->'ref'->>'kind' = 'job' then (select case when j.state in ('done') then 'done' when j.state in ('failed', 'cancelled') then j.state end
                                               from pipeline.admin_jobs j where j.id = (s->'ref'->>'id')::uuid)
        when s->'ref'->>'kind' = 'onboarding' then (select case when o.status in ('waiting_admit', 'done', 'scholarships') then 'done' when o.status = 'stopped' then 'stopped' when o.status = 'cancelled' then 'cancelled' end
                                                      from pipeline.provider_onboarding o where o.id = (s->'ref'->>'id')::uuid) end;
      if v_state is null and (s->>'started_at')::timestamptz < now() - make_interval(hours => v_max) then v_state := 'timed_out'; end if;
      if v_state is not null then
        update pipeline.enrich_plan_runs set updated_at = now(),
               steps = jsonb_set(steps, array[i::text], (steps->i) || jsonb_build_object('status', v_state, 'finished_at', now(),
                         'note', case v_state when 'stopped' then 'onboarding stopped: ' || coalesce((select o.stop_reason from pipeline.provider_onboarding o where o.id = (s->'ref'->>'id')::uuid), '')
                                              when 'timed_out' then 'still running after ' || v_max || ' hours; the task carries on' end))
         where id = r.id;
      end if;
    end if;
  end loop;
  return jsonb_build_object('finished', v_done, 'started', v_started);
end $function$;
revoke execute on function security.enrich_plan_tick_v1(uuid) from public, anon, authenticated;

-- The planner ------------------------------------------------------------------------------------------------------------------------
create or replace function security.enrich_plan_priority_v1()
 returns table(provider_id uuid, name text, country text, courses bigint, missing bigint, best_rank int)
 language sql
 stable security definer
 set search_path to ''
as $function$
  select a.provider_id, max(coalesce(p.display_name, p.canonical_name)), max(a.country_code), count(distinct a.course_id),
         count(*) filter (where a.state <> 'admitted'),
         (select min(coalesce(o.rank_low, o.rank_exact)) from ranking.observation_provider_links l join ranking.observations o on o.id = l.observation_id where l.provider_id = a.provider_id)
    from pipeline.course_attribute_coverage a join pipeline.field_register r on r.field = a.attribute and r.reader in ('coverage', 'enrich')
    join catalogue.providers p on p.id = a.provider_id
   where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = a.provider_id)
   group by a.provider_id
  having count(*) filter (where a.state <> 'admitted') > 0
$function$;
revoke execute on function security.enrich_plan_priority_v1() from public, anon, authenticated;

create or replace function security.enrich_plan_auto_v1()
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare c pipeline.enrich_plan_control%rowtype; v_open int; v_room int; v_n int := 0; q record; v_plan jsonb; v_steps jsonb;
begin
  select * into c from pipeline.enrich_plan_control where id = 1;
  if not coalesce(c.auto_enabled, false) then return jsonb_build_object('auto', 'off'); end if;
  select count(*) into v_open from pipeline.enrich_plan_runs where mode = 'auto' and state in ('queued', 'running');
  v_room := least(security.pipeline_num_v1('plans.auto_open_max', 20)::int - v_open, security.pipeline_num_v1('plans.auto_per_run', 10)::int);
  if v_room <= 0 then return jsonb_build_object('auto', 'full', 'open', v_open); end if;
  for q in select x.* from security.enrich_plan_priority_v1() x
            where not exists (select 1 from pipeline.enrich_plan_runs r where r.provider_id = x.provider_id
                               and (r.state in ('queued', 'running') or (r.mode = 'auto' and r.created_at > now() - make_interval(days => security.pipeline_num_v1('plans.redo_days', 14)::int))))
            order by x.missing desc, x.best_rank nulls last limit v_room * 3 loop
    exit when v_n >= v_room;
    v_plan := security.enrich_plan_v1(q.provider_id);
    v_steps := (select coalesce(jsonb_agg(x || jsonb_build_object('status', 'pending')), '[]'::jsonb) from jsonb_array_elements(v_plan->'steps') x where not coalesce((x->>'running')::boolean, false));
    continue when jsonb_array_length(v_steps) = 0 or (select bool_and(coalesce((x->>'person')::boolean, false)) from jsonb_array_elements(v_steps) x);
    insert into pipeline.enrich_plan_runs(provider_id, mode, steps, estimate, requested_by, reason)
    values (q.provider_id, 'auto', v_steps, jsonb_build_object('credits', v_plan->'est_credits', 'usd', v_plan->'est_usd', 'missing', q.missing), c.owner,
            'Automatic enrichment plan (most missing first): ' || c.reason)
    on conflict do nothing;
    if found then v_n := v_n + 1; end if;
  end loop;
  return jsonb_build_object('auto', 'on', 'started', v_n, 'open', v_open + v_n);
end $function$;
revoke execute on function security.enrich_plan_auto_v1() from public, anon, authenticated;

-- Screen ---------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_enrich_plan(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_pid uuid := nullif(p_args->>'provider', '')::uuid; v_reason text := btrim(coalesce(p_args->>'reason', ''));
        v_plan jsonb; v_steps jsonb; v_est_c numeric; v_est_u numeric; v_left_c numeric; v_left_u numeric; v_id uuid; v_cc text := upper(nullif(btrim(coalesce(p_args->>'country', '')), ''));
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  v_left_c := greatest(0, security.fc_setting_num_v1('ondemand_credits_per_day', 2000) - security.fc_on_demand_today_v1());
  v_left_u := greatest(0, coalesce((security.toolset_setting('openrouter', 'ondemand_usd_per_day'))::text::numeric, 0)
                          - coalesce((select sum(coalesce((r.actual->>'usd')::numeric, (r.estimate->>'usd')::numeric, 0)) from pipeline.enrich_plan_runs r
                                       where r.mode = 'manual' and r.created_at >= security.fc_day_start_v1()), 0));
  if p_action = 'overview' then
    return jsonb_build_object(
      'auto', (select jsonb_build_object('enabled', c.auto_enabled, 'reason', c.reason, 'at', c.updated_at) from pipeline.enrich_plan_control c where c.id = 1),
      'open', jsonb_build_object('auto', (select count(*) from pipeline.enrich_plan_runs where mode = 'auto' and state in ('queued', 'running')),
                                 'manual', (select count(*) from pipeline.enrich_plan_runs where mode = 'manual' and state in ('queued', 'running'))),
      'on_demand', jsonb_build_object('credits', security.fc_setting_num_v1('ondemand_credits_per_day', 2000), 'credits_used', security.fc_on_demand_today_v1(), 'credits_left', v_left_c,
                                      'usd', (security.toolset_setting('openrouter', 'ondemand_usd_per_day'))::text::numeric, 'usd_left', v_left_u),
      'shares', (select jsonb_object_agg(g, jsonb_build_object('share', security.fc_setting_num_v1('daily_share_' || g, 0), 'left', security.fc_budget_left_v1(pp)))
                   from (values ('course_search', 'course_link_search'), ('reads', 'scrape'), ('central', 'central_map'), ('scholarships', 'sch_scrape'), ('other', 'other')) v(g, pp)),
      'limits', jsonb_build_object('open_max', security.pipeline_num_v1('plans.auto_open_max', 20), 'per_run', security.pipeline_num_v1('plans.auto_per_run', 10),
                                   'redo_days', security.pipeline_num_v1('plans.redo_days', 14), 'wait_hours', security.pipeline_num_v1('plans.step_wait_hours', 48)),
      'unit_costs', security.enrich_unit_costs_v1(), 'can_run', v_rank >= 4, 'can_manage', v_rank >= 6);
  elsif p_action = 'list' then
    return jsonb_build_object('items', (select coalesce(jsonb_agg(z order by z.missing desc, z.best_rank nulls last), '[]'::jsonb) from (
      select x.provider_id, x.name, x.country, x.courses, x.missing, x.best_rank,
             (select jsonb_build_object('id', r.id, 'mode', r.mode, 'state', r.state, 'created_at', r.created_at, 'finished_at', r.finished_at,
                       'step', (select e->>'label' from jsonb_array_elements(r.steps) e where e->>'status' in ('pending', 'waiting', 'running') limit 1))
                from pipeline.enrich_plan_runs r where r.provider_id = x.provider_id order by r.created_at desc limit 1) last_run
        from security.enrich_plan_priority_v1() x
       where (v_cc is null or x.country = v_cc) and (coalesce(p_args->>'query', '') = '' or x.name ilike '%' || (p_args->>'query') || '%')
       order by x.missing desc, x.best_rank nulls last
       limit least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200) offset greatest(coalesce((p_args->>'offset')::int, 0), 0)) z));
  elsif p_action = 'plan' then
    if v_pid is null then raise exception 'choose a university'; end if;
    return security.enrich_plan_v1(v_pid) || jsonb_build_object('on_demand', jsonb_build_object('credits_left', v_left_c, 'usd_left', v_left_u),
      'runs', (select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc), '[]'::jsonb) from (select * from pipeline.enrich_plan_runs where provider_id = v_pid order by created_at desc limit 10) r),
      'can_run', v_rank >= 4);
  elsif p_action = 'run' then
    if v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept with the run)'; end if;
    v_plan := security.enrich_plan_v1(v_pid);
    if v_plan is null then raise exception 'choose a university'; end if;
    if v_plan->'open_run' is not null and v_plan->>'open_run' <> 'null' then raise exception 'a plan is already running for this university'; end if;
    v_steps := (select coalesce(jsonb_agg(x || jsonb_build_object('status', 'pending')), '[]'::jsonb) from jsonb_array_elements(v_plan->'steps') x
                 where x->>'step' in (select jsonb_array_elements_text(coalesce(p_args->'steps', '[]'::jsonb))));
    if jsonb_array_length(v_steps) = 0 then raise exception 'choose at least one step'; end if;
    select coalesce(sum((x->>'est_credits')::numeric), 0), coalesce(sum((x->>'est_usd')::numeric), 0) into v_est_c, v_est_u from jsonb_array_elements(v_steps) x;
    if v_est_c > v_left_c then raise exception 'the estimate (% credits) is more than the on-demand allowance left today (% credits); lower the steps, or raise the allowance on Models & services › Toolsets & limits', round(v_est_c), round(v_left_c); end if;
    if v_est_u > v_left_u then raise exception 'the estimate (US$%) is more than the on-demand AI allowance left today (US$%)', round(v_est_u, 2), round(v_left_u, 2); end if;
    insert into pipeline.enrich_plan_runs(provider_id, mode, steps, estimate, requested_by, reason)
    values (v_pid, 'manual', v_steps, jsonb_build_object('credits', v_est_c, 'usd', v_est_u), auth.uid(), v_reason) returning id into v_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('enrich_plan', 'run', v_pid::text, jsonb_build_object('run', v_id, 'steps', p_args->'steps', 'estimate_credits', v_est_c, 'estimate_usd', v_est_u, 'reason', v_reason), auth.uid());
    perform security.enrich_plan_tick_v1(v_id);  -- the first step starts now (this run only)
    return jsonb_build_object('run_id', v_id, 'estimate', jsonb_build_object('credits', v_est_c, 'usd', v_est_u));
  elsif p_action = 'cancel' then
    if v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
    update pipeline.enrich_plan_runs set state = 'cancelled', finished_at = now(), updated_at = now(), reason = reason || ' · cancelled: ' || coalesce(nullif(v_reason, ''), 'by a person')
     where id = (p_args->>'run_id')::uuid and state in ('queued', 'running');
    return jsonb_build_object('cancelled', found);
  elsif p_action = 'control' then
    if v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    update pipeline.enrich_plan_control set auto_enabled = coalesce((p_args->>'auto')::boolean, auto_enabled), owner = auth.uid(), reason = v_reason, updated_at = now() where id = 1;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('enrich_plan', case when (p_args->>'auto')::boolean then 'auto_on' else 'auto_off' end, 'enrich-plan-auto', jsonb_build_object('reason', v_reason), auth.uid());
    return public.admin_enrich_plan('overview', '{}'::jsonb);
  end if;
  raise exception 'unknown action %', p_action using errcode = '22023';
end $function$;
revoke execute on function public.admin_enrich_plan(text, jsonb) from public, anon;
grant execute on function public.admin_enrich_plan(text, jsonb) to authenticated;

-- Jobs, catalogue, register --------------------------------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('enrich-plan-run', 'Course pages', 31, 'Enrichment plans: run the steps', 'Every 5 minutes: starts the next step of each open university plan (manual or automatic) with the existing task or onboarding, and moves on when it has finished; automatic steps wait for room in their toolset share. Layer 2/3 › Enrichment plan.', 6, false),
 ('enrich-plan-auto', 'Course pages', 32, 'Enrichment plans: start automatic plans', 'Hourly, while switched on: starts plans for the universities with the most missing values (then world ranking), within the limits on Pipeline settings › Onboarding. Layer 2/3 › Enrichment plan.', 6, false)
on conflict (jobname) do nothing;
select cron.schedule('enrich-plan-run', '*/5 * * * *', $$select security.enrich_plan_tick_v1()$$);
select cron.schedule('enrich-plan-auto', '41 * * * *', $$select security.enrich_plan_auto_v1()$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('table', 'pipeline.enrich_plan_runs', 'Layer 2', 'University enrichment plan runs (manual and automatic)', 'active', '20261021170000'),
 ('table', 'pipeline.enrich_plan_control', 'Layer 2', 'Automatic enrichment plans on or off', 'active', '20261021170000'),
 ('function', 'security.enrich_plan_v1', 'Layer 2', 'A university''s enrichment plan from its gaps, with estimates', 'active', '20261021170000'),
 ('function', 'security.enrich_unit_costs_v1', 'Layer 2', 'What each enrichment step used in the last 30 days', 'active', '20261021170000'),
 ('function', 'security.enrich_provider_fields_v1', 'Layer 2', 'Filled and missing values per field for one university', 'active', '20261021170000'),
 ('function', 'security.enrich_plan_start_step_v1', 'Layer 2', 'Starts one plan step with the existing task or onboarding', 'active', '20261021170000'),
 ('function', 'security.enrich_plan_tick_v1', 'Layer 2', 'Runs the open plans step by step', 'active', '20261021170000'),
 ('function', 'security.enrich_plan_priority_v1', 'Layer 2', 'Universities by missing values', 'active', '20261021170000'),
 ('function', 'security.enrich_plan_auto_v1', 'Layer 2', 'Starts automatic plans, most missing first', 'active', '20261021170000'),
 ('function', 'security.fc_on_demand_today_v1', 'Layer 2', 'Firecrawl credits charged to the on-demand allowance today', 'active', '20261021170000'),
 ('function', 'public.admin_enrich_plan', 'Layer 2', 'Layer 2/3 › Enrichment plan', 'active', '20261021170000'),
 ('job', 'enrich-plan-run', 'Layer 2', 'Enrichment plans: run the steps', 'active', '20261021170000'),
 ('job', 'enrich-plan-auto', 'Layer 2', 'Enrichment plans: start automatic plans', 'active', '20261021170000')
on conflict (kind, name) do nothing;
