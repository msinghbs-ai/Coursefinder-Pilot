-- CF-247 (Decision 214, 2 Oct 2026). Platform Admin, 07:31: "I don't still see the real time progress or what is
-- happening on each layer ... UI should be more transparent what is running and happening at each layer at any given
-- time." Live activity (admin_read 'live_activity', every role): for every scheduled job, by area, whether it is running
-- now, its last run and result, failures in 24 hours, work left and done in 24 hours where the job has a queue, the
-- latest worker summary, and what is waiting for a person. Read only.

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
  ('scholarship-discover-refill', 'Scholarships', 15, 'Line up providers for discovery', 'Keeps 30 providers waiting for scholarship discovery, adding the largest not yet searched.', 5, false),
  ('scholarship-savings', 'Scholarships', 70, 'Work out scholarship savings', 'Works out the saving a year for percentage-off-tuition scholarships from each course''s annual international fee.', 5, false)
on conflict (jobname) do nothing;

-- the top-level counts of a worker's reply (lists left out); null when it is not JSON
create or replace function security.live_worker_summary(p_content text) returns jsonb
language plpgsql immutable set search_path = '' as $fn$
declare j jsonb;
begin
  begin j := p_content::jsonb; exception when others then return null; end;
  if jsonb_typeof(j) <> 'object' then return null; end if;
  return (select jsonb_object_agg(e.key, e.value) from jsonb_each(j) e
           where jsonb_typeof(e.value) in ('number','string','boolean')
              or (jsonb_typeof(e.value) = 'object' and e.key in ('tally','changes','candidates')));
end $fn$;

create or replace function security.admin_live_activity_v1() returns jsonb
language plpgsql stable security definer set search_path = '' as $fn$
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
           (select count(*) from pipeline.layer3_work_items where task_class = 'provider_current_tuition_validation' and completed_at > now() - interval '24 hours')),
  jobs as (
    select a.jobname, a.area, a.sort, a.label, a.description, j.schedule, j.active,
           coalesce(g.running, false) running, coalesce(g.runs_24h, 0) runs_24h, coalesce(g.failed_24h, 0) failed_24h,
           r.start_time last_start, r.end_time last_end, r.status last_status, left(r.return_message, 240) last_message,
           q.unit, q.work_left, q.done_24h,
           substring(j.command from '"mode":"([a-z_]+)"') worker_mode, substring(j.command from '"task":"([a-z_]+)"') worker_task
      from pipeline.automation_catalogue a join cron.job j on j.jobname = a.jobname
      left join agg g on g.jobid = j.jobid
      left join runs r on r.jobid = j.jobid and r.rn = 1
      left join q on q.jobname = a.jobname),
  -- the latest summary each coverage-sweep worker mode returned (kept a few hours by pg_net)
  worker as (
    select m.mode, m.task, x.content, x.created at
      from (select distinct worker_mode mode, worker_task task from jobs where worker_mode is not null) m
      left join lateral (select h.content, h.created from net._http_response h
                          where h.status_code = 200 and h.content like '%"mode":"' || m.mode || '"%'
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
    'in_flight', (select count(*) from net.http_request_queue)
  ) into v;
  return v;
end $fn$;
revoke all on function security.admin_live_activity_v1() from public, anon;
grant execute on function security.admin_live_activity_v1() to authenticated;

-- through public.admin_read (runs as the signed-in user)
do $r$
declare s text; d text; v text;
  o text := $o$if p_operation='platform_health' then return security.admin_platform_health_v1(p_args); end if;$o$;
  n text := $n$if p_operation='platform_health' then return security.admin_platform_health_v1(p_args); end if;
 if p_operation='live_activity' then return security.admin_live_activity_v1(); end if;$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'admin_read';
  v := md5(s);
  if v is distinct from '37a306b7181912d59ee61b2f8cd53c04' then raise exception 'admin_read changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'platform health route not found once'; end if;
  execute replace(d, o, n);
end $r$;
