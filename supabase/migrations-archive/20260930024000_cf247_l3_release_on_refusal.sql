-- CF-247 Layer 3 cascade: when OpenRouter refuses a call (HTTP 401/402/403/429: key, billing or rate limit), the page is
-- not a model failure. The route stops the batch and releases the page (work item failed with a note, interpretation
-- cancelled, hand-off freed without using its retry allowance) instead of escalating it or sending it to Layer 4.
create or replace function public.layer3_fact_release_service(p_work_item_id uuid, p_interpretation_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
declare w pipeline.layer3_work_items%rowtype;
begin
  perform public.layer3_routing_service_guard();
  select * into w from pipeline.layer3_work_items where id=p_work_item_id for update;
  if w.id is null or w.interpretation_id is distinct from p_interpretation_id then raise exception 'work item / interpretation mismatch'; end if;
  if w.status<>'interpreting' then return jsonb_build_object('work_status',w.status,'note','already completed'); end if;
  update pipeline.layer3_interpretations set status='cancelled', call_completed_at=now(),
         validator_result=jsonb_build_object('valid',false,'errors',jsonb_build_array(left(coalesce(p_reason,'provider refusal'),300)),'routing','cf247-l3-cascade-v1')
   where id=p_interpretation_id;
  update pipeline.layer3_work_items set status='failed', updated_at=now(), last_error=left('released: provider refused the call; the page will be retried ('||coalesce(p_reason,'')||')',500) where id=w.id;
  update pipeline.layer3_fact_handoffs set work_item_id=null where work_item_id=w.id;
  return jsonb_build_object('work_status','released');
end $f$;
revoke all on function public.layer3_fact_release_service(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.layer3_fact_release_service(uuid,uuid,text) to service_role;
