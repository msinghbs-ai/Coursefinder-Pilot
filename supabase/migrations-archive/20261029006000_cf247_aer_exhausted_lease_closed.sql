-- CF-247 AER programme (Platform Admin consolidated mandate, 28 Oct 2026 23:22: holds are recorded, never a silent skip): a read whose
-- worker stopped without reporting back (cut by the platform's wall clock) keeps its lease. Once the lease ran out on the last of
-- entry.matrix_attempts it was never picked again and never closed, so it showed as "leased" for ever (Wollongong, 28 Oct 14:49).
-- The fire job now closes such a run as failed, naming the tries and the last error, so it shows as a hold in the Provider drawer.
-- Nothing is re-read and nothing is spent; runs with tries left are picked again as before.
-- Replaces: security.entry_matrix_fire_v1 (same name, md5-guarded edit)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table, setting or status.

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_n('security.entry_matrix_fire_v1()', '85d54db58fe5718080a69cd4a6937b36', array[
  array[$o$  v_q := security.entry_matrix_enqueue_v1();$o$,
        $n$  v_q := security.entry_matrix_enqueue_v1();
  -- 29 Oct 2026: a run whose lease ran out on its last try is closed as failed (the worker stopped without reporting back)
  update pipeline.entry_matrix_runs r set state = 'failed', leased_until = null, updated_at = now(),
         error = left('stopped after ' || r.attempts || ' tries without a reply: ' || coalesce(r.error, 'no error recorded'), 400)
   where r.state = 'leased' and r.leased_until < now() and r.attempts >= security.pipeline_num_v1('entry.matrix_attempts', 3);$n$]], array[1]);
