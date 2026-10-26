-- CF-247 AER v1.1 (Platform Admin 26 Oct 2026 21:45 "RMIT first (band ladder is the most complex — prove the pattern)"): a read of a
-- stored entry-requirements page can be done again when the reader changes. Record: admin docs/platform/aer-v1.1-build-log.md.
-- Why: the first six runs (26 Oct 22:5x-23:2x) read RMIT's band ladders as plain text; the level is named once per group of rows, so 21 of
-- 22 RMIT rows were dropped as quote_not_on_page (worker v0.48.1 now gives each table row whole). A run is keyed on (source, content
-- hash), so an unchanged page is never read again by itself.
-- 1 Column pipeline.entry_matrix_runs.previous_results (additive): each earlier result of the run, kept when it is read again.
-- 2 public.admin_entry_matrix_reread(source ids, reason): Platform Admin (or the database owner, actor recorded as null), logged. For each
--   finished run of those sources: its proposed rows become superseded (never active rows: an admitted row stays until a person changes
--   it), its pending Layer 4 item becomes superseded, the earlier result is kept in previous_results, and the run is queued again.
--   Nothing runs while entry.matrix_enabled is 0.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped, renamed or deleted. The consumer API is not touched (no consumer function reads these tables).

alter table pipeline.entry_matrix_runs add column if not exists previous_results jsonb not null default '[]'::jsonb;
comment on column pipeline.entry_matrix_runs.previous_results is 'Earlier results of this run, kept when the page is read again with a changed reader (admin_entry_matrix_reread).';

create or replace function public.admin_entry_matrix_reread(p_source_ids uuid[], p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare r pipeline.entry_matrix_runs%rowtype; v_runs int := 0; v_rows int := 0; v_items int := 0; v_n int;
begin
  if current_user <> 'postgres' and (auth.uid() is null or security.current_role_rank() < 6) then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'reason required'; end if;
  if coalesce(array_length(p_source_ids, 1), 0) = 0 then raise exception 'no sources given'; end if;
  for r in select * from pipeline.entry_matrix_runs where source_id = any(p_source_ids) and state = 'done' for update loop
    -- rows first, then the item: the item's trigger (entry_matrix_review_apply_v1) then finds no proposed rows left to change
    update catalogue.provider_entry_matrix set status = 'superseded', status_reason = 'read again: ' || trim(p_reason), updated_at = now()
     where run_id = r.id and status = 'proposed';
    get diagnostics v_n = row_count; v_rows := v_rows + v_n;
    if r.review_item_id is not null then
      update pipeline.layer4_review_items set status = 'superseded' where id = r.review_item_id and status = 'pending';
      get diagnostics v_n = row_count; v_items := v_items + v_n;
    end if;
    update pipeline.entry_matrix_runs
       set previous_results = previous_results || jsonb_build_array(jsonb_build_object('result', r.result, 'rows_admitted', r.rows_admitted,
             'rows_dropped', r.rows_dropped, 'cost_usd', r.cost_usd, 'model', r.model_code, 'review_item_id', r.review_item_id, 'done_at', r.done_at,
             'reread_at', now(), 'reason', trim(p_reason))),
           state = 'queued', attempts = 0, leased_until = null, result = null, rows_admitted = 0, rows_dropped = 0, review_item_id = null,
           error = null, done_at = null, updated_at = now()
     where id = r.id;
    v_runs := v_runs + 1;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_matrix', 'reread', 'pipeline.entry_matrix_runs',
          jsonb_build_object('sources', to_jsonb(p_source_ids), 'runs', v_runs, 'rows_superseded', v_rows, 'items_superseded', v_items, 'reason', trim(p_reason)), auth.uid());
  return jsonb_build_object('ok', true, 'runs', v_runs, 'rows_superseded', v_rows, 'items_superseded', v_items);
end $$;
revoke all on function public.admin_entry_matrix_reread(uuid[], text) from public, anon;
grant execute on function public.admin_entry_matrix_reread(uuid[], text) to authenticated;
comment on function public.admin_entry_matrix_reread(uuid[], text) is 'CF-247 AER v1.1: read stored entry-requirements pages again after a reader change; proposed rows and pending items superseded, earlier result kept. Platform Admin, logged.';
