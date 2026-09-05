-- CF-206 — enable/disable reusable Layer 4 Scholarship scope rules with audited reason.
create or replace function public.layer4_scope_rule_set_state(p_rule_id uuid,p_enabled boolean,p_reason text)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline','auth' as $$
declare v_actor uuid:=auth.uid();v_rank int;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
 if length(trim(coalesce(p_reason,'')))<8 then raise exception 'state-change reason must be at least 8 characters'; end if;
 update pipeline.layer4_scope_rules set enabled=p_enabled,updated_at=now(),conditions=conditions||jsonb_build_object('last_state_reason',trim(p_reason),'last_state_actor',v_actor,'last_state_at',now()) where id=p_rule_id;
 if not found then raise exception 'rule not found'; end if;
 return jsonb_build_object('ok',true,'rule_id',p_rule_id,'enabled',p_enabled,'publication_changed',false);
end$$;
revoke all on function public.layer4_scope_rule_set_state(uuid,boolean,text) from public,anon;
grant execute on function public.layer4_scope_rule_set_state(uuid,boolean,text) to authenticated,service_role;
