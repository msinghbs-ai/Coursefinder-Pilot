-- CF-247 AER programme batch 3 (Platform Admin mandate 29 Oct 2026 12:23, B1 and B3; admin docs/platform/AER-OPERATIONS-WORKSPACE-DECISION-2026-10-29.md W24 and W25).
-- 1. B1 "Re-read each source once after correction through the existing governed mechanism": Federation, Wollongong, Otago Polytechnic
--    and UWA, whose v0.51.0 reads dropped quotes that were on the stored page with their table structure, are read once again through
--    security.aer_reread_v1 (Catalogue › Entry requirements › Read again) by worker coverage-sweep-worker-v0.52.0 (release v2.15.367,
--    deployed and verified before this migration is merged). Earlier incomplete items are superseded, never approved; a refusal is recorded
--    and not retried.
-- 2. B3 one bounded course-level batch through security.course_entry_batch_v1 (next by priority), refused by the function if the estimate
--    would take the OpenRouter balance below its floor (balance and floor are read by the function at the time it runs). Every course read
--    goes to Layer 4.
-- Actor: the Platform Admin. Count-guarded: exactly four sources, at most one batch.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table, setting or status.

do $$
declare v_pa constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';  -- the Platform Admin (mandate 29 Oct 2026 12:23)
        v_reason constant text := 'AER programme batch 3 (Platform Admin mandate 29 Oct 2026 12:23 B1): one read with the corrected reader v0.52.0';
        v_ids uuid[]; r record; v_res jsonb; v_out jsonb := '[]'::jsonb; v_batch jsonb;
begin
  select array_agg(s.id) into v_ids from pipeline.entry_matrix_sources s
   where s.id in ('58c60102-e549-4482-be03-7b6358059ada', 'c9a5c1d5-8334-4fd6-89f7-f194deb5ad53', 'd74fcba4-a492-4cde-a1f0-70a398e6bfda',
                  '74306034-c24a-4ed8-a859-1770edd7ab0b');
  if coalesce(array_length(v_ids, 1), 0) <> 4 then raise exception 'expected exactly the four named sources, found %', coalesce(array_length(v_ids, 1), 0); end if;
  for r in select s.id, s.url from pipeline.entry_matrix_sources s where s.id = any (v_ids) order by s.url loop
    begin
      v_res := security.aer_reread_v1(r.id, v_reason, v_pa);
    exception when others then
      v_res := jsonb_build_object('refused', sqlerrm);  -- recorded, not retried
    end;
    v_out := v_out || jsonb_build_array(jsonb_build_object('source', r.id, 'url', r.url, 'result', v_res));
  end loop;
  begin
    v_batch := security.course_entry_batch_v1(null, null, 'AER course-level programme, batch 3 (Platform Admin mandate 29 Oct 2026 12:23 B3): next by priority, above the credit floor', v_pa, false);
  exception when others then
    v_batch := jsonb_build_object('refused', sqlerrm);
  end;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_matrix', 'programme_batch', 'migration 20261029090000', jsonb_build_object('rereads', v_out, 'course_batch', v_batch, 'reason', v_reason), v_pa);
end $$;
