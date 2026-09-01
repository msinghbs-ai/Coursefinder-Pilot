-- CF-CHG-20260830-048
-- M2.4.4 A26: recover stale acquiring items after an Edge invocation timeout.
-- Prefer attaching an already-succeeded matching acquisition Job; only requeue
-- when no reusable successful acquisition exists.

create or replace function public.layer2_run_batch_recover_stale(
  p_batch_id uuid,
  p_stale_after_seconds integer default 120
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','pipeline'
as $$
declare
  r record;
  v_job uuid;
  v_recovered integer:=0;
  v_requeued integer:=0;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  for r in
    select i.id,i.source_url,i.selected_provider_id,i.last_attempt_at
    from pipeline.layer2_run_items i
    where i.batch_id=p_batch_id
      and i.status='acquiring'
      and i.updated_at < now() - make_interval(secs=>greatest(30,coalesce(p_stale_after_seconds,120)))
    for update
  loop
    select j.id into v_job
    from pipeline.jobs j
    where j.status='succeeded'
      and j.created_at >= coalesce(r.last_attempt_at,now()-interval '10 minutes') - interval '5 seconds'
      and j.payload->>'target_url'=r.source_url
      and nullif(j.result->>'provider_id','')::uuid is not distinct from r.selected_provider_id
      and nullif(j.result->>'attempt_id','') is not null
      and nullif(j.result->>'evidence_id','') is not null
    order by j.completed_at desc nulls last,j.created_at desc
    limit 1;

    if v_job is not null then
      update pipeline.layer2_run_items
      set status='extracting',
          job_id=v_job,
          evidence_count=greatest(evidence_count,1),
          blocker=null,
          updated_at=now()
      where id=r.id;
      v_recovered:=v_recovered+1;
    else
      update pipeline.layer2_run_items
      set status='queued',
          blocker='requeued_after_stale_acquisition',
          completed_at=null,
          updated_at=now()
      where id=r.id;
      v_requeued:=v_requeued+1;
    end if;
  end loop;

  if v_recovered+v_requeued>0 then
    update pipeline.layer2_run_batches
    set heartbeat_at=now(),updated_at=now()
    where id=p_batch_id and status in('queued','running');
  end if;

  return jsonb_build_object(
    'batch_id',p_batch_id,
    'recovered_acquisitions',v_recovered,
    'requeued_items',v_requeued
  );
end $$;

revoke all on function public.layer2_run_batch_recover_stale(uuid,integer) from public,anon,authenticated;
grant execute on function public.layer2_run_batch_recover_stale(uuid,integer) to service_role;
