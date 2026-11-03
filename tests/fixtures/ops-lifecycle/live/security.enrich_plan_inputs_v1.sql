CREATE OR REPLACE FUNCTION security.enrich_plan_inputs_v1(p_provider uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with a as (select r.id, r.state, r.steps, r.created_at, coalesce(r.finished_at, r.created_at) base from pipeline.enrich_plan_runs r
              where r.provider_id = p_provider order by r.created_at desc limit 1)
  select jsonb_build_object(
    'last_run', a.id, 'last_state', a.state, 'last_at', a.created_at, 'since', a.base,
    'evidence_at', ev.at, 'evidence_new', coalesce(ev.n, 0),
    'central_at', cs.searched_at, 'central_new', coalesce(cs.searched_at > a.base, false),
    'retry_steps', coalesce(rt.steps, '[]'::jsonb))
    from (select 1) one
    left join a on true
    -- verified course pages: bound, read, with stored evidence (index provider_id, read_at)
    left join lateral (select max(g.read_at) at, count(*) filter (where g.read_at > a.base) n from pipeline.coverage_course_pages g
                        where g.provider_id = p_provider and g.evidence_id is not null and g.read_status = 'read') ev on true
    left join lateral (select s.searched_at from pipeline.provider_central_search s where s.provider_id = p_provider and s.state = 'done') cs on true
    -- steps of the latest run (not one a person cancelled) whose failure cause has cleared, each retried a bounded number of times
    left join lateral (select jsonb_agg(distinct s->>'step') steps from jsonb_array_elements(case when a.state = 'cancelled' then '[]'::jsonb else a.steps end) s
       where ((s->>'status' = 'skipped' and coalesce(s->>'note', '') like 'no room in the % share%'
               and security.fc_budget_left_v1(case s->>'group' when 'course_search' then 'course_link_search' when 'scholarships' then 'sch_scrape' when 'reads' then 'scrape' when 'central' then 'central_map' else 'other' end)
                   >= least(coalesce((s->>'est_credits')::numeric, 0), security.fc_setting_num_v1('daily_share_' || (s->>'group'), 0)))
          or (s->>'status' in ('failed', 'stopped', 'cancelled')
              and coalesce((s->>'finished_at')::timestamptz, a.base) <= now() - make_interval(hours => security.pipeline_num_v1('plans.retry_after_hours', 6)::int)
              -- a cause that time does not clear (too few pages, no website, not a search target ...) waits for new evidence or gaps
              and not exists (select 1 from pipeline.platform_toolset_settings w cross join lateral jsonb_array_elements_text(coalesce(w.value, '[]'::jsonb)) k(t)
                               where w.toolset_key = 'pipeline' and w.key = 'plans.retry_waits_for_change' and position(lower(k.t) in lower(coalesce(s->>'note', ''))) > 0))
          or (s->>'status' = 'timed_out'
              and case s->'ref'->>'kind'
                    when 'job' then exists (select 1 from pipeline.admin_jobs j where j.id = nullif(s->'ref'->>'id', '')::uuid and j.state in ('failed', 'cancelled'))
                    when 'onboarding' then exists (select 1 from pipeline.provider_onboarding o where o.id = nullif(s->'ref'->>'id', '')::uuid and o.status in ('stopped', 'cancelled'))
                    else true end))
         and (select count(*) from pipeline.enrich_plan_runs r2 cross join lateral jsonb_array_elements(r2.steps) s2
               where r2.provider_id = p_provider and r2.created_at > now() - make_interval(days => security.pipeline_num_v1('plans.redo_days', 14)::int)
                 and s2->>'step' = s->>'step' and s2->>'status' in ('failed', 'stopped', 'cancelled', 'timed_out', 'skipped'))
             < security.pipeline_num_v1('plans.step_retry_max', 3)) rt on true
$function$
