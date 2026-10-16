-- CF-247 (16 Oct 2026): daily housekeeping job. Platform Admin 16 Oct 2026 23:44: "Run 1,2,6,7" (housekeeping advice to bring the database
-- under 2 GB: 2 purge expired one-time request codes daily; 7 keep the job run log short).
-- One catalogued job, housekeeping-daily (about 03:47 Melbourne), runs security.housekeeping_daily_v1:
--   - removes one-time request codes (pipeline.pilot_edge_nonces, each valid 5 minutes) that expired more than retention.nonce_keep_days ago;
--   - removes scheduled-job run records (cron.job_run_details) older than retention.job_log_keep_days;
--   each up to batch.housekeeping_rows per run, and records what it removed in pipeline.admin_control_events.
-- retention.job_log_keep_days goes from 7 to 3: the log has been kept 3 days since the cron-history-trim job (about 35,000 runs a day).
-- Replaces: jobs cron-history-retention (14 days, number in the command) and cron-history-trim (3 days, number in the command), both made
--   outside git; switched off here and marked retiring (replaced_by housekeeping-daily). They are removed by a paste file after 14 days.
-- Retires: cron-history-retention, cron-history-trim
-- Nothing dropped or deleted by this migration (the job removes rows when it runs).
-- Step 6 (sync item history) needs no rule: pipeline.website_sync_items and zoho_sync_items hold one current row per item, the live feeds.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'retention.nonce_keep_days', 'Keep expired request codes for', 'The daily housekeeping job removes one-time request codes (each valid 5 minutes) that expired more than this many days ago.', 'number', to_jsonb(1), 1, 30, 'days', 743, 'Platform Admin 16 Oct 2026: purge expired request codes daily', 'Housekeeping', 'security.housekeeping_daily_v1'),
 ('pipeline', 'batch.housekeeping_rows', 'Rows removed per housekeeping run (each kind)', 'The daily housekeeping job removes up to this many request codes and up to this many job run records in one run.', 'number', to_jsonb(400000), 10000, 1000000, 'rows', 747, 'Platform Admin 16 Oct 2026: daily housekeeping', 'Housekeeping', 'security.housekeeping_daily_v1')
on conflict (toolset_key, key) do nothing;

update pipeline.platform_toolset_settings
   set value = to_jsonb(3), updated_at = now(),
       reason = 'CF-247 16 Oct 2026: 3 days, as kept by cron-history-trim since 13 Oct (about 35,000 runs a day); now used by the daily housekeeping job',
       used_by = 'security.housekeeping_daily_v1; security.retention_tick_v1; security.retention_estimate_v1',
       help = 'The daily housekeeping job (and Storage & retention, job log) removes scheduled-job run records older than this.'
 where toolset_key = 'pipeline' and key = 'retention.job_log_keep_days' and value = to_jsonb(7);

create or replace function security.housekeeping_daily_v1()
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_limit int := security.pipeline_num_v1('batch.housekeeping_rows', 400000)::int; v_nonces int := 0; v_log int := 0;
begin
  delete from pipeline.pilot_edge_nonces where id in (
    select n.id from pipeline.pilot_edge_nonces n
     where n.expires_at < now() - make_interval(days => security.pipeline_num_v1('retention.nonce_keep_days', 1)::int)
     limit v_limit);
  get diagnostics v_nonces = row_count;
  delete from cron.job_run_details where runid in (
    select d.runid from cron.job_run_details d
     where d.start_time < now() - make_interval(days => security.pipeline_num_v1('retention.job_log_keep_days', 3)::int)
     limit v_limit);
  get diagnostics v_log = row_count;
  if v_nonces + v_log > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('retention', 'housekeeping', 'housekeeping-daily', jsonb_build_object('request_codes', v_nonces, 'job_log', v_log), null);
  end if;
  return jsonb_build_object('request_codes', v_nonces, 'job_log', v_log);
end $function$;
revoke execute on function security.housekeeping_daily_v1() from public, anon, authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('housekeeping-daily', 'Platform upkeep', 67, 'Daily housekeeping', 'Daily (about 03:47 Melbourne): removes expired one-time request codes and scheduled-job run records older than their settings (Settings › Pipeline settings › Housekeeping). Each run is recorded in the admin events.', 6, false)
on conflict (jobname) do nothing;
select cron.schedule('housekeeping-daily', '47 16 * * *', 'select security.housekeeping_daily_v1()');

-- the two old trims stop now (switched off, not removed)
select cron.alter_job((select jobid from cron.job where jobname = 'cron-history-retention'), active := false);
select cron.alter_job((select jobid from cron.job where jobname = 'cron-history-trim'), active := false);
update pipeline.automation_catalogue set description = description || ' Retired 16 Oct 2026: replaced by Daily housekeeping (housekeeping-daily).'
 where jobname in ('cron-history-retention', 'cron-history-trim') and description not like '%Retired 16 Oct 2026%';

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('job', 'housekeeping-daily', 'Platform', 'Daily housekeeping: expired request codes and old job run records', 'active', '20261016110000'),
 ('function', 'security.housekeeping_daily_v1', 'Platform', 'Daily housekeeping run (settings retention.nonce_keep_days, retention.job_log_keep_days, batch.housekeeping_rows)', 'active', '20261016110000')
on conflict (kind, name) do nothing;
update pipeline.component_register set status = 'retiring', replaced_by = 'housekeeping-daily', retire_after = (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date,
       note = 'Switched off 16 Oct 2026 (migration 20261016110000); the number was in the job command; made outside git', updated_at = now()
 where kind = 'job' and name in ('cron-history-retention', 'cron-history-trim');

do $post$
begin
  if not exists (select 1 from cron.job where jobname = 'housekeeping-daily' and active) then raise exception 'housekeeping post-check: job missing'; end if;
  if exists (select 1 from cron.job where jobname in ('cron-history-retention', 'cron-history-trim') and active) then raise exception 'housekeeping post-check: old trims still on'; end if;
  if (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'retention.job_log_keep_days') <> to_jsonb(3) then
    raise exception 'housekeeping post-check: job log days not 3';
  end if;
end $post$;
