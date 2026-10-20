CREATE OR REPLACE FUNCTION pim_api.manual_pim_candidates_read(p_status text DEFAULT NULL::text, p_entity_type text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'security', 'auth'
AS $function$
declare v_actor uuid:=auth.uid(); v_rank int; v_items jsonb;
begin
  if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  if v_rank<5 then raise exception 'PIM Operator role required' using errcode='42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_items
  from (
    select id,entity_type,target_provider_id,source_kind,external_identifier,source_url,evidence_id,candidate_payload,status,reason,decision_reason,created_by,created_at,updated_by,updated_at
    from pipeline.pim_source_candidates
    where (p_status is null or status=p_status) and (p_entity_type is null or entity_type=p_entity_type)
    order by created_at desc limit least(greatest(coalesce(p_limit,100),1),200)
  ) x;
  return jsonb_build_object('items',v_items);
end $function$
