-- CF-247 s1213 (S2-Build; Atlas brief 26 Nov 2026 11:59 AEDT, Platform Admin approval: zero-cost daytime CPU and I/O isolation so portal
-- searches stay sub-second in counsellor and UAT hours without a larger compute tier). Version above main's 20261129061000.
-- Measured (cron.job_run_details, last 24 hours, read in a rolled-back run): 363,920 job-seconds a day (about 15,200 an hour), 177,899 of them
-- between 08:00 and 20:00 Melbourne time. The heaviest direct background jobs that serve no person waiting on a screen:
--   coverage-ai-match-prepare 28,216 s (every 2 minutes), fee-reader 27,581 s, scholarship-ai-extract 14,203 s (both every minute),
--   course-description-machine 13,498 s and provider-description-read 11,854 s: 95,352 job-seconds a day, about 47,700 of them by day.
-- Kept running all day: website-sync-check and zoho-sync-check (the change feeds the website and Zoho read), admin-jobs (Task manager,
-- on-demand work; one change owner), the rollup and admission-rule dispatchers (their own registered targets), and every light handler.
-- Change: daytime quiet hours. security.quiet_hours_open_v1(job) is false from pipeline.quiet_hours.start_hour to pipeline.quiet_hours.end_hour
-- (08:00 to 20:00 Australia/Melbourne, so daylight saving needs no change) for the jobs named in pipeline.quiet_hours.jobs, while
-- pipeline.quiet_hours.enabled is 1. Each of the five job commands is its own call followed by "where security.quiet_hours_open_v1('<job>')":
-- by day the job still starts each minute and returns at once, so the scheduler, its run history and the job count are unchanged; at night
-- it runs exactly as before. The Platform Admin changes the window, the list or switches it off on Settings > Pipeline settings, with a reason.
-- No job is added, removed, activated or deactivated (active cron jobs unchanged); no retired job is touched. No AI or Firecrawl call; US$0.
-- Not the consumer API (G3 checked). G1: no new job; the five catalogue descriptions say when they run. G2: four settings with label, range,
-- unit and used_by. Locks untouched. Nothing dropped.
-- Replaces: the daytime runs of coverage-ai-match-prepare, fee-reader, scholarship-ai-extract, course-description-machine and provider-description-read.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the job and catalogue updates

create temp table s1213_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before;

create temp table s1213_jobs (jobname text primary key, command_before text not null) on commit drop;
insert into s1213_jobs values
 ('coverage-ai-match-prepare', 'select security.coverage_ai_match_prepare_v1(security.pipeline_num_v1(''batch.ai_match_prepare_universities'', 200)::int, security.pipeline_num_v1(''batch.ai_match_prepare_courses'', 1000)::int)'),
 ('fee-reader', 'select security.fee_reader_tick_v1()'),
 ('scholarship-ai-extract', 'select security.scholarship_ai_fire_v1()'),
 ('course-description-machine', 'select security.course_description_machine_run_v1()'),
 ('provider-description-read', 'select security.provider_description_fire_v1()');

do $pre$
declare v jsonb := security.consumer_api_check_v1(); r record;
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
  for r in select s.jobname, s.command_before, j.command, j.active from s1213_jobs s left join cron.job j on j.jobname = s.jobname loop
    if r.command is distinct from r.command_before or not coalesce(r.active, false) then
      raise exception 'pre-check: job % is not the active job this change was written against (command %)', r.jobname, r.command;
    end if;
  end loop;
end $pre$;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
 ('pipeline', 'quiet_hours.enabled', 'Daytime quiet hours: on',
  'While 1, the background jobs named in Daytime quiet hours: jobs do no work between the start and end hour (Melbourne time), so counsellor and portal searches get the database by day; they run as before outside those hours. 0 lets them run all day.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 3330, 'Scheduling', 'security.quiet_hours_open_v1; the five job commands', 'CF-247 s1213 (Atlas brief 26 Nov 2026 11:59 AEDT, Platform Admin approval)'),
 ('pipeline', 'quiet_hours.start_hour', 'Daytime quiet hours: from (Melbourne hour)',
  'The hour, Melbourne time, from which the named background jobs do no work (8 means 08:00).',
  'number', to_jsonb(8), 0, 23, 'hour (Melbourne)', 3331, 'Scheduling', 'security.quiet_hours_open_v1', 'CF-247 s1213'),
 ('pipeline', 'quiet_hours.end_hour', 'Daytime quiet hours: until (Melbourne hour)',
  'The hour, Melbourne time, at which the named background jobs work again (20 means 20:00). When it is not after the start hour, the window runs past midnight.',
  'number', to_jsonb(20), 0, 23, 'hour (Melbourne)', 3332, 'Scheduling', 'security.quiet_hours_open_v1', 'CF-247 s1213'),
 ('pipeline', 'quiet_hours.jobs', 'Daytime quiet hours: jobs held',
  'The scheduled jobs that do no work in the quiet hours. A job named here is held only if its command checks security.quiet_hours_open_v1 (the five jobs of CF-247 s1213 do); removing a name lets that job run all day.',
  'list', '["coverage-ai-match-prepare", "fee-reader", "scholarship-ai-extract", "course-description-machine", "provider-description-read"]'::jsonb,
  null, null, 'jobs', 3333, 'Scheduling', 'security.quiet_hours_open_v1', 'CF-247 s1213')
on conflict do nothing;

create or replace function security.quiet_hours_open_v1(p_job text, p_at timestamptz default now())
returns boolean language sql stable security definer set search_path = '' as $function$
  -- true when the job may work now: quiet hours off, the job not in the list, or the Melbourne hour outside the window
  select coalesce(security.pipeline_num_v1('quiet_hours.enabled', 1), 1) <> 1
      or not coalesce((select s.value ? p_job from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'quiet_hours.jobs'), false)
      or not (case when security.pipeline_num_v1('quiet_hours.start_hour', 8) < security.pipeline_num_v1('quiet_hours.end_hour', 20)
                   then extract(hour from p_at at time zone 'Australia/Melbourne') >= security.pipeline_num_v1('quiet_hours.start_hour', 8)
                    and extract(hour from p_at at time zone 'Australia/Melbourne') < security.pipeline_num_v1('quiet_hours.end_hour', 20)
                   else extract(hour from p_at at time zone 'Australia/Melbourne') >= security.pipeline_num_v1('quiet_hours.start_hour', 8)
                     or extract(hour from p_at at time zone 'Australia/Melbourne') < security.pipeline_num_v1('quiet_hours.end_hour', 20) end)  -- fixed: the Melbourne calendar
$function$;
comment on function security.quiet_hours_open_v1(text, timestamptz) is 'CF-247 s1213: false while a job named in pipeline.quiet_hours.jobs is inside the daytime quiet hours (Melbourne time); the job commands check it.';
revoke all on function security.quiet_hours_open_v1(text, timestamptz) from public, anon, authenticated;

-- each job keeps its own call; by day it returns at once
select cron.alter_job(j.jobid, command := s.command_before || ' where security.quiet_hours_open_v1(''' || s.jobname || ''')')
  from s1213_jobs s join cron.job j on j.jobname = s.jobname;

update pipeline.automation_catalogue c
   set description = c.description || ' Daytime quiet hours: no work from 08:00 to 20:00 Melbourne time (Settings > Pipeline settings > Scheduling, Daytime quiet hours).'
 where c.jobname in (select jobname from s1213_jobs) and c.description not like '%Daytime quiet hours%';

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('function', 'security.quiet_hours_open_v1', 'Platform', 'Scheduling', 'Daytime quiet hours: whether a named background job may work now (Melbourne time)', 'active', '{}', '20261129070000')
on conflict do nothing;

do $post$
declare v jsonb := security.consumer_api_check_v1(); r record; v_day timestamptz := timestamptz '2026-11-26 12:00:00+11'; v_night timestamptz := timestamptz '2026-11-26 23:00:00+11';
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'post-check: consumer API baseline changed: %', v;
  end if;
  if (select count(*) from cron.job where active) <> (select cron_before from s1213_guard) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1213_guard) then raise exception 'post-check: manual locks changed'; end if;
  for r in select s.jobname, j.command, j.active from s1213_jobs s join cron.job j on j.jobname = s.jobname loop
    if r.command <> (select command_before from s1213_jobs where jobname = r.jobname) || ' where security.quiet_hours_open_v1(''' || r.jobname || ''')' or not r.active then
      raise exception 'post-check: job % command is %', r.jobname, r.command;
    end if;
    if security.quiet_hours_open_v1(r.jobname, v_day) or not security.quiet_hours_open_v1(r.jobname, v_night) then
      raise exception 'post-check: quiet hours for % are not closed at noon and open at 23:00', r.jobname;
    end if;
  end loop;
  if not security.quiet_hours_open_v1('website-sync-check', v_day) or not security.quiet_hours_open_v1('admin-jobs', v_day) then
    raise exception 'post-check: a job not in the list is held';
  end if;
  if (select count(*) from pipeline.automation_catalogue where jobname in (select jobname from s1213_jobs) and description like '%Daytime quiet hours%') <> 5 then
    raise exception 'post-check: not every catalogue description says when the job runs';
  end if;
end $post$;
