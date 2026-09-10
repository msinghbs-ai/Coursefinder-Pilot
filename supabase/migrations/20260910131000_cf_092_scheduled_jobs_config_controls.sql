-- CF-CHG-20260910-092
-- M2.4.5 H4 additive reopening: bounded schedule editing and on-demand queueing.
-- Preserves the CF-209 prohibition on generic retry/replay/reset.

create or replace function public.scheduler_policy_control(
  p_layer smallint,
  p_country_code text,
  p_target text,
  p_freshness_class text,
  p_action text,
  p_cadence_days integer default null,
  p_next_due_at timestamptz default null,
  p_enabled boolean default null,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, security, pipeline, auth
as $$
declare
  v_actor uuid := auth.uid();
  v_policy pipeline.refresh_policies%rowtype;
  v_target_kind text;
  v_target_id uuid;
  v_target_entity_type text;
  v_count integer;
  v_request_id uuid;
  v_existing_request_id uuid;
begin
  if v_actor is null or security.current_role_rank() < 4 then
    raise exception 'pipeline operator role required' using errcode='42501';
  end if;
  if p_action not in ('edit_schedule','queue_now') then
    raise exception 'unsupported scheduler action';
  end if;
  if length(trim(coalesce(p_reason,''))) < 5 then
    raise exception 'governance reason required';
  end if;
  if p_layer not between 1 and 3 then
    raise exception 'on-demand scheduler controls apply to Layer 1, Layer 2 or Layer 3';
  end if;
  if p_target is null or position(':' in p_target)=0 then
    raise exception 'bounded policy target required';
  end if;

  v_target_kind := split_part(p_target,':',1);
  begin
    v_target_id := split_part(p_target,':',2)::uuid;
  exception when others then
    raise exception 'invalid bounded policy target';
  end;
  if v_target_kind not in ('source','profile') then
    v_target_entity_type := v_target_kind;
    v_target_kind := 'entity';
  end if;

  select count(*) into v_count
  from pipeline.refresh_policies p
  where p.layer=p_layer
    and p.country_code is not distinct from upper(nullif(p_country_code,''))
    and p.freshness_class=p_freshness_class
    and (
      (v_target_kind='source' and p.source_id=v_target_id and p.source_profile_id is null and p.entity_id is null)
      or (v_target_kind='profile' and p.source_profile_id=v_target_id and p.source_id is null and p.entity_id is null)
      or (v_target_kind='entity' and p.entity_id=v_target_id and p.entity_type=v_target_entity_type)
    );
  if v_count <> 1 then
    raise exception 'scheduler policy target is ambiguous or missing';
  end if;

  select * into v_policy
  from pipeline.refresh_policies p
  where p.layer=p_layer
    and p.country_code is not distinct from upper(nullif(p_country_code,''))
    and p.freshness_class=p_freshness_class
    and (
      (v_target_kind='source' and p.source_id=v_target_id and p.source_profile_id is null and p.entity_id is null)
      or (v_target_kind='profile' and p.source_profile_id=v_target_id and p.source_id is null and p.entity_id is null)
      or (v_target_kind='entity' and p.entity_id=v_target_id and p.entity_type=v_target_entity_type)
    )
  for update;

  if p_action='edit_schedule' then
    if p_cadence_days is not null and (p_cadence_days < 1 or p_cadence_days > 3650) then
      raise exception 'cadence days must be between 1 and 3650';
    end if;
    update pipeline.refresh_policies
    set cadence_interval = case when p_cadence_days is null then cadence_interval else make_interval(days=>p_cadence_days) end,
        next_due_at = coalesce(p_next_due_at,next_due_at),
        enabled = coalesce(p_enabled,enabled),
        change_control_ref = 'CF-CHG-20260910-092',
        updated_at = now()
    where id=v_policy.id
    returning * into v_policy;

    return jsonb_build_object(
      'ok',true,'action','edit_schedule','policy_id',v_policy.id,'layer',v_policy.layer,
      'next_due_at',v_policy.next_due_at,'enabled',v_policy.enabled,
      'cadence_interval',v_policy.cadence_interval::text,'queued',false
    );
  end if;

  select r.id into v_existing_request_id
  from pipeline.refresh_requests r
  where r.requested_layer=v_policy.layer
    and r.status in ('queued','running')
    and r.source_id is not distinct from v_policy.source_id
    and r.source_profile_id is not distinct from v_policy.source_profile_id
    and r.entity_id is not distinct from v_policy.entity_id
  order by r.created_at desc
  limit 1;

  if v_existing_request_id is not null then
    return jsonb_build_object(
      'ok',true,'action','queue_now','policy_id',v_policy.id,
      'request_id',v_existing_request_id,'queued',false,'state','already_active'
    );
  end if;

  insert into pipeline.refresh_requests(
    requested_layer,country_code,source_id,source_profile_id,entity_type,entity_id,
    reason,trigger_type,requested_by,change_control_ref
  ) values (
    v_policy.layer,v_policy.country_code,v_policy.source_id,v_policy.source_profile_id,
    v_policy.entity_type,v_policy.entity_id,trim(p_reason),'manual_policy',v_actor,'CF-CHG-20260910-092'
  ) returning id into v_request_id;

  return jsonb_build_object(
    'ok',true,'action','queue_now','policy_id',v_policy.id,
    'request_id',v_request_id,'queued',true,'state','queued'
  );
end $$;

revoke all on function public.scheduler_policy_control(smallint,text,text,text,text,integer,timestamptz,boolean,text)
from public, anon;
grant execute on function public.scheduler_policy_control(smallint,text,text,text,text,integer,timestamptz,boolean,text)
to authenticated, service_role;

comment on function public.scheduler_policy_control(smallint,text,text,text,text,integer,timestamptz,boolean,text)
is 'CF-092 rank-gated bounded scheduler edit/on-demand queue control. No generic job replay/reset.';
