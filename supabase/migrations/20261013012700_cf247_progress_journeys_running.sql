-- CF-247 v2.15.267 (Platform Admin, 13 Oct 2026 14:23, with screenshots: "progress mock-up and actual implementation for Journey is very
-- different. Even Running now is all tasks are empty"). admin_progress_read:
--   journeys: sorted by courses (as the mock-up); filter "held up by" (needs a person, waiting for course pages, scholarship credits,
--     search stopped or held, AI reading pages, anything) and "only held up"; each row also carries whether its scholarships were searched;
--   journey (new): one university's journey as steps (stage, from, to, last note) from its onboarding events, with its facts and
--     scholarship counts, for the selected-journey panel;
--   running_unis: more jobs say which universities they worked on in the last hour (central and fee pages, CRICOS-code matches,
--     scholarship pages read again, discovery queue, Firecrawl targets); when a job touched no particular university in the last hour,
--     the universities now at its journey stage are listed instead, marked as such (no job is empty any more).
-- Read only; nothing dropped or deleted.

do $guard$
declare v_expected jsonb := '{"public.admin_progress_read(text,jsonb)": "16ff49192512a33a1ef17eec25409735"}'::jsonb;
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
    with base as (
      select o.id onboarding_id, o.provider_id, coalesce(p.display_name, p.canonical_name) as name, security.coverage_country(o.provider_id) as country,
             security.fc_provider_tier_v1(o.provider_id) tier,
             case when exists (select 1 from pipeline.onboarding_pilot c where c.provider_id = o.provider_id and c.cohort = 'au-top-2026-10-12') then 'top'
                  when exists (select 1 from pipeline.onboarding_pilot c where c.provider_id = o.provider_id and c.cohort = 'pilot-2026-10-12') then 'pilot' else '' end grp,
             o.status, o.stop_reason, o.note, o.updated_at, o.result, security.provider_onboarding_stage_v1(o.status, o.stop_reason, o.result) stage,
             f.facts, f.at facts_at, coalesce((f.facts->>'courses')::int, 0) courses,
             (select count(*) from pipeline.scholarship_page_candidates c where c.provider_id = o.provider_id and c.read_status = 'read' and c.admit_status is null) waiting_ai,
             exists (select 1 from pipeline.scholarship_discovery_providers d where d.provider_id = o.provider_id and d.status in ('mapped', 'empty', 'failed')) sch_searched,
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
         and (nullif(p_args->>'q', '') is null or coalesce(p.display_name, p.canonical_name) ilike '%' || (p_args->>'q') || '%')),
    sel as (
      select b.* from base b
       where (nullif(p_args->>'stop', '') is null or b.stop_reason = p_args->>'stop')
         and case coalesce(p_args->>'held', '')
               when '' then true
               when 'any' then b.held_by is not null or b.waiting_ai > 0
               when 'person' then b.held_by in ('nothing_ready', 'approve_central')
               when 'pages' then b.held_by in ('too_few_pages', 'no_website', 'recipe_off') or (b.stage = 'prepare' and b.held_by is null)
               when 'cap' then b.held_by = 'scholarship_cap'
               when 'search' then b.held_by in ('search_held', 'search_stopped')
               when 'ai' then b.waiting_ai > 0
               when 'stopped' then b.status = 'stopped'
               else true end)
    select jsonb_build_object('total', (select count(*) from sel),
             'rows', coalesce((select jsonb_agg(to_jsonb(r) - 'result' order by r.courses desc, r.name) from (select * from sel order by courses desc, name
                                limit least(coalesce((p_args->>'limit')::int, 200), 500)) r), '[]'::jsonb)) into v;
    return v || jsonb_build_object('group', v_grp, 'can_manage', v_rank >= 6, 'can_run', v_rank >= 4);

  elsif p_view = 'journey' then
    -- one university's journey: its onboarding events grouped into stages (from, to, last note), facts and scholarships
    return (select jsonb_build_object('onboarding_id', o.id, 'provider_id', o.provider_id, 'name', coalesce(p.display_name, p.canonical_name),
        'country', security.coverage_country(o.provider_id), 'status', o.status, 'stop_reason', o.stop_reason, 'note', o.note,
        'stage', security.provider_onboarding_stage_v1(o.status, o.stop_reason, o.result), 'started_at', o.created_at, 'source', o.source,
        'grp', case when exists (select 1 from pipeline.onboarding_pilot c where c.provider_id = o.provider_id and c.cohort = 'au-top-2026-10-12') then 'top'
                    when exists (select 1 from pipeline.onboarding_pilot c where c.provider_id = o.provider_id and c.cohort = 'pilot-2026-10-12') then 'pilot' else '' end,
        'facts', f.facts, 'facts_at', f.at, 'auto_admitted', o.result->'auto_admitted',
        'waiting_ai', (select count(*) from pipeline.scholarship_page_candidates c where c.provider_id = o.provider_id and c.read_status = 'read' and c.admit_status is null),
        'sch_status', (select d.status from pipeline.scholarship_discovery_providers d where d.provider_id = o.provider_id),
        'steps', (select coalesce(jsonb_agg(jsonb_build_object('stage', g.stage, 'from', g.first_at, 'to', g.last_at, 'n', g.n, 'note', g.note) order by g.first_at), '[]'::jsonb)
                    from (select x.stage, min(x.at) first_at, max(x.at) last_at, count(*) n, (array_agg(x.note order by x.at desc) filter (where x.note is not null))[1] note
                            from (select y.*, sum(case when y.stage is distinct from y.prev then 1 else 0 end) over (order by y.at, y.id) grp_no
                                    from (select e.id, e.at, e.note, security.provider_onboarding_stage_v1(e.status, e.stop_reason, null) stage,
                                                 lag(security.provider_onboarding_stage_v1(e.status, e.stop_reason, null)) over (order by e.at, e.id) prev
                                            from pipeline.provider_onboarding_events e where e.onboarding_id = o.id) y) x
                           group by x.grp_no, x.stage) g),
        'can_manage', v_rank >= 6, 'can_run', v_rank >= 4)
      from pipeline.provider_onboarding o join catalogue.providers p on p.id = o.provider_id
      left join pipeline.progress_provider_facts f on f.provider_id = o.provider_id
     where o.id = (p_args->>'onboarding_id')::uuid);

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
          union all
          select u.provider_id, sum(u.units) || ' credits on central and fee pages', sum(u.units)::bigint from pipeline.coverage_vendor_usage u
           where v_job ~ '^(provider-facts|central-)' and (u.purpose like 'provider\_facts%' or u.purpose like 'central\_%') and u.at > now() - interval '1 hour' and u.provider_id is not null group by 1
          union all
          select c.provider_id, count(*) || ' pages matched by CRICOS code', count(*) from pipeline.coverage_course_pages c
           where v_job = 'course-link-reverse' and c.bound_at > now() - interval '1 hour' and c.basis like 'cricos%' group by 1
          union all
          select s.provider_id, count(*) || ' scholarship pages read again', count(*) from pipeline.scholarship_pages sp join scholarship.scholarships s on s.id = sp.scholarship_id
           where v_job = 'scholarship-read' and sp.read_at > now() - interval '1 hour' group by 1
          union all
          select d.provider_id, 'discovery ' || d.status, 1 from pipeline.scholarship_discovery_providers d
           where v_job = 'scholarship-discover-refill' and d.updated_at > now() - interval '1 hour'
          union all
          select t.provider_id, 'Firecrawl target (' || coalesce(t.courses, 0) || ' courses)', coalesce(t.courses, 0)::bigint from pipeline.firecrawl_target_cache t
           where v_job = 'firecrawl-targets' and t.included
        ) x join catalogue.providers p on p.id = x.provider_id
        left join pipeline.provider_onboarding o on o.provider_id = x.provider_id
       order by x.n desc nulls last, 2 limit 50) z;
    -- v2.15.267: a job that touched no particular university in the last hour lists the universities now at its journey stage
    if jsonb_array_length(coalesce(v, '[]'::jsonb)) = 0 then
      select coalesce(jsonb_agg(z), '[]'::jsonb) into v from (
        select o.provider_id, coalesce(p.display_name, p.canonical_name) as name, security.coverage_country(o.provider_id) as country, o.id onboarding_id,
               security.provider_onboarding_stage_v1(o.status, o.stop_reason, o.result) stage,
               case when o.status = 'stopped' then 'at this stage, stopped' else 'at this stage now' end what, coalesce((f.facts->>'courses')::bigint, 0) n
          from pipeline.provider_onboarding o join catalogue.providers p on p.id = o.provider_id
          left join pipeline.progress_provider_facts f on f.provider_id = o.provider_id
         where security.provider_onboarding_stage_v1(o.status, o.stop_reason, o.result) = any (
                 case split_part(coalesce(p_args->>'stage', ''), ' ', 1)
                   when '2' then array['prepare'] when '3–4' then array['create_adapter', 'admit'] when '5' then array['enrich']
                   when '6' then array['scholarship_adapter'] when '7' then array['admit_scholarships']
                   when '1–7' then array['provider_in', 'prepare', 'create_adapter', 'admit', 'enrich', 'scholarship_adapter', 'admit_scholarships']
                   else array[]::text[] end)
         order by (o.status = 'stopped'), coalesce((f.facts->>'courses')::int, 0) desc limit 50) z;
      return jsonb_build_object('job', v_job, 'unis', v, 'fallback', true);
    end if;
    return jsonb_build_object('job', v_job, 'unis', v, 'fallback', false);

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
declare v_expected jsonb := '{"public.admin_progress_read(text,jsonb)": "e526fbbad139a8dff69e2b60206462ae"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.267 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
