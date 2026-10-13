-- CF-247 v2.15.266: Levers › Onboarding switched on counted journey events, not universities ("476 universities moved a stage" was 476
-- events). It now counts the universities that moved a stage in the last hour. Read only; nothing dropped or deleted.

do $guard$
declare v_expected jsonb := '{"public.admin_progress_read(text,jsonb)": "79d2c159373ad88504d617d780a9aaae"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

CREATE OR REPLACE FUNCTION public.admin_progress_read(p_view text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
          'effect', (select count(distinct e.onboarding_id) || ' universities moved a stage in the last hour (' || count(*) || ' steps)' from pipeline.provider_onboarding_events e where e.at > now() - interval '1 hour')),
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
end $function$;

do $post$
declare v_expected jsonb := '{"public.admin_progress_read(text,jsonb)": "16ff49192512a33a1ef17eec25409735"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.266 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
