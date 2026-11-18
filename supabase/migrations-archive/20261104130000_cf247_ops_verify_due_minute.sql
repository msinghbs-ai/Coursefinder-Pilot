-- CF-247 P0 workstream A: a verification due at a run is done in that run (Integration Controller 3 Nov 2026 20:05; branch cf247-ops-a3).
-- Why (production, read-only, 3 Nov 2026 20:03-20:04 AEDT): IQ-00067 was diagnosed reopened_on_stale_evidence at 19:24 and remedy
--   reclose_stale_reopen acted (run 17, finished 19:24:02.08). The controller set next_action_at to the run's own start plus the cool-down,
--   19:24:00.369247 + 30 minutes = 19:54:00.369247. The 19:54 run of job ops-controller started at 19:54:00.312177, 57 ms earlier, so
--   security.ops_controller_tick_v1 saw next_action_at > its start and skipped the verification without a trace (step 1: "if next_action_at >
--   v_t0 then continue"). security.ops_verify_stale_reopen_v1(67) passed when called at 20:04 (11 coverage-admit runs since the close, none
--   failed): the verification path itself is sound. A cool-down equal to the schedule interval makes every verification depend on the
--   scheduler's start-time jitter (it slips a whole run whenever a run starts a fraction of a second earlier in its minute than the last one);
--   the same comparison picks the issues due for diagnosis.
-- What: an action or look due at any time within the run's minute is due in that run (both comparisons), and a verification not yet due is
--   counted in the run summary (not_due) instead of being skipped silently. The rule that a verification runs on a later run than its action is
--   unchanged (finished_at < the run's start). Stored next_action_at values are not rewritten; IQ-00067 is verified at the next run.
-- Replaces: security.ops_controller_tick_v1 (same name; md5-guarded edit)
-- Retires: nothing
-- Nothing is dropped, deleted or switched on. No spend. Consumer API untouched (G3).
-- md5 (pg_get_functiondef) before -> after:
--   security.ops_controller_tick_v1()                                 b4df5f8106fcbaca1bfcd933f532a55f -> 5dce3c4735eb6cd0594c0fdbb77b6486

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

select pg_temp.edit_once('security.ops_controller_tick_v1()', 'b4df5f8106fcbaca1bfcd933f532a55f', '5dce3c4735eb6cd0594c0fdbb77b6486', array[
  array[$o$    if coalesce(i.next_action_at, '-infinity') > v_t0 then continue; end if;$o$,
        $n$    -- due within this run's minute: the scheduler starts each run a fraction of a second after the minute, and the cool-down is measured from
    -- the acting run's start (IQ-00067, 3 Nov 2026 19:54: due 19:54:00.369, run started 19:54:00.312); a run not yet due is counted, not hidden
    if coalesce(i.next_action_at, '-infinity') >= date_trunc('minute', v_t0) + interval '1 minute' then  -- fixed: one scheduler minute
      v_n := v_n || jsonb_build_object('not_due', coalesce((v_n->>'not_due')::int, 0) + 1); continue;
    end if;$n$],
  array[$o$(coalesce(x.next_action_at, '-infinity') <= v_t0 or$o$,
        $n$(coalesce(x.next_action_at, '-infinity') < date_trunc('minute', v_t0) + interval '1 minute' or$n$]  -- fixed: one scheduler minute
]::text[][], array[1, 1]);
