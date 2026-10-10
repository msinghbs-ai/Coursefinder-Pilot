begin;

-- CF-CHG-20260910-092
-- Governed Scheduled Tasks mutations. Browser-visible wrappers remain SECURITY INVOKER;
-- the privileged hop is confined to the non-exposed security schema and independently
-- enforces authenticated Pipeline Operator rank, exact existing policy identity and bounded targets.

create table if not exists pipeline.refresh_policy_action_events (
  id uuid primary key default gen_random_uuid(),
  policy_id uuid not null references pipeline.refresh_policies(id) on delete restrict,
  action text not null check (action in ('edit_schedule','run_on_demand')),
  reason text not null check (length(trim(reason)) >= 5),
  actor_id uuid not null,
  change_control_ref text not null default 'CF-CHG-20260910-092',
  before_state jsonb not null default '{}'::jsonb,
  after_state jsonb not null default '{}'::jsonb,
  refresh_request_id uuid references pipeline.refresh_requests(id) on delete set null,
  outcome text not null default 'applied' check (outcome in ('applied','queued','existing_active')),
  created_at timestamptz not null default now()
);

alter table pipeline.refresh_policy_action_events enable row level security;
revoke all on pipeline.refresh_policy_action_events from public,anon,authenticated;
drop policy if exists refresh_policy_action_events_deny_authenticated on pipeline.refresh_policy_action_events;
create policy refresh_policy_action_events_deny_authenticated
  on pipeline.refresh_policy_action_events
  for all to authenticated
  using (false)
  with check (false);

create index if not exists refresh_policy_action_events_policy_created_idx
  on pipeline.refresh_policy_action_events(policy_id,created_at desc);
create index if not exists refresh_policy_action_events_request_idx
  on pipeline.refresh_policy_action_events(refresh_request_id)
  where refresh_request_id is not null;

create or replace function security.scheduler_policy_edit_v1_browser_bridge(
  p_policy_id uuid,
  p_cadence_days integer,
  p_next_due_at timestamptz,
  p_enabled boolean,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor uuid := auth.uid();
  v_policy pipeline.refresh_policies%rowtype;
  v_before jsonb;
begin
  if v_actor is null or security.current_role_rank() < 4 then
    raise exception 'pipeline operator role required' using errcode='42501';
  end if;
  if length(trim(coalesce(p_reason,''))) < 5 then
    raise exception 'governance reason required' using errcode='22023';
  end if;
  if p_cadence_days is null or p_cadence_days < 1 or p_cadence_days > 3650 then
    raise exception 'cadence days must be 1..3650' using errcode='22023';
  end if;
  if p_next_due_at is null then
    raise exception 'next run required' using errcode='22023';
  end if;

  select * into v_policy
  from pipeline.refresh_policies
  where id=p_policy_id
  for update;

  if not found then raise exception 'refresh policy not found' using errcode='22023'; end if;
  if v_policy.layer not in (1,2,3) then
    raise exception 'only Layer 1..3 schedules are editable here' using errcode='22023';
  end if;
  if v_policy.freshness_class='event-driven' then
    raise exception 'event-driven policy has no recurring schedule' using errcode='22023';
  end if;
  if v_policy.source_id is null and v_policy.source_profile_id is null and v_policy.entity_id is null then
    raise exception 'bounded target required' using errcode='22023';
  end if;

  v_before:=jsonb_build_object(
    'cadence_interval',v_policy.cadence_interval::text,
    'next_due_at',v_policy.next_due_at,
    'enabled',v_policy.enabled,
    'change_control_ref',v_policy.change_control_ref
  );

  update pipeline.refresh_policies
  set cadence_interval=make_interval(days=>p_cadence_days),
      next_due_at=p_next_due_at,
      enabled=p_enabled,
      change_control_ref='CF-CHG-20260910-092',
      updated_at=now()
  where id=v_policy.id;

  insert into pipeline.refresh_policy_action_events(
    policy_id,action,reason,actor_id,change_control_ref,before_state,after_state,outcome
  ) values (
    v_policy.id,'edit_schedule',trim(p_reason),v_actor,'CF-CHG-20260910-092',v_before,
    jsonb_build_object(
      'cadence_days',p_cadence_days,
      'next_due_at',p_next_due_at,
      'enabled',p_enabled,
      'change_control_ref','CF-CHG-20260910-092'
    ),'applied'
  );

  return jsonb_build_object('ok',true,'policy_id',v_policy.id,'action','edit_schedule');
end
$function$;

create or replace function security.scheduler_policy_run_now_v1_browser_bridge(
  p_policy_id uuid,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor uuid := auth.uid();
  v_policy pipeline.refresh_policies%rowtype;
  v_request_id uuid;
  v_existing boolean := false;
begin
  if v_actor is null or security.current_role_rank() < 4 then
    raise exception 'pipeline operator role required' using errcode='42501';
  end if;
  if length(trim(coalesce(p_reason,''))) < 5 then
    raise exception 'governance reason required' using errcode='22023';
  end if;

  select * into v_policy
  from pipeline.refresh_policies
  where id=p_policy_id
  for update;

  if not found then raise exception 'refresh policy not found' using errcode='22023'; end if;
  if not v_policy.enabled then
    raise exception 'enable this schedule before running it on demand' using errcode='22023';
  end if;
  if v_policy.layer not in (1,2,3) then
    raise exception 'only Layer 1..3 schedules can run on demand here' using errcode='22023';
  end if;
  if v_policy.source_id is null and v_policy.source_profile_id is null and v_policy.entity_id is null then
    raise exception 'bounded target required' using errcode='22023';
  end if;

  select r.id into v_request_id
  from pipeline.refresh_requests r
  where r.status in ('queued','running')
    and r.requested_layer=v_policy.layer
    and r.country_code is not distinct from v_policy.country_code
    and r.source_id is not distinct from v_policy.source_id
    and r.source_profile_id is not distinct from v_policy.source_profile_id
    and r.entity_type is not distinct from v_policy.entity_type
    and r.entity_id is not distinct from v_policy.entity_id
  order by r.created_at desc
  limit 1;

  if v_request_id is null then
    insert into pipeline.refresh_requests(
      requested_layer,country_code,source_id,source_profile_id,entity_type,entity_id,
      reason,trigger_type,status,requested_by,change_control_ref
    ) values (
      v_policy.layer,v_policy.country_code,v_policy.source_id,v_policy.source_profile_id,v_policy.entity_type,v_policy.entity_id,
      trim(p_reason),'manual_governed','queued',v_actor,'CF-CHG-20260910-092'
    ) returning id into v_request_id;
  else
    v_existing:=true;
  end if;

  insert into pipeline.refresh_policy_action_events(
    policy_id,action,reason,actor_id,change_control_ref,before_state,after_state,refresh_request_id,outcome
  ) values (
    v_policy.id,'run_on_demand',trim(p_reason),v_actor,'CF-CHG-20260910-092',
    jsonb_build_object('cadence_interval',v_policy.cadence_interval::text,'next_due_at',v_policy.next_due_at,'enabled',v_policy.enabled),
    jsonb_build_object('policy_unchanged',true,'request_id',v_request_id),v_request_id,
    case when v_existing then 'existing_active' else 'queued' end
  );

  return jsonb_build_object(
    'ok',true,'policy_id',v_policy.id,'request_id',v_request_id,
    'existing_active',v_existing,'action','run_on_demand'
  );
end
$function$;

revoke all on function security.scheduler_policy_edit_v1_browser_bridge(uuid,integer,timestamptz,boolean,text)
  from public,anon;
revoke all on function security.scheduler_policy_run_now_v1_browser_bridge(uuid,text)
  from public,anon;
grant execute on function security.scheduler_policy_edit_v1_browser_bridge(uuid,integer,timestamptz,boolean,text)
  to authenticated,service_role;
grant execute on function security.scheduler_policy_run_now_v1_browser_bridge(uuid,text)
  to authenticated,service_role;

create or replace function public.scheduler_policy_edit_v1(
  p_policy_id uuid,p_cadence_days integer,p_next_due_at timestamptz,p_enabled boolean,p_reason text
) returns jsonb
language sql
security invoker
set search_path=''
as $function$
  select security.scheduler_policy_edit_v1_browser_bridge(p_policy_id,p_cadence_days,p_next_due_at,p_enabled,p_reason)
$function$;

create or replace function public.scheduler_policy_run_now_v1(p_policy_id uuid,p_reason text)
returns jsonb
language sql
security invoker
set search_path=''
as $function$
  select security.scheduler_policy_run_now_v1_browser_bridge(p_policy_id,p_reason)
$function$;

revoke all on function public.scheduler_policy_edit_v1(uuid,integer,timestamptz,boolean,text)
  from public,anon;
revoke all on function public.scheduler_policy_run_now_v1(uuid,text)
  from public,anon;
grant execute on function public.scheduler_policy_edit_v1(uuid,integer,timestamptz,boolean,text)
  to authenticated,service_role;
grant execute on function public.scheduler_policy_run_now_v1(uuid,text)
  to authenticated,service_role;

commit;
