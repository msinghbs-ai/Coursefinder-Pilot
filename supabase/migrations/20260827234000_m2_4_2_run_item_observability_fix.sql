-- M2.4.2 — correct run-item retry semantics and add service-only performance metrics marker.
begin;

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
set search_path to 'pg_catalog','pipeline'
as $$
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_status not in ('queued','discovering','acquiring','extracting','resolved_l2','layer3_required','blocked','cancelled') then raise exception 'invalid item status'; end if;
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
  where id=p_item_id;
  return found;
end $$;

revoke all on function public.layer2_run_item_mark(uuid,text,uuid,integer,numeric,numeric,integer,integer,text) from public,anon,authenticated;
grant execute on function public.layer2_run_item_mark(uuid,text,uuid,integer,numeric,numeric,integer,integer,text) to service_role;

create or replace function public.layer2_run_item_metrics_mark(
  p_item_id uuid,
  p_response_ms integer default null,
  p_extraction_ms integer default null,
  p_evidence_bytes bigint default null,
  p_outcome_code text default null,
  p_failure_class text default null
) returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline'
as $$
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  update pipeline.layer2_run_items
  set response_ms=coalesce(p_response_ms,response_ms),
      extraction_ms=coalesce(p_extraction_ms,extraction_ms),
      evidence_bytes=coalesce(p_evidence_bytes,evidence_bytes),
      outcome_code=coalesce(p_outcome_code,outcome_code),
      failure_class=coalesce(p_failure_class,failure_class),
      updated_at=now()
  where id=p_item_id;
  return found;
end $$;

revoke all on function public.layer2_run_item_metrics_mark(uuid,integer,integer,bigint,text,text) from public,anon,authenticated;
grant execute on function public.layer2_run_item_metrics_mark(uuid,integer,integer,bigint,text,text) to service_role;

-- This active representative batch had no item-level requeue/resume attempts before this correction.
update pipeline.layer2_run_items
set retry_count=0, updated_at=now()
where batch_id='6abe8558-e1b9-4a6f-ba97-47481ba488bb'
  and retry_count=1;

commit;
