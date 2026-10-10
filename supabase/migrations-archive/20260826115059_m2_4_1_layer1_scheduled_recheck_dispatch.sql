alter table pipeline.refresh_requests add column if not exists dispatched_at timestamptz;
alter table pipeline.refresh_requests add column if not exists dispatch_request_id bigint;
alter table pipeline.refresh_requests add column if not exists schedule_error text;

alter table pipeline.refresh_requests drop constraint if exists refresh_requests_status_check;
alter table pipeline.refresh_requests add constraint refresh_requests_status_check check (status = any(array['queued'::text,'running'::text,'completed'::text,'cancelled'::text,'blocked'::text,'failed'::text]));

create index if not exists refresh_requests_layer1_schedule_idx on pipeline.refresh_requests(requested_layer,status,source_id,created_at) where requested_layer=1;

create or replace function public.svc_layer1_scheduled_context(p_refresh_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline','ref'
as $function$
declare v jsonb;
begin
  select jsonb_build_object(
    'refresh_request_id',r.id,'status',r.status,'source_id',r.source_id,'country_code',r.country_code,
    'reason',r.reason,'trigger_type',r.trigger_type,'dispatched_at',r.dispatched_at,
    'source',jsonb_build_object('url',s.url,'metadata',s.metadata,'source_type',s.source_type),
    'profile',to_jsonb(o)-'updated_by'
  ) into v
  from pipeline.refresh_requests r
  join pipeline.sources s on s.id=r.source_id
  join pipeline.layer1_source_operations o on o.source_id=r.source_id
  where r.id=p_refresh_request_id and r.requested_layer=1 and r.status='running';
  if v is null then raise exception 'active Layer 1 scheduled request not found'; end if;
  return v;
end $function$;

revoke all on function public.svc_layer1_scheduled_context(uuid) from public,anon,authenticated;
grant execute on function public.svc_layer1_scheduled_context(uuid) to service_role;

create or replace function public.svc_layer1_schedule_complete(p_refresh_request_id uuid,p_success boolean,p_changed boolean,p_message text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline'
as $function$
declare v_source uuid; v_status text;
begin
  select source_id into v_source from pipeline.refresh_requests where id=p_refresh_request_id and requested_layer=1 and status='running' for update;
  if v_source is null then raise exception 'running Layer 1 scheduled request not found'; end if;
  v_status:=case when p_success then 'completed' else 'failed' end;
  update pipeline.refresh_requests
     set status=v_status,completed_at=now(),schedule_error=case when p_success then null else left(coalesce(p_message,'scheduled verification failed'),1000) end
   where id=p_refresh_request_id;
  update pipeline.layer1_source_operations
     set last_schedule_status=case when p_success and p_changed then 'completed_changed' when p_success then 'completed_unchanged' else 'failed' end,
         last_schedule_error=case when p_success then null else left(coalesce(p_message,'scheduled verification failed'),1000) end,
         consecutive_failures=case when p_success then 0 else consecutive_failures+1 end,
         updated_at=now()
   where source_id=v_source;
  return jsonb_build_object('refresh_request_id',p_refresh_request_id,'source_id',v_source,'status',v_status,'changed',p_changed);
end $function$;

revoke all on function public.svc_layer1_schedule_complete(uuid,boolean,boolean,text) from public,anon,authenticated;
grant execute on function public.svc_layer1_schedule_complete(uuid,boolean,boolean,text) to service_role;

create or replace function pipeline.svc_pilot_submit_nonce(p_function text,p_body jsonb default '{}'::jsonb)
returns bigint
language plpgsql
security definer
set search_path to 'pipeline','net','public','extensions'
as $function$
declare v_nonce uuid:=extensions.gen_random_uuid(); v_id bigint;
begin
  if p_function not in (
    'layer1-ca-niagara-catalogue','qilt-au-etl','prisms-au-etl','layer1-au-depth','layer1-au-completeness',
    'coursefacts-au-rmit','coursefacts-au-uq','coursefacts-au-qut','layer1-au-cricos-facts','layer1-operations-scheduled'
  ) then raise exception 'one-time Pilot Edge function is not allowlisted'; end if;
  insert into pipeline.pilot_edge_nonces(id,function_name,expires_at) values(v_nonce,p_function,now()+interval '2 minutes');
  select net.http_post(
    url:='https://fxcwkweaxjtknorudmwp.supabase.co/functions/v1/'||p_function,
    headers:=jsonb_build_object('content-type','application/json','x-cf-run-nonce',v_nonce::text),
    body:=coalesce(p_body,'{}'::jsonb),timeout_milliseconds:=120000
  ) into v_id;
  return v_id;
end $function$;

create or replace function security.layer1_regulatory_scheduler_tick_impl(p_now timestamptz default now(),p_limit integer default 20,p_dispatch boolean default true)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','security','pipeline'
as $function$
declare v_created int:=0; v_dispatched int:=0; v_recovered int:=0; v_failed int:=0; rec record; v_net bigint;
begin
  with stale as (
    update pipeline.refresh_requests r
       set status='failed',completed_at=p_now,schedule_error='Scheduled Layer 1 verification dispatch exceeded 30 minute heartbeat window.'
     where r.requested_layer=1 and r.status='running' and r.dispatched_at is not null and r.dispatched_at < p_now-interval '30 minutes'
     returning r.source_id
  ), upd as (
    update pipeline.layer1_source_operations o
       set last_schedule_status='failed',last_schedule_error='Scheduled Layer 1 verification dispatch exceeded 30 minute heartbeat window.',consecutive_failures=o.consecutive_failures+1,updated_at=p_now
     where o.source_id in (select source_id from stale)
     returning 1
  ) select count(*) into v_recovered from stale;

  with due as (
    select o.source_id,c.iso_alpha2::text country_code
      from pipeline.layer1_source_operations o
      join pipeline.sources s on s.id=o.source_id
      join ref.countries c on c.id=s.country_id
     where o.active and not o.paused and o.next_verification_at is not null and o.next_verification_at<=p_now
       and not exists(select 1 from pipeline.refresh_requests r where r.requested_layer=1 and r.source_id=o.source_id and r.status in ('queued','running'))
     order by o.next_verification_at
     limit least(greatest(p_limit,1),100)
     for update of o skip locked
  ), ins as (
    insert into pipeline.refresh_requests(requested_layer,country_code,source_id,reason,trigger_type,status,requested_by,change_control_ref)
    select 1,d.country_code,d.source_id,'Layer 1 scheduled authoritative-source verification due','freshness_expired','queued',null,'CF-CHG-20260826-043' from due d
    returning id
  ) select count(*) into v_created from ins;

  if p_dispatch then
    for rec in
      select r.id,r.source_id from pipeline.refresh_requests r
      join pipeline.layer1_source_operations o on o.source_id=r.source_id
      where r.requested_layer=1 and r.status='queued' and o.active and not o.paused
      order by r.created_at
      limit least(greatest(p_limit,1),100)
      for update of r skip locked
    loop
      begin
        update pipeline.refresh_requests set status='running',dispatched_at=p_now,schedule_error=null where id=rec.id;
        v_net:=pipeline.svc_pilot_submit_nonce('layer1-operations-scheduled',jsonb_build_object('refresh_request_id',rec.id));
        update pipeline.refresh_requests set dispatch_request_id=v_net where id=rec.id;
        v_dispatched:=v_dispatched+1;
      exception when others then
        update pipeline.refresh_requests set status='failed',completed_at=p_now,schedule_error=left(sqlerrm,1000) where id=rec.id;
        update pipeline.layer1_source_operations set last_schedule_status='failed',last_schedule_error=left(sqlerrm,1000),consecutive_failures=consecutive_failures+1,updated_at=p_now where source_id=rec.source_id;
        v_failed:=v_failed+1;
      end;
    end loop;
  end if;
  return jsonb_build_object('ok',true,'created',v_created,'dispatched',v_dispatched,'dispatch_failed',v_failed,'stuck_recovered',v_recovered,'at',p_now,'dispatch_enabled',p_dispatch);
end $function$;

revoke all on function security.layer1_regulatory_scheduler_tick_impl(timestamptz,integer,boolean) from public,anon,authenticated;
grant execute on function security.layer1_regulatory_scheduler_tick_impl(timestamptz,integer,boolean) to service_role;

select cron.schedule('coursefinder-layer1-regulatory-scheduler','5,20,35,50 * * * *','select security.layer1_regulatory_scheduler_tick_impl(now(),20,true);')
where not exists(select 1 from cron.job where jobname='coursefinder-layer1-regulatory-scheduler');