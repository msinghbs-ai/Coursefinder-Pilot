-- Layer 4 "Send back to AI check (Layer 3)" now re-runs tuition items.
-- Found 25 Sep 2026: the action recorded a decision and a refresh request, but nothing
-- consumes Layer 3 refresh requests for tuition, so a returned item left the queue and
-- was never re-checked. A trigger on the decision record re-queues the matching Layer 3
-- work item (waiting, due now), so single decisions and batches both work, without
-- changing the decision function. Items past the attempt limit get the existing
-- corrective-retry authorisation so the dispatcher does not park them again.
create or replace function security.layer4_return_layer3_requeue_trg()
returns trigger language plpgsql security definer
set search_path to 'pg_catalog','security','pipeline'
as $function$
declare v_item pipeline.layer4_review_items%rowtype;
begin
  if new.action<>'return_layer3' then return new; end if;
  select * into v_item from pipeline.layer4_review_items where id=new.review_item_id;
  if v_item.field_code<>'provider_current_tuition_validation' or v_item.layer3_interpretation_id is null then return new; end if;
  update pipeline.layer3_work_items w
  set status='pending', available_at=now(), completed_at=null, reserved_at=null, reserved_by=null,
      last_error='Returned by a Layer 4 reviewer for another AI check',
      corrective_retry_reason=left('Layer 4 send-back: '||coalesce(new.reason,''),2000),
      corrective_retry_count=w.corrective_retry_count + case when w.attempt_count>=5 then 1 else 0 end,
      corrective_retry_authorized_at=case when w.attempt_count>=5 then now() else w.corrective_retry_authorized_at end,
      updated_at=now()
  where w.interpretation_id=v_item.layer3_interpretation_id and w.status in ('layer4_required','parked','no_candidate','rejected');
  return new;
end $function$;
revoke all on function security.layer4_return_layer3_requeue_trg() from public, anon, authenticated;
drop trigger if exists layer4_return_layer3_requeue on pipeline.layer4_decisions;
create trigger layer4_return_layer3_requeue after insert on pipeline.layer4_decisions
for each row execute function security.layer4_return_layer3_requeue_trg();

-- Suggest "Send back" for items refused only because of link formatting, once a newly
-- qualified tuition binding is active (the pre-fix binding c45afa50... is excluded).
do $mig$
declare d text;
  a1 text := $q$i.evidence_quotes, i.confidence ai_confidence,$q$;
  b1 text := $q$i.evidence_quotes, i.confidence ai_confidence, i.validator_result l3_validator,$q$;
  a2 text := $q$      when b.field_code<>'provider_current_tuition_validation' then jsonb_build_object('action','check','text','Check the page, then decide.')$q$;
  b2 text := $q$      when b.field_code<>'provider_current_tuition_validation' then jsonb_build_object('action','check','text','Check the page, then decide.')
      when coalesce(b.l3_validator->'errors','[]'::jsonb) ? 'evidence quote not present in governed Evidence'
        and exists(select 1 from pipeline.layer3_model_profiles mp where mp.enabled and not mp.paused
                   and 'provider_current_tuition_validation'=any(mp.allowed_task_classes)
                   and coalesce(mp.quality_benchmark->>'binding_hash','') not in ('','c45afa505cb3dbf1bc4bafb43713ae8a55c43ae20e88ff61063df8e92218e0bf'))
        then jsonb_build_object('action','return_layer3','text','The AI''s quote was refused only because the page is saved with link formatting. That is now fixed: send it back for another AI check.')$q$;
begin
  d := pg_get_functiondef('security.layer4_review_desk_v1_impl(text,integer)'::regprocedure);
  if strpos(d,'saved with link formatting')>0 then return; end if;
  if (length(d)-length(replace(d,a1,'')))/length(a1) <> 1 then raise exception 'anchor 1 not found exactly once'; end if;
  if (length(d)-length(replace(d,a2,'')))/length(a2) <> 1 then raise exception 'anchor 2 not found exactly once'; end if;
  execute replace(replace(d,a1,b1),a2,b2);
end $mig$;
