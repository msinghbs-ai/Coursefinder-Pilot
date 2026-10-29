-- CF-247 AER bounded paid reads, close-out: entry.course_batch_size back to 50.
-- It was raised from 50 to 200 by 20261030090000 for the approved B3 and B4 batches only (Platform Admin mandate 30 Oct 2026 06:53).
-- B3 (500 AU courses) and B4 (421 NZ courses) are complete, and no further batch is approved (B5 is not approved), so the setting returns to
-- the value it had before the mandate. The change is applied only while it still holds 200 and no course read is waiting.
-- Actor: the Platform Admin.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table, setting or status.

do $$
declare v_n int;
begin
  select count(*) into v_n from pipeline.field_enrich_items f where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased');
  if v_n <> 0 then raise exception 'precondition: % course reads are still waiting', v_n; end if;
  update pipeline.platform_toolset_settings set value = to_jsonb(50), updated_at = now(),
         reason = 'CF-247 AER bounded paid reads close-out (Platform Admin mandate 30 Oct 2026 06:53): B3 and B4 complete; back to the value before the mandate'
   where toolset_key = 'pipeline' and key = 'entry.course_batch_size' and value = to_jsonb(200);
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'entry.course_batch_size was not 200; nothing changed'; end if;
end $$;
