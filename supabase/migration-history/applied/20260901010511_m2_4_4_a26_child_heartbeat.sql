-- CF-CHG-20260830-048
-- M2.4.4 A26: child item progress refreshes the owning batch heartbeat so
-- long Firecrawl calls do not appear stale between batch reconciliations.

create or replace function public.layer2_run_item_mark(
  p_item_id uuid,
  p_status text,
  p_job_id uuid default null,
  p_evidence_count integer default null,
  p_vendor_units numeric default null,
  p_vendor_cost_usd numeric default null,
  p_fields_targeted integer default null,
  p_fields_resolved integer default null,
  p_blocker text default null
) returns boolean
language plpgsql
security definer
set search_path='pg_catalog','pipeline'
as $$
declare v_batch uuid;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  if p_status not in ('queued','discovering','acquiring','extracting','resolved_l2','layer3_required','blocked','cancelled') then
    raise exception 'invalid item status';
  end if;

  update pipeline.layer2_run_items
  set status=p_status,
      job_id=coalesce(p_job_id,job_id),
      evidence_count=coalesce(p_evidence_count,evidence_count),
      vendor_units=coalesce(p_vendor_units,vendor_units),
      vendor_cost_usd=coalesce(p_vendor_cost_usd,vendor_cost_usd),
      fields_targeted=coalesce(p_fields_targeted,fields_targeted),
      fields_resolved=coalesce(p_fields_resolved,fields_resolved),
      blocker=p_blocker,
      started_at=case when p_status in ('acquiring','extracting') then coalesce(started_at,now()) else started_at end,
      retry_count=case when p_status='acquiring' and last_attempt_at is not null then retry_count+1 else retry_count end,
      last_attempt_at=case when p_status='acquiring' then now() else last_attempt_at end,
      completed_at=case when p_status in ('resolved_l2','layer3_required','blocked','cancelled') then now() else null end,
      updated_at=now()
  where id=p_item_id
  returning batch_id into v_batch;

  if v_batch is not null then
    update pipeline.layer2_run_batches
    set heartbeat_at=now(),updated_at=now()
    where id=v_batch and status in('queued','running');
  end if;

  return v_batch is not null;
end $$;

revoke all on function public.layer2_run_item_mark(uuid,text,uuid,integer,numeric,numeric,integer,integer,text) from public,anon,authenticated;
grant execute on function public.layer2_run_item_mark(uuid,text,uuid,integer,numeric,numeric,integer,integer,text) to service_role;
