CREATE OR REPLACE FUNCTION security.layer4_batch_decide_v1_impl(p_item_ids uuid[], p_action text, p_reason text, p_confirmation text, p_batch_label text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'auth'
AS $function$
declare v_actor uuid:=auth.uid(); v_ids uuid[]; v_n int; v_kinds int; v_not_pending int; v_field text; v_entity text; v_res jsonb; v_results jsonb:='[]'::jsonb; v_id uuid; v_op uuid;
begin
  if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank()<4 then raise exception 'Pipeline Operator role is required for batch decisions' using errcode='42501'; end if;
  if p_action not in ('approve','reject','request_more_evidence','return_layer2','return_layer3') then raise exception 'this action cannot be applied as a batch'; end if;
  if length(trim(coalesce(p_reason,'')))<8 then raise exception 'a batch reason of at least 8 characters is required'; end if;
  select array_agg(distinct x) into v_ids from unnest(p_item_ids) x where x is not null;
  v_n := coalesce(cardinality(v_ids),0);
  if v_n<2 then raise exception 'a batch needs at least 2 items'; end if;
  if v_n>100 then raise exception 'a batch can hold at most 100 items'; end if;
  if trim(coalesce(p_confirmation,'')) <> upper(p_action)||' '||v_n then
    raise exception 'confirmation must exactly match "%"', upper(p_action)||' '||v_n;
  end if;
  select count(*) filter (where status<>'pending'), count(distinct (entity_type,field_code)), min(field_code), min(entity_type)
    into v_not_pending, v_kinds, v_field, v_entity
  from pipeline.layer4_review_items where id = any(v_ids);
  if (select count(*) from pipeline.layer4_review_items where id=any(v_ids)) <> v_n then raise exception 'some items were not found'; end if;
  if v_not_pending>0 then raise exception '% item(s) in this batch have already been decided; refresh and preview again', v_not_pending; end if;
  if v_kinds<>1 then raise exception 'a batch must contain one kind of item'; end if;
  -- CF-247 A2 (Platform Admin 30 Oct 2026 06:53): AER items are never decided in a batch; the batch is skipped and counted, nothing is decided
  if v_field = any (security.aer_review_kinds_v1()) then
    return jsonb_build_object('ok',false,'decided',0,'skipped_aer',v_n,'action',p_action,'reason','aer_review_path_only',
      'message',v_n||' AER item(s) skipped: AER items are decided one at a time in the AER review path (decision A2)');
  end if;
  if exists(select 1 from pipeline.layer4_review_items where id=any(v_ids) and assigned_to is not null and assigned_to<>v_actor and claimed_at > now()-interval '30 minutes') then
    raise exception '% item(s) in this batch are being reviewed by someone else; untick them or try later', (select count(*) from pipeline.layer4_review_items where id=any(v_ids) and assigned_to is not null and assigned_to<>v_actor and claimed_at > now()-interval '30 minutes');
  end if;
  if p_action='approve' and v_entity<>'course' then raise exception 'only course facts can be approved in a batch'; end if;

  foreach v_id in array v_ids loop
    v_res := security.layer4_review_decide_impl(v_id, p_action, trim(p_reason), null);
    v_results := v_results || jsonb_build_array(jsonb_build_object('review_item_id',v_id,'decision_id',v_res->>'decision_id','status',v_res->>'status'));
  end loop;

  insert into pipeline.layer4_mass_operations(target_kind,action,actor_id,group_key,reason,before_count,affected_count,result,change_control_ref)
  values ('review_batch',p_action,v_actor,jsonb_build_object('batch_label',p_batch_label,'entity_type',v_entity,'field_code',v_field,'item_ids',to_jsonb(v_ids)),
          trim(p_reason),v_n,jsonb_array_length(v_results),jsonb_build_object('decisions',v_results),'CF-CHG-20260915-247')
  returning id into v_op;
  return jsonb_build_object('ok',true,'mass_operation_id',v_op,'decided',jsonb_array_length(v_results),'action',p_action,'skipped_aer',0);
end $function$
;
