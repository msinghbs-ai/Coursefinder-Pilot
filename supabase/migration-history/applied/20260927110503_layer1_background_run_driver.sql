-- CF-247 / Decision 155 (part 1): Layer 1 runs execute in the background.
-- * A run is advanced by the database, not by a browser tab or a user sign-in token.
-- * One worker at a time per run (lease), so the self-continuation chain and the driver never overlap.
-- * Temporary source errors (HTTP 5xx/429, timeouts) are retried automatically with back-off
--   (5 attempts: 1, 2, 4, 8, 15 minutes) before a run is marked failed with the real error.
-- * Unchanged register listing snapshots are stored once (evidence lookup by content hash).
-- Consumer API: no consumer-facing object is touched.

alter table pipeline.layer1_run_queue
  add column if not exists lease_until timestamptz,
  add column if not exists driver_dispatched_at timestamptz,
  add column if not exists driver_dispatches integer not null default 0;

-- Claim / release the single-worker lease for a run.
create or replace function public.svc_layer1_run_claim(p_run_id uuid, p_seconds integer default 240)
returns boolean language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
declare v_ok boolean;
begin
  update pipeline.layer1_run_queue set lease_until=now()+make_interval(secs=>greatest(30,least(coalesce(p_seconds,240),900)))
   where id=p_run_id and status in ('queued','running') and (lease_until is null or lease_until<now());
  v_ok:=found;
  return v_ok;
end $f$;

create or replace function public.svc_layer1_run_release(p_run_id uuid)
returns void language sql security definer set search_path to 'pg_catalog','pipeline' as $f$
  update pipeline.layer1_run_queue set lease_until=null where id=p_run_id;
$f$;

-- Reuse an identical evidence snapshot instead of storing it again (download once, store once).
create or replace function public.svc_layer1_evidence_by_hash(p_source_id uuid, p_hash text)
returns uuid language sql stable security definer set search_path to 'pg_catalog','pipeline' as $f$
  select e.id from pipeline.evidence_artifacts e
   where e.source_id=p_source_id and e.content_hash=p_hash
   order by e.created_at desc limit 1;
$f$;

revoke all on function public.svc_layer1_run_claim(uuid,integer) from public, anon, authenticated;
revoke all on function public.svc_layer1_run_release(uuid) from public, anon, authenticated;
revoke all on function public.svc_layer1_evidence_by_hash(uuid,text) from public, anon, authenticated;
grant execute on function public.svc_layer1_run_claim(uuid,integer) to service_role;
grant execute on function public.svc_layer1_run_release(uuid) to service_role;
grant execute on function public.svc_layer1_evidence_by_hash(uuid,text) to service_role;

create index if not exists evidence_artifacts_source_hash_idx on pipeline.evidence_artifacts(source_id, content_hash);

-- Allow the driver to call layer1-operations-control with a one-time nonce (checksum-guarded patch).
do $patch$
declare v_def text; v_new text; v_md5 text;
begin
  v_def:=pg_get_functiondef('pipeline.svc_pilot_submit_nonce(text,jsonb)'::regprocedure);
  v_md5:=md5(v_def);
  if v_def like '%''layer1-operations-control''%' then raise notice 'allow-list already contains layer1-operations-control'; return; end if;
  if v_md5<>'24c2d10135375a149f608ab0496700be' then raise exception 'svc_pilot_submit_nonce changed (md5 %); aborting', v_md5; end if;
  if (select count(*) from regexp_matches(v_def,'''layer1-operations-scheduled'',','g'))<>1 then raise exception 'allow-list anchor not found exactly once'; end if;
  v_new:=replace(v_def,'''layer1-operations-scheduled'',','''layer1-operations-scheduled'',''layer1-operations-control'',');
  execute v_new;
end $patch$;

-- Expose the current retry attempt to the worker (checksum-guarded patch).
do $patch$
declare v_def text; v_md5 text;
begin
  v_def:=pg_get_functiondef('public.svc_layer1_queue_context(uuid)'::regprocedure);
  if v_def like '%retry_attempt%' then raise notice 'queue context already exposes retry_attempt'; return; end if;
  v_md5:=md5(v_def);
  if v_md5<>'f7e15e7f49e0b383aaefe759d8cb4867' then raise exception 'svc_layer1_queue_context changed (md5 %); aborting', v_md5; end if;
  if (select count(*) from regexp_matches(v_def,'''heartbeat_at'',q\.heartbeat_at\)','g'))<>1 then raise exception 'queue context anchor not found exactly once'; end if;
  execute replace(v_def,'''heartbeat_at'',q.heartbeat_at)','''heartbeat_at'',q.heartbeat_at,''retry_attempt'',coalesce(nullif(q.result->''retry''->>''attempt'','''')::int,0))');
end $patch$;

-- The driver: every minute, advance runs whose worker has gone quiet or whose retry is due.
create or replace function security.layer1_run_driver_tick_v1(p_limit integer default 3)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','security' as $f$
declare rec record; v_dispatched int:=0; v_gave_up int:=0;
begin
  for rec in
    select q.id, q.current_stage, q.driver_dispatches
      from pipeline.layer1_run_queue q
     where q.status in ('queued','running')
       and (q.lease_until is null or q.lease_until<now())
       and coalesce(q.driver_dispatched_at,'-infinity'::timestamptz)<now()-interval '3 minutes'
       and (
         (q.current_stage='retry_waiting' and coalesce(nullif(q.result->'retry'->>'next_at','')::timestamptz,now())<=now())
         or (q.current_stage is distinct from 'retry_waiting' and coalesce(q.heartbeat_at,q.requested_at)<now()-interval '3 minutes')
       )
     order by q.requested_at
     limit greatest(1,least(coalesce(p_limit,3),10))
     for update of q skip locked
  loop
    if rec.driver_dispatches>=40 then
      update pipeline.layer1_run_queue
         set status='failed',current_stage='failed',completed_at=now(),heartbeat_at=now(),failed_count=failed_count+1,
             error_text='Stopped after 40 background restarts without finishing. Check the source, then use Retry / resume.',updated_at=now()
       where id=rec.id;
      v_gave_up:=v_gave_up+1;
      continue;
    end if;
    update pipeline.layer1_run_queue
       set driver_dispatched_at=now(),driver_dispatches=driver_dispatches+1,
           result=coalesce(result,'{}'::jsonb)||jsonb_build_object('driver',jsonb_build_object('last_dispatch_at',now(),'dispatches',rec.driver_dispatches+1,'reason',case when rec.current_stage='retry_waiting' then 'retry_due' else 'worker_quiet' end))
     where id=rec.id;
    perform pipeline.svc_pilot_submit_nonce('layer1-operations-control',jsonb_build_object('action','continue','run_id',rec.id));
    v_dispatched:=v_dispatched+1;
  end loop;
  return jsonb_build_object('dispatched',v_dispatched,'gave_up',v_gave_up,'at',now());
end $f$;
revoke all on function security.layer1_run_driver_tick_v1(integer) from public, anon, authenticated;

-- Queue a governed run under the system automation identity (same guards as the operator command).
create or replace function security.layer1_queue_system_run_v1(p_source_id uuid, p_mode text, p_resume_cursor bigint default 0, p_retry_of_run_id uuid default null, p_reason text default 'Background run (system)')
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','security' as $f$
declare v_profile pipeline.layer1_source_operations; v_country text; v_id uuid; v_mode text:=lower(coalesce(p_mode,'dry_run'));
begin
  if v_mode not in ('dry_run','apply') then raise exception 'invalid mode'; end if;
  select * into v_profile from pipeline.layer1_source_operations where source_id=p_source_id;
  if not found then raise exception 'source operations profile missing'; end if;
  if not v_profile.active or v_profile.paused then raise exception 'source is inactive or paused'; end if;
  if coalesce(v_profile.verification_status,'') not in ('passed','warning') then raise exception 'source verification must pass before run'; end if;
  if v_profile.next_verification_at is not null and v_profile.next_verification_at<now() then raise exception 'source verification is stale'; end if;
  if v_profile.variance_decision='block' then raise exception 'record-count variance is blocked'; end if;
  if v_mode='apply' and v_profile.variance_decision='warn' then raise exception 'variance warning needs an operator acknowledgement'; end if;
  if exists(select 1 from pipeline.layer1_run_queue where source_id=p_source_id and status in ('queued','running')) then raise exception 'a run is already queued or running for this source'; end if;
  select co.iso_alpha2::text into v_country from pipeline.sources s join ref.countries co on co.id=s.country_id where s.id=p_source_id;
  insert into pipeline.layer1_run_queue(source_id,country_code,mode,status,idempotency_key,requested_by,expected_count,resume_cursor,processed_count,source_hash,warning_acknowledged,current_stage,heartbeat_at,retry_of_run_id,result)
  values(p_source_id,v_country,v_mode,'queued','system:'||p_source_id::text||':'||extract(epoch from clock_timestamp())::text,'c0ffee00-0000-4000-8000-000000000150',
         v_profile.last_expected_count,greatest(coalesce(p_resume_cursor,0),0),greatest(coalesce(p_resume_cursor,0),0),v_profile.last_source_hash,false,'queued',now()-interval '5 minutes',p_retry_of_run_id,
         jsonb_build_object('start_cursor',greatest(coalesce(p_resume_cursor,0),0),'requested_reason',left(coalesce(p_reason,''),300)))
  returning id into v_id;
  return jsonb_build_object('run_id',v_id,'status','queued','country_code',v_country,'mode',v_mode);
end $f$;
revoke all on function security.layer1_queue_system_run_v1(uuid,text,bigint,uuid,text) from public, anon, authenticated;

select cron.schedule('layer1-run-driver','* * * * *','select security.layer1_run_driver_tick_v1(3);');
