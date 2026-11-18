-- CF-247 StudySearch SS-014 (Platform Admin mandate 31 Oct 2026 14:27, "Self-sustaining operations": improve existing controls first;
-- admin docs/platform/nz-enrichment-brief/2026-10-31-studysearch-transformation.md §30) and SS-013 (one register comment renamed).
-- Why (verified live 31 Oct 2026):
--   1. Failure alerts flapped and never escalated. The platform health check (job platform-health, every 10 minutes) raised a job failure
--      only for failures in the last hour, and called it critical only when 3 runs in that hour all failed. An hourly or daily job therefore
--      could never be critical, and each failure closed itself within the hour: 62 separate "job failed" issues opened and auto-closed in
--      4 days (waste-guard 23, coverage-ai-match-prepare 12, l4-rule-low-agreement daily for 3 days), none acknowledged.
--   2. The AI cost control watched the wrong number. "OpenRouter spend in 24 hours" counted Layer 3 calls only (US$0 today), while the
--      enrichment, AI-match and entry reads spend through the same account; and the health detail labelled the remaining credit
--      (US$98.93) as the 24-hour spend. The US$14 daily ceiling was written into the code.
-- What (security.platform_health_check_v1, md5-guarded single-purpose edits; no new job, table, check or screen):
--   * a job failure stays open while the job's last run failed, or while it failed at least health.job_failure_repeat_count times in
--     health.job_failure_window_hours; it is critical when its last health.job_failure_critical_consecutive runs all failed, at any frequency;
--   * AI spend over 24 hours is measured from the OpenRouter credit balance the openrouter-balance job already records (every decrease; a
--     top-up is not spend), so every route is counted; the ceiling is setting budgets.ai_daily_ceiling_usd (US$14, today's value); the
--     health detail names the remaining credit as such.
-- Dry run (live, rolled back): full forced health run 14.3 s; spend 24 h US$0.25 (credit US$98.93); waste-guard (10 failures in 24 h)
-- and coverage-ai-match-prepare (9) now stay visible as warnings until they have run cleanly for the window.
-- Replaces: security.platform_health_check_v1 (same name; md5-guarded edit)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. No new table, job or status. Consumer API untouched.

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'health.job_failure_window_hours', 'Health: count job failures over',
  'A scheduled job that failed this often (Health: repeated failures) within this many hours stays on the health list as a warning until it runs cleanly for the window.', 'number',
  to_jsonb(24), 1, 168, 'hours', 795, 'Platform upkeep', 'security.platform_health_check_v1 (cron check)', 'StudySearch SS-014 (31 Oct 2026): job failures stay visible instead of closing within the hour'),
 ('pipeline', 'health.job_failure_repeat_count', 'Health: repeated failures',
  'Number of failures within the window that keeps a scheduled job on the health list, even when its last run succeeded.', 'number',
  to_jsonb(3), 1, 50, 'failures', 796, 'Platform upkeep', 'security.platform_health_check_v1 (cron check)', 'StudySearch SS-014 (31 Oct 2026)'),
 ('pipeline', 'health.job_failure_critical_consecutive', 'Health: consecutive failures that are critical',
  'A scheduled job whose last this-many runs all failed is shown as critical, whatever its schedule (hourly and daily jobs included).', 'number',
  to_jsonb(3), 2, 20, 'runs', 797, 'Platform upkeep', 'security.platform_health_check_v1 (cron check)', 'StudySearch SS-014 (31 Oct 2026): hourly and daily jobs could never become critical'),
 ('pipeline', 'budgets.ai_daily_ceiling_usd', 'AI spend: daily ceiling',
  'All OpenRouter spend in 24 hours (enrichment, AI match, entry reads, Layer 3), measured from the credit balance. A warning at 80%, critical at the ceiling.', 'number',
  to_jsonb(14), 1, 500, 'US$', 798, 'Platform upkeep', 'security.platform_health_check_v1 (budgets check)', 'StudySearch SS-014 (31 Oct 2026): was written into the code as US$14 and counted Layer 3 only')
on conflict do nothing;

select pg_temp.edit_once('security.platform_health_check_v1(boolean)', '293156782123a7e66b6fd1c021e22af0', 'd245c53574b1de0251711b0cb41c47cf', array[
 array[$o$v_counts jsonb; v_jobs int:=0; v_fail int:=0; v_stale int:=0;$o$, $n$v_counts jsonb; v_jobs int:=0; v_fail int:=0; v_stale int:=0; v_spend numeric;$n$],
 array[$o$count(*) filter (where d.start_time>=now()-interval '1 hour') runs_1h,  -- fixed: health check observation window$o$, $n$count(*) filter (where d.start_time>=now()-interval '1 hour') runs_1h,  -- fixed: health check observation window
                 -- SS-014 (31 Oct 2026): a failure stays visible until the job runs cleanly again, and repeats are counted over a set window
                 count(*) filter (where d.status='failed' and d.start_time>=now()-make_interval(hours=>security.pipeline_num_v1('health.job_failure_window_hours', 24)::int)) fails_win,
                 (array_agg(d.status order by d.start_time desc))[1] last_status,$n$],
 array[$o$a.last_run, coalesce(a.fails_1h,0) fails_1h, coalesce(a.runs_1h,0) runs_1h, a.last_error,$o$, $n$a.last_run, coalesce(a.fails_1h,0) fails_1h, coalesce(a.runs_1h,0) runs_1h, a.last_error, coalesce(a.fails_win,0) fails_win, a.last_status,$n$],
 array[$o$if r.fails_1h>0 then$o$, $n$if r.fails_1h>0 or r.last_status='failed' or r.fails_win>=security.pipeline_num_v1('health.job_failure_repeat_count', 3) then$n$],
 array[$o$(select d.status from cron.job_run_details d where d.jobid=r.jobid order by d.start_time desc limit 3) x;$o$, $n$(select d.status from cron.job_run_details d where d.jobid=r.jobid order by d.start_time desc limit security.pipeline_num_v1('health.job_failure_critical_consecutive', 3)::int) x;$n$],
 array[$o$case when v_bool and r.runs_1h>=3 then 'critical' else 'warning' end$o$, $n$case when v_bool then 'critical' else 'warning' end$n$],
 array[$o$' run(s) in the last hour',$o$, $n$' run(s) in the last hour'||case when r.fails_win>r.fails_1h then '; '||r.fails_win||' failure(s) in the last '||security.pipeline_num_v1('health.job_failure_window_hours', 24)::int||' hours' else '' end||case when r.last_status='failed' then '; the last run failed' else '' end,$n$],
 array[$o$'last_three_failed',coalesce(v_bool,false))$o$, $n$'last_three_failed',coalesce(v_bool,false),'failures_window',r.fails_win,'last_status',r.last_status)$n$],
 array[$o$select coalesce((select sum(estimated_cost_usd) from pipeline.layer3_interpretations where created_at>=now()-interval '24 hours'),0)  -- fixed: health check observation window$o$, $n$-- SS-014 (31 Oct 2026): all OpenRouter spend (enrichment, AI match, entry reads, Layer 3), measured from the credit balance; top-ups are not counted
      select coalesce((select sum(greatest(o.prev - o.remaining_usd, 0)) from (select x.remaining_usd, lag(x.remaining_usd) over (order by x.observed_at) prev
                         from pipeline.layer3_openrouter_observations x where x.kind = 'credits' and x.remaining_usd is not null and x.observed_at>=now()-interval '24 hours') o),0)  -- fixed: health check observation window$n$],
 array[$o$into v_num;  -- CF-247 20 Oct 2026 (D11)$o$, $n$into v_num; v_spend:=round(v_num,4);  -- CF-247 20 Oct 2026 (D11)$n$],
 array[$o$if v_num>=14 then$o$, $n$if v_num>=security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14) then$n$],
 array[$o$elsif v_num>=11.2 then$o$, $n$elsif v_num>=0.8*security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14) then  -- fixed: notice at 80% of the ceiling$n$],
 array[$o$US$14 combined daily ceiling$o$, $n$US$'||security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14)||' combined daily ceiling$n$],
 array[$o$'ceiling_usd',14)$o$, $n$'ceiling_usd',security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14))$n$],
 array[$o$'openrouter_spend_24h_usd',round(v_num,4),'openrouter_daily_ceiling_usd',5));$o$, $n$'openrouter_credit_remaining_usd',round(v_num,4),'openrouter_spend_24h_usd',v_spend,'ai_daily_ceiling_usd',security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14)));$n$]],
 array[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 1]);

-- SS-013: the register's description of the capacity thresholds uses the platform's name
comment on table pipeline.platform_capacity_policy is 'Operational warning/high/critical planning thresholds. These are StudySearch policy thresholds, not vendor hard quotas.';
update pipeline.component_register set purpose = replace(purpose, 'CourseFinder policy thresholds', 'StudySearch policy thresholds'), updated_at = now()
 where name = 'pipeline.platform_capacity_policy' and purpose like '%CourseFinder policy thresholds%';

-- post-check
do $$
begin
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in
      ('health.job_failure_window_hours', 'health.job_failure_repeat_count', 'health.job_failure_critical_consecutive', 'budgets.ai_daily_ceiling_usd')) <> 4 then
    raise exception 'SS-014 post-check: the four settings are not all present'; end if;
  if (select prosrc from pg_proc where oid = 'security.platform_health_check_v1(boolean)'::regprocedure) ~ 'v_num>=14 then|runs_1h>=3 then' then
    raise exception 'SS-014 post-check: a fixed threshold is left in the health check'; end if;
end $$;
