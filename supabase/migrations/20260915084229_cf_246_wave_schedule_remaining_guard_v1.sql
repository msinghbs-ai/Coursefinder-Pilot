-- CF-CHG-20260915-246 — enforce bounded one-wave semantics when schedule_remaining=false.
-- Corrects a demonstrated runtime defect where manual continuation dispatched another wave.

create or replace function security.layer2_wave_dispatch_request(p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','security','pipeline','public'
as $$
declare
  v_req pipeline.layer2_scope_wave_requests%rowtype;
  v_remaining integer:=0;
  v_active integer:=0;
  v_dispatched integer:=0;
  v_batch uuid;
  r record;
begin
  select * into v_req from pipeline.layer2_scope_wave_requests where id=p_request_id for update;
  if not found then raise exception 'wave request not found' using errcode='22023'; end if;

  update pipeline.layer2_scope_wave_items wi
  set status=case when b.status in('completed','completed_with_fallout','partial') then 'completed' else 'failed' end,
      updated_at=now()
  from pipeline.layer2_run_batches b
  where wi.request_id=p_request_id and wi.batch_id=b.id and wi.status='dispatched'
    and b.status not in('queued','running');

  select count(*) into v_active
  from pipeline.layer2_scope_wave_items wi
  join pipeline.layer2_run_batches b on b.id=wi.batch_id
  where wi.request_id=p_request_id and wi.status='dispatched' and b.status in('queued','running','partial');
  if v_active>0 then
    return jsonb_build_object('ok',true,'status','active_wave_in_progress','request_id',p_request_id,'active_items',v_active);
  end if;

  if not coalesce(v_req.schedule_remaining,false)
     and exists(select 1 from pipeline.layer2_scope_wave_items where request_id=p_request_id and batch_id is not null) then
    select count(*) into v_remaining
    from pipeline.layer2_scope_wave_items
    where request_id=p_request_id and status='pending';

    update pipeline.layer2_scope_wave_requests q
    set dispatched_items=(select count(*) from pipeline.layer2_scope_wave_items where request_id=p_request_id and batch_id is not null),
        completed_items=(select count(*) from pipeline.layer2_scope_wave_items where request_id=p_request_id and status='completed'),
        failed_items=(select count(*) from pipeline.layer2_scope_wave_items where request_id=p_request_id and status='failed'),
        next_wave_not_before=null,
        status='completed',
        metadata=coalesce(q.metadata,'{}'::jsonb)||jsonb_build_object('single_wave_limit_enforced',true,'remaining_unprocessed',v_remaining),
        updated_at=now()
    where q.id=p_request_id;

    return jsonb_build_object(
      'ok',true,'status','bounded_wave_complete','request_id',p_request_id,
      'dispatched_now',0,'remaining',v_remaining,'schedule_remaining',false,
      'accepted_wave_size',v_req.accepted_wave_size,'route_mode',v_req.route_mode
    );
  end if;

  for r in
    with selected as(
      select wi.* from pipeline.layer2_scope_wave_items wi
      where wi.request_id=p_request_id and wi.status='pending'
      order by wi.ordinal
      limit v_req.accepted_wave_size
    )
    select profile_id,
           jsonb_agg(jsonb_build_object(
             'entity_type','course','entity_id',course_id,'source_url',source_url,
             'provider_id',selected_provider_id
           ) order by ordinal) items,
           array_agg(id order by ordinal) item_ids
    from selected
    group by profile_id
  loop
    if exists(select 1 from pipeline.layer2_run_batches b where b.profile_id=r.profile_id and b.status in('queued','running')) then
      continue;
    end if;
    v_batch:=public.layer2_run_batch_create(r.profile_id,'schedule',v_req.requested_by,r.items);
    perform public.layer2_run_batch_dispatch(v_batch);
    update pipeline.layer2_scope_wave_items
    set status='dispatched',batch_id=v_batch,updated_at=now()
    where id=any(r.item_ids);
    v_dispatched:=v_dispatched+coalesce(array_length(r.item_ids,1),0);
  end loop;

  select count(*) into v_remaining from pipeline.layer2_scope_wave_items where request_id=p_request_id and status='pending';
  update pipeline.layer2_scope_wave_requests q
  set dispatched_items=(select count(*) from pipeline.layer2_scope_wave_items where request_id=p_request_id and status in('dispatched','completed','failed')),
      completed_items=(select count(*) from pipeline.layer2_scope_wave_items where request_id=p_request_id and status='completed'),
      failed_items=(select count(*) from pipeline.layer2_scope_wave_items where request_id=p_request_id and status='failed'),
      last_wave_at=case when v_dispatched>0 then now() else q.last_wave_at end,
      next_wave_not_before=case when v_remaining>0 and q.schedule_remaining then now()+interval '15 minutes' else null end,
      status=case
        when v_remaining=0 and not exists(select 1 from pipeline.layer2_scope_wave_items wi join pipeline.layer2_run_batches b on b.id=wi.batch_id where wi.request_id=p_request_id and wi.status='dispatched' and b.status in('queued','running','partial')) then 'completed'
        when v_remaining>0 and q.schedule_remaining then 'scheduled'
        when v_remaining>0 then 'wave1_dispatched'
        else 'running' end,
      updated_at=now()
  where q.id=p_request_id;

  return jsonb_build_object(
    'ok',true,'request_id',p_request_id,'dispatched_now',v_dispatched,'remaining',v_remaining,
    'schedule_remaining',v_req.schedule_remaining,'accepted_wave_size',v_req.accepted_wave_size,
    'route_mode',v_req.route_mode
  );
end $$;

revoke all on function security.layer2_wave_dispatch_request(uuid) from public,anon,authenticated;
grant execute on function security.layer2_wave_dispatch_request(uuid) to service_role;
