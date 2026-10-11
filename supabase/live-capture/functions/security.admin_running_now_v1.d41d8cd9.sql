CREATE OR REPLACE FUNCTION security.admin_running_now_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object('at', now(),
    'scheduled', (select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'label', coalesce(c.label, j.jobname), 'area', coalesce(c.area, 'Other'), 'started_at', d.start_time,
                     'seconds', extract(epoch from now() - d.start_time)::int, 'active', j.active, 'schedule', j.schedule, 'control_rank', coalesce(c.control_rank, 6)) order by d.start_time), '[]'::jsonb)
                   from cron.job_run_details d join cron.job j on j.jobid = d.jobid left join pipeline.automation_catalogue c on c.jobname = j.jobname
                  where d.status in ('running', 'starting') and d.start_time > now() - interval '6 hours'),
    'worker_calls', (select coalesce(jsonb_agg(jsonb_build_object('function', x.function_name, 'mode', x.mode, 'calls', x.n, 'oldest_at', x.oldest, 'seconds', extract(epoch from now() - x.oldest)::int) order by x.oldest), '[]'::jsonb)
                      from (select l.function_name, coalesce(l.mode, '') mode, count(*) n, min(l.created_at) oldest from pipeline.edge_request_log l
                             where l.created_at > now() - interval '10 minutes' and not exists (select 1 from net._http_response r where r.id = l.request_id) group by 1, 2) x),
    'credits_last_hour', (select coalesce(jsonb_object_agg(u.purpose, u.n), '{}'::jsonb) from (select purpose, sum(units) n from pipeline.coverage_vendor_usage where at > now() - interval '1 hour' group by 1) u))
$function$
