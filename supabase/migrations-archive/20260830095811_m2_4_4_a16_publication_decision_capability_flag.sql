create or replace function security.layer4_publication_state_read(p_entity_type text,p_entity_id uuid,p_target_scope text default 'governed_publication')
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','security','pipeline','auth'
as $$
declare v_last pipeline.layer4_publication_decisions%rowtype; v_rank int;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  select * into v_last from pipeline.layer4_publication_decisions
  where entity_type=p_entity_type and entity_id=p_entity_id and target_scope=p_target_scope
  order by created_at desc,id desc limit 1;
  return jsonb_build_object(
    'target_scope',p_target_scope,
    'can_decide',(v_rank>=5),
    'effective_decision',case when found and v_last.event_type<>'revert' then v_last.event_type else 'no_override' end,
    'decision_id',case when found then v_last.id else null end,
    'actor_id',case when found then v_last.actor_id else null end,
    'actor_email',case when found then v_last.actor_email else null end,
    'decided_at',case when found then v_last.created_at else null end,
    'reason_code',case when found then v_last.reason_code else null end,
    'comment',case when found then v_last.comment else null end,
    'readiness_snapshot',case when found then v_last.readiness_snapshot else '{}'::jsonb end,
    'overridden_checks',case when found then v_last.overridden_checks else '[]'::jsonb end
  );
end $$;