CREATE OR REPLACE FUNCTION security.admin_live_activity_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 1 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  with runs as (
    select d.jobid, d.start_time, d.end_time, d.status, d.return_message,
           row_number() over (partition by d.jobid order by d.start_time desc) rn
      from cron.job_run_details d where d.start_time > now() - interval '2 days'),
  agg as (
    select jobid,
           count(*) filter (where start_time > now() - interval '24 hours') runs_24h,
           count(*) filter (where start_time > now() - interval '24 hours' and status = 'failed') failed_24h,
           bool_or(status in ('running','starting')) running
      from runs group by jobid),
  -- work left and done in 24 hours, for jobs that work through a queue
  q(jobname, unit, work_left, done_24h) as (
    select 'scholarship-discover', 'providers',
           (select count(*) from pipeline.scholarship_discovery_providers where status = 'pending' and attempts < 3),
           (select count(*) from pipeline.scholarship_discovery_providers where discovered_at > now() - interval '24 hours')
    union all select 'scholarship-read', 'pages',
           (select count(*) from pipeline.scholarship_pages p join scholarship.scholarships s on s.id = p.scholarship_id and s.lifecycle_status = 'active'
             where p.next_read_at <= now() and p.attempts < 5),
           (select count(*) from pipeline.scholarship_pages where read_at > now() - interval '24 hours')
    union all select 'provider-facts', 'searches and documents',
           (select count(*) from pipeline.provider_fact_search where state = 'queued') + (select count(*) from pipeline.provider_fact_sources where status = 'found' and attempts < 3),
           (select count(*) from pipeline.provider_fact_search where done_at > now() - interval '24 hours') + (select count(*) from pipeline.provider_fact_sources where read_at > now() - interval '24 hours')
    union all select 'course-link-search-worker', 'courses',
           (select count(*) from pipeline.course_link_search where state = 'queued'),
           (select count(*) from pipeline.course_link_search where done_at > now() - interval '24 hours')
    union all select 'coverage-read', 'course pages',
           (select count(*) from pipeline.coverage_course_pages where status in ('bound','ambiguous') and coalesce(next_read_at, now()) <= now() and read_attempts < 3),
           (select count(*) from pipeline.coverage_course_pages where read_at > now() - interval '24 hours')
    union all select 'layer3-intake-route', 'AI checks',
           (select count(*) from pipeline.layer3_work_items where task_class = 'provider_intake_validation' and status in ('pending','retry','reserved')),
           (select count(*) from pipeline.layer3_work_items where task_class = 'provider_intake_validation' and completed_at > now() - interval '24 hours')
    union all select 'layer3-english-route', 'AI checks',
           (select count(*) from pipeline.layer3_work_items where task_class = 'provider_english_validation' and status in ('pending','retry','reserved')),
           (select count(*) from pipeline.layer3_work_items where task_class = 'provider_english_validation' and completed_at > now() - interval '24 hours')
    union all select 'layer3-tuition-dispatch', 'AI checks',
           (select count(*) from pipeline.layer3_work_items where task_class = 'provider_current_tuition_validation' and status in ('pending','retry','reserved')),
           (select count(*) from pipeline.layer3_work_items where task_class = 'provider_current_tuition_validation' and completed_at > now() - interval '24 hours')
    union all select 'evidence-link-index', 'pages',
           (select count(*) from pipeline.evidence_artifacts e left join pipeline.evidence_link_index_state st on st.evidence_id = e.id
              join pipeline.sources s on s.id = e.source_id join pipeline.layer2_onboarding_snapshot o on o.provider_id = s.provider_id
             where e.storage_path is not null and e.storage_path !~ '^[a-z-]+://'
               and e.evidence_type in ('layer2_html_snapshot','layer2_extraction_input','source_snapshot','provider_contact_html_snapshot')
               and (e.mime_type ilike '%html%' or e.mime_type ilike '%json%')
               and (st.evidence_id is null or (st.status = 'error' and st.indexed_at < now() - interval '6 hours'))),
           (select count(*) from pipeline.evidence_link_index_state where status in ('indexed','no_links') and indexed_at > now() - interval '24 hours')),
  jobs as (
    select a.jobname, a.area, a.sort, a.label, a.description, j.schedule, j.active,
           coalesce(g.running, false) running, coalesce(g.runs_24h, 0) runs_24h, coalesce(g.failed_24h, 0) failed_24h,
           r.start_time last_start, r.end_time last_end, r.status last_status, left(r.return_message, 240) last_message,
           q.unit, q.work_left, q.done_24h,
           coalesce(substring(j.command from '"mode":"([a-z_]+)"'), case a.jobname when 'evidence-link-index' then 'evidence_link_index' end) worker_mode, substring(j.command from '"task":"([a-z_]+)"') worker_task
      from pipeline.automation_catalogue a join cron.job j on j.jobname = a.jobname
      left join agg g on g.jobid = j.jobid
      left join runs r on r.jobid = j.jobid and r.rn = 1
      left join q on q.jobname = a.jobname),
  -- the latest summary each coverage-sweep worker mode returned (kept a few hours by pg_net)
  worker as (
    select m.mode, m.task, x.content, x.created at
      from (select distinct worker_mode mode, worker_task task from jobs where worker_mode is not null) m
      left join lateral (select h.content, h.created from net._http_response h
                          where h.status_code = 200 and (case when m.mode = 'evidence_link_index' then h.content like '%"processed":%"summary":{"indexed"%' else h.content like '%"mode":"' || m.mode || '"%' end)
                            and (m.task is null or h.content like '%"task":"' || m.task || '"%')
                          order by h.created desc limit 1) x on true),
  pub as (select p.publishable, p.missing, s.publication_status, s.lifecycle_status
            from security.scholarship_publishability_v1() p join scholarship.scholarships s on s.id = p.scholarship_id)
  select jsonb_build_object(
    'now', now(),
    'jobs', (select jsonb_agg(jsonb_build_object(
        'job', j.jobname, 'area', j.area, 'label', j.label, 'description', j.description, 'schedule', j.schedule, 'active', j.active,
        'running', j.running, 'runs_24h', j.runs_24h, 'failed_24h', j.failed_24h,
        'last', jsonb_build_object('start', j.last_start, 'end', j.last_end, 'status', j.last_status, 'message', j.last_message),
        'queue', case when j.unit is null then null else jsonb_build_object('unit', j.unit, 'left', j.work_left, 'done_24h', j.done_24h) end,
        'worker', case when j.worker_mode is null then null else (select jsonb_build_object('mode', w.mode, 'at', w.at,
                   'result', security.live_worker_summary(w.content)) from worker w where w.mode = j.worker_mode and w.task is not distinct from j.worker_task) end)
        order by j.area, j.sort, j.jobname) from jobs j),
    'needs_person', jsonb_build_object(
        'fee_schedules', (select count(*) from pipeline.provider_fact_sources where kind = 'fee_schedule' and status = 'parsed' and decision is null),
        'layer4_reviews', (select count(*) from pipeline.layer4_review_items where status = 'pending'),
        'flagged_values', (select count(*) from pipeline.data_flags where status = 'open'),
        'ranking_links', (select count(*) from ranking.provider_mappings where status = 'candidate'),
        'scholarships_ready', (select count(*) from pub where publishable and coalesce(publication_status, 'unpublished') <> 'published'),
        'scholarships_domestic', (select count(*) from pub where lifecycle_status = 'active' and 'eligibility lists domestic students only' = any(missing))),
    'in_flight', (select count(*) from net.http_request_queue),
    -- Decision 215: replies from workers with an error status (pg_net keeps them a few hours)
    'worker_errors', (select coalesce(jsonb_agg(jsonb_build_object('function', x.fn, 'job', x.job, 'status', x.status_code, 'timed_out', x.timed_out, 'message', x.message, 'count', x.n, 'last', x.last) order by x.last desc), '[]'::jsonb)
                        from (select e.*, (select a.label from pipeline.automation_catalogue a join cron.job j on j.jobname = a.jobname
                                            where e.fn <> '' and j.command like '%''' || e.fn || '''%' and (e.mode is null or j.command like '%"mode":"' || e.mode || '"%')
                                            order by a.sort limit 1) job
                                from (select coalesce(l.function_name, '') fn, l.mode, h.status_code, h.timed_out, left(coalesce(h.error_msg, h.content), 200) message, count(*) n, max(h.created) last
                                        from net._http_response h left join pipeline.edge_request_log l on l.slot = (h.id % 50000)::int and l.request_id = h.id
                                       where h.status_code >= 400 or h.status_code is null
                                       group by 1, 2, 3, 4, 5) e
                               where not exists (select 1 from pipeline.live_error_acks k where k.function_name = e.fn and k.status_code = coalesce(e.status_code, -1)
                                                    and k.message_md5 = md5(e.message) and k.acked_at >= e.last)
                               order by e.last desc limit 10) x)
  ) into v;
  return v;
end $function$
