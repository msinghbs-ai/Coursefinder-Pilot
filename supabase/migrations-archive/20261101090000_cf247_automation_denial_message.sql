-- CF-247 StudySearch SS-016 (Platform Admin direction 1 Nov 2026 21:02, §2): correct the misleading role-denial message.
-- Why: security.admin_automation_control_v1 (pause, resume, Run now, how often, per run) refuses ranks below 5 with "Platform Admin role
--   required", although its floor is rank 5 (PIM Admin) and the per-automation check (control_rank, default 6) decides the rest. A Pipeline
--   Operator was told the wrong role; a PIM Admin was already allowed.
-- What: the floor's message only. The boundary is unchanged: same rank-5 floor, same per-automation control_rank check, same area rule.
-- Before: 30c319b8ed37dbc1df6700a0d3f5c46f. After: 71951aa2faf643f0dd86aae580e6c34d (dry run in a rolled-back transaction, 1 Nov 21:10).
-- Rollback: re-apply the before definition (the same edit reversed).
-- Replaces: security.admin_automation_control_v1 (same name; md5-guarded edit of one message)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API untouched (G3). No setting: a message, not a value (G2).

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

select pg_temp.edit_once('security.admin_automation_control_v1(text,text,jsonb)', '30c319b8ed37dbc1df6700a0d3f5c46f', '71951aa2faf643f0dd86aae580e6c34d', array[
 array[$o$if auth.uid() is null or v_rank<5 then raise exception 'Platform Admin role required' using errcode='42501'; end if;$o$,
       $n$-- SS-016 (Platform Admin 1 Nov 2026 21:02): the floor is rank 5, so the refusal names the PIM Admin; the boundary is unchanged
  if auth.uid() is null or v_rank<5 then raise exception 'PIM Admin role or above required to change automations. A Pipeline Operator records the issue and raises it with the PIM Admin' using errcode='42501'; end if;$n$]],
 array[1]);
