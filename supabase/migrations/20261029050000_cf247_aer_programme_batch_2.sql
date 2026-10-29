-- CF-247 AER programme batch 2 (Platform Admin mandate 29 Oct 2026 12:23, B2 and B3; admin docs/platform/AER-OPERATIONS-WORKSPACE-DECISION-2026-10-29.md W25).
-- 1. B2 "Thirteen outstanding Read again actions — approved": nine ANU pages read before worker v0.50.1 (one row kept of 8 to 12), three
--    Melbourne pages and UTS read from Firecrawl markdown copies. One governed attempt each through security.aer_reread_v1 (Catalogue ›
--    Entry requirements › Read again): ANU pages are read again with the current reader; markdown-stored pages are fetched again as HTML.
--    Earlier partial items are superseded, never approved. A refusal is recorded and not retried.
-- 2. B3 one bounded course-level batch through security.course_entry_batch_v1 (next by priority), refused by the function if the estimate
--    would take the OpenRouter balance below its floor; then DP020 (RMIT Diploma of Commerce, 111278B) is read once from its stored page
--    (security.course_entry_read_enqueue_v1, the "Read from the stored page" mechanism) for the A3 verification. Every course read goes to Layer 4.
-- Actor: the Platform Admin. Count-guarded: exactly thirteen sources, at most one batch and one course read.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table, setting or status.

do $$
declare v_pa constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';  -- the Platform Admin (mandate 29 Oct 2026 12:23)
        v_reason constant text := 'AER programme batch 2 (Platform Admin mandate 29 Oct 2026 12:23 B2): one governed attempt with the current reader';
        v_ids uuid[]; r record; v_res jsonb; v_out jsonb := '[]'::jsonb; v_batch jsonb; v_dp020 jsonb;
begin
  select array_agg(s.id) into v_ids from pipeline.entry_matrix_sources s
   where s.id in ('86ef4c8b-c5cb-4c50-b939-b8321da0ca9f', 'f2fde9f0-2c7b-4484-8403-6156a7d21254', '7675875e-11f2-4dc5-a89c-b7a87e4c6f6d',
                  '4a860899-38c7-45d7-9f4e-aded848363e9', '67776138-b392-4bab-aab7-994455cdc6c9', '886c3e6b-fd31-4250-b169-6c4929dffb79',
                  '0cc3e0b1-33a3-4938-aca6-9d49b33631cb', '84c08ade-6373-4527-af54-cc50ebec9e44', '76b38128-193c-4a06-9d48-b3b90efa5936',
                  'b2adafb5-cd4c-4655-8343-fb4efebab483', '76b365ed-839c-4b10-ac96-c9da8d23822b', '467c7a0c-c3b1-42c1-b4ca-32511f6afd04',
                  '87f40035-ff4a-47b2-be18-0f2bfd817f1d');
  if coalesce(array_length(v_ids, 1), 0) <> 13 then raise exception 'expected exactly the thirteen named sources, found %', coalesce(array_length(v_ids, 1), 0); end if;
  for r in select s.id, s.url from pipeline.entry_matrix_sources s where s.id = any (v_ids) order by s.url loop
    begin
      v_res := security.aer_reread_v1(r.id, v_reason, v_pa);
    exception when others then
      v_res := jsonb_build_object('refused', sqlerrm);  -- recorded, not retried
    end;
    v_out := v_out || jsonb_build_array(jsonb_build_object('source', r.id, 'url', r.url, 'result', v_res));
  end loop;
  begin
    v_batch := security.course_entry_batch_v1(null, null, 'AER course-level programme, batch 2 (Platform Admin mandate 29 Oct 2026 12:23 B3): next by priority, above the credit floor', v_pa, false);
  exception when others then
    v_batch := jsonb_build_object('refused', sqlerrm);
  end;
  if not exists (select 1 from pipeline.field_enrich_items f where f.course_id = 'b365fde8-d003-4ef6-80c3-4136fbd5587a' and f.field = 'entry_requirements') then
    v_dp020 := jsonb_build_object('job_id', security.course_entry_read_enqueue_v1('b365fde8-d003-4ef6-80c3-4136fbd5587a'::uuid, v_pa,
                 'A3 verification (Platform Admin mandate 29 Oct 2026 12:23): RMIT Diploma of Commerce DP020 read once from its stored page'));
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_matrix', 'programme_batch', 'migration 20261029050000', jsonb_build_object('rereads', v_out, 'course_batch', v_batch, 'dp020', v_dp020, 'reason', v_reason), v_pa);
end $$;
