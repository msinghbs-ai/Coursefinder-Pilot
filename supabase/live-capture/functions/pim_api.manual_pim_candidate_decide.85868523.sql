CREATE OR REPLACE FUNCTION pim_api.manual_pim_candidate_decide(p_candidate_id uuid, p_action text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'security', 'auth'
AS $function$
declare v_actor uuid:=auth.uid(); v_rank int; v_status text;
begin
  if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  if v_rank<5 then raise exception 'PIM Operator role required' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'decision reason required' using errcode='22023'; end if;
  v_status:=case p_action when 'validate' then 'validated' when 'review' then 'needs_review' when 'ready' then 'ready_for_acquisition' when 'reject' then 'rejected' when 'cancel' then 'cancelled' else null end;
  if v_status is null then raise exception 'invalid candidate action' using errcode='22023'; end if;
  update pipeline.pim_source_candidates set status=v_status,decision_reason=trim(p_reason),updated_by=v_actor,updated_at=now() where id=p_candidate_id;
  if not found then raise exception 'candidate not found' using errcode='22023'; end if;
  return jsonb_build_object('ok',true,'candidate_id',p_candidate_id,'status',v_status,'canonical_written',false,'published',false);
end $function$
