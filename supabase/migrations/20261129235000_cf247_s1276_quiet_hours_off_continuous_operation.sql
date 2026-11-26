-- CF-247 s1276 (S1-Build; Platform Admin via SS-Programme-Control 26 Nov 2026 21:01 AEDT, "Permanent 24x7 autonomous production operation":
-- "Remove existing production quiet-hour restrictions, including the previously approved 08:00-20:00 Melbourne processing pause under s1213").
-- What this does: switches the s1213 daytime quiet hours off through their own audited setting (pipeline.quiet_hours.enabled 1 -> 0, with the reason),
--   so coverage-ai-match-prepare, fee-reader, scholarship-ai-extract, course-description-machine and provider-description-read run every minute of the day
--   again; security.quiet_hours_open_v1 is true for every job while the switch is 0. The five catalogue descriptions say they run all day.
--   The only time-of-day processing pause found live is this one (Boost windows are already 0 to 24). Rate limits, retry backoff, refresh intervals,
--   empty-run pauses, admission gates, spending caps (US$5.00 a day) and Firecrawl ceilings are unchanged.
-- Risk accepted by the direction: daytime portal search latency, which s1213 protected, is watched after deploy.
-- G1: no job added, removed or (de)activated. G2: an existing setting, changed with its reason. G3: no consumer object touched (checked). Locks untouched.
-- Replaces: the s1213 daytime quiet hours (08:00 to 20:00 Melbourne). Retires: nothing (the switch stays, at 0). Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the setting and catalogue updates

create temp table s1276_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before;

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'guard: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
  if security.pipeline_num_v1('quiet_hours.enabled', -1) <> 1 then raise exception 'guard: daytime quiet hours are not on'; end if;
end $g$;

do $a$
declare v_reason constant text := 'Platform Admin 26 Nov 2026 21:01 AEDT (SS-Programme-Control, permanent 24x7 autonomous production operation): daytime quiet hours removed (CF-247 s1276)';
begin
  update pipeline.platform_toolset_settings set value = to_jsonb(0), reason = v_reason, updated_at = now()
   where toolset_key = 'pipeline' and key = 'quiet_hours.enabled';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('toolsets', 'setting', 'pipeline.quiet_hours.enabled', jsonb_build_object('before', 1, 'after', 0, 'reason', v_reason, 'via', 'CF-247 s1276 migration'), null);
  update pipeline.automation_catalogue c
     set description = replace(c.description,
           ' Daytime quiet hours: no work from 08:00 to 20:00 Melbourne time (Settings > Pipeline settings > Scheduling, Daytime quiet hours).',
           ' Runs all day (Platform Admin 26 Nov 2026 21:01: daytime quiet hours off; the switch is on Settings > Pipeline settings > Scheduling).')
   where c.jobname in ('coverage-ai-match-prepare', 'fee-reader', 'scholarship-ai-extract', 'course-description-machine', 'provider-description-read');
end $a$;

do $c$
declare v jsonb := security.consumer_api_check_v1(); j text;
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API moved: %', v; end if;
  if (select count(*) from cron.job where active) <> (select cron_before from s1276_guard) then raise exception 'post-check: active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1276_guard) then raise exception 'post-check: manual locks changed'; end if;
  foreach j in array array['coverage-ai-match-prepare', 'fee-reader', 'scholarship-ai-extract', 'course-description-machine', 'provider-description-read'] loop
    if not security.quiet_hours_open_v1(j) then raise exception 'post-check: % is still held by quiet hours', j; end if;
  end loop;
  if exists (select 1 from pipeline.automation_catalogue where description like '%no work from 08:00 to 20:00%') then raise exception 'post-check: a catalogue description still names the quiet hours'; end if;
end $c$;
