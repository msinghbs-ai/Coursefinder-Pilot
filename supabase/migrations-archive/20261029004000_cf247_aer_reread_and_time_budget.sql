-- CF-247 AER programme (Platform Admin consolidated mandate, 28 Oct 2026 23:22): after worker v0.50.1 answers live (#725, merged
-- separately: the 28 Oct deploy-order lesson), the ANU pages whose reads ended with no row because their rank-to-score tables were bare
-- numbers are read once more. Only runs with no Layer 4 item and no row are re-queued (16 expected, bounded at 20); runs whose rows wait
-- in Layer 4 are left to the Platform Admin's decision. The re-read goes to Layer 4 as a first read, as any other.
--
-- Also, a read cut by the worker's call time after it has spent on the model (a large page in many slices, Wollongong) was queued again
-- without using a try, so it could repeat and spend without end. It now uses one of entry.matrix_attempts; a read cut before any model
-- call still waits without using one. Slices are made larger again (entry.matrix_slice_chars 20,000; the answer limit is now 16,000
-- tokens, so the cut-off answers of 28 Oct do not recur), so large pages need fewer calls.
-- Replaces: public.svc_entry_matrix_record (same name, md5-guarded edit)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table or status.

do $$ declare v_n int; begin
  -- the earlier reading is kept whole in the run history before the run is queued again
  update pipeline.entry_matrix_runs set previous_results = previous_results || jsonb_build_array(jsonb_build_object('held', false, 'reason', 'read again after worker v0.50.1 (numeric tables named)',
                                          'attempt', attempts, 'model', model_code, 'at', now(), 'result', result)),
         state = 'queued', attempts = 0, leased_until = null, error = null, updated_at = now()
   where provider_id = 'e47a940d-186f-4a17-bb22-2b794b73248c' and state = 'done' and review_item_id is null and coalesce(rows_admitted, 0) = 0;
  get diagnostics v_n = row_count;
  if v_n > 20 then raise exception 'expected at most 20 ANU runs to read again, found %', v_n; end if;
end $$;

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

select pg_temp.edit_n('public.svc_entry_matrix_record(uuid,jsonb,numeric,text)', 'e1a130e278ff535e33eade3c2e0b9aa2', array[
  array[$o$when p_error = 'time budget' then 'queued' when attempts$o$,
        $n$when p_error = 'time budget' and coalesce(p_cost, 0) = 0 then 'queued' when attempts$n$],
  array[$o$attempts = case when p_error = 'time budget' then greatest(attempts - 1, 0) else attempts end,$o$,
        $n$attempts = case when p_error = 'time budget' and coalesce(p_cost, 0) = 0 then greatest(attempts - 1, 0) else attempts end,  -- 29 Oct 2026: a cut read that spent uses a try$n$]], array[1, 1]);

update pipeline.platform_toolset_settings set value = to_jsonb(20000), updated_at = now(),
       reason = 'CF-247 AER programme 29 Oct 2026: with the 16,000-token answer limit, 20,000-character slices fit; fewer calls for large pages (Wollongong ran out of call time in 12,000-character slices)'
 where toolset_key = 'pipeline' and key = 'entry.matrix_slice_chars';
