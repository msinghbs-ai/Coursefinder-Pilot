-- CF-247 StudySearch usability remediation UR-07 (Platform Admin mandate 1 Nov 2026 11:48, Tranche C; record §36).
-- Why: Automations showed Resume, Run now and frequency controls on jobs the component register records as retiring or retired
--   (l4-rule-low-agreement, cron-history-retention, cron-history-trim), and Resume area switched on every job in the area.
-- What: security.admin_automation_control_v1 (md5-guarded) refuses resume, run now, frequency and batch changes for a retiring or retired
--   job (naming its replacement) and Resume area skips them; pause stays allowed. security.admin_automations_read_v1 (md5-guarded) returns
--   each such job's retirement (status, replacement, removal date) so the screen shows Retiring/Retired without controls. No job is retired,
--   dropped or switched by this change. UR-13 is in scripts/ci/apply-migration.sh (same release).
-- Dry run (rolled back, Platform Admin): resume and run now of l4-rule-low-agreement refused; Resume area left the 3 retiring jobs off.
-- Rollback: re-apply md5 d90af04c and 81d5e16a.
-- Replaces: security.admin_automation_control_v1, security.admin_automations_read_v1 (same names; md5-guarded edits)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API untouched (G3).

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

select pg_temp.edit_once('security.admin_automation_control_v1(text,text,jsonb)', 'd90af04ccda6b74a88a506c58c0299fb', '30c319b8ed37dbc1df6700a0d3f5c46f', array[
 array[$o$where c2.area=p_args->>'area' and c2.control_rank<=v_rank loop$o$,
       $n$where c2.area=p_args->>'area' and c2.control_rank<=v_rank
                 -- UR-07 (1 Nov 2026): an area resume never switches on a retiring or retired job
                 and not (p_action='resume_area' and exists (select 1 from pipeline.component_register cr where cr.kind='job' and cr.name=j2.jobname and cr.status in ('retiring','retired'))) loop$n$],
 array[$o$  if p_action in ('pause','resume') then
    perform cron.alter_job(j.jobid, active => p_action='resume');$o$,
       $n$  -- UR-07 (1 Nov 2026): a retiring or retired job cannot be switched on, run or re-scheduled; it can still be paused
  if p_action <> 'pause' and exists (select 1 from pipeline.component_register cr where cr.kind='job' and cr.name=p_job and cr.status in ('retiring','retired')) then
    raise exception 'this automation is retired (%); it cannot be switched on, run or changed',
      coalesce((select 'replaced by '||cr.replaced_by from pipeline.component_register cr where cr.kind='job' and cr.name=p_job and cr.status in ('retiring','retired') and cr.replaced_by is not null limit 1), 'no replacement recorded');
  end if;
  if p_action in ('pause','resume') then
    perform cron.alter_job(j.jobid, active => p_action='resume');$n$]],
 array[1, 1]);

select pg_temp.edit_once('security.admin_automations_read_v1()', '81d5e16a3b3101c9e308696377886c68', 'f5120aedfd35a82bdf905597cec0267f', array[
 array[$o$'failed_24h',coalesce(a.failed_24h,0)
      ) order by$o$,
       $n$'failed_24h',coalesce(a.failed_24h,0),
        -- UR-07 (1 Nov 2026): a retiring or retired job says so, with its replacement and removal date
        'retirement',(select jsonb_build_object('status',cr.status,'replaced_by',cr.replaced_by,'retire_after',cr.retire_after) from pipeline.component_register cr
                       where cr.kind='job' and cr.name=j.jobname and cr.status in ('retiring','retired') limit 1)
      ) order by$n$]],
 array[1]);
