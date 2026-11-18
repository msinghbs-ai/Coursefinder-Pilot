-- CF-247 Pipeline Maintenance Mode (Platform Admin 15 Nov 2026 17:49: "a reusable Pipeline Maintenance Mode control ... so I can gracefully
-- pause, drain, and resume busy background workers before any DB migration"; choices 17:5x: pause every active job, settings snapshot only,
-- one new setting for the alert time).
--   1. pipeline.maintenance_state (one row) and pipeline.maintenance_job_snapshot (the pre-pause copy of every cron job and every setting).
--   2. pipeline.pause_for_maintenance(reason): refuses a second pause (the first snapshot is never overwritten), copies cron.job and
--      pipeline.platform_toolset_settings, then switches off every active job (the controllers that switch jobs on again first).
--      Jobs already off stay off and are left alone on resume.
--   3. pipeline.get_maintenance_drain_status(): running cron runs, busy database sessions on catalogue or pipeline, edge worker calls that may
--      still be running, live worker leases, catalogue locks, jobs switched on again during the window; safe_to_migrate when all are 0.
--   4. pipeline.resume_from_maintenance(): switches on exactly the jobs the pause switched off (by name; a retiring or retired job stays off),
--      never writes a setting (the settings copy is for audit: resume lists what changed), and returns the count restored.
--   5. The controllers that switch jobs on again (security.flag_recheck_v1 for coverage-read and the other coverage-sweep lanes,
--      security.waste_idle_guard_v1, security.flag_requeue_v1) and the Automations control do nothing that switches a job on while the
--      pipeline is paused (md5-guarded edits). An advisory lock makes a pause wait for a controller already running.
--   6. public.admin_pipeline_maintenance(action, args): the Admin UI entry point (Scheduled jobs > Automations > Pipeline maintenance).
-- Who: pause and resume need the Platform Admin role (rank 6), as they change every automation; status can be read by any admin role.
-- The database owner (session postgres, e.g. a migration or the SQL editor) may also call them; it is recorded as "database owner".
-- G1: no new job. G2: one new setting, maintenance.alert_after_minutes (inserted; no existing setting is changed, post-check).
-- G3: no consumer API object is read or changed; the website and Zoho APIs keep answering while jobs are paused.
-- Replaces: security.flag_recheck_v1(), security.waste_idle_guard_v1(), security.flag_requeue_v1(bigint),
--   security.admin_automation_control_v1(text,text,jsonb) (same names and signatures; md5-guarded edits that add the maintenance check).
-- Retires: nothing.

set local lock_timeout = '5s';

select set_config('cf247.maint_before', jsonb_build_object(
  'settings', (select md5(string_agg(s.toolset_key || '.' || s.key || '=' || s.value::text, '|' order by s.toolset_key, s.key)) from pipeline.platform_toolset_settings s),
  'jobs', (select md5(string_agg(j.jobname || ':' || j.active || ':' || j.schedule || ':' || md5(j.command), '|' order by j.jobname)) from cron.job j))::text, false);

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_old text, p_new text) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
end $f$;

-- 1. State and snapshot
create table if not exists pipeline.maintenance_state (
  id boolean primary key default true check (id),
  is_paused boolean not null default false,
  window_id uuid,
  paused_at timestamptz,
  paused_by text,
  reason text,
  auto_alert_after_minutes int,
  resumed_at timestamptz,
  resumed_by text,
  last_result jsonb,
  updated_at timestamptz not null default now()
);
comment on table pipeline.maintenance_state is 'Pipeline Maintenance Mode: one row saying whether every scheduled job is paused for a database change, since when, by whom and why (security definer RPCs only)';
insert into pipeline.maintenance_state(id) values (true) on conflict do nothing;
alter table pipeline.maintenance_state enable row level security;

create table if not exists pipeline.maintenance_job_snapshot (
  id bigint generated always as identity primary key,
  window_id uuid not null,
  kind text not null check (kind in ('job', 'setting')),
  name text not null,
  jobid bigint,
  schedule text,
  active boolean,
  command_md5 text,
  toolset_key text,
  setting_key text,
  value jsonb,
  switched_off boolean not null default false,
  restored_at timestamptz,
  restore_note text,
  taken_at timestamptz not null default now(),
  unique (window_id, kind, name)
);
comment on table pipeline.maintenance_job_snapshot is 'Pipeline Maintenance Mode: the copy taken at each pause of every cron job (jobid, name, schedule, active) and every platform toolset setting; resume switches on only the jobs marked switched_off';
create index if not exists maintenance_job_snapshot_window_idx on pipeline.maintenance_job_snapshot(window_id, kind);
alter table pipeline.maintenance_job_snapshot enable row level security;

-- 2. The setting (G2): how long a pause may last before the screen and the status call it overdue
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values ('pipeline', 'maintenance.alert_after_minutes', 'Maintenance pause: warn after',
        'While the pipeline is paused for maintenance, Automations turns the pause amber and the status reports it overdue after this long.',
        'number', to_jsonb(15), 5, 240, 'minutes', 1810, 'Pipeline Maintenance Mode (Platform Admin 15 Nov 2026)', 'Maintenance mode',
        'pipeline.pause_for_maintenance; pipeline.get_maintenance_drain_status (Scheduled jobs > Automations > Pipeline maintenance)')
on conflict do nothing;

-- 3. Who may act. Raises for anyone else; returns the name recorded on the state row.
create or replace function pipeline.maintenance_actor_v1(p_min_rank int) returns text
language plpgsql stable security definer set search_path to '' as $function$
begin
  if auth.uid() is null then
    if session_user in ('postgres', 'supabase_admin') then return 'database owner (' || session_user || ')'; end if;
    raise exception 'sign in as an admin to use Pipeline maintenance' using errcode = '42501';
  end if;
  if security.current_role_rank() < p_min_rank then
    raise exception 'Pipeline maintenance is changed by the Platform Admin' using errcode = '42501';
  end if;
  return auth.uid()::text;
end $function$;

-- The check the controllers use: waits for a pause or resume in progress, then says whether the pipeline is paused.
create or replace function security.maintenance_hold_v1() returns boolean
language plpgsql volatile security definer set search_path to '' as $function$
begin
  perform pg_advisory_xact_lock_shared(hashtext('cf247.pipeline_maintenance'));
  return coalesce((select s.is_paused from pipeline.maintenance_state s where s.id), false);
end $function$;

-- 4. Drain status
create or replace function pipeline.get_maintenance_drain_status() returns jsonb
language plpgsql volatile security definer set search_path to '' as $function$
declare s pipeline.maintenance_state; v_me int := pg_backend_pid();
        v_cron jsonb; v_db jsonb; v_api int; v_edge int; v_netq int; v_fei int; v_pages int; v_l4 int; v_locks jsonb; v_back jsonb;
        v_off int; v_active int; v_settings int; v_elapsed numeric; v_alert int; v_safe boolean;
begin
  perform pipeline.maintenance_actor_v1(1);
  select * into s from pipeline.maintenance_state where id;
  -- cron runs still going (only runs whose session is alive count; a crashed run left as 'running' is listed as stale)
  select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'started', d.start_time, 'stale', a.pid is null) order by d.start_time), '[]'::jsonb) into v_cron
    from cron.job_run_details d left join cron.job j on j.jobid = d.jobid left join pg_stat_activity a on a.pid = d.job_pid
   where d.status in ('running', 'starting');
  -- busy database sessions (not this one, not the API's own connections) that touch catalogue or pipeline
  select coalesce(jsonb_agg(jsonb_build_object('pid', a.pid, 'app', a.application_name, 'user', a.usename, 'state', a.state, 'since', coalesce(a.xact_start, a.query_start),
                                               'query', left(regexp_replace(a.query, '\s+', ' ', 'g'), 160)) order by a.query_start), '[]'::jsonb) into v_db
    from pg_stat_activity a
   where a.backend_type = 'client backend' and a.pid <> v_me and coalesce(a.state, 'idle') <> 'idle' and a.application_name not like 'PostgREST%'
     and (a.query ~* '\m(catalogue|pipeline)\.' or exists (select 1 from pg_locks l join pg_class c on c.oid = l.relation join pg_namespace n on n.oid = c.relnamespace
                                                            where l.pid = a.pid and n.nspname in ('catalogue', 'pipeline')));
  -- website, Zoho and admin reads through the API: shown, not counted (they are short and a migration waits for them)
  select count(*) into v_api from pg_stat_activity a where a.backend_type = 'client backend' and a.pid <> v_me and coalesce(a.state, 'idle') <> 'idle' and a.application_name like 'PostgREST%';
  -- edge worker calls that may still be running: sent within the edge function time limit and not answered (or the wait timed out)
  select count(*) into v_edge from pipeline.edge_request_log e left join net._http_response r on r.id = e.request_id
   where e.created_at > now() - interval '150 seconds'  -- fixed: Supabase edge function wall-clock limit (API time-out)
     and (r.id is null or coalesce(r.timed_out, false));
  select count(*) into v_netq from net.http_request_queue;
  -- live worker leases
  select count(*) into v_fei from pipeline.field_enrich_items where state = 'leased' and coalesce(leased_until, 'infinity') > now();
  select count(*) into v_pages from pipeline.coverage_course_pages where leased_until > now();
  select count(*) into v_l4 from pipeline.layer4_review_items where status = 'pending' and claimed_at is not null;
  -- locks other sessions hold or wait for on catalogue tables (any but a plain read), or write locks on pipeline tables
  select coalesce(jsonb_agg(jsonb_build_object('table', n.nspname || '.' || c.relname, 'mode', l.mode, 'granted', l.granted, 'pid', l.pid)), '[]'::jsonb) into v_locks
    from pg_locks l join pg_class c on c.oid = l.relation join pg_namespace n on n.oid = c.relnamespace
   where l.pid <> v_me and l.locktype = 'relation' and c.relkind in ('r', 'p', 'm')
     and ((n.nspname = 'catalogue' and (not l.granted or l.mode <> 'AccessShareLock'))
       or (n.nspname = 'pipeline' and c.relname not like 'maintenance\_%' and (not l.granted or l.mode not in ('AccessShareLock', 'RowShareLock'))));
  select count(*) into v_active from cron.job where active;
  if s.is_paused then
    select count(*) into v_off from pipeline.maintenance_job_snapshot where window_id = s.window_id and kind = 'job' and switched_off;
    select coalesce(jsonb_agg(j.jobname order by j.jobname), '[]'::jsonb) into v_back
      from pipeline.maintenance_job_snapshot m join cron.job j on j.jobname = m.name
     where m.window_id = s.window_id and m.kind = 'job' and m.switched_off and j.active;
    select count(*) into v_settings
      from (select * from pipeline.maintenance_job_snapshot where window_id = s.window_id and kind = 'setting') m
      full join pipeline.platform_toolset_settings t on t.toolset_key = m.toolset_key and t.key = m.setting_key
     where m.id is null or t.key is null or m.value is distinct from t.value;
    v_elapsed := round(extract(epoch from now() - s.paused_at)::numeric);
    v_alert := coalesce(s.auto_alert_after_minutes, security.pipeline_num_v1('maintenance.alert_after_minutes', 15)::int);
  end if;
  v_safe := coalesce(s.is_paused, false)
            and jsonb_array_length(v_cron) = 0 and jsonb_array_length(v_db) = 0 and v_edge = 0 and v_netq = 0
            and v_fei = 0 and v_pages = 0 and v_l4 = 0 and jsonb_array_length(v_locks) = 0 and jsonb_array_length(coalesce(v_back, '[]'::jsonb)) = 0;
  return jsonb_build_object(
    'checked_at', now(), 'is_paused', coalesce(s.is_paused, false),
    'state', case when not coalesce(s.is_paused, false) then 'ACTIVE' when v_safe then 'SAFE' else 'DRAINING' end,
    'window_id', s.window_id, 'paused_at', s.paused_at, 'paused_by', s.paused_by, 'reason', s.reason,
    'elapsed_seconds', v_elapsed, 'alert_after_minutes', v_alert, 'overdue', coalesce(v_elapsed > v_alert * 60, false),
    'active_jobs', v_active, 'jobs_switched_off', coalesce(v_off, 0), 'jobs_switched_on_again', coalesce(v_back, '[]'::jsonb),
    'running_cron', jsonb_array_length(v_cron), 'running_cron_detail', v_cron,
    'db_backends', jsonb_array_length(v_db), 'db_backends_detail', v_db, 'api_reads', v_api,
    'edge_calls_in_flight', v_edge, 'http_queue', v_netq,
    'leases', jsonb_build_object('field_enrich_items', v_fei, 'coverage_course_pages', v_pages, 'layer4_claims', v_l4), 'leases_total', v_fei + v_pages + v_l4,
    'catalogue_locks', jsonb_array_length(v_locks), 'locks_detail', v_locks,
    'settings_changed_since_pause', coalesce(v_settings, 0),
    'safe_to_migrate', v_safe,
    'last_result', s.last_result);
end $function$;

-- 5. Pause
create or replace function pipeline.pause_for_maintenance(p_reason text) returns jsonb
language plpgsql volatile security definer set search_path to '' set lock_timeout to '30s'  -- fixed: waits for a controller run already under way
as $function$
declare v_actor text := pipeline.maintenance_actor_v1(6); s pipeline.maintenance_state; v_window uuid := gen_random_uuid(); v_n int := 0; r record;
        v_controllers text[] := array['flag-recheck', 'waste-guard', 'ops-controller', 'ops-diagnose', 'ops-job-lifecycle', 'work-continuity', 'work-continuity-lanes',
                                      'queue-watch', 'zero-yield-detect', 'admin-jobs', 'enrich-plan-auto', 'enrich-plan-run', 'layer1-run-driver'];
begin
  if nullif(btrim(coalesce(p_reason, '')), '') is null then raise exception 'say why the pipeline is paused (for example the migration name)'; end if;
  perform pg_advisory_xact_lock(hashtext('cf247.pipeline_maintenance'));
  select * into s from pipeline.maintenance_state where id for update;
  if s.is_paused then
    return pipeline.get_maintenance_drain_status() || jsonb_build_object('already_paused', true, 'note', 'Already paused; the first snapshot is kept.');
  end if;
  insert into pipeline.maintenance_job_snapshot(window_id, kind, name, jobid, schedule, active, command_md5)
  select v_window, 'job', j.jobname, j.jobid, j.schedule, j.active, md5(j.command) from cron.job j;
  insert into pipeline.maintenance_job_snapshot(window_id, kind, name, toolset_key, setting_key, value)
  select v_window, 'setting', t.toolset_key || '.' || t.key, t.toolset_key, t.key, t.value from pipeline.platform_toolset_settings t;
  -- the controllers that switch jobs on again go first, then every other active job
  for r in select m.id, m.jobid, m.name from pipeline.maintenance_job_snapshot m
            where m.window_id = v_window and m.kind = 'job' and m.active
            order by (m.name = any (v_controllers)) desc, m.name loop
    perform cron.alter_job(r.jobid, active => false);
    update pipeline.maintenance_job_snapshot set switched_off = true where id = r.id;
    v_n := v_n + 1;
  end loop;
  update pipeline.maintenance_state
     set is_paused = true, window_id = v_window, paused_at = now(), paused_by = v_actor, reason = btrim(p_reason),
         auto_alert_after_minutes = security.pipeline_num_v1('maintenance.alert_after_minutes', 15)::int,
         resumed_at = null, resumed_by = null, last_result = jsonb_build_object('action', 'pause', 'switched_off', v_n), updated_at = now()
   where id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('maintenance', 'pause', 'pipeline', jsonb_build_object('window_id', v_window, 'reason', btrim(p_reason), 'switched_off', v_n, 'by', v_actor), auth.uid());
  return pipeline.get_maintenance_drain_status() || jsonb_build_object('switched_off', v_n);
end $function$;

-- 6. Resume
create or replace function pipeline.resume_from_maintenance() returns jsonb
language plpgsql volatile security definer set search_path to '' set lock_timeout to '30s'  -- fixed: waits for a controller run already under way
as $function$
declare v_actor text := pipeline.maintenance_actor_v1(6); s pipeline.maintenance_state; r record; v_jobid bigint; v_active boolean;
        v_n int := 0; v_on int := 0; v_missing jsonb := '[]'::jsonb; v_retired jsonb := '[]'::jsonb; v_new jsonb; v_changed jsonb; v_out jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('cf247.pipeline_maintenance'));
  select * into s from pipeline.maintenance_state where id for update;
  if not s.is_paused then return pipeline.get_maintenance_drain_status() || jsonb_build_object('not_paused', true, 'restored', 0); end if;
  for r in select m.id, m.name from pipeline.maintenance_job_snapshot m
            where m.window_id = s.window_id and m.kind = 'job' and m.switched_off and m.restored_at is null order by m.name loop
    select j.jobid, j.active into v_jobid, v_active from cron.job j where j.jobname = r.name;
    if v_jobid is null then
      v_missing := v_missing || to_jsonb(r.name);
      update pipeline.maintenance_job_snapshot set restore_note = 'job no longer exists' where id = r.id;
    elsif exists (select 1 from pipeline.component_register c where c.kind = 'job' and c.name = r.name and c.status in ('retiring', 'retired')) then
      v_retired := v_retired || to_jsonb(r.name);  -- UR-07: a retiring or retired job is never switched on
      update pipeline.maintenance_job_snapshot set restore_note = 'retiring or retired: left off' where id = r.id;
    elsif v_active then
      v_on := v_on + 1;
      update pipeline.maintenance_job_snapshot set restored_at = now(), restore_note = 'already on' where id = r.id;
    else
      perform cron.alter_job(v_jobid, active => true);
      update pipeline.maintenance_job_snapshot set restored_at = now(), restore_note = 'switched on' where id = r.id;
      v_n := v_n + 1;
    end if;
  end loop;
  select coalesce(jsonb_agg(j.jobname order by j.jobname), '[]'::jsonb) into v_new from cron.job j
   where not exists (select 1 from pipeline.maintenance_job_snapshot m where m.window_id = s.window_id and m.kind = 'job' and m.name = j.jobname);
  select coalesce(jsonb_agg(coalesce(m.name, t.toolset_key || '.' || t.key) order by coalesce(m.name, t.toolset_key || '.' || t.key)), '[]'::jsonb) into v_changed
    from (select * from pipeline.maintenance_job_snapshot where window_id = s.window_id and kind = 'setting') m
    full join pipeline.platform_toolset_settings t on t.toolset_key = m.toolset_key and t.key = m.setting_key
   where m.id is null or t.key is null or m.value is distinct from t.value;
  v_out := jsonb_build_object('action', 'resume', 'restored', v_n, 'already_on', v_on, 'missing_jobs', v_missing, 'left_off_retired', v_retired,
                              'jobs_added_during_pause', v_new, 'settings_changed_during_pause', v_changed, 'paused_minutes', round(extract(epoch from now() - s.paused_at)::numeric / 60, 1));
  update pipeline.maintenance_state set is_paused = false, resumed_at = now(), resumed_by = v_actor, last_result = v_out, updated_at = now() where id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('maintenance', 'resume', 'pipeline', v_out || jsonb_build_object('window_id', s.window_id, 'by', v_actor), auth.uid());
  return pipeline.get_maintenance_drain_status() || v_out;
end $function$;

-- 7. The Admin UI entry point
create or replace function public.admin_pipeline_maintenance(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql volatile security definer set search_path to '' as $function$
begin
  if p_action = 'status' then return pipeline.get_maintenance_drain_status();
  elsif p_action = 'pause' then return pipeline.pause_for_maintenance(coalesce(p_args->>'reason', ''));
  elsif p_action = 'resume' then return pipeline.resume_from_maintenance();
  else raise exception 'unknown action (status, pause or resume)'; end if;
end $function$;

revoke all on function pipeline.maintenance_actor_v1(int), security.maintenance_hold_v1(), pipeline.get_maintenance_drain_status(),
  pipeline.pause_for_maintenance(text), pipeline.resume_from_maintenance(), public.admin_pipeline_maintenance(text, jsonb) from public, anon, authenticated;
grant execute on function public.admin_pipeline_maintenance(text, jsonb) to authenticated;

-- 8. The controllers and the Automations control: nothing switches a job on while the pipeline is paused
select pg_temp.edit_once('security.flag_recheck_v1()', 'c772071dba57e82bbde371c44e960ffe',
  $o$begin
  v_jobs := security.flag_jobs_v1();$o$,
  $n$begin
  -- Pipeline Maintenance Mode (15 Nov 2026): while paused, nothing is released and no job is switched on
  if security.maintenance_hold_v1() then return jsonb_build_object('maintenance', 'paused'); end if;
  v_jobs := security.flag_jobs_v1();$n$);

select pg_temp.edit_once('security.waste_idle_guard_v1()', '2fff04de64403f7bd4fcf9e671dd546e',
  $o$begin
  for w in select * from pipeline.job_idle_watch order by jobname loop$o$,
  $n$begin
  -- Pipeline Maintenance Mode (15 Nov 2026): while paused, no job is switched off or on here
  if security.maintenance_hold_v1() then return jsonb_build_array(jsonb_build_object('maintenance', 'paused')); end if;
  for w in select * from pipeline.job_idle_watch order by jobname loop$n$);

select pg_temp.edit_once('security.flag_requeue_v1(bigint)', '8550df00f0d93d0479bf5df3dab84fab',
  $o$    if v_jobid is not null then perform cron.alter_job(v_jobid, active := true); end if;$o$,
  $n$    -- Pipeline Maintenance Mode (15 Nov 2026): a job is not switched on while the pipeline is paused
    if v_jobid is not null and security.maintenance_hold_v1() then
      raise exception 'The pipeline is paused for maintenance: no job is switched on until Resume Pipeline (Automations)' using errcode = '55000';
    end if;
    if v_jobid is not null then perform cron.alter_job(v_jobid, active := true); end if;$n$);

select pg_temp.edit_once('security.admin_automation_control_v1(text,text,jsonb)', '431aff603f21b8c8a030073b07a08259',
  $o$  if p_action in ('pause_area','resume_area') then
$o$,
  $n$  -- Pipeline Maintenance Mode (15 Nov 2026): while paused, a job can still be paused but not switched on, run or changed
  if p_action not in ('pause','pause_area') and security.maintenance_hold_v1() then
    raise exception 'The pipeline is paused for maintenance: use Resume Pipeline on Automations first' using errcode = '55000';
  end if;
  if p_action in ('pause_area','resume_area') then
$n$);

-- 9. The register
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.maintenance_state', 'Platform', 'Maintenance mode', 'Whether every scheduled job is paused for a database change', 'active', '{}', '20261115180000'),
 ('table', 'pipeline.maintenance_job_snapshot', 'Platform', 'Maintenance mode', 'The copy of every cron job and setting taken at each pause', 'active', '{}', '20261115180000'),
 ('function', 'pipeline.pause_for_maintenance', 'Platform', 'Maintenance mode', 'Pause every active job for a database change', 'active', '{}', '20261115180000'),
 ('function', 'pipeline.get_maintenance_drain_status', 'Platform', 'Maintenance mode', 'What is still running while paused, and whether it is safe to apply database changes', 'active', '{}', '20261115180000'),
 ('function', 'pipeline.resume_from_maintenance', 'Platform', 'Maintenance mode', 'Switch on exactly the jobs the pause switched off', 'active', '{}', '20261115180000'),
 ('function', 'public.admin_pipeline_maintenance', 'Platform', 'Maintenance mode', 'Admin UI entry point for Pipeline maintenance (Automations)', 'active', '{}', '20261115180000')
on conflict do nothing;

-- 10. Post-checks: not paused; no cron job and no existing setting changed by this migration; the guards are in place
do $c$
declare v_before jsonb := current_setting('cf247.maint_before')::jsonb;
begin
  if (select is_paused from pipeline.maintenance_state where id) then raise exception 'post-check: the pipeline is not paused by this migration'; end if;
  if (select md5(string_agg(j.jobname || ':' || j.active || ':' || j.schedule || ':' || md5(j.command), '|' order by j.jobname)) from cron.job j) is distinct from v_before->>'jobs' then
    raise exception 'post-check: no cron job is changed by this migration';
  end if;
  if (select md5(string_agg(s.toolset_key || '.' || s.key || '=' || s.value::text, '|' order by s.toolset_key, s.key)) from pipeline.platform_toolset_settings s
       where not (s.toolset_key = 'pipeline' and s.key = 'maintenance.alert_after_minutes')) is distinct from v_before->>'settings' then
    raise exception 'post-check: no existing setting is changed (only maintenance.alert_after_minutes is added)';
  end if;
  if pg_get_functiondef('security.flag_recheck_v1()'::regprocedure) not like '%maintenance_hold_v1%'
     or pg_get_functiondef('security.waste_idle_guard_v1()'::regprocedure) not like '%maintenance_hold_v1%'
     or pg_get_functiondef('security.flag_requeue_v1(bigint)'::regprocedure) not like '%maintenance_hold_v1%'
     or pg_get_functiondef('security.admin_automation_control_v1(text,text,jsonb)'::regprocedure) not like '%maintenance_hold_v1%' then
    raise exception 'post-check: every controller checks the maintenance state';
  end if;
end $c$;