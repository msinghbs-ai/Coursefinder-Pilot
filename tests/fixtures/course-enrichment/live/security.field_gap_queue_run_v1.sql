create or replace function security.field_gap_queue_run_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 P0 mandate 3 Nov 2026 10:44 §3 Agent C: job field-gap-queue. Runs security.field_gap_queue_tick_v1 and records the run with an honest
-- outcome: done (a task with items), held (the previous standing task is still open, or the pass continues next run), idle (a full pass found
-- nothing), switched_off (the queue is off). A run never says "nothing due" while its pass is unfinished.
declare v jsonb; v_t0 timestamptz := clock_timestamp(); v_scan jsonb; v_out text; v_hold text; v_q text;
begin
  v := security.field_gap_queue_tick_v1();
  v_scan := v->'scan'; v_q := v->>'queue';
  v_out := case when v_q = 'started' then 'done' when v_q = 'off' then 'switched_off' when v_q = 'previous run still open' then 'held'
                when v_scan is not null and not coalesce((v_scan->>'cycle_complete')::boolean, true) then 'held'
                when v_scan->'waiting_for_page_proof' <> '{}'::jsonb then 'held'
                else 'idle' end;
  v_hold := case when v_q = 'previous run still open' then 'previous_run_open' when v_q = 'off' then 'queue_off'
                 when v_out = 'held' and not coalesce((v_scan->>'cycle_complete')::boolean, true) then 'scan_continues'
                 when v_out = 'held' then 'waiting_for_page_proof' when v_out = 'idle' then 'nothing_due' end;
  insert into pipeline.field_gap_queue_runs(outcome, hold_reason, items, scanned, cycle, cursor_from, cursor_to, cycle_complete, job_id, ms, detail)
  values (v_out, v_hold, coalesce((v->>'items')::int, 0), coalesce((v_scan->>'scanned')::int, 0), (v_scan->>'cycle')::int,
          (v_scan->>'cursor_from')::uuid, (v_scan->>'cursor_to')::uuid, (v_scan->>'cycle_complete')::boolean, (v->>'job_id')::uuid,
          (extract(epoch from clock_timestamp() - v_t0) * 1000)::int, v - 'crosscheck');  -- fixed: milliseconds
  return v || jsonb_build_object('outcome', v_out, 'hold_reason', v_hold);
end $function$;
