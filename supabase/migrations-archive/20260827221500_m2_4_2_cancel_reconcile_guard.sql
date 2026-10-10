-- M2.4.2 — preserve cancelled batches during late in-flight reconciliation.
begin;

create or replace function public.layer2_run_batch_reconcile(p_batch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline'
as $$
declare
  v_total int;
  v_processed int;
  v_resolved int;
  v_l3 int;
  v_blocked int;
  v_units numeric;
  v_cost numeric;
  v_status text;
  v_existing text;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  select status into v_existing
  from pipeline.layer2_run_batches
  where id=p_batch_id
  for update;

  if v_existing is null then
    raise exception 'batch not found' using errcode='22023';
  end if;

  select
    count(*),
    count(*) filter(where status not in ('queued','discovering','acquiring','extracting')),
    count(*) filter(where status='resolved_l2'),
    count(*) filter(where status='layer3_required'),
    count(*) filter(where status='blocked'),
    coalesce(sum(vendor_units),0),
    coalesce(sum(vendor_cost_usd),0)
  into v_total,v_processed,v_resolved,v_l3,v_blocked,v_units,v_cost
  from pipeline.layer2_run_items
  where batch_id=p_batch_id;

  if v_existing='cancelled' then
    v_status:='cancelled';
  else
    v_status:=case
      when v_total=0 then 'failed'
      when v_processed<v_total then 'running'
      when v_blocked=v_total then 'failed'
      when v_blocked>0 or v_l3>0 then 'partial'
      else 'completed'
    end;
  end if;

  update pipeline.layer2_run_batches
  set status=v_status,
      processed_count=v_processed,
      resolved_l2_count=v_resolved,
      escalated_l3_count=v_l3,
      blocked_count=v_blocked,
      vendor_units=v_units,
      vendor_cost_usd=v_cost,
      started_at=coalesce(started_at,case when v_status<>'queued' then now() end),
      completed_at=case
        when v_status='cancelled' then coalesce(completed_at,now())
        when v_processed=v_total then coalesce(completed_at,now())
        else null
      end,
      heartbeat_at=case when v_status='cancelled' then coalesce(heartbeat_at,now()) else heartbeat_at end,
      updated_at=now()
  where id=p_batch_id;

  return public.layer2_run_batch_summary(p_batch_id);
end $$;

revoke all on function public.layer2_run_batch_reconcile(uuid) from public,anon,authenticated;
grant execute on function public.layer2_run_batch_reconcile(uuid) to service_role;

commit;
