-- M2.5 — reconcile accepted Pilot qualification into environment gates and add reversible Layer 4 blocking ledger.
-- CF-CHG-20260901-051

begin;

-- Reconcile only evidence-backed accepted Pilot states. No Production rows are created.
insert into pipeline.environment_source_gates(
  environment,source_id,capability,lifecycle_state,enabled,uat_ref,approval_evidence,reason,change_control_ref
)
select 'pilot',o.source_id,c.capability,'pilot_uat_pass',true,'33468512515',
       jsonb_build_object(
         'verification_status',o.verification_status,
         'variance_decision',o.variance_decision,
         'last_verified_at',o.last_verified_at
       ),
       'Reconciled from accepted M2.4.4 Layer 1 Pilot baseline; Production remains separately gated.',
       'CF-CHG-20260901-051'
from pipeline.layer1_source_operations o
cross join lateral (values('provider_ingestion'),('course_ingestion')) c(capability)
where o.active and not o.paused
  and o.verification_status='passed'
  and o.variance_decision='pass'
on conflict(environment,source_id,capability) do update set
  lifecycle_state='pilot_uat_pass',
  enabled=true,
  uat_ref=excluded.uat_ref,
  approval_evidence=excluded.approval_evidence,
  reason=excluded.reason,
  updated_at=now();

update pipeline.layer2_provider_environment_gates g
set qualification_state='pilot_qualified',
    enabled=true,
    uat_ref='33468512515',
    qualification_evidence=jsonb_build_object(
      'basis','accepted_M2.4.4_acquisition_route',
      'provider_key',p.provider_key,
      'successful_attempts',x.successful_attempts,
      'last_attempt_at',x.last_attempt_at
    ),
    reason='Reconciled only for acquisition providers with substantial successful Pilot evidence in the accepted M2.4.4 route.',
    updated_at=now()
from pipeline.layer2_acquisition_providers p
cross join lateral (
  select count(*) filter(where a.status in ('completed','success','succeeded')) successful_attempts,
         max(a.created_at) last_attempt_at
  from pipeline.layer2_provider_attempts a
  where a.acquisition_provider_id=p.id
) x
where g.acquisition_provider_id=p.id
  and g.environment='pilot'
  and p.provider_key in ('direct-http','firecrawl')
  and x.successful_attempts>0;

update pipeline.layer3_profile_environment_gates g
set qualification_state='pilot_qualified',
    enabled=true,
    uat_ref=coalesce(p.uat_ref,'33468512515'),
    benchmark_ref=coalesce(p.quality_benchmark->>'run_id',p.quality_benchmark->>'benchmark_run_id'),
    qualification_evidence=jsonb_build_object(
      'basis','existing_benchmark_pass',
      'model_identifier',p.model_identifier,
      'allowed_task_classes',p.allowed_task_classes,
      'quality_benchmark',p.quality_benchmark
    ),
    reason='Reconciled from enabled, unpaused, benchmark-PASS Pilot profile; Production remains separately gated.',
    updated_at=now()
from pipeline.layer3_model_profiles p
where g.profile_id=p.id
  and g.environment='pilot'
  and p.enabled and not p.paused
  and coalesce((p.quality_benchmark->>'pass')::boolean,false);

create table if not exists pipeline.layer4_block_decisions (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('provider','course','campus','scholarship','provider_contact')),
  entity_id uuid not null,
  block_scope text not null check (block_scope in (
    'operational','publication','search','data_quality_quarantine'
  )),
  event_type text not null check (event_type in ('block','unblock')),
  reason_code text not null,
  comment text,
  actor_id uuid not null,
  actor_email text,
  expires_at timestamptz,
  review_at timestamptz,
  supersedes_decision_id uuid references pipeline.layer4_block_decisions(id) on delete restrict,
  approval_context jsonb not null default '{}'::jsonb,
  change_control_ref text not null default 'CF-CHG-20260901-051',
  created_at timestamptz not null default now(),
  check (length(trim(reason_code))>=3),
  check (expires_at is null or expires_at>created_at),
  check (review_at is null or review_at>created_at)
);

create index if not exists layer4_block_decisions_entity_idx
  on pipeline.layer4_block_decisions(entity_type,entity_id,block_scope,created_at desc,id desc);

comment on table pipeline.layer4_block_decisions is
'Append-only reversible governance decisions. Blocking is state, never deletion; each scope is independent.';

create or replace function security.layer4_block_state_read(
  p_entity_type text,p_entity_id uuid,p_block_scope text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','security','pipeline','auth'
as $$
declare v_rank int;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
  if not security.layer4_entity_exists(p_entity_type,p_entity_id) then
    raise exception 'entity not found' using errcode='22023';
  end if;
  if p_block_scope is not null and p_block_scope not in ('operational','publication','search','data_quality_quarantine') then
    raise exception 'invalid block scope' using errcode='22023';
  end if;

  return coalesce((
    with latest as (
      select distinct on(block_scope)
        id,block_scope,event_type,reason_code,comment,actor_id,actor_email,
        expires_at,review_at,created_at
      from pipeline.layer4_block_decisions
      where entity_type=p_entity_type and entity_id=p_entity_id
        and (p_block_scope is null or block_scope=p_block_scope)
      order by block_scope,created_at desc,id desc
    )
    select jsonb_build_object(
      'entity_type',p_entity_type,'entity_id',p_entity_id,
      'states',coalesce(jsonb_agg(jsonb_build_object(
        'scope',block_scope,
        'blocked',event_type='block' and (expires_at is null or expires_at>now()),
        'event_type',event_type,'reason_code',reason_code,'comment',comment,
        'actor_id',actor_id,'actor_email',actor_email,
        'expires_at',expires_at,'review_at',review_at,'created_at',created_at
      ) order by block_scope),'[]'::jsonb)
    ) from latest
  ),jsonb_build_object('entity_type',p_entity_type,'entity_id',p_entity_id,'states','[]'::jsonb));
end $$;

revoke all on function security.layer4_block_state_read(text,uuid,text) from public,anon;
grant execute on function security.layer4_block_state_read(text,uuid,text) to authenticated,service_role;

create or replace function security.layer4_entity_blocked(
  p_entity_type text,p_entity_id uuid,p_block_scope text
)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog','pipeline'
as $$
  select coalesce((
    select d.event_type='block' and (d.expires_at is null or d.expires_at>now())
    from pipeline.layer4_block_decisions d
    where d.entity_type=p_entity_type and d.entity_id=p_entity_id and d.block_scope=p_block_scope
    order by d.created_at desc,d.id desc
    limit 1
  ),false)
$$;

revoke all on function security.layer4_entity_blocked(text,uuid,text) from public,anon,authenticated;
grant execute on function security.layer4_entity_blocked(text,uuid,text) to service_role;

create or replace function l4_api.block_decide(
  p_entity_type text,p_entity_id uuid,p_block_scope text,p_event_type text,
  p_reason_code text,p_comment text default null,p_expires_at timestamptz default null,
  p_review_at timestamptz default null,p_approval_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','l4_api','security','pipeline','auth'
as $$
declare v_actor uuid:=auth.uid(); v_rank int; v_prev uuid; v_id uuid; v_email text;
begin
  if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  if v_rank<5 then raise exception 'PIM Admin role required for block/unblock' using errcode='42501'; end if;
  if not security.layer4_entity_exists(p_entity_type,p_entity_id) then raise exception 'entity not found' using errcode='22023'; end if;
  if p_block_scope not in ('operational','publication','search','data_quality_quarantine') then raise exception 'invalid block scope' using errcode='22023'; end if;
  if p_event_type not in ('block','unblock') then raise exception 'invalid block event' using errcode='22023'; end if;
  if length(trim(coalesce(p_reason_code,'')))<3 then raise exception 'reason code required' using errcode='22023'; end if;
  if p_expires_at is not null and p_expires_at<=now() then raise exception 'expiry must be in the future' using errcode='22023'; end if;
  if p_review_at is not null and p_review_at<=now() then raise exception 'review must be in the future' using errcode='22023'; end if;

  select id into v_prev
  from pipeline.layer4_block_decisions
  where entity_type=p_entity_type and entity_id=p_entity_id and block_scope=p_block_scope
  order by created_at desc,id desc limit 1;

  select email into v_email from auth.users where id=v_actor;

  insert into pipeline.layer4_block_decisions(
    entity_type,entity_id,block_scope,event_type,reason_code,comment,
    actor_id,actor_email,expires_at,review_at,supersedes_decision_id,approval_context
  ) values (
    p_entity_type,p_entity_id,p_block_scope,p_event_type,trim(p_reason_code),
    nullif(trim(coalesce(p_comment,'')),''),
    v_actor,v_email,p_expires_at,p_review_at,v_prev,coalesce(p_approval_context,'{}')
  ) returning id into v_id;

  return jsonb_build_object(
    'ok',true,'decision_id',v_id,'event_type',p_event_type,'scope',p_block_scope,
    'blocked',p_event_type='block',
    'deletion_performed',false,
    'canonical_changed',false,
    'consumer_cutover_authorised',false
  );
end $$;

revoke all on function l4_api.block_decide(text,uuid,text,text,text,text,timestamptz,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function l4_api.block_decide(text,uuid,text,text,text,text,timestamptz,timestamptz,jsonb) to authenticated,service_role;

create or replace function public.layer4_block_decide(
  p_entity_type text,p_entity_id uuid,p_block_scope text,p_event_type text,
  p_reason_code text,p_comment text default null,p_expires_at timestamptz default null,
  p_review_at timestamptz default null,p_approval_context jsonb default '{}'::jsonb
)
returns jsonb
language sql
security invoker
set search_path to 'pg_catalog','public','l4_api'
as $$
  select l4_api.block_decide(
    p_entity_type,p_entity_id,p_block_scope,p_event_type,p_reason_code,p_comment,
    p_expires_at,p_review_at,p_approval_context
  )
$$;

create or replace function public.layer4_block_state(
  p_entity_type text,p_entity_id uuid,p_block_scope text default null
)
returns jsonb
language sql
stable
security invoker
set search_path to 'pg_catalog','public','security'
as $$ select security.layer4_block_state_read(p_entity_type,p_entity_id,p_block_scope) $$;

revoke all on function public.layer4_block_decide(text,uuid,text,text,text,text,timestamptz,timestamptz,jsonb) from public,anon;
revoke all on function public.layer4_block_state(text,uuid,text) from public,anon;
grant execute on function public.layer4_block_decide(text,uuid,text,text,text,text,timestamptz,timestamptz,jsonb) to authenticated,service_role;
grant execute on function public.layer4_block_state(text,uuid,text) to authenticated,service_role;

commit;
