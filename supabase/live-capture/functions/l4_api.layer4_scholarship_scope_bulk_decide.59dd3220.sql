CREATE OR REPLACE FUNCTION l4_api.layer4_scholarship_scope_bulk_decide(p_scholarship_id uuid, p_candidate_reason text, p_action text, p_reason text, p_confirmation text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'security', 'pipeline', 'scholarship', 'catalogue', 'auth'
AS $function$
declare v_actor uuid:=auth.uid();v_rank int;v_count int;v_missing int;v_mismatch int;v_inserted int:=0;v_affected int:=0;v_op uuid;v_expected text;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank();if v_rank<4 then raise exception 'pipeline_operator role required for mass decisions' using errcode='42501';end if;
 if p_action not in('accept','reject') then raise exception 'invalid mass action';end if;
 if length(trim(coalesce(p_reason,'')))<8 then raise exception 'decision reason must be at least 8 characters';end if;
 select count(*),count(*) filter(where cmc.evidence_id is null),count(*) filter(where c.provider_id is distinct from s.provider_id)
 into v_count,v_missing,v_mismatch
 from scholarship.course_mapping_candidates cmc join scholarship.scholarships s on s.id=cmc.scholarship_id join catalogue.courses c on c.id=cmc.course_id
 where cmc.status='needs_review' and cmc.scholarship_id=p_scholarship_id and cmc.candidate_reason=p_candidate_reason;
 if v_count=0 then raise exception 'no pending candidates in this cohort';end if;
 v_expected:=upper(p_action)||' '||v_count;if trim(coalesce(p_confirmation,''))<>v_expected then raise exception 'confirmation must exactly match %',v_expected;end if;
 if p_action='accept' and (v_missing>0 or v_mismatch>0) then raise exception 'structural blockers prevent bulk accept: missing evidence %, provider mismatch %',v_missing,v_mismatch;end if;
 insert into pipeline.layer4_mass_operations(target_kind,action,actor_id,group_key,reason,before_count,result)
 values('scholarship_course_scope',p_action,v_actor,jsonb_build_object('scholarship_id',p_scholarship_id,'candidate_reason',p_candidate_reason),trim(p_reason),v_count,jsonb_build_object('confirmation',p_confirmation,'semantic_warning',lower(coalesce(p_candidate_reason,'')) ~ '(exclusion|exact|requires governed review|country|eligib)')) returning id into v_op;
 if p_action='accept' then
  insert into scholarship.course_mappings(scholarship_id,course_id,mapping_state,mapping_basis,evidence_id,mapped_by)
  select cmc.scholarship_id,cmc.course_id,'mapped','layer4_mass_review:'||v_op::text,cmc.evidence_id,v_actor
  from scholarship.course_mapping_candidates cmc where cmc.status='needs_review' and cmc.scholarship_id=p_scholarship_id and cmc.candidate_reason=p_candidate_reason
  on conflict(scholarship_id,course_id) do nothing;
  get diagnostics v_inserted=row_count;
  update scholarship.course_mapping_candidates set status='accepted',updated_at=now() where status='needs_review' and scholarship_id=p_scholarship_id and candidate_reason=p_candidate_reason;
  get diagnostics v_affected=row_count;
 else
  update scholarship.course_mapping_candidates set status='rejected',updated_at=now() where status='needs_review' and scholarship_id=p_scholarship_id and candidate_reason=p_candidate_reason;
  get diagnostics v_affected=row_count;
 end if;
 update pipeline.layer4_mass_operations set affected_count=v_affected,result=result||jsonb_build_object('mappings_inserted',v_inserted,'missing_evidence',v_missing,'provider_mismatch',v_mismatch,'publication_changed',false) where id=v_op;
 return jsonb_build_object('ok',true,'operation_id',v_op,'action',p_action,'affected_count',v_affected,'mappings_inserted',v_inserted,'publication_changed',false,'search_refresh_required',false);
end $function$
