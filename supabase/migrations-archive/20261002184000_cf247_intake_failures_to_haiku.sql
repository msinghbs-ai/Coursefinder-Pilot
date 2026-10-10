-- CF-247 (2 Oct 2026). With intake cascade step 2 (Claude Haiku 4.5) switched on by the Platform Admin, the waiting
-- intake reviews that step 1 could not settle for a quoting or format reason (quote not on the saved page, too many
-- quotes, an answer that was not JSON) are sent back once, so they go through Qwen3 30B and then Haiku. Reviews about
-- months not written in the quotes (mostly "Semester 1" or rolling intakes) and every other review stay for a person.
-- Each review is superseded with the reason kept; the page goes back to the Layer 3 queue.
with l4 as (
  update pipeline.layer4_review_items l set status = 'superseded', decided_at = now(),
         escalation_reason = 'Superseded: sent back to Layer 3 for the cascade with Claude Haiku 4.5 as step 2 (was: ' || left(l.escalation_reason, 120) || ').'
   where l.status = 'pending' and l.layer3_interpretation_id is not null and l.before_value is null
     and l.field_code = 'course_intake'
     and (l.layer3_state->'errors' ? 'quote_not_in_page_text' or l.layer3_state->'errors' ? 'too_many_quotes'
          or exists (select 1 from jsonb_array_elements_text(coalesce(l.layer3_state->'errors', '[]'::jsonb)) e where e like 'unparseable%'))
     and not (l.layer3_state->'errors' ? 'month_not_in_quotes')
  returning l.layer3_interpretation_id),
fact as (
  update pipeline.layer3_work_items w set status = 'failed', updated_at = now(), last_error = 'released: sent back to Layer 3 for the Haiku step (2 Oct 2026)'
    from l4 where w.interpretation_id = l4.layer3_interpretation_id and w.status = 'layer4_required'
  returning w.id)
update pipeline.layer3_fact_handoffs h set work_item_id = null, attempts = 0 from fact where h.work_item_id = fact.id;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('requeue', 'send_back', 'Intakes: quoting and format failures, for the Haiku step', jsonb_build_object('decision', 'Haiku step 2 switched on, 2 Oct 2026'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
