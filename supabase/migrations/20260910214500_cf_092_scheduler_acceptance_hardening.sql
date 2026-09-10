begin;

-- CF-CHG-20260910-092
-- Acceptance hardening: optimistic concurrency for schedule edits, complete paged policy reads,
-- and explicit refusal to manufacture generic Layer 3 execution context.

drop function if exists public.scheduler_policy_edit_v1(uuid,integer,timestamptz,boolean,text);
drop function if exists security.scheduler_policy_edit_v1_browser_bridge(uuid,integer,timestamptz,boolean,text);

create or replace function security.scheduler_policy_edit_v1_browser_bridge(
  p_policy_id uuid,
  p_expected_updated_at timestamptz,
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
  if p_expected_updated_at is null then
    raise exception 'expected policy version required' using errcode='22023';
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
  if v_policy.updated_at is distinct from p_expected_updated_at then
    raise exception 'schedule changed since it was opened; refresh and try again' using errcode='40001';
  end if;
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
    'updated_at',v_policy.updated_at,
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

create or replace function public.scheduler_policy_edit_v1(
  p_policy_id uuid,p_expected_updated_at timestamptz,p_cadence_days integer,p_next_due_at timestamptz,p_enabled boolean,p_reason text
) returns jsonb
language sql
security invoker
set search_path=''
as $function$
  select security.scheduler_policy_edit_v1_browser_bridge(p_policy_id,p_expected_updated_at,p_cadence_days,p_next_due_at,p_enabled,p_reason)
$function$;

revoke all on function security.scheduler_policy_edit_v1_browser_bridge(uuid,timestamptz,integer,timestamptz,boolean,text) from public,anon;
grant execute on function security.scheduler_policy_edit_v1_browser_bridge(uuid,timestamptz,integer,timestamptz,boolean,text) to authenticated,service_role;
revoke all on function public.scheduler_policy_edit_v1(uuid,timestamptz,integer,timestamptz,boolean,text) from public,anon;
grant execute on function public.scheduler_policy_edit_v1(uuid,timestamptz,integer,timestamptz,boolean,text) to authenticated,service_role;

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
  if v_policy.layer not in (1,2) then
    raise exception 'Layer 3 on-demand execution requires Evidence/profile-specific control from the Layer 3 workspace' using errcode='22023';
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

  return jsonb_build_object('ok',true,'policy_id',v_policy.id,'request_id',v_request_id,'existing_active',v_existing,'action','run_on_demand');
end
$function$;

create or replace function security.scheduler_policies_list_v1_browser_bridge(
  p_limit integer default 50,
  p_offset integer default 0
) returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_limit integer:=least(greatest(coalesce(p_limit,50),1),100);
  v_offset integer:=greatest(coalesce(p_offset,0),0);
begin
  if auth.uid() is null or security.current_role_rank() < 3 then
    raise exception 'curator role required' using errcode='42501';
  end if;
  return jsonb_build_object(
    'total',(select count(*) from pipeline.refresh_policies p where p.layer between 1 and 3 and (p.source_id is not null or p.source_profile_id is not null or p.entity_id is not null)),
    'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.next_due_at nulls last,x.id) from (
      select p.id,p.country_code,p.layer,p.source_id,p.source_profile_id,p.entity_type,p.entity_id,
             p.freshness_class,p.cadence_interval,p.next_due_at,p.hash_sensitive,p.important_date_sensitive,
             p.enabled,p.change_control_ref,p.updated_at
      from pipeline.refresh_policies p
      where p.layer between 1 and 3
        and (p.source_id is not null or p.source_profile_id is not null or p.entity_id is not null)
      order by p.next_due_at nulls last,p.id
      limit v_limit offset v_offset
    ) x),'[]'::jsonb)
  );
end
$function$;

create or replace function public.scheduler_policies_list_v1(p_limit integer default 50,p_offset integer default 0)
returns jsonb
language sql
stable
security invoker
set search_path=''
as $function$
  select security.scheduler_policies_list_v1_browser_bridge(p_limit,p_offset)
$function$;

revoke all on function security.scheduler_policies_list_v1_browser_bridge(integer,integer) from public,anon;
grant execute on function security.scheduler_policies_list_v1_browser_bridge(integer,integer) to authenticated,service_role;
revoke all on function public.scheduler_policies_list_v1(integer,integer) from public,anon;
grant execute on function public.scheduler_policies_list_v1(integer,integer) to authenticated,service_role;

commit;
