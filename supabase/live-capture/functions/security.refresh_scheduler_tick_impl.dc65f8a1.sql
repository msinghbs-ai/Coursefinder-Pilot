CREATE OR REPLACE FUNCTION security.refresh_scheduler_tick_impl(p_now timestamp with time zone DEFAULT now(), p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline'
AS $function$
declare v_policy_count int:=0; v_date_count int:=0; v_l3_count int:=0; v_expired_dates int:=0;
begin
  with due as (
    select p.*
    from pipeline.refresh_policies p
    where p.enabled
      and p.layer in (1,2,3)
      and p.freshness_class <> 'event-driven'
      and p.cadence_interval is not null
      and p.next_due_at is not null
      and p.next_due_at <= p_now
    order by p.next_due_at
    limit least(greatest(p_limit,1),500)
    for update skip locked
  ), ins as (
    insert into pipeline.refresh_requests(
      requested_layer,country_code,source_id,source_profile_id,entity_type,entity_id,
      reason,trigger_type,requested_by,change_control_ref
    )
    select d.layer,d.country_code,d.source_id,d.source_profile_id,d.entity_type,d.entity_id,
           'Governed '||d.freshness_class||' freshness policy due','freshness_expired',null,d.change_control_ref
    from due d
    where not exists (
      select 1 from pipeline.refresh_requests r
      where r.status in ('queued','running')
        and r.requested_layer=d.layer
        and r.source_id is not distinct from d.source_id
        and r.source_profile_id is not distinct from d.source_profile_id
        and r.entity_id is not distinct from d.entity_id
    )
    returning 1
  ), adv as (
    update pipeline.refresh_policies p
    set next_due_at = greatest(p.next_due_at,p_now) + p.cadence_interval, updated_at=p_now
    where p.id in (select id from due)
    returning 1
  )
  select count(*) into v_policy_count from ins;

  with target_dates as (
    select d.*,
      coalesce(d.starts_at, case when d.starts_on is null then null
        else d.starts_on::timestamp at time zone coalesce(nullif(d.timezone,''),'UTC') end) as operational_start,
      coalesce(d.ends_at, case when d.ends_on is null then null
        else (d.ends_on + 1)::timestamp at time zone coalesce(nullif(d.timezone,''),'UTC') end) as operational_end
    from pipeline.important_dates d
    where d.status='active'
      and d.refresh_layer is not null
      and (d.starts_at is not null or d.starts_on is not null)
      and (d.source_id is not null or d.source_profile_id is not null or d.entity_id is not null)
  ), due_dates as (
    select *
    from target_dates d
    where d.operational_start - d.warning_window <= p_now
      and (d.operational_end is null or d.operational_end >= p_now)
    order by d.operational_start
    limit least(greatest(p_limit,1),500)
  ), ins as (
    insert into pipeline.refresh_requests(
      requested_layer,country_code,source_id,source_profile_id,entity_type,entity_id,
      reason,trigger_type,important_date_id,requested_by,change_control_ref
    )
    select d.refresh_layer,d.country_code,d.source_id,d.source_profile_id,d.entity_type,d.entity_id,
           'Important Date warning window: '||d.title,'important_date',d.id,null,d.change_control_ref
    from due_dates d
    where not exists (
      select 1 from pipeline.refresh_requests r
      where r.important_date_id=d.id and r.status in ('queued','running','completed')
    )
    returning 1
  )
  select count(*) into v_date_count from ins;

  with expired as (
    select i.*
    from pipeline.layer3_interpretations i
    where i.status in ('validated','no_candidate')
      and i.interpretation_expires_at is not null
      and i.interpretation_expires_at <= p_now
    order by i.interpretation_expires_at
    limit least(greatest(p_limit,1),500)
  ), ins as (
    insert into pipeline.refresh_requests(
      requested_layer,entity_type,entity_id,evidence_id,layer3_profile_id,revalidation_ref,
      reason,trigger_type,requested_by,change_control_ref
    )
    select 3,i.entity_type,i.entity_id,i.evidence_id,i.profile_id,'EXPIRY:'||i.id::text,
           'Layer 3 interpretation freshness expired','freshness_expired',null,i.change_control_ref
    from expired i
    where not exists (
      select 1 from pipeline.refresh_requests r
      where r.requested_layer=3 and r.evidence_id=i.evidence_id and r.layer3_profile_id=i.profile_id
        and r.status in ('queued','running')
    )
    returning 1
  )
  select count(*) into v_l3_count from ins;

  update pipeline.important_dates
  set status='expired',updated_at=p_now
  where status='active' and expires_at is not null and expires_at<=p_now;
  get diagnostics v_expired_dates = row_count;

  return jsonb_build_object(
    'ok',true,'policy_requests_created',v_policy_count,'important_date_requests_created',v_date_count,
    'layer3_expiry_requests_created',v_l3_count,'important_dates_expired',v_expired_dates,'at',p_now
  );
end $function$
