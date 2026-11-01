CREATE OR REPLACE FUNCTION security.layer4_review_decide_impl(p_review_item_id uuid, p_action text, p_reason text, p_final_value jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'auth'
AS $function$
declare
  v_actor uuid:=auth.uid(); v_rank int; v_item pipeline.layer4_review_items%rowtype;
  v_final jsonb; v_state text; v_scalar jsonb; v_scalar_id uuid; v_decision uuid;
  v_refresh_id uuid; v_search_signal_id uuid; v_evidence pipeline.evidence_artifacts%rowtype; v_aer jsonb;
begin
  if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
  if p_action not in ('approve','edit_and_approve','reject','request_more_evidence','return_layer2','return_layer3') then
    raise exception 'invalid action';
  end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'decision reason required'; end if;

  select * into v_item from pipeline.layer4_review_items where id=p_review_item_id for update;
  if not found then raise exception 'review item not found'; end if;
  if v_item.status<>'pending' then raise exception 'review item already decided'; end if;
  select * into v_evidence from pipeline.evidence_artifacts where id=v_item.evidence_id;

  v_final:=case when p_action='approve' then v_item.proposed_value when p_action='edit_and_approve' then p_final_value else null end;
  if p_action='edit_and_approve' and p_final_value is null then raise exception 'edited final value required'; end if;
  -- CF-247 A1-A3 (Platform Admin 30 Oct 2026 06:53): AER items take the evidence-aware review path only
  if v_item.field_code = any (security.aer_review_kinds_v1()) then
    -- A3: AER admission and rejection are the Platform Admin's; Curators keep their operational editing in the workspace
    if v_rank<6 then raise exception 'Platform Admin role required: AER items are admitted or rejected by the Platform Admin (decision A3)' using errcode='42501'; end if;
    v_aer:=security.aer_review_lineage_v1(v_item.id);
    if p_action='approve' then
      v_final:=v_item.proposed_value-'exclude_row_ids';  -- A1: a plain approval never carries an exclusion
    elsif p_action='edit_and_approve' then
      -- A1: the only edit of an AER item is Approve except: explicit waiting rows, one reason, the reviewer and the lineage recorded
      v_final:=security.aer_approve_except_v1(v_item.id,p_final_value,trim(p_reason),v_actor,v_aer);
    end if;
  end if;

  if p_action in ('approve','edit_and_approve') then
    if v_item.field_code='provider_current_tuition_validation' then
      -- Layer 4 tuition decisions record the fee (same convention as Layer 3 admission).
      v_scalar:=security.layer4_tuition_apply_impl(v_actor,v_item.id,v_final,trim(p_reason));
      v_scalar_id:=null;
    elsif v_item.field_code='official_course_url' then
      v_scalar:=security.layer4_course_link_apply_impl(v_actor,v_item.id,v_final,trim(p_reason));
      v_scalar_id:=null;
    elsif v_item.field_code='course_english' then
      -- CF-247 17 Oct 2026: English decisions write the course's English requirement (it was refused before)
      v_scalar:=security.layer4_course_english_apply_impl(v_actor,v_item.id,v_final,trim(p_reason));
      v_scalar_id:=null;
    elsif v_item.entity_type='provider' and v_item.field_code in ('no_page_first_run','conjoint_rule_first_run') then
      -- CF-247 SP-1: first run per provider (no page published / conjoint rule); reject etc. are applied by trigger
      v_scalar:=security.no_page_review_apply_v1(v_item.id,'approve',v_final,trim(p_reason));
      v_scalar_id:=null;
    elsif v_item.entity_type='provider' and v_item.field_code in ('entry_matrix_first_run','entry_matrix_change') then
      -- CF-247 Track C: approving an entry matrix run admits its rows (edit-and-approve may exclude rows); reject etc. quarantine by trigger
      v_scalar:=security.entry_matrix_review_apply_v1(v_item.id,'approve',v_final,trim(p_reason));
      v_scalar_id:=null;
    elsif v_item.entity_type='course' and v_item.field_code='course_entry_first_read' then
      -- CF-247 Track C Step B: approving a course entry read admits its rows (edit-and-approve may exclude rows); reject etc. by trigger
      v_scalar:=security.course_entry_review_apply_v1(v_item.id,'approve',v_final,trim(p_reason));
      v_scalar_id:=null;
    elsif v_item.entity_type='scholarship' and v_item.field_code='scope_resolution' then
      v_scalar:=security.layer4_scholarship_scope_close_impl(v_item.id);
      v_scalar_id:=null;
    else
    if v_item.entity_type<>'course' then raise exception 'terminal apply currently supports course scalar facts only'; end if;
    v_scalar:=security.layer4_course_scalar_resolve_impl(v_actor,v_item.entity_id,v_item.field_code,v_final,trim(p_reason));
    v_scalar_id:=nullif(v_scalar->>'resolution_id','')::uuid;
    end if;
    v_state:=case when p_action='approve' then 'approved' else 'edited_approved' end;
  elsif p_action='reject' then v_state:='rejected';
  elsif p_action='request_more_evidence' then v_state:='more_evidence';
  elsif p_action='return_layer2' then v_state:='returned_layer2';
  else v_state:='returned_layer3'; end if;

  update pipeline.layer4_review_items set status=v_state,decided_at=now() where id=v_item.id;
  insert into pipeline.layer4_decisions(
    review_item_id,action,actor_id,reason,before_value,proposed_value,final_value,evidence_id,
    layer2_state,layer3_state,scalar_resolution_id,change_control_ref
  ) values (
    v_item.id,p_action,v_actor,trim(p_reason),v_item.before_value,v_item.proposed_value,v_final,
    v_item.evidence_id,v_item.layer2_state,v_item.layer3_state,v_scalar_id,v_item.change_control_ref
  ) returning id into v_decision;
  if v_aer is not null then
    -- A1: every AER inclusion and exclusion is audited with its lineage (item, run, source, stored copy hash, rows)
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer4', case when p_action='edit_and_approve' then 'aer_approve_except' else 'aer_'||p_action end, 'pipeline.layer4_review_items',
            jsonb_build_object('review_item_id', v_item.id, 'decision_id', v_decision, 'kind', v_item.field_code, 'reason', trim(p_reason),
                               'lineage', v_aer, 'excluded_row_ids', coalesce(v_final->'exclude_row_ids', '[]'::jsonb), 'result', v_scalar), v_actor);
  end if;

  if p_action in ('request_more_evidence','return_layer2') then
    insert into pipeline.refresh_requests(
      requested_layer,source_id,entity_type,entity_id,evidence_id,reason,trigger_type,requested_by,change_control_ref
    ) values (
      2,v_evidence.source_id,v_item.entity_type,v_item.entity_id,v_item.evidence_id,trim(p_reason),
      'layer4_return',v_actor,v_item.change_control_ref
    ) returning id into v_refresh_id;
  elsif p_action='return_layer3' then
    insert into pipeline.refresh_requests(
      requested_layer,source_id,entity_type,entity_id,evidence_id,layer3_profile_id,revalidation_ref,
      reason,trigger_type,requested_by,change_control_ref
    ) values (
      3,v_evidence.source_id,v_item.entity_type,v_item.entity_id,v_item.evidence_id,
      nullif(v_item.layer3_state->>'profile_id','')::uuid,
      'L4:'||v_decision::text,trim(p_reason),'layer4_return',v_actor,v_item.change_control_ref
    ) returning id into v_refresh_id;
  end if;

  if p_action in ('approve','edit_and_approve') then
    insert into pipeline.search_refresh_signals(
      entity_type,entity_id,review_decision_id,reason,change_control_ref
    ) values (
      v_item.entity_type,v_item.entity_id,v_decision,
      'Accepted Layer 4 canonical change: '||trim(p_reason),v_item.change_control_ref
    ) returning id into v_search_signal_id;
  end if;

  return jsonb_build_object(
    'ok',true,'decision_id',v_decision,'review_item_id',v_item.id,'action',p_action,'status',v_state,
    'final_value',v_final,'scalar_resolution_id',v_scalar_id,'refresh_request_id',v_refresh_id,
    'publication_changed',false,'search_refresh_required',v_search_signal_id is not null,
    'search_refresh_signal_id',v_search_signal_id
  );
end $function$
