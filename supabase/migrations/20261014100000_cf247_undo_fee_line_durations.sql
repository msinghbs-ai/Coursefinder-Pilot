-- CF-247 v2.15.276, website requirements register O7 (Platform Admin decision, 14 Oct 2026 20:04, multiple choice: "Undo and tighten rule").
--   Two New Zealand course durations were admitted by Enrich fields from a fee line ("International fee(s) displayed is/are for 1 year of
--   study"), not from the course length. They are cleared on the course only where the course still holds exactly the value the job wrote and
--   no hand lock exists; the items keep their value and quote and are marked skipped with the reason, so the change can be reversed.
--   Worker v0.23.2 rejects such quotes from now on. Semester durations stay null in the website API (decision "Keep null").
-- Nothing dropped or deleted.

with bad as (
  select i.id, i.course_id, (i.value->>'value')::numeric v, i.value->>'unit' u
    from pipeline.field_enrich_items i
   where i.field = 'duration' and i.state = 'filled'
     and i.quote ~* 'fees?\s+(displayed|shown|quoted|listed)\s+(is|are)\s+for|(per|for)\s+(1|one)\s+year\s+of\s+study'),
cleared as (
  update catalogue.courses c set duration_value = null, duration_unit = null, updated_at = now()
    from bad b
   where c.id = b.course_id and c.duration_value = b.v and c.duration_unit = b.u
     and not exists (select 1 from pipeline.manual_locks l where to_jsonb(l)::text like '%' || c.id::text || '%')
  returning c.id)
update pipeline.field_enrich_items i set state = 'skipped', updated_at = now(),
       reason = 'undone 14 Oct 2026 (O7): the quote is about the fee basis, not the course length'
  from bad b where i.id = b.id and b.course_id in (select id from cleared);

do $$ declare n int; begin
  select count(*) into n from pipeline.field_enrich_items where field = 'duration' and reason like 'undone 14 Oct 2026 (O7)%';
  if n <> 2 then raise exception 'O7 post-check: expected 2 durations undone, found %', n; end if;
end $$;
