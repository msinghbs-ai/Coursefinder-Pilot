-- CF-CHG-20260901-054
-- Defence-in-depth: legacy Layer 3 completion overload must also bypass generic Layer 4 field-review creation for source_pattern.
CREATE OR REPLACE FUNCTION public.layer3_complete_interpretation_service(p_interpretation_id uuid, p_raw_result jsonb, p_candidate_value jsonb, p_confidence numeric, p_rationale text, p_evidence_quotes jsonb, p_validator_result jsonb, p_valid boolean, p_response_model text, p_input_tokens integer, p_output_tokens integer, p_estimated_cost_usd numeric, p_expiry timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'catalogue'
AS $function$
declare v_i pipeline.layer3_interpretations%rowtype; v_review uuid; v_before jsonb;
begin
  select * into v_i from pipeline.layer3_interpretations where id=p_interpretation_id for update;
  if not found then raise exception 'interpretation not found'; end if;
  if v_i.status not in ('reserved','calling') then raise exception 'interpretation is not completable'; end if;
  if p_estimated_cost_usd<0 then raise exception 'invalid cost'; end if;
  update pipeline.layer3_interpretations set raw_result=p_raw_result,candidate_value=p_candidate_value,confidence=p_confidence,rationale=p_rationale,
    evidence_quotes=coalesce(p_evidence_quotes,'[]'::jsonb),validator_result=coalesce(p_validator_result,'{}'::jsonb),
    status=case when not p_valid then 'rejected_validation' when p_candidate_value is null or p_candidate_value='null'::jsonb then 'no_candidate' else 'validated' end,
    aggregator_response_model=p_response_model,input_tokens=p_input_tokens,output_tokens=p_output_tokens,estimated_cost_usd=coalesce(p_estimated_cost_usd,0),call_completed_at=now(),interpretation_expires_at=p_expiry
  where id=p_interpretation_id;
  if p_valid and v_i.task_class<>'source_pattern' and p_candidate_value is not null and p_candidate_value<>'null'::jsonb then
    if v_i.entity_type='course' then
      if v_i.task_class='course_description' then select to_jsonb(description) into v_before from catalogue.courses where id=v_i.entity_id;
      elsif v_i.task_class='delivery_mode' then select to_jsonb(delivery_mode) into v_before from catalogue.courses where id=v_i.entity_id;
      elsif v_i.task_class='duration' then select jsonb_build_object('value',duration_value,'unit',duration_unit) into v_before from catalogue.courses where id=v_i.entity_id;
      elsif v_i.task_class='official_course_url' then select to_jsonb(url) into v_before from catalogue.course_links where course_id=v_i.entity_id and link_type='official_course' and coalesce(status,'active')='active' order by last_verified_at desc nulls last,created_at desc limit 1;
      end if;
    end if;
    insert into pipeline.layer4_review_items(entity_type,entity_id,field_code,evidence_id,layer3_interpretation_id,before_value,proposed_value,layer2_state,layer3_state,escalation_reason)
    values(v_i.entity_type,v_i.entity_id,v_i.task_class,v_i.evidence_id,v_i.id,v_before,p_candidate_value,v_i.layer2_state,
      jsonb_build_object('profile_id',v_i.profile_id,'prompt_profile_version',v_i.prompt_profile_version,'candidate_value',p_candidate_value,'confidence',p_confidence,'rationale',p_rationale,'validator_result',p_validator_result,'response_model',p_response_model),'validated Layer 3 candidate requires human decision') returning id into v_review;
  end if;
  return jsonb_build_object('ok',true,'interpretation_id',p_interpretation_id,'validated',p_valid,'review_item_id',v_review);
end $function$;

revoke all on function public.layer3_complete_interpretation_service(uuid,jsonb,jsonb,numeric,text,jsonb,jsonb,boolean,text,integer,integer,numeric,timestamptz) from public,anon,authenticated;
grant execute on function public.layer3_complete_interpretation_service(uuid,jsonb,jsonb,numeric,text,jsonb,jsonb,boolean,text,integer,integer,numeric,timestamptz) to service_role;
