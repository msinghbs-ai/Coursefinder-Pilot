-- CF-247 StudySearch SS-016 acceptance S1 (role walkthrough fixtures, overnight mandate 1 Nov 2026 22:01 §4): the per-automation refusal names
-- the role that changes the automation. Why: "this automation needs a higher role to change" named no owner, so a PIM Admin refused on a
-- Platform Admin automation could not tell whom to ask (UR-02 "denial names the next owner").
-- What: the message of the control_rank check in security.admin_automation_control_v1 only. The check itself is unchanged (same rank floor,
-- same control_rank, same retired-job rules).
-- Before: 71951aa2faf643f0dd86aae580e6c34d. After: 431aff603f21b8c8a030073b07a08259 (rolled-back dry run, 1 Nov 2026 23:18 AEDT; live unchanged).
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

select pg_temp.edit_once('security.admin_automation_control_v1(text,text,jsonb)', '71951aa2faf643f0dd86aae580e6c34d', '431aff603f21b8c8a030073b07a08259', array[
 array[$o$if v_rank<coalesce(c.control_rank,6) then raise exception 'this automation needs a higher role to change' using errcode='42501'; end if;$o$,
       $n$-- SS-016 acceptance S1 (1 Nov 2026): the refusal names the role that changes this automation; the check is unchanged
  if v_rank<coalesce(c.control_rank,6) then raise exception 'this automation is changed by the %', case when coalesce(c.control_rank,6)>=6 then 'Platform Admin' when c.control_rank=5 then 'PIM Admin' else 'Pipeline Operator or above' end using errcode='42501'; end if;$n$]],
 array[1]);
