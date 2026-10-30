-- CF-247 D5, option R1 (integrator, admin decision §11.2, 30 Oct 2026; under Platform Admin decision A4 and approval D5 of 30 Oct 2026 08:45):
-- a person can record a printed grade whose page states no grading scale. In the AER workspace (public.admin_aer, the existing governed
-- edit and add path with a reason, history and optimistic concurrency) the matrix scale gains the choice "Not stated on the page"
-- (`not_stated`), stored as no scale (grade_scale null) beside the printed min_grade; the Website API v2 marker reads it as scale_stated false.
-- Admin side only: this file changes no consumer API function (the marker itself is the separate paste-applied consumer change).
--   - `not_stated` is refused until the consumer marker is live, so a row with no scale never reaches the website without the marker.
--   - It needs the grade as printed (the existing "printed in the quote" check still applies) and no numeric value (W7 unchanged).
--   - A new row has scale 'none' unless one is chosen (before, an add that sent no scale stored null by omission; none exists).
--   - Matrix rows only: course-page rows hold no scale and are unchanged. No reader change, no automatic admission, nothing re-read.
--   - The 20 quarantined RMIT Gao Kao rows are not touched (no data is written by this file).
-- Re-runnable: md5-guarded (before → after); a second run finds the after-md5 and changes nothing.
-- Replaces: public.admin_aer (same name, md5-guarded edit)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. No new table, column, job, setting or status.

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_once('public.admin_aer(text,jsonb)', '09dbbaf2aadc78e1c992d21a1048e661', '5e58f5d6126b3b2fe026e376a56c7686', array[
  -- 1 the matrix scale choice "Not stated on the page"
  array[$o$if coalesce(v_txt, 'none') not in ('percentage', 'points', 'aggregate', 'gpa', 'letter', 'rank', 'none') then raise exception 'unknown scale' using errcode = '22023'; end if; m.grade_scale := coalesce(v_txt, 'none');$o$,
        $n$if coalesce(v_txt, 'none') not in ('percentage', 'points', 'aggregate', 'gpa', 'letter', 'rank', 'none', 'not_stated') then raise exception 'unknown scale' using errcode = '22023'; end if;
          -- CF-247 D5 (decision A4, admin §11.2): "Not stated on the page" keeps the printed grade with no scale; the website marker reads it
          if v_txt = 'not_stated' and (position('scale_stated' in pg_get_functiondef('security.entry_matrix_payload_v1(uuid,text)'::regprocedure)) = 0
                                       or position('scale_stated' in pg_get_functiondef('security.entry_resolve_v1(uuid,text)'::regprocedure)) = 0) then
            raise exception '"Not stated on the page" can be chosen once the website marker is live (D5)' using errcode = '22023'; end if;
          m.grade_scale := case when v_txt = 'not_stated' then null else coalesce(v_txt, 'none') end;$n$],
  -- 2 a new matrix row states no scale unless one is chosen (never null by omission)
  array[$o$m.provenance := jsonb_build_object('reader', 'manual', 'actor', auth.uid(), 'reason', v_reason, 'at', now(), 'evidence_id', v_ev.id);$o$,
        $n$m.provenance := jsonb_build_object('reader', 'manual', 'actor', auth.uid(), 'reason', v_reason, 'at', now(), 'evidence_id', v_ev.id);
      m.grade_scale := 'none';  -- CF-247 D5: no scale is stored by omission; "Not stated on the page" is chosen explicitly$n$],
  -- 3 "Not stated on the page" needs the printed grade and no numeric value
  array[$o$if m.min_value is not null and coalesce(m.grade_scale, 'none') = 'none' then raise exception 'a numeric value needs its scale (percentage, points, GPA, ...)' using errcode = '22023'; end if;$o$,
        $n$if m.min_value is not null and coalesce(m.grade_scale, 'none') = 'none' then raise exception 'a numeric value needs its scale (percentage, points, GPA, ...)' using errcode = '22023'; end if;
      -- CF-247 D5: a scale not stated on the page keeps the grade as printed and holds no number
      if m.grade_scale is null and m.min_grade is null then raise exception '"Not stated on the page" needs the grade as printed' using errcode = '22023'; end if;$n$]],
  array[1, 1, 1]);
