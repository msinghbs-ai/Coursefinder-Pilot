CREATE OR REPLACE FUNCTION l4_api.publication_control_preview(p_entity_type text, p_entity_ids uuid[], p_target_scope text, p_action text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'security', 'auth'
AS $function$
declare v_actor uuid:=auth.uid(); v_rank int; v_ids uuid[]; v_id uuid; v_items jsonb:='[]'::jsonb; v_token text; v_state jsonb; v_auto boolean;
begin
  if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  if v_rank<5 then raise exception 'PIM Admin role required' using errcode='42501'; end if;
  if p_action not in ('publish','unpublish','rollback') then raise exception 'invalid publication action' using errcode='22023'; end if;
  if p_target_scope not in ('search_api','website','zoho','governed_publication') then raise exception 'invalid target scope' using errcode='22023'; end if;
  select array_agg(distinct x order by x) into v_ids from unnest(coalesce(p_entity_ids,'{}'::uuid[])) x;
  if coalesce(array_length(v_ids,1),0)<1 then raise exception 'at least one entity required' using errcode='22023'; end if;
  if array_length(v_ids,1)>100 then raise exception 'publication cohort exceeds 100 records' using errcode='22023'; end if;
  foreach v_id in array v_ids loop
    if not security.layer4_entity_exists(p_entity_type,v_id) then raise exception 'entity not found: %',v_id using errcode='22023'; end if;
    v_state:=public.layer4_publication_state(p_entity_type,v_id,p_target_scope);
    v_items:=v_items||jsonb_build_array(jsonb_build_object('entity_id',v_id,'current_state',v_state));
  end loop;
  select auto_publication_enabled into v_auto from pipeline.publication_control_settings where singleton=true;
  v_token:=md5(p_entity_type||'|'||p_target_scope||'|'||p_action||'|'||array_to_string(v_ids,','));
  return jsonb_build_object('entity_type',p_entity_type,'target_scope',p_target_scope,'action',p_action,'count',array_length(v_ids,1),'confirmation_token',v_token,'items',v_items,'auto_publication_enabled',coalesce(v_auto,false),'mutated',false);
end $function$
