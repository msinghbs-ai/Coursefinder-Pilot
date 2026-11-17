-- CF-247 StudySearch SS-004 follow-up (Platform Admin mandate 1 Nov 2026 08:57; admin 2026-10-31-studysearch-transformation.md §33).
-- Why (verified live 1 Nov 2026 09:28 and 09:38): after v2.15.387 the health check's scheduled-job section took 25.1 and 25.2 s (was 2.1 to 2.6 s)
--   and the whole run 27.9 s (was 14.3 to 19.5 s), because security.cron_run_outcome_v1 was called for every run in the scheduler log
--   (about 120,000 rows). Measured in one session: 2,295 ms called for every row; 65 ms called only for "job canceled" rows; 53 ms raw.
-- What: the health check (both places) and the scorecard call the classifier only for a run reported failed with "job canceled";
--   every other status passes through unchanged, so results are identical (same rule, same post-check).
-- Rollback: re-apply the v2.15.387 definitions (health check md5 43f5ba0f, scorecard md5 18dcf612) from migration 20261101010000.
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

select pg_temp.edit_once('security.platform_health_check_v1(boolean)', '43f5ba0f68140ccafe4a2d46fe0cf4ad', '964db44f6fbcf2cf4c6e6463f4860b40', array[
 array[$o$security.cron_run_outcome_v1(j0.jobname, d0.status, d0.return_message, d0.start_time) status
$o$,
       $n$case when d0.status='failed' and d0.return_message='job canceled' then security.cron_run_outcome_v1(j0.jobname, d0.status, d0.return_message, d0.start_time) else d0.status end status  -- SS-004 (1 Nov 2026): classified only when cancelled (keeps the section at its former run time)
$n$],
 array[$o$(select security.cron_run_outcome_v1(r.jobname, d.status, d.return_message, d.start_time) status from cron.job_run_details d$o$,
       $n$(select case when d.status='failed' and d.return_message='job canceled' then security.cron_run_outcome_v1(r.jobname, d.status, d.return_message, d.start_time) else d.status end status from cron.job_run_details d$n$]],
 array[1, 1]);

select pg_temp.edit_once('security.ops_scorecard_v1(date,jsonb)', '18dcf612e1572f51797fb80853f0dbe3', '100bd14801534ae6a1ce947b0cb1876b', array[
 array[$o$security.cron_run_outcome_v1(j.jobname, d.status, d.return_message, d.start_time) status, j.jobname from cron.job_run_details d$o$,
       $n$case when d.status='failed' and d.return_message='job canceled' then security.cron_run_outcome_v1(j.jobname, d.status, d.return_message, d.start_time) else d.status end status, j.jobname from cron.job_run_details d$n$]],
 array[1]);
