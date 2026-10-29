-- CF-247 AER decision W28 (29 Oct 2026, lodged by the integrator): Read again targets the newest stored copy.
-- security.aer_reread_v1 handed a finished read to public.admin_entry_matrix_reread(array[source]), which re-queues EVERY done or failed run
-- of the source. A source fetched twice keeps one run per stored copy, so Read again on Otago Polytechnic (d74fcba4) re-ran the 28 Oct copy
-- (run 0d4ca5a0, content_hash fb572a9f...) as well as the 29 Oct copy (run 55ace659, 370a12ce...) and left two pending Layer 4 items
-- (f14ae480 stale, 81d14690 current).
-- Now:
--   * "Newest" is the run on the source's current stored copy: entry_matrix_sources.content_hash, which is the hash of the source's current
--     evidence (entry_matrix_sources.evidence_id); verified live 29 Oct 2026: 0 sources differ, every source with runs has one on that copy.
--     Ties, or a source with no run on that copy, fall back to the latest run created (the previous rule).
--   * Only that run is read again (done: its proposed rows and pending item superseded, its result kept in previous_results, re-queued;
--     failed and not held: re-queued as before).
--   * Runs on older stored copies are not re-queued and keep their history (state, result, previous_results, review_item_id untouched).
--     Their still-proposed rows and still-pending Layer 4 item are closed with the statuses the function already uses for an earlier read
--     ('superseded'), rows first, then the item, as admin_entry_matrix_reread does. Items already decided are not touched (status = 'pending'
--     only), nor are the rows of a run whose item is decided; rows in any status other than 'proposed' are not touched.
-- Unchanged: every guard (reason, scope, AI limits, queued/leased, waiting fetch, held_unparsed), the markdown re-fetch branch, the quote,
-- identity, completeness and admission gates (worker and svc_entry_matrix_record are not edited), public.admin_entry_matrix_reread (its md5 is
-- pinned by security.governed_aer_close_snapshot_v1, so it is left as it is) and the consumer API (G3: no consumer function is edited).
-- No new status, action or setting vocabulary: statuses 'superseded' / 'pending' / 'proposed' and event action 'reread' already exist.
-- Replaces: security.aer_reread_v1 (same name and signature, md5-guarded edit); its done-run hand-off to public.admin_entry_matrix_reread
-- Retires: nothing
-- Nothing dropped, deleted or renamed. No new job, table, setting or status.

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

select pg_temp.edit_n('security.aer_reread_v1(uuid,text,uuid)', '7da109835cf52fb9790778eec6882664', array[
  -- 1. the run read again is the run on the newest stored copy
  array[$o$  select * into v_run from pipeline.entry_matrix_runs where source_id = v_src.id order by created_at desc limit 1;$o$,
        $n$  -- W28 (29 Oct 2026): the run on the newest stored copy (the source's current content_hash), else the latest run; older copies keep their history
  select * into v_run from pipeline.entry_matrix_runs where source_id = v_src.id
   order by (content_hash is not distinct from v_src.content_hash) desc, created_at desc, id desc limit 1;$n$],
  -- 2. older copies closed (not re-read); a finished newest run read again on its own, not through admin_entry_matrix_reread(array[source])
  array[$o$  if v_run.state = 'done' then
    return public.admin_entry_matrix_reread(array[v_src.id], v_reason);
  end if;$o$,
        $n$  -- W28: runs on older stored copies are not read again. Their proposed rows, then their still-pending item, are superseded; decided items stay
  update catalogue.provider_entry_matrix m set status = 'superseded', status_reason = 'older stored copy; read again on the newest copy: ' || v_reason, updated_at = now()
   where m.status = 'proposed' and m.run_id in (select r.id from pipeline.entry_matrix_runs r left join pipeline.layer4_review_items li on li.id = r.review_item_id
                                                 where r.source_id = v_src.id and r.id <> v_run.id and (li.id is null or li.status = 'pending'));
  get diagnostics v_rows = row_count;
  update pipeline.layer4_review_items li set status = 'superseded'
   where li.status = 'pending' and li.id in (select r.review_item_id from pipeline.entry_matrix_runs r where r.source_id = v_src.id and r.id <> v_run.id);
  get diagnostics v_items = row_count;

  if v_run.state = 'done' then
    -- the newest copy's run only: rows first, then the item (its trigger then finds no proposed rows left), result kept, re-queued
    update catalogue.provider_entry_matrix set status = 'superseded', status_reason = 'read again: ' || v_reason, updated_at = now()
     where run_id = v_run.id and status = 'proposed';
    get diagnostics v_n = row_count; v_rows := v_rows + v_n;
    if v_run.review_item_id is not null then
      update pipeline.layer4_review_items set status = 'superseded' where id = v_run.review_item_id and status = 'pending';
      get diagnostics v_n = row_count; v_items := v_items + v_n;
    end if;
    update pipeline.entry_matrix_runs
       set previous_results = previous_results || jsonb_build_array(jsonb_build_object('result', result, 'rows_admitted', rows_admitted,
             'rows_dropped', rows_dropped, 'cost_usd', cost_usd, 'model', model_code, 'review_item_id', review_item_id, 'done_at', done_at,
             'reread_at', now(), 'reason', v_reason, 'state', state, 'error', error, 'attempts_used', attempts, 'earlier_index', jsonb_array_length(previous_results))),
           state = 'queued', attempts = 0, leased_until = null, result = null, rows_admitted = 0, rows_dropped = 0, review_item_id = null,
           error = null, done_at = null, updated_at = now()
     where id = v_run.id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('entry_matrix', 'reread', 'pipeline.entry_matrix_runs',
            jsonb_build_object('sources', jsonb_build_array(v_src.id), 'runs', 1, 'run', v_run.id, 'content_hash', v_run.content_hash,
                               'rows_superseded', v_rows, 'items_superseded', v_items, 'reason', v_reason), p_actor);
    return jsonb_build_object('ok', true, 'runs', 1, 'run', v_run.id, 'rows_superseded', v_rows, 'items_superseded', v_items);
  end if;$n$],
  -- 3. a failed (not held) newest run: the event and the answer also count what was closed on older copies
  array[$o$jsonb_build_object('source', v_src.id, 'run', v_run.id, 'reason', v_reason), p_actor);$o$,
        $n$jsonb_build_object('source', v_src.id, 'run', v_run.id, 'rows_superseded', v_rows, 'items_superseded', v_items, 'reason', v_reason), p_actor);$n$],
  array[$o$return jsonb_build_object('ok', true, 'runs', 1);$o$,
        $n$return jsonb_build_object('ok', true, 'runs', 1, 'run', v_run.id, 'rows_superseded', v_rows, 'items_superseded', v_items);$n$]
], array[1, 1, 1, 1]);

comment on function security.aer_reread_v1(uuid, text, uuid) is 'CF-247 AER W12: one source read again (or fetched again as HTML when its stored copy is markdown); called by public.admin_aer after the Platform Admin check, and by approved programme migrations. Owner only. W28 (29 Oct 2026): only the run on the newest stored copy (the source''s current content_hash) is read again; runs on older copies keep their history, and their proposed rows and pending Layer 4 item are superseded.';
