-- CF-247 Operations backend alignment: Task manager time-out, stranded tasks, health checks that follow the dispatchers, Storage & retention
-- staging figures and an Evidence audit trail (S2-Build, Platform Admin 18 Nov 2026 12:49, screenshots of v2.16.36).
--
-- What was read live (18 Nov 2026 13:00 to 13:40 AEDT)
--   * Scheduled jobs › Task manager (admin_jobs read with running) took 9.4 s against the 8 s statement time-out of the signed-in role
--     (ref KEW72U). 10.4 s of it was security.admin_job_status_v1 over the 50 newest running tasks: each call looked up the last run of job
--     admin-jobs with max(start_time) over cron.job_run_details (160,000 rows, no index on jobid). Scheduled jobs › Jobs (pipeline_jobs_page)
--     reads in 0.37 s and is not changed.
--   * 257 tasks were "running". 254 are AER entry readings (54 scheduled first reads, 200 corrected reads D-R2 of Layer 4 items), each with
--     one item waiting in state ai since 16-17 Nov: the AI route course_entry_requirements is switched off on Models & services, so
--     public.svc_enrich_ai_next hands them to no reader and they can never finish. Each corrected read also holds an open supersession
--     (pipeline.aer_read_supersessions, state requested) that keeps its Layer 4 item out of later recovery. The scheduled entry reading
--     (aer-scheduled-read) does not check that route, so it would ask for more reads the moment these close.
--   * The other 3 are Find course pages tasks a person started. Task manager said "the course page search lane is switched off": its cron
--     row course-link-search-worker is off because coverage-lane-dispatch runs that worker live. The real hold is today's Firecrawl share for
--     course search (0 left). They are genuine waiting work and are kept; the reason is corrected.
--   * Platform health (18 checks): Scholarship queues read critical "its scheduled job is missing or paused" for scholarship-read and
--     scholarship-discover, which the Platform Admin paused on 17 Nov 13:11 for the bulk ingestion (pause recorded, temporary). The work
--     queue watchdog showed seven queues "Switched off by a person" whose jobs coverage-lane-dispatch runs live, and "Read scholarship pages"
--     stuck behind the same paused job. Nothing checked the dispatchers themselves, the Boost caps, the Layer 4 backlog or G1/G3 parity.
--   * Storage & retention had sizes and purge categories but no staging-table figures; Evidence had no trail of dispatcher runs, Boost
--     qualifications or Layer 4 decisions.
--
-- What it changes
--   1. security.admin_job_status_v1: the last admin-jobs run is read newest-first by run id (index scan, 0.3 ms instead of about 180 ms a task).
--   2. security.job_dispatched_v1(job) and security.job_paused_by_person_v1(job): the dispatcher (rollup-scheduler, coverage-lane-dispatch,
--      admission-rule-runner) that runs a legacy job live, and the recorded pause of a job a person switched off.
--   3. security.link_search_block_v1, security.queue_watch_run_v1 and security.platform_health_stall_v1 treat a job a dispatcher runs as
--      running; a queue waiting on a job a person paused (with a recorded pause) reads "paused" with that pause's reason, not stuck or
--      critical. A job with no cron row and no dispatcher, or switched off with no recorded pause, still raises as before.
--   4. security.aer_schedule_tick_v1 (AER v1, correctness fix under Decision 276): asks for no new or corrected course read while the AI
--      route course_entry_requirements is held; matrix page refreshes are unchanged.
--   5. The 254 stranded AER tasks are closed (cancelled with the reason), their items skipped with the reason, and their open supersessions
--      closed as refused, only while that route is held at apply time. Values, Layer 4 items and evidence are not touched.
--   6. security.platform_health_consolidated_v1 (rollup-scheduler target platform-health-consolidated, every 10 minutes) records four more
--      checks on Platform health: Dispatchers, Boost admission and spend, Layer 4 backlog, Guardrails G1 and G3. Their issues use their own
--      check keys and resolve themselves when they clear.
--   7. Storage & retention: admin_retention read returns storage (staging tables, rows and size, what the nightly staging retention would
--      remove and its switch). Evidence: public.admin_ops_audit_v1, the latest dispatcher runs, Boost model qualifications and Layer 4
--      decisions, read-only.
-- Nothing is dropped or deleted. No catalogue value is changed. G3 untouched (no consumer function, table or column is touched).
-- Replaces: the cron-row-only job state in the Task manager block reason, the work-queue watchdog and the platform health stall check;
--           the max() run lookup in security.admin_job_status_v1.
-- Retires: nothing (the 254 tasks are closed, not removed).

-- 0. a local helper for guarded single-substring edits of a live function body
create or replace function pg_temp.cf_edit(p_sig regprocedure, p_md5 text, p_old text, p_new text, p_marker text)
returns void language plpgsql as $f$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig); v_def text; v_c int;
begin
  if position(p_marker in v_src) > 0 then raise notice '%: already applied', p_sig; return; end if;
  if md5(v_src) <> p_md5 then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(pg_get_functiondef(p_sig), chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
  if md5((select p.prosrc from pg_proc p where p.oid = p_sig)) <> md5(replace(v_src, p_old, p_new)) then
    raise exception '% after the edit is not the expected body', p_sig;
  end if;
end $f$;

-- 1. settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'health.dispatcher_stale_minutes', 'Platform health: a dispatcher is late after',
  'Dispatchers (rollup-scheduler, coverage-lane-dispatch, admission-rule-runner) run every minute. With no successful run for this many minutes the Dispatchers check raises a warning.',
  'number', '5'::jsonb, 2, 60, 'minutes', 790, 'S2-Build, Platform Admin 18 Nov 2026 12:49', 'Platform upkeep', 'security.platform_health_consolidated_v1'),
 ('pipeline', 'health.layer4_pending_warn', 'Platform health: Layer 4 backlog warning at',
  'Items waiting in Layer 4 review. At or above this count the Layer 4 backlog check raises a warning.',
  'number', '6000'::jsonb, 100, 100000, 'items', 791, 'S2-Build, Platform Admin 18 Nov 2026 12:49; 4,959 waiting on 18 Nov', 'Platform upkeep', 'security.platform_health_consolidated_v1'),
 ('pipeline', 'health.layer4_oldest_warn_days', 'Platform health: Layer 4 oldest item warning after',
  'The oldest item waiting in Layer 4 review. Older than this many days, the Layer 4 backlog check raises a warning.',
  'number', '45'::jsonb, 1, 365, 'days', 792, 'S2-Build, Platform Admin 18 Nov 2026 12:49; oldest 25 Oct on 18 Nov', 'Platform upkeep', 'security.platform_health_consolidated_v1'),
 ('pipeline', 'audit.trail_rows', 'Evidence audit trail: rows per list',
  'How many of the latest dispatcher runs, Boost qualifications and Layer 4 decisions the Evidence audit trail shows in each list.',
  'number', '50'::jsonb, 10, 200, 'rows', 793, 'S2-Build, Platform Admin 18 Nov 2026 12:49', 'Platform upkeep', 'public.admin_ops_audit_v1')
on conflict (toolset_key, key) do nothing;

-- 2. which dispatcher runs a legacy job, and the recorded pause of a job a person switched off
create or replace function security.job_dispatched_v1(p_job text)
returns text language sql stable security definer set search_path to '' as $f$
  select coalesce(
    (select 'rollup-scheduler' from pipeline.rollup_targets r where r.legacy_job = p_job and r.enabled and r.mode = 'live' limit 1),
    (select 'coverage-lane-dispatch' from pipeline.field_execution_registry f where f.legacy_job = p_job and f.enabled and f.mode = 'live' limit 1),
    (select 'admission-rule-runner' from pipeline.admission_rules a where a.legacy_job = p_job and a.enabled and a.mode = 'live' limit 1))
$f$;
comment on function security.job_dispatched_v1(text) is
  'CF-247 18 Nov 2026: the dispatcher that runs a legacy cron job live (its cron row is off after the cutover), or null.';

create or replace function security.job_paused_by_person_v1(p_job text)
returns jsonb language sql stable security definer set search_path to '' as $f$
  select jsonb_build_object('at', e.created_at, 'reason', coalesce(e.detail->>'reason', 'switched off on Automations'), 'temporary', coalesce((e.detail->>'temporary')::boolean, false))
    from cron.job j
    join lateral (select x.* from pipeline.admin_control_events x where x.area = 'automations' and x.target = p_job and x.action in ('pause', 'resume')
                   order by x.id desc limit 1) e on e.action = 'pause'
   where j.jobname = p_job and not j.active
$f$;
comment on function security.job_paused_by_person_v1(text) is
  'CF-247 18 Nov 2026: the latest recorded pause of a cron job that is switched off (area automations, newer than any resume), or null.';
revoke all on function security.job_dispatched_v1(text) from public, anon, authenticated;
revoke all on function security.job_paused_by_person_v1(text) from public, anon, authenticated;

-- 3. Task manager: index-backed last run of the task runner
select pg_temp.cf_edit('security.admin_job_status_v1(uuid)'::regprocedure, '1b70a367c5bab3d65528e08b16e981f5',
  '(select max(d.start_time) from cron.job_run_details d where d.jobid = c.jobid) last_run',
  '(select d.start_time from cron.job_run_details d where d.jobid = c.jobid order by d.runid desc limit 1) last_run',
  'order by d.runid desc limit 1) last_run');

-- 4. Find course pages: the search worker that a dispatcher runs is not "switched off"
select pg_temp.cf_edit('security.link_search_block_v1(uuid,uuid[])'::regprocedure, '17d1361308106379c5feb119c7b26613',
  'if v_job.active is distinct from true and v_flag.flagged_at is null then',
  'if v_job.active is distinct from true and v_flag.flagged_at is null and security.job_dispatched_v1(''course-link-search-worker'') is null then',
  'security.job_dispatched_v1(''course-link-search-worker'') is null');

-- 5. work-queue watchdog: a dispatched job is not paused; a queue waiting on a job a person paused reads paused, not stuck
select pg_temp.cf_edit('security.queue_watch_run_v1(boolean)'::regprocedure, 'bdb83b3873fc0eecbb0c446626f73edd',
  'where not j.active and not exists',
  'where not j.active and security.job_dispatched_v1(j.jobname) is null and not exists',
  'security.job_dispatched_v1(j.jobname) is null');
select pg_temp.cf_edit('security.queue_watch_run_v1(boolean)'::regprocedure,
  md5(replace((select p.prosrc from pg_proc p where p.oid = 'security.queue_watch_run_v1(boolean)'::regprocedure), chr(13), '')),
  'v_state := ''stuck''; v_reason := ',
  'v_state := case when cardinality(v_paused) > 0 then ''paused'' else ''stuck'' end; v_reason := case when cardinality(v_paused) > 0 then ''Waiting on a job switched off by a person: '' || array_to_string(v_paused, '', '') || ''; '' else '''' end || ',
  'Waiting on a job switched off by a person: ');

-- 6. platform health stall check: dispatched jobs run; a recorded pause by a person is information, not a breakage
do $e$
begin
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.platform_health_stall_v1(text,text,text,text,timestamp with time zone,text,integer)'::regprocedure))
     not in ('06ab0ba96c5a353558d1ac5a2d3489fe') and position('job_paused_by_person_v1' in (select p.prosrc from pg_proc p where p.proname = 'platform_health_stall_v1')) = 0 then
    raise exception 'live security.platform_health_stall_v1 differs from the definition this change replaces';
  end if;
end $e$;

create or replace function security.platform_health_stall_v1(p_key text, p_area text, p_label text, p_job text, p_last_progress timestamp with time zone,
                                                               p_pending_sql text, p_default_interval_s integer default 600)
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog', 'pipeline', 'security', 'public', 'catalogue', 'scholarship' as $function$
declare v_int int; v_active boolean; v_warn interval; v_crit interval; v_pending bigint; v_age interval:=now()-coalesce(p_last_progress,'-infinity'::timestamptz); v_unit boolean:=false;
        v_disp text; v_pause jsonb;
begin
  select security.platform_cron_interval_seconds(j.schedule), j.active into v_int, v_active from cron.job j where j.jobname=p_job;
  -- 18 Nov 2026 (S2-Build): a legacy job a dispatcher runs live is running, on the dispatcher's own schedule for it
  v_disp:=security.job_dispatched_v1(p_job);
  if v_disp is not null then
    v_active:=true;
    v_int:=coalesce(security.platform_cron_interval_seconds(coalesce(
             (select r.schedule from pipeline.rollup_targets r where r.legacy_job=p_job and r.enabled and r.mode='live' limit 1),
             (select f.schedule from pipeline.field_execution_registry f where f.legacy_job=p_job and f.enabled and f.mode='live' limit 1),
             (select a.schedule from pipeline.admission_rules a where a.legacy_job=p_job and a.enabled and a.mode='live' limit 1))), v_int);
  end if;
  v_int:=coalesce(v_int,p_default_interval_s);
  v_warn:=greatest(make_interval(secs=>3*v_int), interval '15 minutes');  -- fixed: the stall rule of this check (three runs, at least 15 minutes)
  v_crit:=greatest(make_interval(secs=>12*v_int), interval '2 hours');    -- fixed: as above (twelve runs, at least 2 hours)
  if v_age <= v_warn then
    return jsonb_build_object('queue',p_key,'status','moving','last_progress',p_last_progress) || case when v_disp is not null then jsonb_build_object('dispatcher',v_disp) else '{}'::jsonb end;
  end if;
  execute p_pending_sql into v_pending;
  if coalesce(v_pending,0)=0 then
    return jsonb_build_object('queue',p_key,'status','idle','pending',0,'last_progress',p_last_progress);
  end if;
  -- 18 Nov 2026 (S2-Build): a job a person switched off with a recorded pause (Automations, or a migration that logged it) waits by decision
  if v_active is false then
    v_pause:=security.job_paused_by_person_v1(p_job);
    if v_pause is not null then
      return jsonb_build_object('queue',p_key,'status','paused','pending',v_pending,'last_progress',p_last_progress,'job',p_job,'job_active',false,
        'paused_at',v_pause->>'at','paused_reason',v_pause->>'reason','temporary',(v_pause->>'temporary')::boolean);
    end if;
  end if;
  -- SS-014 (31 Oct 2026): a job the flag unit paused because its runs found nothing is switched on again by the flag unit when work
  -- waits (security.flag_jobs_v1, security.waste_idle_guard_v1); until the critical age that is information, not a breakage
  if v_active is false then
    select true into v_unit from pipeline.enrichment_flags f
     where f.entity='job' and f.entity_key=p_job and f.field='' and f.reason_code='idle_paused' and f.cleared_at is null and coalesce(f.state,'raised')='raised' limit 1;
    v_unit:=coalesce(v_unit,false);
  end if;
  return jsonb_build_object('queue',p_key,'status','stalled','pending',v_pending,'last_progress',p_last_progress,
    'job',p_job,'job_active',coalesce(v_active,false),'dispatcher',v_disp,'paused_by_flag_unit',v_unit,'stalled_minutes',round(extract(epoch from least(v_age, interval '365 days'))/60),
    'threshold_minutes',round(extract(epoch from v_warn)/60),
    'issue',security.platform_health_issue_v1(p_key,
      case when v_age>v_crit or (coalesce(v_active,false)=false and not v_unit) then 'critical' when v_unit then 'info' else 'warning' end, p_area,
      p_label||' has stopped: '||v_pending||' waiting, nothing processed for '||
        case when p_last_progress is null then 'as long as records exist' else round(extract(epoch from v_age)/60)||' minutes' end||
        case when v_unit then ' (its job is paused because its recent runs found nothing; the flag unit switches it on again when work is waiting)'
             when v_active is distinct from true then ' (its scheduled job is missing, or switched off with no recorded pause)'
             when v_disp is not null then ' (run by '||v_disp||')' else '' end,
      jsonb_build_object('pending',v_pending,'last_progress',p_last_progress,'job',p_job,'job_active',coalesce(v_active,false),'dispatcher',v_disp,
        'threshold_minutes',round(extract(epoch from v_warn)/60))));
end $function$;

-- 7. AER scheduled reading (v1, correctness fix): no course read is asked while its AI route is held
select pg_temp.cf_edit('security.aer_schedule_tick_v1(boolean)'::regprocedure, '800af9161234c24387bff6a74d6acb99',
  'when v_ai is not null then',
  'when (security.ai_enrich_routes_v1()->''held'') ? ''course_entry_requirements'' then ''the entry requirements AI route is held: '' || (security.ai_enrich_routes_v1()->''held''->>''course_entry_requirements'') || ''; no course read is asked until it is on'' -- 18 Nov 2026 (S2-Build): reads asked of a held route never finish
                when v_ai is not null then',
  'the entry requirements AI route is held: ');

-- 8. the stranded AER tasks (only while the route is held at apply time)
do $e$
declare v_jobs uuid[]; v_items int := 0; v_sup int := 0; r record;
        v_why constant text := 'not read: the entry requirements AI route is switched off (Models & services); the task was closed on 18 Nov 2026 (Platform Admin 12:49, S2-Build) and is asked again only when the route is on';
begin
  if not ((security.ai_enrich_routes_v1()->'held') ? 'course_entry_requirements') then
    raise notice 'the entry requirements route is not held: no task closed'; return;
  end if;
  select coalesce(array_agg(j.id), '{}') into v_jobs
    from pipeline.admin_jobs j
   where j.kind = 'enrich_fields' and j.state = 'running'
     and exists (select 1 from pipeline.field_enrich_items i where i.job_id = j.id)
     and not exists (select 1 from pipeline.field_enrich_items i where i.job_id = j.id and not (i.field = 'entry_requirements' and i.state in ('ai', 'queued', 'waiting')));
  update pipeline.field_enrich_items i set state = 'skipped', reason = v_why, leased_until = null, updated_at = now()
   where i.job_id = any (v_jobs) and i.state in ('ai', 'queued', 'waiting');
  get diagnostics v_items = row_count;
  for r in select s.id from pipeline.aer_read_supersessions s where s.state = 'requested' and s.job_id = any (v_jobs) loop
    perform security.aer_read_supersession_close_v1(r.id, 'refused', 'the corrected read was not made: the entry requirements AI route is switched off (Models & services)', null, null);
    v_sup := v_sup + 1;
  end loop;
  update pipeline.admin_jobs set state = 'cancelled', finished_at = now(), updated_at = now(), cancel_requested = true,
         result = coalesce(result, '{}'::jsonb) || jsonb_build_object('closed_because', v_why)
   where id = any (v_jobs);
  insert into pipeline.admin_job_events(job_id, note, detail)
  select x, 'closed: superseded (the entry requirements AI route is switched off)', jsonb_build_object('reason', v_why, 'by', 'migration 20261118160000')
    from unnest(v_jobs) x;
  perform security.admin_job_close_v1(x) from unnest(v_jobs) x;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('jobs', 'tasks_closed', 'enrich_fields (entry requirements)',
          jsonb_build_object('tasks', cardinality(v_jobs), 'items_skipped', v_items, 'supersessions_refused', v_sup, 'reason', v_why,
                             'by', 'migration 20261118160000', 'decision', 'Platform Admin 18 Nov 2026 12:49 (S2-Build)'), null);
  raise notice 'closed % tasks, % items skipped, % supersessions refused', cardinality(v_jobs), v_items, v_sup;
end $e$;

-- 9. four more Platform health checks
create or replace function security.platform_health_consolidated_v1()
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_stale interval := make_interval(mins => security.pipeline_num_v1('health.dispatcher_stale_minutes', 5)::int);
        v_l4warn int := security.pipeline_num_v1('health.layer4_pending_warn', 6000)::int;
        v_l4days int := security.pipeline_num_v1('health.layer4_oldest_warn_days', 45)::int;
        v_found jsonb := '[]'::jsonb; v_det jsonb := '{}'::jsonb; v_x jsonb; v_t timestamptz; v_n int; v_m int; v_ts timestamptz; r record;
        v_keys constant text[] := array['dispatchers', 'boost', 'layer4_backlog', 'guardrails'];
begin
  -- Dispatchers: each dispatcher cron job runs and succeeds; live targets that fail or are held open
  v_t := clock_timestamp(); v_x := '[]'::jsonb;
  for r in select c.jobname, c.active,
                  (select d.status from cron.job_run_details d where d.jobid = c.jobid order by d.runid desc limit 1) last_status,
                  (select max(d.start_time) from (select d2.start_time from cron.job_run_details d2 where d2.jobid = c.jobid and d2.status = 'succeeded' order by d2.runid desc limit 1) d) last_ok
             from cron.job c where c.jobname ~ '^(rollup-scheduler|coverage-lane-dispatch(-[bc])?|admission-rule-runner(-[bc])?)$' order by c.jobname loop
    v_x := v_x || jsonb_build_object('job', r.jobname, 'active', r.active, 'last_status', r.last_status, 'last_ok', r.last_ok);
    if not r.active or r.last_ok is null or r.last_ok < now() - v_stale then
      v_found := v_found || security.platform_health_issue_v1('dispatchers:' || r.jobname, 'critical', 'scheduled jobs',
        'Dispatcher ' || r.jobname || case when not r.active then ' is switched off' else ' has not run successfully since ' || coalesce(to_char(r.last_ok at time zone 'Australia/Sydney', 'DD Mon HH24:MI'), 'it started') end,
        jsonb_build_object('job', r.jobname, 'active', r.active, 'last_ok', r.last_ok, 'last_status', r.last_status));
    end if;
  end loop;
  select count(*) filter (where t.last_status = 'failed'), count(*) filter (where t.mode = 'shadow') into v_n, v_m from pipeline.rollup_targets t where t.enabled;
  if v_n > 0 then
    v_found := v_found || security.platform_health_issue_v1('dispatchers:rollup_targets', 'warning', 'scheduled jobs',
      v_n || ' rollup-scheduler target(s) failed on their last run: ' || (select string_agg(t.target_code, ', ' order by t.target_code) from pipeline.rollup_targets t where t.enabled and t.last_status = 'failed'),
      jsonb_build_object('failed', (select jsonb_agg(jsonb_build_object('target', t.target_code, 'error', left(t.last_error, 200), 'at', t.last_finished_at)) from pipeline.rollup_targets t where t.enabled and t.last_status = 'failed')));
  end if;
  v_det := v_det || jsonb_build_object('dispatchers', jsonb_build_object('jobs', v_x,
    'rollup_targets', jsonb_build_object('enabled', (select count(*) from pipeline.rollup_targets t where t.enabled), 'failed', v_n, 'shadow', v_m),
    'coverage_lanes', (select jsonb_build_object('enabled', count(*), 'live', count(*) filter (where f.mode = 'live'), 'held_open', count(*) filter (where f.open_until > now()),
                              'failing', count(*) filter (where f.consecutive_failures > 0)) from pipeline.field_execution_registry f where f.enabled),
    'admission_rules', (select jsonb_build_object('enabled', count(*), 'live', count(*) filter (where a.mode = 'live'), 'held_open', count(*) filter (where a.open_until > now()),
                               'failing', count(*) filter (where a.consecutive_failures > 0)) from pipeline.admission_rules a where a.enabled),
    'ms', round(extract(epoch from clock_timestamp() - v_t) * 1000)));
  select count(*) into v_n from pipeline.field_execution_registry f where f.enabled and f.mode = 'live' and f.open_until > now();
  if v_n > 0 then
    v_found := v_found || security.platform_health_issue_v1('dispatchers:coverage_lanes', 'warning', 'scheduled jobs',
      v_n || ' coverage-lane-dispatch lane(s) are held after repeated failures: ' || (select string_agg(f.lane_code, ', ' order by f.lane_code) from pipeline.field_execution_registry f where f.enabled and f.mode = 'live' and f.open_until > now()),
      jsonb_build_object('lanes', (select jsonb_agg(jsonb_build_object('lane', f.lane_code, 'until', f.open_until, 'error', left(f.last_error, 200))) from pipeline.field_execution_registry f where f.enabled and f.mode = 'live' and f.open_until > now())));
  end if;

  -- Boost: switches, the Layer 4 admission cap, staging, qualified models and spend (last 24 hours)
  v_t := clock_timestamp();
  select count(*) into v_n from pipeline.boost_study_load_reviews b where b.status = 'open';
  v_det := v_det || jsonb_build_object('boost', jsonb_build_object(
    'switches', jsonb_build_object('ingest', security.pipeline_num_v1('boost.ingest_on', 0) >= 1, 'extract', security.pipeline_num_v1('boost.extract_on', 0) >= 1,
                                   'fields', security.pipeline_num_v1('boost.fields_on', 0) >= 1, 'benchmark', security.pipeline_num_v1('boost.benchmark_on', 0) >= 1),
    'layer4_open', v_n, 'layer4_open_max', security.pipeline_num_v1('boost.layer4_open_max', 400)::int,
    'staging', (select coalesce(jsonb_object_agg(z.promotion_state, z.n), '{}'::jsonb) from (select s.promotion_state, count(*) n from pipeline.boost_inbound_staging s group by 1) z),
    'qualified', (select coalesce(jsonb_agg(jsonb_build_object('lane', q.lane, 'model', q.model, 'at', q.qualified_at)), '[]'::jsonb) from pipeline.boost_model_qualifications q),
    'spend_24h_usd', (select coalesce(jsonb_object_agg(z.lane, z.usd), '{}'::jsonb) from (select l.lane, round(sum(l.cost_usd), 4) usd from pipeline.ai_spend_ledger l where l.at > now() - interval '1 day' and l.lane like 'boost%' group by 1) z),  -- fixed: the 24-hour window this report states
    'ai_daily_ceiling_usd', security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14),
    'ai_refusal', security.ai_use_refusal_v1('enrich_fields'),
    'ms', round(extract(epoch from clock_timestamp() - v_t) * 1000)));
  for r in select c.jobname, (select d.status from cron.job_run_details d where d.jobid = c.jobid order by d.runid desc limit 1) st,
                  (select left(d.return_message, 200) from cron.job_run_details d where d.jobid = c.jobid order by d.runid desc limit 1) msg
             from cron.job c where c.active and c.jobname ~ '^(boost-|worker-boost-)' loop
    if r.st = 'failed' then
      v_found := v_found || security.platform_health_issue_v1('boost:' || r.jobname, 'warning', 'boost', 'Boost job ' || r.jobname || ' failed on its last run', jsonb_build_object('job', r.jobname, 'error', r.msg));
    end if;
  end loop;

  -- Layer 4 backlog: waiting items, the oldest, and the last 24 hours in and out
  v_t := clock_timestamp();
  select count(*), min(i.created_at) into v_n, v_ts from pipeline.layer4_review_items i where i.status = 'pending';
  v_det := v_det || jsonb_build_object('layer4_backlog', jsonb_build_object('pending', v_n, 'oldest', v_ts, 'warn_at', v_l4warn, 'oldest_warn_days', v_l4days,
    'created_24h', (select count(*) from pipeline.layer4_review_items i where i.created_at > now() - interval '1 day'),  -- fixed: the 24-hour window this report states
    'decided_24h', (select count(*) from pipeline.layer4_decisions d where d.created_at > now() - interval '1 day'),     -- fixed: as above
    'by_field', (select coalesce(jsonb_object_agg(z.field_code, z.n), '{}'::jsonb) from (select i.field_code, count(*) n from pipeline.layer4_review_items i where i.status = 'pending' group by 1 order by 2 desc limit 12) z),
    'ms', round(extract(epoch from clock_timestamp() - v_t) * 1000)));
  if v_n >= v_l4warn then
    v_found := v_found || security.platform_health_issue_v1('layer4_backlog:pending', 'warning', 'Layer 4', v_n || ' items wait in Layer 4 review (warning at ' || v_l4warn || ')', jsonb_build_object('pending', v_n));
  end if;
  if v_ts < now() - make_interval(days => v_l4days) then
    v_found := v_found || security.platform_health_issue_v1('layer4_backlog:oldest', 'warning', 'Layer 4', 'The oldest Layer 4 item has waited since ' || to_char(v_ts at time zone 'Australia/Sydney', 'DD Mon YYYY'), jsonb_build_object('oldest', v_ts));
  end if;

  -- Guardrails: G1 (every running job catalogued) and G3 (consumer API matches its baseline)
  v_t := clock_timestamp();
  select count(*) into v_n from cron.job c where c.active and not exists (select 1 from pipeline.automation_catalogue a where a.jobname = c.jobname);
  select count(*) into v_m from pipeline.enrichment_flags f where f.entity = 'api' and f.entity_key = 'consumer' and f.reason_code = 'consumer_api_drift' and f.state = 'raised';
  v_det := v_det || jsonb_build_object('guardrails', jsonb_build_object(
    'g1_uncatalogued_jobs', v_n,
    'g1_uncatalogued', (select coalesce(jsonb_agg(c.jobname order by c.jobname), '[]'::jsonb) from cron.job c where c.active and not exists (select 1 from pipeline.automation_catalogue a where a.jobname = c.jobname)),
    'g3_functions', (select count(*) from security.consumer_api_functions_v1()), 'g3_relations', (select count(*) from security.consumer_api_relations_v1()),
    'g3_baseline_functions', (select count(*) from pipeline.consumer_api_baseline b where b.kind = 'function'),
    'g3_baseline_relations', (select count(*) from pipeline.consumer_api_baseline b where b.kind = 'relation'),
    'g3_drift_flag', v_m > 0,
    'ms', round(extract(epoch from clock_timestamp() - v_t) * 1000)));
  if v_n > 0 then
    v_found := v_found || security.platform_health_issue_v1('guardrails:g1', 'warning', 'scheduled jobs', v_n || ' running scheduled job(s) are not in the automation catalogue (G1)', v_det->'guardrails');
  end if;
  if v_m > 0 then
    v_found := v_found || security.platform_health_issue_v1('guardrails:g3', 'critical', 'search/API', 'The consumer API differs from its baseline (G3, Decision 266)', v_det->'guardrails');
  end if;

  -- record: issues (dedup on check_key), resolve what cleared, store the four checks
  for r in select distinct on (x.check_key) x.check_key, x.severity, x.area, x.title, x.detail
             from jsonb_to_recordset(v_found) x(check_key text, severity text, area text, title text, detail jsonb)
            order by x.check_key, case x.severity when 'critical' then 1 when 'warning' then 2 else 3 end loop
    insert into pipeline.platform_issues as i (check_key, severity, area, title, detail)
    values (r.check_key, r.severity, r.area, left(r.title, 300), coalesce(r.detail, '{}'::jsonb))
    on conflict (check_key) where resolved_at is null do update set severity = excluded.severity, area = excluded.area, title = excluded.title,
      detail = excluded.detail, last_seen = now(), occurrences = i.occurrences + 1;
  end loop;
  update pipeline.platform_issues i set resolved_at = now()
   where i.resolved_at is null and split_part(i.check_key, ':', 1) = any (v_keys)
     and not exists (select 1 from jsonb_array_elements(v_found) f where f->>'check_key' = i.check_key);
  insert into pipeline.platform_health_checks as c (key, area, label, status, detail, checked_at, duration_ms, cadence_minutes, slow, sort_order)
  select k.key, k.area, k.label,
         coalesce((select case min(case f->>'severity' when 'critical' then 1 when 'warning' then 2 else 3 end) when 1 then 'critical' when 2 then 'warning' else 'ok' end
                     from jsonb_array_elements(v_found) f where split_part(f->>'check_key', ':', 1) = k.key), 'ok'),
         v_det->k.key, now(), (v_det->k.key->>'ms')::int, 10, false, k.sort  -- fixed: the cadence of target platform-health-consolidated
    from (values ('dispatchers', 'scheduled jobs', 'Dispatchers run: rollup-scheduler, coverage-lane-dispatch, admission-rule-runner', 15),
                 ('boost', 'boost', 'Boost admission and spend: switches, Layer 4 cap, staging, qualified models', 175),
                 ('layer4_backlog', 'Layer 4', 'Layer 4 review backlog: waiting, oldest, in and out', 65),
                 ('guardrails', 'governance', 'Guardrails: G1 every job catalogued, G3 consumer API unchanged', 5)) k(key, area, label, sort)
  on conflict (key) do update set area = excluded.area, label = excluded.label, status = excluded.status, detail = excluded.detail,
    checked_at = excluded.checked_at, duration_ms = excluded.duration_ms, cadence_minutes = excluded.cadence_minutes, sort_order = excluded.sort_order;
  return jsonb_build_object('issues', jsonb_array_length(v_found), 'checks', v_det);
end $f$;
comment on function security.platform_health_consolidated_v1() is
  'CF-247 18 Nov 2026 (S2-Build, Platform Admin 12:49): Platform health checks Dispatchers, Boost, Layer 4 backlog and Guardrails (G1, G3); rollup-scheduler target platform-health-consolidated.';
revoke all on function security.platform_health_consolidated_v1() from public, anon, authenticated;

insert into pipeline.rollup_targets(target_code, legacy_job, call_sql, call_md5, schedule, rollup_group, priority, enabled, mode, expected_ms, note)
values ('platform-health-consolidated', null, 'select security.platform_health_consolidated_v1()', md5('select security.platform_health_consolidated_v1()'),
        '4-59/10 * * * *', 'A', 40, true, 'live', 2000,
        'CF-247 18 Nov 2026 (Platform Admin 12:49): new target, no legacy job; Platform health checks Dispatchers, Boost, Layer 4 backlog, Guardrails')
on conflict (target_code) do nothing;

-- 10. Storage & retention: staging tables and the nightly staging retention
create or replace function security.retention_storage_v1()
returns jsonb language sql stable security definer set search_path to '' as $f$
  select jsonb_build_object(
    'staging', (select coalesce(jsonb_agg(jsonb_build_object('table', n.nspname || '.' || c.relname, 'rows', greatest(c.reltuples, 0)::bigint,
                                  'bytes', pg_catalog.pg_total_relation_size(c.oid)) order by pg_catalog.pg_total_relation_size(c.oid) desc), '[]'::jsonb)
                  from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
                 where c.relkind = 'r' and n.nspname = 'pipeline'
                   and c.relname in ('source_record_staging', 'boost_inbound_staging', 'staging_hash_ledger', 'boost_extract_items', 'boost_field_items',
                                     'boost_field_candidates', 'boost_benchmark_items', 'boost_ingest_files', 'firecrawl_run_items', 'firecrawl_calls', 'firecrawl_target_cache')),
    'boost_states', (select coalesce(jsonb_object_agg(z.promotion_state, z.n), '{}'::jsonb) from (select b.promotion_state, count(*) n from pipeline.boost_inbound_staging b group by 1) z),
    'prune', jsonb_build_object(
      'on', security.pipeline_num_v1('retention.staging_prune_on', 0) >= 1,
      'keep_days', security.pipeline_num_v1('retention.staging_keep_days', 90),
      'boost_keep_days', security.pipeline_num_v1('retention.boost_staging_keep_days', 90),
      'raw_hash_keep_years', security.pipeline_num_v1('retention.raw_hash_keep_years', 7),
      'rows_per_run', security.pipeline_num_v1('batch.staging_prune_rows', 1000),
      'would_go_staging', (select count(*) from pipeline.source_record_staging s left join pipeline.source_retention_policies p on p.source_id = s.source_id
                            where s.status = 'processed' and s.processed_at < now() - make_interval(days => coalesce(p.staging_keep_days, security.pipeline_num_v1('retention.staging_keep_days', 90)::int))),
      'would_go_boost', (select count(*) from pipeline.boost_inbound_staging b where b.promotion_state in ('shadow', 'proposed', 'refused') and b.promoted_at is not null
                          and b.promoted_at < now() - make_interval(days => security.pipeline_num_v1('retention.boost_staging_keep_days', 90)::int)),
      'ledger_rows', (select count(*) from pipeline.staging_hash_ledger),
      'last_runs', (select coalesce(jsonb_agg(jsonb_build_object('at', e.created_at, 'action', e.action, 'detail', e.detail) order by e.id desc), '[]'::jsonb)
                      from (select * from pipeline.admin_control_events x where x.area = 'retention' order by x.id desc limit 5) e)))  -- fixed: the five latest nights shown
$f$;
comment on function security.retention_storage_v1() is
  'CF-247 18 Nov 2026 (S2-Build): Storage & retention staging figures: staging tables (rows, size), Boost staging states, what the nightly staging retention would remove and its switch.';
revoke all on function security.retention_storage_v1() from public, anon, authenticated;

select pg_temp.cf_edit('public.admin_retention(text,jsonb)'::regprocedure, 'a88a77bbd26da57ff2d52762fcb5fe1a',
  '''database_bytes'', pg_database_size(current_database()),',
  '''database_bytes'', pg_database_size(current_database()),
      ''storage'', security.retention_storage_v1(),  -- 18 Nov 2026 (S2-Build): staging tables and the nightly staging retention',
  'security.retention_storage_v1()');

-- 11. Evidence: audit trail of dispatcher runs, Boost qualifications and Layer 4 decisions (read-only)
create or replace function public.admin_ops_audit_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path to '' as $f$
declare v_n int := greatest(1, least(security.pipeline_num_v1('audit.trail_rows', 50)::int, 200));  -- fixed: the hard ceiling of one list
        v_failed boolean := coalesce((p_args->>'failed_only')::boolean, false);
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator or above required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'dispatcher_runs', (select coalesce(jsonb_agg(x order by x->>'at' desc), '[]'::jsonb) from (
        select * from (
          (select jsonb_build_object('dispatcher', 'rollup-scheduler', 'target', r.target_code, 'mode', r.mode, 'status', r.status, 'at', r.started_at, 'ms', r.ms, 'error', left(r.error, 300)) x
             from pipeline.rollup_runs r where r.started_at is not null and (not v_failed or r.status = 'failed') order by r.tick_at desc limit v_n)
          union all
          (select jsonb_build_object('dispatcher', 'coverage-lane-dispatch', 'target', c.lane_code, 'mode', c.mode, 'status', c.status, 'at', c.started_at, 'ms', c.ms, 'error', left(c.error, 300))
             from pipeline.coverage_lane_runs c where c.started_at is not null and (not v_failed or c.status = 'failed') order by c.tick_at desc limit v_n)
          union all
          (select jsonb_build_object('dispatcher', 'admission-rule-runner', 'target', a.rule_code, 'mode', a.mode, 'status', a.status, 'at', a.started_at, 'ms', a.ms, 'error', left(a.error, 300))
             from pipeline.admission_rule_runs a where a.started_at is not null and (not v_failed or a.status = 'failed') order by a.tick_at desc limit v_n)) u
        order by u.x->>'at' desc limit v_n) z),
    'boost_qualifications', (select coalesce(jsonb_agg(jsonb_build_object('lane', q.lane, 'provider', q.provider, 'model', q.model, 'at', q.qualified_at,
                                     'by', (select u.email from auth.users u where u.id = q.qualified_by), 'reason', q.reason) order by q.qualified_at desc), '[]'::jsonb)
                               from pipeline.boost_model_qualifications q),
    'layer4_decisions', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'item_id', d.review_item_id, 'action', d.action, 'at', d.created_at, 'reason', left(d.reason, 300),
                                 'by', (select u.email from auth.users u where u.id = d.actor_id), 'field', i.field_code, 'entity_type', i.entity_type, 'entity_id', i.entity_id,
                                 'evidence_id', d.evidence_id) order by d.created_at desc), '[]'::jsonb)
                           from (select * from pipeline.layer4_decisions x order by x.created_at desc limit v_n) d
                           left join pipeline.layer4_review_items i on i.id = d.review_item_id),
    'rows', v_n, 'read_at', now());
end $f$;
comment on function public.admin_ops_audit_v1(jsonb) is
  'CF-247 18 Nov 2026 (S2-Build, Platform Admin 12:49): Evidence › Audit trail: latest dispatcher runs, Boost model qualifications and Layer 4 decisions. Read-only, Curator and above.';
revoke all on function public.admin_ops_audit_v1(jsonb) from public, anon;
grant execute on function public.admin_ops_audit_v1(jsonb) to authenticated;

-- 12. run the new checks once and register what is new
select security.platform_health_consolidated_v1();

insert into pipeline.component_register(kind, name, layer, area, purpose, status, introduced_in)
select v.kind, v.name, 'Operations', v.area, v.purpose, 'active', '20261118160000'
  from (values
    ('function', 'security.job_dispatched_v1', 'Platform health', 'The dispatcher that runs a legacy cron job live (used by Task manager, the work-queue watchdog and the health stall check)'),
    ('function', 'security.job_paused_by_person_v1', 'Platform health', 'The recorded pause of a switched-off cron job (a queue waiting on it reads paused, not stuck)'),
    ('function', 'security.platform_health_consolidated_v1', 'Platform health', 'Checks Dispatchers, Boost, Layer 4 backlog and Guardrails (rollup-scheduler target platform-health-consolidated, every 10 minutes)'),
    ('function', 'security.retention_storage_v1', 'Storage & retention', 'Staging tables, Boost staging states and the nightly staging retention figures on Platform health › Storage & retention'),
    ('function', 'public.admin_ops_audit_v1', 'Evidence', 'Evidence › Audit trail: latest dispatcher runs, Boost qualifications and Layer 4 decisions')) v(kind, name, area, purpose)
 where not exists (select 1 from pipeline.component_register r where r.kind = v.kind and r.name = v.name);

-- 13. post-checks
do $e$
begin
  if (select count(*) from security.consumer_api_functions_v1()) <> 75 or (select count(*) from security.consumer_api_relations_v1()) <> 48 then
    raise exception 'G3: the consumer API surface changed';
  end if;
  if exists (select 1 from pipeline.admin_jobs j where j.kind = 'enrich_fields' and j.state = 'running'
               and not exists (select 1 from pipeline.field_enrich_items i where i.job_id = j.id and not (i.field = 'entry_requirements' and i.state in ('ai', 'queued', 'waiting'))))
     and ((security.ai_enrich_routes_v1()->'held') ? 'course_entry_requirements') then
    raise exception 'stranded entry requirement tasks are still running';
  end if;
  if (select count(*) from pipeline.platform_health_checks where key in ('dispatchers', 'boost', 'layer4_backlog', 'guardrails')) <> 4 then
    raise exception 'the four new Platform health checks were not recorded';
  end if;
end $e$;
