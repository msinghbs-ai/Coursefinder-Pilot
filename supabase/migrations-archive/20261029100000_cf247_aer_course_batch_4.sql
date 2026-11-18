-- CF-247 AER course-level programme batch 4 (Platform Admin mandate 29 Oct 2026 12:23, B3; admin docs/platform/AER-OPERATIONS-WORKSPACE-DECISION-2026-10-29.md W25).
-- One bounded course-level batch through security.course_entry_batch_v1 (next by priority). The function reads the OpenRouter balance and
-- its floor when it runs and refuses a batch whose estimate would take the balance below the floor; a refusal is recorded, not retried.
-- Every course read goes to Layer 4; generic notes (such as a minimum age) are left for reviewer judgement.
-- Actor: the Platform Admin. At most one batch.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table, setting or status.

do $$
declare v_pa constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';  -- the Platform Admin (mandate 29 Oct 2026 12:23)
        v_reason constant text := 'AER course-level programme, batch 4 (Platform Admin mandate 29 Oct 2026 12:23 B3): next by priority, above the credit floor';
        v_batch jsonb;
begin
  begin
    v_batch := security.course_entry_batch_v1(null, null, v_reason, v_pa, false);
  exception when others then
    v_batch := jsonb_build_object('refused', sqlerrm);  -- recorded, not retried
  end;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_matrix', 'programme_batch', 'migration 20261029100000', jsonb_build_object('course_batch', v_batch, 'reason', v_reason), v_pa);
end $$;
