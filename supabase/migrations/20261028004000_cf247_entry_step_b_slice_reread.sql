-- CF-247 Track C Step B, B1: the decided slice read of RMIT BH126 once more, on the whole page (worker v0.49.1, verified live before this
-- merge). Count-guarded: only when the one earlier item is the skipped first read (21:39, "the page does not state it"). Record: admin
-- docs/platform/ENTRY-REQUIREMENTS-STEP-B-DECISION-2026-10-28.md; build log 28 Oct 2026.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched. No new job.

do $$
declare v_course uuid := '09431698-3cfd-4c2b-8669-e924bc65c329';  -- RMIT Bachelor of Engineering (Honours) BH126 (decision record section 2)
begin
  if (select count(*) from pipeline.field_enrich_items where field = 'entry_requirements') = 1
     and exists (select 1 from pipeline.field_enrich_items where field = 'entry_requirements' and course_id = v_course and state = 'skipped' and reason = 'the page does not state it') then
    perform security.course_entry_read_enqueue_v1(v_course, '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid,
      'Track C Step B slice read again on the whole page (worker v0.49.1; first read 21:39 saw only the page''s main element)');
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('entry_requirements', 'course_read', v_course::text, jsonb_build_object('reason', 'Track C Step B slice read again on the whole page', 'migration', '20261028004000'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid);
  end if;
  if (select count(*) from pipeline.field_enrich_items where field = 'entry_requirements') > 2 then
    raise exception 'slice guard: more than two entry_requirements items would exist';
  end if;
end $$;
