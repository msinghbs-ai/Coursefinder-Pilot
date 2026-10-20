CREATE OR REPLACE FUNCTION pim_api.manual_pim_candidate_register(p_entity_type text, p_target_provider_id uuid DEFAULT NULL::uuid, p_source_kind text DEFAULT 'first_party'::text, p_external_identifier text DEFAULT NULL::text, p_source_url text DEFAULT NULL::text, p_evidence_id uuid DEFAULT NULL::uuid, p_candidate_payload jsonb DEFAULT '{}'::jsonb, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'security', 'auth'
AS $function$
declare v_actor uuid:=auth.uid(); v_rank int; v_id uuid;
begin
  if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  if v_rank<5 then raise exception 'PIM Operator role required' using errcode='42501'; end if;
  if p_entity_type not in ('provider','course','campus','scholarship') then raise exception 'invalid entity type' using errcode='22023'; end if;
  if p_source_kind not in ('authority','first_party') then raise exception 'invalid source kind' using errcode='22023'; end if;
  if p_entity_type in ('course','campus','scholarship') and p_target_provider_id is null then raise exception 'target Provider required' using errcode='22023'; end if;
  if p_evidence_id is null and length(trim(coalesce(p_source_url,'')))<8 then raise exception 'source URL or Evidence required' using errcode='22023'; end if;
  if p_evidence_id is not null and not exists(select 1 from pipeline.evidence_artifacts where id=p_evidence_id) then raise exception 'Evidence not found' using errcode='22023'; end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'reason required' using errcode='22023'; end if;
  insert into pipeline.pim_source_candidates(entity_type,target_provider_id,source_kind,external_identifier,source_url,evidence_id,candidate_payload,reason,created_by,updated_by)
  values(p_entity_type,p_target_provider_id,p_source_kind,nullif(trim(coalesce(p_external_identifier,'')),''),nullif(trim(coalesce(p_source_url,'')),''),p_evidence_id,coalesce(p_candidate_payload,'{}'::jsonb),trim(p_reason),v_actor,v_actor)
  returning id into v_id;
  return jsonb_build_object('ok',true,'candidate_id',v_id,'status','submitted','canonical_written',false,'published',false);
exception when unique_violation then
  raise exception 'matching active source-backed candidate already exists' using errcode='23505';
end $function$
