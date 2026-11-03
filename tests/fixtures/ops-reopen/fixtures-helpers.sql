-- helpers for the ops-reopen fixtures (scratch PostgreSQL only)
create or replace function fx.ok(p_cond boolean, p_case text) returns void language plpgsql as $f$
begin if not coalesce(p_cond, false) then raise exception 'FAILED: %', p_case; end if; raise notice 'ok: %', p_case; end $f$;
create or replace function fx.issue(p_fp text) returns pipeline.integration_issues language sql as $f$ select * from pipeline.integration_issues where fingerprint = p_fp $f$;
create or replace function fx.only(p_fps text[]) returns void language sql as $f$
  update pipeline.integration_issues set next_action_at = now() + interval '30 days' where not (fingerprint = any (p_fps)) and status <> 'closed' $f$;
create or replace function fx.age(p_min int) returns void language plpgsql as $f$
declare d interval := make_interval(mins => p_min);
begin
  update pipeline.ops_remedy_runs set started_at = started_at - d, finished_at = finished_at - d;
  update pipeline.integration_issues set next_action_at = next_action_at - d;
  update pipeline.ops_checkpoints set at = at - d;
end $f$;
create or replace function fx.run(p_job text, p_status text, p_msg text, p_at timestamptz) returns void language sql as $f$
  insert into cron.job_run_details(jobid, status, return_message, start_time, end_time) select j.jobid, p_status, p_msg, p_at, p_at + interval '30 seconds' from cron.job j where j.jobname = p_job $f$;
insert into cron.job(jobname, schedule, command, active) values ('coverage-admit', '3-59/10 * * * *', 'select security.coverage_admission_gated_v1()', true) on conflict (jobname) do nothing;
