-- CF-247 (2 Oct 2026). With English cascade step 3 (MiMo v2.6 Pro) switched on by the Platform Admin, the waiting
-- English reviews that steps 1 and 2 could not settle for a checking reason (score out of range, test listed twice,
-- quote not on the saved page, quote not naming the test) and that have no value on record are sent back once, so they
-- go through all three steps. Reviews where the page differs from a value already held stay with a person. Each review
-- is superseded with the reason kept; the page goes back to the Layer 3 queue. Same pattern as Decision 226 and the
-- intake send-back of 2 Oct 2026 (migration 20261002184000).
with l4 as (
  update pipeline.layer4_review_items l set status = 'superseded', decided_at = now(),
         escalation_reason = 'Superseded: sent back to Layer 3 for the English cascade with MiMo v2.6 Pro as step 3 (was: ' || left(l.escalation_reason, 120) || ').'
   where l.status = 'pending' and l.layer3_interpretation_id is not null and l.before_value is null
     and l.field_code = 'course_english'
  returning l.layer3_interpretation_id),
fact as (
  update pipeline.layer3_work_items w set status = 'failed', updated_at = now(), last_error = 'released: sent back to Layer 3 for the MiMo step (2 Oct 2026)'
    from l4 where w.interpretation_id = l4.layer3_interpretation_id and w.status = 'layer4_required'
  returning w.id)
update pipeline.layer3_fact_handoffs h set work_item_id = null, attempts = 0 from fact where h.work_item_id = fact.id;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('requeue', 'send_back', 'English: checking failures with no value on record, for the MiMo step', jsonb_build_object('decision', 'English step 3 switched on, 2 Oct 2026 (Decision 230)'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
