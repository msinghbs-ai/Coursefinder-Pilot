-- The human-assisted recovery release's edit of security.ops_report_v1 (cf247-human-assisted-recovery, migration 20261104450000 section 12,
-- afbbe4f0), copied verbatim with its helper: 5a1e21cc -> 3ba694dc. Fixture database only.
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
select pg_temp.edit_once('security.ops_report_v1(integer)', '5a1e21cc42f8f54cbf0d9f3f7fe81c71', '3ba694dc078995d88a983e8e92b2f425',
  array[array[$o$  return v_out;
end $o$, $n$  -- human-assisted recovery (Platform Admin decision 4 Nov 2026 06:30 §9): interventions per workstream (security.layer4_intervention_report_v1)
  begin
    v_out := v_out || jsonb_build_object('human_assisted_recovery', security.layer4_intervention_report_v1());
  exception when others then v_out := v_out || jsonb_build_object('human_assisted_recovery', jsonb_build_object('error', left(sqlerrm, 200)));
  end;
  return v_out;
end $n$]], array[1]);
