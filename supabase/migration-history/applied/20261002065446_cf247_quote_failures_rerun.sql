-- CF-247 (Decision 226, 2 Oct 2026). Platform Admin, 16:42: "We should concentrate on intakes and English requirements",
-- and by multiple choice: re-run the reviews where the AI's quote did not match the saved page.
--  1. The 446 waiting intake and English reviews whose only reason is "The AI quoted text that is not on the saved page"
--     are sent back to the Layer 3 cascade, as "Send back to AI" does: the review is superseded and the page goes back
--     into the Layer 3 queue for another check.
--  2. "Retry failed" for tuition no longer brings back tuition work parked because the regulator publishes the fee
--     (Decision 225). Patch behind an md5 guard.
with l4 as (
  update pipeline.layer4_review_items l set status = 'superseded', decided_at = now(),
         escalation_reason = 'Superseded: sent back to Layer 3 to be retried (the AI''s quote did not match the saved page; Decision 226).'
   where l.status = 'pending' and l.layer3_interpretation_id is not null and l.before_value is null
     and l.field_code in ('course_intake', 'course_english')
     and l.escalation_reason like 'The AI quoted text that is not on the saved page%'
  returning l.layer3_interpretation_id),
fact as (
  update pipeline.layer3_work_items w set status = 'failed', updated_at = now(), last_error = 'released: sent back to Layer 3 (Decision 226)'
    from l4 where w.interpretation_id = l4.layer3_interpretation_id and w.status = 'layer4_required'
  returning w.id)
update pipeline.layer3_fact_handoffs h set work_item_id = null, attempts = 0 from fact where h.work_item_id = fact.id;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('requeue', 'send_back', 'Intakes and English: quote not on the saved page', jsonb_build_object('decision', 'Decision 226'), null);

do $p$
declare s text; d text;
  o1 text := $o$where task_class=v_task and status in ('failed','parked') and v_tuition is not null;$o$;
  n1 text := $n$where task_class=v_task and status in ('failed','parked') and v_tuition is not null
         and security.tuition_chase_enabled((select c.provider_id from catalogue.courses c where c.id=entity_id));$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'security' and p.proname = 'admin_requeue_v1';
  if md5(s) is distinct from '9e8d37c5fa530978105e50ceb3a9f3eb' then raise exception 'admin_requeue_v1 changed (md5 %); not replacing', md5(s); end if;
  if (length(d) - length(replace(d, o1, ''))) / length(o1) <> 1 then raise exception 'piece not found once'; end if;
  execute replace(d, o1, n1);
end $p$;
