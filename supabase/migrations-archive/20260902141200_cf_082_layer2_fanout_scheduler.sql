begin;

create or replace function security.layer2_fanout_scheduler_tick_impl(
  p_now timestamptz default now(),
  p_limit integer default 10,
  p_dispatch boolean default true
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','security','pipeline','public'
as $$
declare
  r record;
  v_dispatched int:=0;
  v_recovered int:=0;
  v_failed int:=0;
  v_request_id bigint;
begin
  update pipeline.layer2_fanout_tasks
  set status='queued',
      started_at=null,
      last_error=coalesce(last_error,'')||case when coalesce(last_error,'')='' then '' else '; ' end||'stale fan-out lease recovered at '||p_now::text
  where status='running'
    and started_at < p_now - interval '30 minutes'
    and task_type in('provider_asset','scholarship_discovery');
  get diagnostics v_recovered=row_count;

  if not p_dispatch then
    return jsonb_build_object('ok',true,'at',p_now,'dispatch_enabled',false,'recovered',v_recovered,'dispatched',0,'failed',0);
  end if;

  for r in
    select shared_fetch_id,min(created_at) first_queued_at
    from pipeline.layer2_fanout_tasks
    where status='queued'
      and task_type in('provider_asset','scholarship_discovery')
    group by shared_fetch_id
    order by min(created_at)
    limit greatest(1,least(coalesce(p_limit,10),25))
  loop
    begin
      update pipeline.layer2_fanout_tasks
      set status='running',started_at=p_now,last_error=null
      where shared_fetch_id=r.shared_fetch_id
        and status='queued'
        and task_type in('provider_asset','scholarship_discovery');

      select pipeline.svc_pilot_invoke_layer2(
        'layer2-provider-page-fanout',
        jsonb_build_object('shared_fetch_id',r.shared_fetch_id,'scheduler','layer2_fanout_scheduler')
      ) into v_request_id;

      update pipeline.layer2_fanout_tasks
      set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'dispatch_request_id',v_request_id,
        'dispatched_at',p_now,
        'scheduler','layer2_fanout_scheduler'
      )
      where shared_fetch_id=r.shared_fetch_id
        and status='running'
        and task_type in('provider_asset','scholarship_discovery');

      v_dispatched:=v_dispatched+1;
    exception when others then
      v_failed:=v_failed+1;
      update pipeline.layer2_fanout_tasks
      set status='queued',started_at=null,last_error=sqlerrm
      where shared_fetch_id=r.shared_fetch_id
        and status='running'
        and task_type in('provider_asset','scholarship_discovery');
    end;
  end loop;

  return jsonb_build_object(
    'ok',true,'at',p_now,'dispatch_enabled',true,
    'recovered',v_recovered,'dispatched',v_dispatched,'failed',v_failed
  );
end $$;

revoke all on function security.layer2_fanout_scheduler_tick_impl(timestamptz,integer,boolean) from public,anon,authenticated;
grant execute on function security.layer2_fanout_scheduler_tick_impl(timestamptz,integer,boolean) to service_role;

do $$
begin
  if exists(select 1 from cron.job where jobname='coursefinder-layer2-fanout-scheduler') then
    perform cron.unschedule((select jobid from cron.job where jobname='coursefinder-layer2-fanout-scheduler' limit 1));
  end if;
  perform cron.schedule(
    'coursefinder-layer2-fanout-scheduler',
    '7-59/10 * * * *',
    'select security.layer2_fanout_scheduler_tick_impl(now(),10,true);'
  );
end $$;

commit;