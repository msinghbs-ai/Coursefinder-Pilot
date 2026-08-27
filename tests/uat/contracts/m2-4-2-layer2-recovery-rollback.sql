-- M2.4.2 rollback-only deployed database recovery contract.
-- Run against Pilot with service/postgres privileges inside a transaction.
-- It must leave no retained test batch/history because the transaction rolls back.

begin;

do $$
declare
  v_actor uuid:=public.layer2_automation_actor();
  v_profile uuid:='c7976665-14f3-40ac-834b-a8ee1c8afc32';
  v_course uuid:='097e7a26-76a4-4b83-9b30-9c3d741e7c57';
  v_url text:='https://study.uq.edu.au/study-options/programs/bachelor-advanced-business-honours-2139';
  v_batch uuid;
  v_batch2 uuid;
  v_status text;
  v_item_status text;
  v_failure text;
begin
  v_batch:=public.layer2_run_batch_create(
    v_profile,'manual',v_actor,
    jsonb_build_array(jsonb_build_object('entity_type','course','entity_id',v_course,'source_url',v_url))
  );
  update pipeline.layer2_run_batches
  set status='running',started_at=now(),heartbeat_at=now(),updated_at=now()
  where id=v_batch;
  update pipeline.layer2_run_items
  set status='acquiring',updated_at=now()
  where batch_id=v_batch;

  perform public.layer2_run_batch_cancel(v_batch,'uat_cancel_during_wave');
  perform public.layer2_run_batch_reconcile(v_batch);

  select status into v_status from pipeline.layer2_run_batches where id=v_batch;
  select status into v_item_status from pipeline.layer2_run_items where batch_id=v_batch limit 1;
  if v_status<>'cancelled' or v_item_status<>'cancelled' then
    raise exception 'cancel/reconcile contract failed: batch %, item %',v_status,v_item_status;
  end if;

  v_batch2:=public.layer2_run_batch_create(
    v_profile,'resume',v_actor,
    jsonb_build_array(jsonb_build_object('entity_type','course','entity_id',v_course,'source_url',v_url))
  );
  update pipeline.layer2_run_batches
  set status='running',started_at=now()-interval '2 hours',
      heartbeat_at=now()-interval '2 hours',updated_at=now()-interval '2 hours'
  where id=v_batch2;
  update pipeline.layer2_run_items
  set status='acquiring',updated_at=now()-interval '2 hours'
  where batch_id=v_batch2;

  perform public.layer2_run_batch_recover_stuck(v_batch2);

  select status into v_status from pipeline.layer2_run_batches where id=v_batch2;
  select status,failure_class into v_item_status,v_failure
  from pipeline.layer2_run_items where batch_id=v_batch2 limit 1;
  if v_status<>'queued' or v_item_status<>'queued' or v_failure<>'stale_recovery' then
    raise exception 'stale recovery contract failed: batch %, item %, failure %',v_status,v_item_status,v_failure;
  end if;
end $$;

select 'PASS' result;
rollback;
