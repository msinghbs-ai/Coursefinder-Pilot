-- Decision 151: Layer 2 parent runs (scope-wave requests) that make no progress are closed, not left
-- "active" indefinitely. A request still planned/scheduled/running/wave1_dispatched whose request and
-- items have not changed for 3 days is set to 'cancelled' with the reason recorded; its pending items
-- become 'blocked' with the same reason so nothing picks them up later. History is kept. Daily.
create or replace function security.layer2_wave_request_close_stale_v1(p_apply boolean default false, p_idle interval default interval '3 days')
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline'
as $$
declare v_list jsonb; v_req int := 0; v_items int := 0; v_ids uuid[];
begin
  with idle as (
    select r.id, r.status, r.scope_type, r.country_code, r.created_at,
           greatest(r.updated_at, coalesce(r.last_wave_at,r.updated_at), coalesce((select max(i.updated_at) from pipeline.layer2_scope_wave_items i where i.request_id=r.id), r.updated_at)) last_activity,
           (select count(*) from pipeline.layer2_scope_wave_items i where i.request_id=r.id and i.status='pending') pending
    from pipeline.layer2_scope_wave_requests r
    where r.status in ('planned','scheduled','running','wave1_dispatched'))
  select jsonb_agg(jsonb_build_object('request_id',id,'status',status,'scope',scope_type||' '||country_code,'created',created_at,'last_activity',last_activity,'pending_items',pending)), array_agg(id)
    into v_list, v_ids from idle where last_activity < now() - p_idle;
  if p_apply and v_ids is not null then
    update pipeline.layer2_scope_wave_items set status='blocked', blocker='parent run closed: no progress for '||p_idle::text, updated_at=now()
     where request_id = any(v_ids) and status='pending';
    get diagnostics v_items = row_count;
    update pipeline.layer2_scope_wave_requests set status='cancelled', updated_at=now(),
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('closed_reason','stale: no progress for '||p_idle::text,'closed_at',now(),'closed_by','layer2_wave_request_close_stale_v1 (Decision 151)')
     where id = any(v_ids);
    get diagnostics v_req = row_count;
  end if;
  return jsonb_build_object('mode',case when p_apply then 'apply' else 'proof' end,'idle_limit',p_idle::text,'requests',coalesce(v_list,'[]'::jsonb),'closed',v_req,'items_blocked',v_items);
end $$;
revoke all on function security.layer2_wave_request_close_stale_v1(boolean,interval) from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname='layer2-stale-wave-closer';
select cron.schedule('layer2-stale-wave-closer','17 3 * * *',$c$select security.layer2_wave_request_close_stale_v1(true);$c$);
