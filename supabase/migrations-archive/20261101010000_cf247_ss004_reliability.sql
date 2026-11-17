-- CF-247 StudySearch SS-004 reliability closure (Platform Admin mandate 1 Nov 2026 08:57, "Reliability Closure and Production
-- Acceptance"; admin docs/platform/nz-enrichment-brief/2026-10-31-studysearch-transformation.md §33).
-- Why (verified live 1 Nov 2026):
--   1. Every "job canceled" run in the scheduler's history (6 in 3.5 days: coverage-read and coverage-read-2, including 31 Oct 15:00 and
--      15:30) started 2.2 to 3.1 s after the flag unit paused that job for idleness (security.flag_jobs_v1, enrichment_flag_events
--      raised/re_raised). pg_cron cancels a run whose job became inactive as it started. Nothing was lost (the job was being paused because
--      its runs found nothing), but each counted as a failed run in the health check and in target T1.
--   2. coverage-admit, coverage-admit-intakes and adapter-overwrite all start at minute :x0 and write the same rows (evidence_entity_links and
--      the course values behind them). In 4 days, 228 of the 231 minutes with heavy admission work had two or more of them heavy at once,
--      and every failure (7 minutes, 31 Oct 17:10 included) was such an overlap: each waited on the others' row locks until the 120 s
--      statement limit. Heavy successful coverage-admit runs took 93 s at the median.
-- What (smallest safe change; no admission rule, batch size, gate, lock or time-out changes):
--   * security.cron_run_outcome_v1(job, status, message, start): a run reported "job canceled" within seconds of the flag unit pausing
--     that job is 'paused', otherwise the status is unchanged. Used by the health check (cron failures, consecutive-failure rule) and the
--     weekly scorecard (T1). Any other cancellation, failure or time-out still counts.
--   * Stall age (health check, coverage page reading and provider discovery) is measured from the later of the last progress and the
--     moment the oldest waiting item became due. On 31 Oct 23:08 and 1 Nov 03:58 one item that had just become due after hours of quiet was
--     reported critical ("nothing processed for 341 / 167 minutes") and cleared at the next run. A queue whose items stay waiting still ages.
--   * Schedules staggered so the three admission writers do not start together: coverage-admit :00 (unchanged), adapter-overwrite :03,
--     coverage-admit-intakes :08; search-refresh-requested keeps :06. Same commands, same frequency (every 10 minutes).
-- Rollback: cron.alter_job back to '*/10 * * * *' for the two jobs; re-apply the previous health check (md5 b648e649) and scorecard
-- (md5 9e212299) definitions.
-- Replaces: security.platform_health_check_v1, security.ops_scorecard_v1 (same names; md5-guarded edits)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. Consumer API untouched (G3).

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

-- 1. the run outcome. Plain SQL with no settings of its own so it is inlined into the callers' queries (it is read for every scheduled
-- run); every name is schema-qualified.
create or replace function security.cron_run_outcome_v1(p_jobname text, p_status text, p_message text, p_start timestamptz) returns text
language sql stable as $function$
  select case when p_status = 'failed' and p_message = 'job canceled'
               and exists (select 1 from pipeline.enrichment_flag_events e join pipeline.enrichment_flags f on f.id = e.flag_id
                            where f.entity = 'job' and f.entity_key = p_jobname and e.action in ('raised', 're_raised')
                              and e.at between p_start - interval '30 seconds' and p_start + interval '5 seconds')  -- fixed: the pause and the cancelled start fall within seconds
              then 'paused' else p_status end
$function$;
revoke all on function security.cron_run_outcome_v1(text, text, text, timestamptz) from public, anon, authenticated;
comment on function security.cron_run_outcome_v1(text, text, text, timestamptz) is 'StudySearch SS-004 (1 Nov 2026): the outcome of a scheduled run for health and target T1: a run pg_cron reports as "job canceled" within seconds of the flag unit pausing that job for idleness is paused, not failed; every other status is returned unchanged. Inlined (no settings), schema-qualified.';

-- 2. the health check counts outcomes, not raw statuses
select pg_temp.edit_once('security.platform_health_check_v1(boolean)', 'b648e6494ccf39dbbe7eea6cec18f993', '43f5ba0f68140ccafe4a2d46fe0cf4ad', array[
 array[$o$from cron.job_run_details d group by d.jobid)$o$, $n$from (select d0.jobid, d0.start_time, d0.return_message, security.cron_run_outcome_v1(j0.jobname, d0.status, d0.return_message, d0.start_time) status
                  from cron.job_run_details d0 join cron.job j0 on j0.jobid=d0.jobid) d group by d.jobid)  -- SS-004 (1 Nov 2026): a run cancelled by the flag unit's idle pause is paused, not failed$n$],
 array[$o$(select d.status from cron.job_run_details d where d.jobid=r.jobid order by d.start_time desc limit$o$, $n$(select security.cron_run_outcome_v1(r.jobname, d.status, d.return_message, d.start_time) status from cron.job_run_details d where d.jobid=r.jobid order by d.start_time desc limit$n$],
 array[$o$select max(read_at) into v_ts from pipeline.coverage_course_pages;$o$, $n$-- SS-004 (1 Nov 2026): waiting is measured from the later of the last read and the moment the oldest waiting page became due, so a page that
      -- has only just become due after a quiet spell is not reported as hours of stall; a page left waiting still ages and goes critical
      select greatest(max(read_at), (select min(coalesce(q.next_read_at, q.bound_at)) from pipeline.coverage_course_pages q
                                      where q.status in ('bound','ambiguous') and coalesce(q.next_read_at,now())<=now() and q.read_attempts<3)) into v_ts from pipeline.coverage_course_pages;$n$],
 array[$o$select max(updated_at) into v_ts from pipeline.coverage_provider_discovery;$o$, $n$select greatest(max(updated_at), (select min(coalesce(q.next_due_at, q.updated_at)) from pipeline.coverage_provider_discovery q
                                         where (q.status='pending' or (q.status in ('mapped','failed') and q.next_due_at<=now())) and q.attempts<3
                                           and security.enrich_focus_v1(q.provider_id) and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id=q.provider_id))) into v_ts from pipeline.coverage_provider_discovery;  -- SS-004 (1 Nov 2026): as above$n$]],
 array[1, 1, 1, 1]);

-- 3. the weekly scorecard (T1) counts outcomes too
select pg_temp.edit_once('security.ops_scorecard_v1(date,jsonb)', '9e21229945de3b96ce3f738de2d1fbae', '18dcf612e1572f51797fb80853f0dbe3', array[
 array[$o$with r as (select (d.start_time at time zone v_tz)::date dy, d.status, j.jobname from cron.job_run_details d join cron.job j on j.jobid = d.jobid$o$,
       $n$with r as (select (d.start_time at time zone v_tz)::date dy, security.cron_run_outcome_v1(j.jobname, d.status, d.return_message, d.start_time) status, j.jobname from cron.job_run_details d join cron.job j on j.jobid = d.jobid$n$]],
 array[1]);

-- 4. stagger the admission writers (commands and frequency unchanged)
select cron.alter_job((select j.jobid from cron.job j where j.jobname = 'adapter-overwrite'), schedule => '3-59/10 * * * *');
select cron.alter_job((select j.jobid from cron.job j where j.jobname = 'coverage-admit-intakes'), schedule => '8-59/10 * * * *');
update pipeline.automation_catalogue set description = description || ' Runs at minute 3 of each 10 (SS-004, 1 Nov 2026: started apart from coverage-admit and coverage-admit-intakes, which write the same rows).'
 where jobname = 'adapter-overwrite' and description not like '%SS-004, 1 Nov 2026%';
update pipeline.automation_catalogue set description = description || ' Runs at minute 8 of each 10 (SS-004, 1 Nov 2026: started apart from coverage-admit and adapter-overwrite, which write the same rows).'
 where jobname = 'coverage-admit-intakes' and description not like '%SS-004, 1 Nov 2026%';

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.cron_run_outcome_v1', 'Platform', 'Platform upkeep', 'SS-004: a run cancelled by the flag unit''s idle pause is paused, not failed', 'active', '{}', '20261101010000')
on conflict do nothing;

-- post-check
do $$
begin
  if (select schedule from cron.job where jobname = 'adapter-overwrite') <> '3-59/10 * * * *'
     or (select schedule from cron.job where jobname = 'coverage-admit-intakes') <> '8-59/10 * * * *'
     or (select schedule from cron.job where jobname = 'coverage-admit') <> '*/10 * * * *' then
    raise exception 'SS-004 post-check: admission schedules'; end if;
  if (select count(*) from cron.job_run_details d join cron.job j on j.jobid = d.jobid
       where d.status = 'failed' and security.cron_run_outcome_v1(j.jobname, d.status, d.return_message, d.start_time) = 'failed' and d.return_message <> 'job canceled'
         and d.start_time > now() - interval '1 day') <>  -- fixed: post-check window
     (select count(*) from cron.job_run_details d where d.status = 'failed' and d.return_message <> 'job canceled' and d.start_time > now() - interval '1 day') then  -- fixed: post-check window
    raise exception 'SS-004 post-check: a real failure was reclassified'; end if;
end $$;
