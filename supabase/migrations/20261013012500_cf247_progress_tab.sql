-- CF-247 v2.15.266 (Platform Admin, 13 Oct 2026): "Show the adapter and scholarship journey and progress I can follow on the UI. Whatever
-- you are providing per hour, what do we need to implement at the UI to have this on demand? Collect the crux of how the platform is
-- progressing, what is running, and where we can tweak or run on demand. If you refactor, make sure redundant UI screens and controls are
-- retired." Decisions: a Progress tab in Coverage & completeness; hourly snapshots kept 90 days; chat updates become 3 a day; retire the
-- Live activity page, the Pilot panel, the Dashboard health strip, Layers and Recent activity, and Task manager's Running now (plus the
-- Wave 1 clean-up, next release). Mock-up approved 13 Oct 2026 ("Mock-up is good to go"; "proceed with Progress tab, as v2.15.266").
--   1 pipeline.progress_provider_facts: each onboarding university's courses and fields (intakes, English, fee, delivery) and its
--     scholarships, refreshed hourly (security.provider_fill_counts_v1 is too slow to read live for 1,200 universities).
--   2 pipeline.progress_snapshots: the Overview of each group (all, pilot, top 50) every hour, kept 90 days.
--   3 security.progress_overview_v1(group), security.progress_snapshot_v1() and the scheduled job progress-snapshot (hourly at :09,
--     in the automation catalogue). The job onboarding-pilot-snapshot is paused (its Pilot panel is retired; Progress replaces it).
--   4 public.admin_progress_read(view, args) for the four views: overview, journeys, running (and running_unis for one job), levers.
--     Rank 3 (Curator) and above. Read only; the actions use the existing calls (onboarding retry, Search again, Find scholarships now).
-- Nothing is dropped or deleted by this file (the snapshot job removes its own snapshots older than 90 days).

create table if not exists pipeline.progress_provider_facts(
  provider_id uuid primary key, at timestamptz not null default now(), facts jsonb not null);
create table if not exists pipeline.progress_snapshots(
  id bigserial primary key, at timestamptz not null default now(), grp text not null, data jsonb not null);
create index if not exists progress_snapshots_grp_at_idx on pipeline.progress_snapshots (grp, at desc);
alter table pipeline.progress_provider_facts enable row level security;
alter table pipeline.progress_snapshots enable row level security;
revoke all on pipeline.progress_provider_facts, pipeline.progress_snapshots from anon, authenticated;

-- Group of providers: all onboarding rows, or a cohort
create or replace function security.progress_cohort_v1(p_group text) returns text language sql immutable set search_path = '' as $f$
  select case p_group when 'pilot' then 'pilot-2026-10-12' when 'top' then 'au-top-2026-10-12' else null end
$f$;

-- Which stage of the journey a scheduled job works on
create or replace function security.progress_job_stage_v1(p_job text, p_area text) returns text language sql immutable set search_path = '' as $f$
  select case
    when p_job in ('provider-onboarding') then '1–7 Onboarding'
    when p_job ~ '^(course-link|coverage-read|coverage-discover|coverage-find-site|coverage-ai-match|coverage-reidentify|coverage-reextract|provider-contact|provider-facts|cricos-peo|firecrawl-)' then '2 Prepare'
    when p_job ~ '^(central-|adapter-)' and p_job <> 'adapter-overwrite' then '3–4 Adapter and central pages'
    when p_job ~ '^(adapter-overwrite|coverage-admit)' then '5 Enrich courses'
    when p_job ~ '^scholarship-(discover|listing)' then '6 Scholarship adapter'
    when p_job ~ '^scholarship-' then '7 Admit scholarships'
    when p_job ~ '(snapshot|report|summary)' then 'Reporting'
    when p_area = 'Layer 1 register' then 'Before onboarding: registers'
    when p_area in ('Search and API') then 'Delivery'
    else coalesce(p_area, 'Other') end
$f$;

create or replace function security.progress_overview_v1(p_group text) returns jsonb language sql stable security definer set search_path = '' as $f$
  with g as (select coalesce(nullif(p_group, ''), 'all') grp, security.progress_cohort_v1(p_group) cohort),
  m as (
    select o.provider_id, o.status, o.stop_reason, o.result, security.provider_onboarding_stage_v1(o.status, o.stop_reason, o.result) stage,
           f.facts n, cp.baseline b
      from pipeline.provider_onboarding o cross join g
      left join pipeline.progress_provider_facts f on f.provider_id = o.provider_id
      left join pipeline.onboarding_pilot cp on cp.provider_id = o.provider_id and cp.cohort = g.cohort
     where g.cohort is null or cp.provider_id is not null),
  pg as (
    select count(*) filter (where c.status = 'bound' and c.read_status = 'read') correct,
           count(*) filter (where c.status = 'mismatch') wrong,
           count(*) filter (where c.read_status not in ('read', 'identity_mismatch')) failed,
           count(*) filter (where c.status = 'bound' and c.read_status = 'read' and c.fetched_via = 'firecrawl') via_firecrawl
      from pipeline.coverage_course_pages c
     where c.read_at > now() - interval '1 hour' and ((select cohort from g) is null or c.provider_id in (select provider_id from m))),
  w as (
    select count(*) n from pipeline.scholarship_page_candidates c
     where c.read_status = 'read' and c.admit_status is null and ((select cohort from g) is null or c.provider_id in (select provider_id from m)))
  select jsonb_build_object(
    'group', (select grp from g), 'at', now(), 'facts_at', (select max(at) from pipeline.progress_provider_facts),
    'universities', (select count(*) from m),
    'stages', (select jsonb_build_object(
        'provider_in', count(*) filter (where stage = 'provider_in'), 'prepare', count(*) filter (where stage = 'prepare'),
        'create_adapter', count(*) filter (where stage = 'create_adapter'), 'admit', count(*) filter (where stage = 'admit'),
        'enrich', count(*) filter (where stage = 'enrich'), 'scholarship_adapter', count(*) filter (where stage = 'scholarship_adapter'),
        'admit_scholarships', count(*) filter (where stage = 'admit_scholarships'), 'done', count(*) filter (where stage = 'done')) from m),
    'needs_person', (select count(*) from m where status = 'stopped' and stop_reason in ('nothing_ready', 'approve_central')),
    'stopped', (select count(*) from m where status = 'stopped' and stop_reason not in ('nothing_ready', 'approve_central')),
    'stop_reasons', (select coalesce(jsonb_object_agg(r, n), '{}'::jsonb) from (select stop_reason r, count(*) n from m where status = 'stopped' group by 1) x),
    'auto_admitted', (select count(*) from m where result ? 'auto_admitted'),
    'fields', (select jsonb_build_object(
        'courses', coalesce(sum((n->>'courses')::int), 0), 'intakes', coalesce(sum((n->>'intakes')::int), 0),
        'english', coalesce(sum((n->>'english')::int), 0), 'fee', coalesce(sum((n->>'fee')::int), 0), 'delivery', coalesce(sum((n->>'delivery')::int), 0),
        'courses_before', sum((b->>'courses')::int), 'intakes_before', sum((b->>'intakes')::int), 'english_before', sum((b->>'english')::int),
        'fee_before', sum((b->>'fee')::int), 'delivery_before', sum((b->>'delivery')::int)) from m),
    'scholarships', (select jsonb_build_object('found', coalesce(sum((n->>'scholarships')::int), 0), 'published', coalesce(sum((n->>'scholarships_published')::int), 0),
        'found_before', sum((b->>'scholarships')::int), 'published_before', sum((b->>'scholarships_published')::int), 'waiting_ai', (select n from w)) from m),
    'pages_hour', (select to_jsonb(pg) from pg),
    'budget', security.fc_budget_status_v1(),
    'ai_today', (select coalesce(jsonb_agg(jsonb_build_object('use', s.use, 'label', s.label, 'spent', s.spent, 'guard', s.guard)), '[]'::jsonb) from security.ai_spend_today_v1() s),
    'openrouter_usd', (select o.remaining_usd from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1))
$f$;

-- Hourly: refresh each onboarding university's facts, record one Overview per group, remove snapshots older than 90 days
create or replace function security.progress_snapshot_v1() returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_n int; v_g text;
begin
  insert into pipeline.progress_provider_facts(provider_id, at, facts)
  select x.provider_id, now(), security.provider_fill_counts_v1(x.provider_id)
    from (select provider_id from pipeline.provider_onboarding union select provider_id from pipeline.onboarding_pilot) x
  on conflict (provider_id) do update set at = excluded.at, facts = excluded.facts;
  get diagnostics v_n = row_count;
  foreach v_g in array array['all', 'pilot', 'top'] loop
    insert into pipeline.progress_snapshots(at, grp, data) values (now(), v_g, security.progress_overview_v1(v_g) - 'budget' - 'ai_today'
      || jsonb_build_object('billed_today', security.fc_billed_today_v1(), 'ai_spent_today', (select coalesce(sum(s.spent), 0) from security.ai_spend_today_v1() s)));
  end loop;
  delete from pipeline.progress_snapshots where at < now() - interval '90 days';
  return jsonb_build_object('providers', v_n, 'at', now());
end $f$;

revoke all on function security.progress_cohort_v1(text), security.progress_job_stage_v1(text, text), security.progress_overview_v1(text),
  security.progress_snapshot_v1() from public, anon, authenticated;

create or replace function public.admin_progress_read(p_view text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_grp text := coalesce(nullif(p_args->>'group', ''), 'all'); v_cohort text; v jsonb;
  v_stopped uuid[]; v_job text := p_args->>'job';
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  v_cohort := security.progress_cohort_v1(v_grp);

  if p_view = 'overview' then
    return security.progress_overview_v1(v_grp)
      || jsonb_build_object('can_manage', v_rank >= 6,
        'groups', (select jsonb_build_object('all', (select count(*) from pipeline.provider_onboarding),
                     'pilot', (select count(*) from pipeline.onboarding_pilot where cohort = 'pilot-2026-10-12'),
                     'top', (select count(*) from pipeline.onboarding_pilot where cohort = 'au-top-2026-10-12'))),
        'notices', (select coalesce(jsonb_agg(n order by case n->>'severity' when 'high' then 0 when 'warning' then 1 else 2 end), '[]'::jsonb)
                      from jsonb_array_elements(security.platform_notices_v1()) n where n->>'toolset' in ('firecrawl', 'openrouter')),
        'trend', (select coalesce(jsonb_agg(jsonb_build_object('at', s.at, 'done', s.data->'stages'->'done', 'published', s.data->'scholarships'->'published',
                     'found', s.data->'scholarships'->'found', 'pages_correct', s.data->'pages_hour'->'correct', 'billed_today', s.data->'billed_today') order by s.at), '[]'::jsonb)
                    from (select * from pipeline.progress_snapshots s where s.grp = v_grp and s.at > now() - make_interval(hours => least(coalesce((p_args->>'hours')::int, 24), 2160))) s));

  elsif p_view = 'journeys' then
    v_stopped := array(select x.provider_id from security.fc_search_stopped_v1() x);
    select coalesce(jsonb_agg(r order by r.tier, r.name), '[]'::jsonb) into v from (
      select o.id onboarding_id, o.provider_id, coalesce(p.display_name, p.canonical_name) as name, security.coverage_country(o.provider_id) as country,
             security.fc_provider_tier_v1(o.provider_id) tier,
             case when exists (select 1 from pipeline.onboarding_pilot c where c.provider_id = o.provider_id and c.cohort = 'au-top-2026-10-12') then 'top'
                  when exists (select 1 from pipeline.onboarding_pilot c where c.provider_id = o.provider_id and c.cohort = 'pilot-2026-10-12') then 'pilot' else '' end grp,
             o.status, o.stop_reason, o.note, o.updated_at, security.provider_onboarding_stage_v1(o.status, o.stop_reason, o.result) stage,
             f.facts, f.at facts_at,
             (select count(*) from pipeline.scholarship_page_candidates c where c.provider_id = o.provider_id and c.read_status = 'read' and c.admit_status is null) waiting_ai,
             case when o.status = 'stopped' then o.stop_reason
                  when exists (select 1 from pipeline.firecrawl_search_holds h where h.provider_id = o.provider_id
                                 and not exists (select 1 from pipeline.firecrawl_search_resumes x where x.provider_id = h.provider_id and x.resumed_at > h.held_at)) then 'search_held'
                  when o.provider_id = any (v_stopped) then 'search_stopped'
                  when o.status = 'scholarships' and security.fc_sch_held_v1(o.provider_id, false) then 'scholarship_cap'
                  else null end held_by
        from pipeline.provider_onboarding o join catalogue.providers p on p.id = o.provider_id
        left join pipeline.progress_provider_facts f on f.provider_id = o.provider_id
       where (v_cohort is null or exists (select 1 from pipeline.onboarding_pilot c where c.provider_id = o.provider_id and c.cohort = v_cohort))
         and (nullif(p_args->>'stage', '') is null or security.provider_onboarding_stage_v1(o.status, o.stop_reason, o.result) = p_args->>'stage')
         and (nullif(p_args->>'country', '') is null or security.coverage_country(o.provider_id) = p_args->>'country')
         and (nullif(p_args->>'q', '') is null or coalesce(p.display_name, p.canonical_name) ilike '%' || (p_args->>'q') || '%')
         and (coalesce(p_args->>'held', '') = '' or (p_args->>'held' = 'person' and o.status = 'stopped' and o.stop_reason in ('nothing_ready', 'approve_central'))
              or (p_args->>'held' = 'stopped' and o.status = 'stopped'))
       order by security.fc_provider_tier_v1(o.provider_id), coalesce(p.display_name, p.canonical_name)
       limit least(coalesce((p_args->>'limit')::int, 200), 500)) r;
    return jsonb_build_object('rows', v, 'group', v_grp, 'can_manage', v_rank >= 6, 'can_run', v_rank >= 4);

  elsif p_view = 'running' then
    v := security.admin_live_activity_v1();
    return jsonb_build_object('at', now(), 'can_manage', v_rank >= 6,
      'jobs', (select coalesce(jsonb_agg(j || jsonb_build_object('stage', security.progress_job_stage_v1(j->>'job', j->>'area'))
                 order by security.progress_job_stage_v1(j->>'job', j->>'area'), j->>'label'), '[]'::jsonb) from jsonb_array_elements(v->'jobs') j),
      'in_flight', v->'in_flight', 'worker_errors', v->'worker_errors',
      'credits_hour', (select coalesce(jsonb_object_agg(g, n), '{}'::jsonb) from (select security.fc_purpose_group_v1(u.purpose) g, sum(u.units) n
                         from pipeline.coverage_vendor_usage u where u.at > now() - interval '1 hour' group by 1) x),
      'refused_hour', (select coalesce(sum(r.n), 0) from pipeline.firecrawl_refusals_by_provider r where r.last_at > now() - interval '1 hour'));

  elsif p_view = 'running_unis' then
    -- the universities one job is working on now (last hour), each with its onboarding row for its journey
    select coalesce(jsonb_agg(z), '[]'::jsonb) into v from (
      select x.provider_id, coalesce(p.display_name, p.canonical_name) as name, security.coverage_country(x.provider_id) as country,
             o.id onboarding_id, security.provider_onboarding_stage_v1(o.status, o.stop_reason, o.result) stage, x.what, x.n
        from (
          select e.provider_id, 'moved to ' || string_agg(distinct e.status, ', ') what, count(*) n
            from (select oo.provider_id, ev.status from pipeline.provider_onboarding_events ev join pipeline.provider_onboarding oo on oo.id = ev.onboarding_id
                   where ev.at > now() - interval '1 hour') e where v_job = 'provider-onboarding' group by 1
          union all
          select u.provider_id, count(*) || ' searches', count(*) from pipeline.coverage_vendor_usage u
           where v_job ~ '^course-link-search' and u.purpose = 'course_link_search' and u.at > now() - interval '1 hour' and u.provider_id is not null group by 1
          union all
          select c.provider_id, count(*) filter (where c.status = 'bound' and c.read_status = 'read') || ' correct, ' || count(*) filter (where c.status = 'mismatch') || ' wrong', count(*)
            from pipeline.coverage_course_pages c where v_job ~ '^(coverage-read|coverage-discover)' and c.read_at > now() - interval '1 hour' group by 1
          union all
          select d.provider_id, coalesce(d.site_source, 'not found yet'), 1 from pipeline.coverage_provider_discovery d
           where v_job = 'coverage-find-site' and d.site_searched_at > now() - interval '1 hour'
          union all
          select u.provider_id, sum(u.units) || ' credits', sum(u.units)::bigint from pipeline.coverage_vendor_usage u
           where v_job ~ '^scholarship-(discover|listing|read)' and u.purpose like 'sch\_%' and u.at > now() - interval '1 hour' and u.provider_id is not null group by 1
          union all
          select r.provider_id, sum(r.n) || ' refused (' || string_agg(distinct r.reason, ', ') || ')', sum(r.n) from pipeline.firecrawl_refusals_by_provider r
           where v_job ~ '^scholarship-(discover|listing|read)' and r.grp = 'scholarships' and r.last_at > now() - interval '1 hour' group by 1
          union all
          select c.provider_id, count(*) || ' pages waiting', count(*) from pipeline.scholarship_page_candidates c
           where v_job in ('scholarship-ai-extract', 'scholarship-ai-backfill') and c.read_status = 'read' and c.admit_status is null group by 1
          union all
          select s.provider_id, count(*) || ' published', count(*) from pipeline.scholarship_publication_batches b
            join scholarship.scholarships s on s.id = any (b.scholarship_ids)
           where v_job = 'scholarship-auto-publish' and b.created_at > security.fc_day_start_v1() group by 1
          union all
          select q.provider_id, count(*) || ' central pages (' || string_agg(distinct q.state, ', ') || ')', count(*) from pipeline.central_ai_queue q
           where v_job ~ '^central-' and coalesce(q.done_at, q.created_at) > now() - interval '1 hour' group by 1
          union all
          select oo.provider_id, 'enriching courses', 1 from pipeline.provider_onboarding oo
           where v_job ~ '^(adapter-overwrite|coverage-admit)' and security.provider_onboarding_stage_v1(oo.status, oo.stop_reason, oo.result) = 'enrich'
        ) x join catalogue.providers p on p.id = x.provider_id
        left join pipeline.provider_onboarding o on o.provider_id = x.provider_id
       order by x.n desc nulls last, 2 limit 50) z;
    return jsonb_build_object('job', v_job, 'unis', v);

  elsif p_view = 'levers' then
    return jsonb_build_object('can_manage', v_rank >= 6, 'sections', jsonb_build_array(
      jsonb_build_object('title', 'Onboarding pace', 'rows', (select jsonb_build_array(
        jsonb_build_object('name', 'Onboarding switched on', 'now', case when s.enabled then 'On' else 'Off' end, 'page', 'layer2', 'tab', 'onboarding', 'where', 'Layer 2 › Onboarding › Settings',
          'effect', (select count(*) || ' universities moved a stage in the last hour' from pipeline.provider_onboarding_events e where e.at > now() - interval '1 hour')),
        jsonb_build_object('name', 'Universities worked at once', 'now', s.max_active::text, 'page', 'layer2', 'tab', 'onboarding', 'where', 'Layer 2 › Onboarding › Settings',
          'effect', (select count(*) filter (where status in ('website', 'course_pages', 'capturing', 'proposing', 'applying', 'qualifying', 'scholarships')) || ' in progress; '
                         || count(*) filter (where status = 'queued') || ' queued' from pipeline.provider_onboarding)),
        jsonb_build_object('name', 'Admit automatically', 'now', case when s.auto_admit then 'On' else 'Off' end, 'page', 'layer2', 'tab', 'onboarding', 'where', 'Layer 2 › Onboarding › Settings',
          'effect', (select count(*) || ' admitted automatically' from pipeline.provider_onboarding o where o.result ? 'auto_admitted')),
        jsonb_build_object('name', 'Start new universities by themselves', 'now', case when s.auto_start_new then 'On' else 'Off' end, 'page', 'layer2', 'tab', 'onboarding', 'where', 'Layer 2 › Onboarding › Settings',
          'effect', (select count(*) || ' new today' from pipeline.provider_onboarding o where o.source = 'new_provider' and o.created_at > security.fc_day_start_v1())))
        from pipeline.provider_onboarding_settings s where s.id = 1)),
      jsonb_build_object('title', 'Firecrawl budget', 'rows', (select coalesce(jsonb_agg(jsonb_build_object('name', t.label, 'key', t.key,
          'now', (t.value #>> '{}') || coalesce(' ' || t.unit, ''), 'page', 'services', 'tab', 'limits', 'where', 'Toolsets & limits › Firecrawl › Daily budget',
          'effect', case
            when t.key like 'daily\_share\_%' then (select coalesce(round((g->>'used')::numeric) || ' used today' || case when (g->>'refused')::int > 0 then ', ' || (g->>'refused') || ' refused' else '' end, '')
                                                   from jsonb_array_elements(security.fc_budget_status_v1()->'groups') g where 'daily_share_' || (g->>'group') = t.key)
            when t.key = 'daily_budget_total' then round(security.fc_billed_today_v1()) || ' billed today'
            when t.key = 'scholarship_cap_per_uni' then (select coalesce(sum(r.n), 0) || ' refused today by the cap' from pipeline.firecrawl_refusals_by_provider r
                                                            where r.day = (now() at time zone 'Australia/Melbourne')::date and r.reason = 'university_cap')
            when t.key = 'scholarship_min_courses' then (select coalesce(sum(r.n), 0) || ' refused today (fewer courses)' from pipeline.firecrawl_refusals_by_provider r
                                                            where r.day = (now() at time zone 'Australia/Melbourne')::date and r.reason = 'not_eligible')
            when t.key = 'search_stop_after' then (select count(*) || ' universities stopped' from security.fc_search_stopped_v1())
            when t.key = 'central_refresh_days' then (select coalesce(sum(r.n), 0) || ' calls not due today' from pipeline.firecrawl_budget_refusals r
                                                         where r.day = (now() at time zone 'Australia/Melbourne')::date and r.reason = 'not_due')
            else '' end,
          'hot', t.key in ('daily_share_scholarships', 'daily_share_course_search', 'daily_share_other')
                 and exists (select 1 from jsonb_array_elements(security.fc_budget_status_v1()->'groups') g where 'daily_share_' || (g->>'group') = t.key and (g->>'used')::numeric >= (g->>'share')::numeric))
          order by t.sort), '[]'::jsonb)
        from pipeline.platform_toolset_settings t where t.toolset_key = 'firecrawl' and t.section = 'Daily budget')),
      jsonb_build_object('title', 'AI (OpenRouter)', 'rows', (select jsonb_build_array(
          jsonb_build_object('name', 'Mode', 'now', case (select x.enforcement from pipeline.platform_toolsets x where x.key = 'openrouter') when 'observe' then 'Observe only' else 'Stop at limits' end,
            'page', 'services', 'tab', 'ai', 'where', 'Models & services › AI & OpenRouter',
            'effect', 'Balance US$' || coalesce(round((select o.remaining_usd from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1), 2)::text, '?')))
        || coalesce((select jsonb_agg(jsonb_build_object('name', s.label || ' daily guard', 'now', 'US$' || s.guard, 'page', 'services', 'tab', 'ai', 'where', 'Models & services › AI & OpenRouter',
              'effect', 'US$' || round(s.spent, 2) || ' spent today', 'hot', s.guard > 0 and s.spent >= s.guard)) from security.ai_spend_today_v1() s), '[]'::jsonb)))
    ));
  else
    raise exception 'unknown view %', p_view using errcode = '22023';
  end if;
end $f$;
revoke all on function public.admin_progress_read(text, jsonb) from public, anon;
grant execute on function public.admin_progress_read(text, jsonb) to authenticated;

-- 3 The hourly snapshot job (standing rule G1: in the automation catalogue); the pilot snapshot is paused, not removed
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('progress-snapshot', 'Reports', 5, 'Snapshot progress (hourly)',
        'Hourly at :09: refreshes each onboarding university''s courses, fields and scholarships, and records the Progress overview for all universities, the pilot and the top 50; kept 90 days. Coverage & completeness › Progress.', 6, false)
on conflict (jobname) do nothing;
select cron.schedule('progress-snapshot', '9 * * * *', 'select security.progress_snapshot_v1()');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'onboarding-pilot-snapshot'), active := false)
 where exists (select 1 from cron.job where jobname = 'onboarding-pilot-snapshot');

-- first snapshot now
select security.progress_snapshot_v1();

do $chk$
begin
  if (select count(*) from pipeline.progress_snapshots) < 3 then raise exception 'v2.15.266 post-check: snapshots'; end if;
  if (select count(*) from pipeline.progress_provider_facts) < 1000 then raise exception 'v2.15.266 post-check: provider facts'; end if;
  if not exists (select 1 from cron.job where jobname = 'progress-snapshot' and active) then raise exception 'v2.15.266 post-check: job'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'progress-snapshot') then raise exception 'v2.15.266 post-check: catalogue'; end if;
end $chk$;
