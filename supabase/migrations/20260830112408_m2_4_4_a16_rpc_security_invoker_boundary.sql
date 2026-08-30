
create schema if not exists l4_api;
revoke all on schema l4_api from public,anon,authenticated;
grant usage on schema l4_api to authenticated,service_role;

create or replace function l4_api.course_scalar_resolve(p_course_id uuid,p_field_code text,p_value jsonb,p_reason text)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','l4_api','security','auth'
as $$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  return security.layer4_course_scalar_resolve_impl(auth.uid(),p_course_id,p_field_code,p_value,p_reason);
end $$;

create or replace function l4_api.effective_entity(p_entity_type text,p_entity_id uuid)
returns jsonb language sql stable security definer
set search_path='pg_catalog','l4_api','security','auth'
as $$ select security.layer4_effective_entity_read(p_entity_type,p_entity_id) $$;

create or replace function l4_api.override_apply(
  p_entity_type text,p_entity_id uuid,p_field_code text,p_value jsonb,
  p_reason_code text,p_comment text default null,p_evidence_refs uuid[] default '{}',
  p_approval_context jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','l4_api','security','auth'
as $$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  return security.layer4_override_apply_impl(auth.uid(),p_entity_type,p_entity_id,p_field_code,p_value,p_reason_code,p_comment,p_evidence_refs,p_approval_context);
end $$;

create or replace function l4_api.override_history(p_entity_type text,p_entity_id uuid,p_field_code text)
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','l4_api','security','pipeline','auth'
as $$
declare v_rank int;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',d.id,'event_type',d.event_type,'underlying_value',d.underlying_value,'override_value',d.override_value,
      'reason_code',d.reason_code,'comment',d.comment,'evidence_refs',d.evidence_refs,
      'actor_id',d.actor_id,'actor_email',d.actor_email,'created_at',d.created_at,'supersedes_override_id',d.supersedes_override_id
    ) order by d.created_at desc,d.id desc)
    from pipeline.layer4_override_decisions d
    where d.entity_type=p_entity_type and d.entity_id=p_entity_id and d.field_code=p_field_code
  ),'[]'::jsonb);
end $$;

create or replace function l4_api.override_revert(
  p_entity_type text,p_entity_id uuid,p_field_code text,p_reason_code text,p_comment text default null
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','l4_api','security','pipeline','auth'
as $$
declare v_actor uuid:=auth.uid(); v_rank int; v_reg pipeline.layer4_field_registry%rowtype;
        v_prev pipeline.layer4_override_decisions%rowtype; v_id uuid; v_email text; v_underlying jsonb;
begin
  if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  select * into v_reg from pipeline.layer4_field_registry where entity_type=p_entity_type and field_code=p_field_code and enabled;
  if not found or v_reg.editability_class='immutable' then raise exception 'field is not revertible through Layer 4' using errcode='42501'; end if;
  if v_rank<v_reg.min_role_rank then raise exception 'insufficient role for Layer 4 field' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason_code,'')))<3 then raise exception 'reason code required' using errcode='22023'; end if;
  select * into v_prev from pipeline.layer4_override_decisions
   where entity_type=p_entity_type and entity_id=p_entity_id and field_code=p_field_code
   order by created_at desc,id desc limit 1;
  if not found or v_prev.event_type='revert' then raise exception 'no active Layer 4 override to revert' using errcode='22023'; end if;
  v_underlying:=security.layer4_underlying_value(p_entity_type,p_entity_id,p_field_code);
  select email into v_email from auth.users where id=v_actor;
  insert into pipeline.layer4_override_decisions(
    entity_type,entity_id,field_code,event_type,underlying_value,override_value,
    reason_code,comment,actor_id,actor_email,supersedes_override_id
  ) values (
    p_entity_type,p_entity_id,p_field_code,'revert',v_underlying,null,
    trim(p_reason_code),nullif(trim(coalesce(p_comment,'')),''),v_actor,v_email,v_prev.id
  ) returning id into v_id;
  return jsonb_build_object('ok',true,'override_id',v_id,'event_type','revert','effective_value',v_underlying,'effective_source','UNDERLYING','canonical_changed',false);
end $$;

create or replace function l4_api.publication_decide(
  p_entity_type text,p_entity_id uuid,p_target_scope text,p_event_type text,
  p_readiness_snapshot jsonb,p_overridden_checks jsonb,p_reason_code text,p_comment text default null,
  p_approval_context jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','l4_api','security','pipeline','auth'
as $$
declare v_actor uuid:=auth.uid(); v_rank int; v_prev uuid; v_id uuid; v_email text;
begin
  if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  if v_rank<5 then raise exception 'PIM Admin role required for publication override' using errcode='42501'; end if;
  if not security.layer4_entity_exists(p_entity_type,p_entity_id) then raise exception 'entity not found' using errcode='22023'; end if;
  if p_event_type not in ('publishable','not_publishable','revert') then raise exception 'invalid publication decision' using errcode='22023'; end if;
  if length(trim(coalesce(p_reason_code,'')))<3 then raise exception 'reason code required' using errcode='22023'; end if;
  select id into v_prev from pipeline.layer4_publication_decisions
   where entity_type=p_entity_type and entity_id=p_entity_id and target_scope=coalesce(nullif(trim(p_target_scope),''),'governed_publication')
   order by created_at desc,id desc limit 1;
  if p_event_type='revert' and v_prev is null then raise exception 'no publication override to revert' using errcode='22023'; end if;
  select email into v_email from auth.users where id=v_actor;
  insert into pipeline.layer4_publication_decisions(
    entity_type,entity_id,target_scope,event_type,readiness_snapshot,overridden_checks,
    reason_code,comment,actor_id,actor_email,supersedes_decision_id,approval_context
  ) values (
    p_entity_type,p_entity_id,coalesce(nullif(trim(p_target_scope),''),'governed_publication'),p_event_type,
    coalesce(p_readiness_snapshot,'{}'),coalesce(p_overridden_checks,'[]'),trim(p_reason_code),
    nullif(trim(coalesce(p_comment,'')),''),v_actor,v_email,v_prev,coalesce(p_approval_context,'{}')
  ) returning id into v_id;
  return jsonb_build_object('ok',true,'publication_decision_id',v_id,'event_type',p_event_type,'publication_status_changed',false,'consumer_cutover_authorised',false);
end $$;

create or replace function l4_api.publication_state(p_entity_type text,p_entity_id uuid,p_target_scope text default 'governed_publication')
returns jsonb language sql stable security definer
set search_path='pg_catalog','l4_api','security','auth'
as $$ select security.layer4_publication_state_read(p_entity_type,p_entity_id,p_target_scope) $$;

revoke all on all functions in schema l4_api from public,anon,authenticated;
grant execute on function l4_api.course_scalar_resolve(uuid,text,jsonb,text) to authenticated,service_role;
grant execute on function l4_api.effective_entity(text,uuid) to authenticated,service_role;
grant execute on function l4_api.override_apply(text,uuid,text,jsonb,text,text,uuid[],jsonb) to authenticated,service_role;
grant execute on function l4_api.override_history(text,uuid,text) to authenticated,service_role;
grant execute on function l4_api.override_revert(text,uuid,text,text,text) to authenticated,service_role;
grant execute on function l4_api.publication_decide(text,uuid,text,text,jsonb,jsonb,text,text,jsonb) to authenticated,service_role;
grant execute on function l4_api.publication_state(text,uuid,text) to authenticated,service_role;

create or replace function public.layer4_course_scalar_resolve(p_course_id uuid,p_field_code text,p_value jsonb,p_reason text)
returns jsonb language sql security invoker
set search_path='pg_catalog','public','l4_api'
as $$ select l4_api.course_scalar_resolve(p_course_id,p_field_code,p_value,p_reason) $$;

create or replace function public.layer4_effective_entity(p_entity_type text,p_entity_id uuid)
returns jsonb language sql stable security invoker
set search_path='pg_catalog','public','l4_api'
as $$ select l4_api.effective_entity(p_entity_type,p_entity_id) $$;

create or replace function public.layer4_override_apply(
  p_entity_type text,p_entity_id uuid,p_field_code text,p_value jsonb,
  p_reason_code text,p_comment text default null,p_evidence_refs uuid[] default '{}',
  p_approval_context jsonb default '{}'::jsonb
) returns jsonb language sql security invoker
set search_path='pg_catalog','public','l4_api'
as $$ select l4_api.override_apply(p_entity_type,p_entity_id,p_field_code,p_value,p_reason_code,p_comment,p_evidence_refs,p_approval_context) $$;

create or replace function public.layer4_override_history(p_entity_type text,p_entity_id uuid,p_field_code text)
returns jsonb language sql stable security invoker
set search_path='pg_catalog','public','l4_api'
as $$ select l4_api.override_history(p_entity_type,p_entity_id,p_field_code) $$;

create or replace function public.layer4_override_revert(
  p_entity_type text,p_entity_id uuid,p_field_code text,p_reason_code text,p_comment text default null
) returns jsonb language sql security invoker
set search_path='pg_catalog','public','l4_api'
as $$ select l4_api.override_revert(p_entity_type,p_entity_id,p_field_code,p_reason_code,p_comment) $$;

create or replace function public.layer4_publication_decide(
  p_entity_type text,p_entity_id uuid,p_target_scope text,p_event_type text,
  p_readiness_snapshot jsonb,p_overridden_checks jsonb,p_reason_code text,p_comment text default null,
  p_approval_context jsonb default '{}'::jsonb
) returns jsonb language sql security invoker
set search_path='pg_catalog','public','l4_api'
as $$ select l4_api.publication_decide(p_entity_type,p_entity_id,p_target_scope,p_event_type,p_readiness_snapshot,p_overridden_checks,p_reason_code,p_comment,p_approval_context) $$;

create or replace function public.layer4_publication_state(
  p_entity_type text,p_entity_id uuid,p_target_scope text default 'governed_publication'
) returns jsonb language sql stable security invoker
set search_path='pg_catalog','public','l4_api'
as $$ select l4_api.publication_state(p_entity_type,p_entity_id,p_target_scope) $$;

revoke all on function public.layer4_course_scalar_resolve(uuid,text,jsonb,text) from public,anon;
revoke all on function public.layer4_effective_entity(text,uuid) from public,anon;
revoke all on function public.layer4_override_apply(text,uuid,text,jsonb,text,text,uuid[],jsonb) from public,anon;
revoke all on function public.layer4_override_history(text,uuid,text) from public,anon;
revoke all on function public.layer4_override_revert(text,uuid,text,text,text) from public,anon;
revoke all on function public.layer4_publication_decide(text,uuid,text,text,jsonb,jsonb,text,text,jsonb) from public,anon;
revoke all on function public.layer4_publication_state(text,uuid,text) from public,anon;
grant execute on function public.layer4_course_scalar_resolve(uuid,text,jsonb,text) to authenticated,service_role;
grant execute on function public.layer4_effective_entity(text,uuid) to authenticated,service_role;
grant execute on function public.layer4_override_apply(text,uuid,text,jsonb,text,text,uuid[],jsonb) to authenticated,service_role;
grant execute on function public.layer4_override_history(text,uuid,text) to authenticated,service_role;
grant execute on function public.layer4_override_revert(text,uuid,text,text,text) to authenticated,service_role;
grant execute on function public.layer4_publication_decide(text,uuid,text,text,jsonb,jsonb,text,text,jsonb) to authenticated,service_role;
grant execute on function public.layer4_publication_state(text,uuid,text) to authenticated,service_role;
