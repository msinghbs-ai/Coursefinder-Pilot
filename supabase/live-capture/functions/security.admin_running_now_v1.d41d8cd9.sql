CREATE OR REPLACE FUNCTION security.admin_running_now_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- v2.15.246 (Platform Admin, 11 Oct 2026: "Task manager was supposed to represent every job running ... which consumes resources"):
  -- running this moment, plus everything in the last 15 minutes (each scheduled job, each worker or API call by kind, scraper
  -- credits, AI spend) and the work waiting in each queue with the job that drains it. One pass over each log.
  with jr as materialized (select d.jobid, d.start_time, d.end_time, d.status from cron.job_run_details d where d.start_time > now() - interval '15 minutes'),
       calls as materialized (select l.function_name, coalesce(l.mode, '') mode, l.created_at, r.status_code, r.timed_out, (r.id is null) pending
                                from pipeline.edge_request_log l left join net._http_response r on r.id = l.request_id where l.created_at > now() - interval '15 minutes')
  select jsonb_build_object('at', now(), 'window_minutes', 15,
    'scheduled', (select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'label', coalesce(c.label, j.jobname), 'area', coalesce(c.area, 'Other'), 'started_at', d.start_time,
                     'seconds', extract(epoch from now() - d.start_time)::int, 'active', j.active, 'schedule', j.schedule, 'control_rank', coalesce(c.control_rank, 6)) order by d.start_time), '[]'::jsonb)
                   from cron.job_run_details d join cron.job j on j.jobid = d.jobid left join pipeline.automation_catalogue c on c.jobname = j.jobname
                  where d.status in ('running', 'starting') and d.start_time > now() - interval '6 hours'),
    'worker_calls', (select coalesce(jsonb_agg(jsonb_build_object('function', x.function_name, 'mode', x.mode, 'calls', x.n, 'oldest_at', x.oldest, 'seconds', extract(epoch from now() - x.oldest)::int) order by x.oldest), '[]'::jsonb)
                      from (select function_name, mode, count(*) n, min(created_at) oldest from calls where pending and created_at > now() - interval '10 minutes' group by 1, 2) x),
    'credits_last_hour', (select coalesce(jsonb_object_agg(u.purpose, u.n), '{}'::jsonb) from (select purpose, sum(units) n from pipeline.coverage_vendor_usage where at > now() - interval '1 hour' group by 1) u),
    'recent_jobs', (select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'label', coalesce(c.label, j.jobname), 'area', coalesce(c.area, 'Other'), 'runs', a.n, 'failed', a.failed,
                         'avg_seconds', a.avg_s, 'max_seconds', a.max_s, 'last_at', a.last_at, 'active', j.active, 'schedule', j.schedule, 'control_rank', coalesce(c.control_rank, 6), 'catalogued', c.jobname is not null)
                         order by a.total_s desc), '[]'::jsonb)
                      from (select jobid, count(*) n, count(*) filter (where status = 'failed') failed, round(avg(extract(epoch from (end_time - start_time)))::numeric, 1) avg_s,
                                   round(max(extract(epoch from (end_time - start_time)))::numeric, 1) max_s, sum(extract(epoch from (coalesce(end_time, now()) - start_time))) total_s, max(start_time) last_at
                              from jr group by jobid) a join cron.job j on j.jobid = a.jobid left join pipeline.automation_catalogue c on c.jobname = j.jobname),
    'recent_calls', (select coalesce(jsonb_agg(jsonb_build_object('function', x.function_name, 'mode', x.mode, 'calls', x.n, 'failed', x.failed, 'on_their_way', x.pending) order by x.n desc), '[]'::jsonb)
                      from (select function_name, mode, count(*) n, count(*) filter (where status_code >= 400 or timed_out) failed, count(*) filter (where pending) pending from calls group by 1, 2) x),
    'credits_15m', (select coalesce(jsonb_object_agg(u.purpose, u.n), '{}'::jsonb) from (select purpose, sum(units) n from pipeline.coverage_vendor_usage where at > now() - interval '15 minutes' group by 1) u),
    'ai_15m', (select coalesce(jsonb_object_agg(s.what, jsonb_build_object('calls', s.n, 'usd', round(s.usd::numeric, 4))), '{}'::jsonb) from (
                 select 'Layer 3 checks' what, count(*) n, sum(coalesce(estimated_cost_usd, 0)) usd from pipeline.layer3_interpretations where created_at > now() - interval '15 minutes'
                 union all select 'Course page matching', count(*), sum(coalesce(cost_usd, 0)) from pipeline.coverage_ai_match where decided_at > now() - interval '15 minutes'
                 union all select 'Page identity checks', count(*), sum(coalesce(cost_usd, 0)) from pipeline.coverage_identity_results where created_at > now() - interval '15 minutes'
                 union all select 'Adapter proposals', count(*), sum(coalesce(cost_usd, 0)) from pipeline.uni_adapter_drafts where updated_at > now() - interval '15 minutes' and cost_usd > 0) s where s.n > 0),
    'queues', jsonb_build_array(
       jsonb_build_object('label', 'Providers waiting for a website search', 'job', 'coverage-find-site', 'waiting', (select count(*) from pipeline.coverage_provider_discovery d where d.status = 'no_website' and coalesce(d.site_searched_at, '-infinity') < now() - interval '30 days')),
       jsonb_build_object('label', 'Providers waiting for a central page search', 'job', 'central-find', 'waiting', (select count(*) from pipeline.provider_central_search s where s.state = 'queued')),
       jsonb_build_object('label', 'Courses waiting for a course page search', 'job', 'course-link-search', 'waiting', (select count(*) from pipeline.course_link_search s where s.state = 'queued')),
       jsonb_build_object('label', 'Scholarship pages due to be read', 'job', 'scholarship-read', 'waiting', (select count(*) from pipeline.scholarship_pages p where p.next_read_at <= now())),
       jsonb_build_object('label', 'Register runs waiting or running', 'job', 'layer1-run-driver', 'waiting', (select count(*) from pipeline.layer1_run_queue q where q.status in ('queued', 'running', 'pending'))),
       jsonb_build_object('label', 'Tasks waiting or running', 'job', 'admin-jobs', 'waiting', (select count(*) from pipeline.admin_jobs a where a.state in ('queued', 'running')))),
    'uncatalogued', (select coalesce(jsonb_agg(j.jobname order by j.jobname), '[]'::jsonb) from cron.job j where not exists (select 1 from pipeline.automation_catalogue c where c.jobname = j.jobname)))
$function$
