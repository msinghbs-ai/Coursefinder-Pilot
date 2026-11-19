-- CF-247 (3 Oct 2026, Decision 238). Part 1 of the Settings page functions: a helper that changes one numeric argument
-- in a scheduled job's JSON body (used by admin_pipeline_settings_write; service-side only).
create or replace function security.pipeline_setting_cron_arg(p_jobname text, p_key text, p_value int)
returns void language plpgsql security definer set search_path to '' as $f$
declare v_cmd text; v_json text; v_new text; v_jobid bigint;
begin
  select jobid, command into v_jobid, v_cmd from cron.job where jobname = p_jobname;
  if v_jobid is null then raise exception 'job % not found', p_jobname; end if;
  v_json := substring(v_cmd from ',''(\{.*\})''::jsonb');
  if v_json is null then raise exception 'job % has no JSON body', p_jobname; end if;
  v_new := jsonb_set(v_json::jsonb, array[p_key], to_jsonb(p_value), true)::text;
  perform cron.alter_job(job_id := v_jobid, command := replace(v_cmd, '''' || v_json || '''', '''' || v_new || ''''));
end $f$;
revoke all on function security.pipeline_setting_cron_arg(text, text, int) from public, anon, authenticated;
