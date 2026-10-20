CREATE OR REPLACE FUNCTION l4_api.layer4_review_bulk_decide(p_entity_type text, p_field_code text, p_escalation_reason text, p_action text, p_reason text, p_confirmation text, p_limit integer DEFAULT 500)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'security', 'pipeline', 'auth'
AS $function$
declare v_actor uuid:=auth.uid();v_rank int;v_count int;v_expected text;v_ok int:=0;v_failed int:=0;v_op uuid;r record;v_err jsonb:='[]'::jsonb;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501';end if;v_rank:=security.current_role_rank();if v_rank<4 then raise exception 'pipeline_operator role required for mass decisions' using errcode='42501';end if;
 if p_action not in('reject','request_more_evidence','return_layer2','return_layer3') then raise exception 'unsupported generic mass action';end if;if length(trim(coalesce(p_reason,'')))<8 then raise exception 'decision reason must be at least 8 characters';end if;
 select count(*) into v_count from pipeline.layer4_review_items where status='pending' and entity_type=p_entity_type and field_code=p_field_code and coalesce(escalation_reason,'')=coalesce(p_escalation_reason,'');if v_count=0 then raise exception 'no pending review items in group';end if;
 v_count:=least(v_count,greatest(1,least(coalesce(p_limit,500),500)));v_expected:=upper(p_action)||' '||v_count;if trim(coalesce(p_confirmation,''))<>v_expected then raise exception 'confirmation must exactly match %',v_expected;end if;
 insert into pipeline.layer4_mass_operations(target_kind,action,actor_id,group_key,reason,before_count) values('review_queue',p_action,v_actor,jsonb_build_object('entity_type',p_entity_type,'field_code',p_field_code,'escalation_reason',coalesce(p_escalation_reason,'')),trim(p_reason),v_count) returning id into v_op;
 for r in select id from pipeline.layer4_review_items where status='pending' and entity_type=p_entity_type and field_code=p_field_code and coalesce(escalation_reason,'')=coalesce(p_escalation_reason,'') order by created_at limit v_count loop
  begin perform security.layer4_review_decide_impl(r.id,p_action,trim(p_reason),null);v_ok:=v_ok+1;exception when others then v_failed:=v_failed+1;if jsonb_array_length(v_err)<10 then v_err:=v_err||jsonb_build_array(jsonb_build_object('review_item_id',r.id,'error',sqlerrm));end if;end;
 end loop;
 update pipeline.layer4_mass_operations set affected_count=v_ok,result=jsonb_build_object('failed_count',v_failed,'sample_errors',v_err,'publication_changed',false) where id=v_op;
 return jsonb_build_object('ok',v_failed=0,'operation_id',v_op,'action',p_action,'processed',v_ok,'failed',v_failed,'remaining_in_group',greatest((select count(*) from pipeline.layer4_review_items where status='pending' and entity_type=p_entity_type and field_code=p_field_code and coalesce(escalation_reason,'')=coalesce(p_escalation_reason,'')),0),'sample_errors',v_err,'publication_changed',false);
end $function$
