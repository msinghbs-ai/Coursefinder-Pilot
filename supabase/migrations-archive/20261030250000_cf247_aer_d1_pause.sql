-- CF-247 AER D1, paused at its ceiling check: enrich.course_entry_slice_concurrency back to 4 (Platform Admin mandate 30 Oct 2026 08:45,
-- D1; decision §11: "back to 4 at D1 close-out"). D1 read 41 long course pages (probe 5, QUT 36), all complete, for US$1.6891, and stopped
-- because the 125 readable unread QUT pages need about US$4.69 at the measured US$0.00259 a slice against US$4.31 left. The approved page
-- limit (entry.course_page_chars 205,000) and slice bound (enrich.course_entry_max_slices 19) stay: they hold no cost and let a long page be
-- read whole when a read is approved. If D1 resumes, concurrency is raised again in that change.
-- Actor: the Platform Admin.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table, setting or status.

do $$
declare v_n int;
begin
  select count(*) into v_n from pipeline.field_enrich_items f where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased');
  if v_n <> 0 then raise exception 'precondition: % entry reads are waiting', v_n; end if;
  update pipeline.platform_toolset_settings set value = to_jsonb(4), updated_by = '63ba56cb-48d4-4169-98c2-7c4d1f72925b', updated_at = now(),
         reason = 'CF-247 AER D1 paused at its ceiling check (Platform Admin mandate 30 Oct 2026 08:45): back to the value before D1'
   where toolset_key = 'pipeline' and key = 'enrich.course_entry_slice_concurrency' and value = to_jsonb(10);
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'enrich.course_entry_slice_concurrency was not 10; nothing changed'; end if;
end $$;
