-- M2.4.2 — Layer 2 Course refresh dispatcher and non-destructive housekeeping.
-- Profile-scoped refresh policies are created disabled; enable only after full-run acceptance.

begin;

create index if not exists refresh_requests_layer2_profile_schedule_idx
  on pipeline.refresh_requests(requested_layer,status,source_profile_id,created_at)
  where requested_layer=2 and source_profile_id is not null;

insert into pipeline.refresh_policies(
  country_code,layer,source_profile_id,source_id,entity_type,entity_id,
  freshness_class,cadence_interval,next_due_at,hash_sensitive,important_date_sensitive,
  enabled,change_control_ref,updated_at
)
select 'AU',2,p.id,p.source_id,'course',null,
       'weekly',make_interval(hours=>coalesce(p.freshness_sla_hours,168)),null,
       true,true,false,'CF-CHG-20260827-044',now()
from pipeline.layer2_source_profiles p
where p.domain='course_facts'
  and p.profile_key in ('au-uq-course-catalogue','au-rmit-course-detail','au-federation-course-detail')
  and not exists(
    select 1 from pipeline.refresh_policies rp
    where rp.layer=2 and rp.source_profile_id=p.id and rp.entity_id is null
  );

create or replace function security.layer2_refresh_scheduler_tick_impl(
  p_now timestamptz default now(),
  p_limit integer default 10,
  p_dispatch boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','security','pipeline','public','catalogue'
as $$
declare
  v_reconciled int:=0; v_dispatched int:=0; v_failed int:=0; v_nothing int:=0; v_stale int:=0;
  rec record; v_batch uuid; v_batch_status text; v_result jsonb; v_ids uuid[];
begin
  for rec in
    select r.id,r.revalidation_ref
    from pipeline.refresh_requests r
    where r.requested_layer=2
      and r.source_profile_id is not null
      and r.status='running'
      and r.revalidation_ref like 'L2BATCH:%'
    order by r.created_at
    limit least(greatest(p_limit,1),100)
    for update skip locked
  loop
    begin
      v_batch:=substring(rec.revalidation_ref from 9)::uuid;
      select b.status into v_batch_status from pipeline.layer2_run_batches b where b.id=v_batch;
      if v_batch_status in ('completed','partial') then
        update pipeline.refresh_requests
        set status='completed',completed_at=p_now,schedule_error=null
        where id=rec.id;
        v_reconciled:=v_reconciled+1;
      elsif v_batch_status in ('failed','cancelled') then
        update pipeline.refresh_requests
        set status='failed',completed_at=p_now,
            schedule_error='Managed Layer 2 refresh batch finished with status '||v_batch_status
        where id=rec.id;
        v_reconciled:=v_reconciled+1;
      end if;
    exception when others then
      update pipeline.refresh_requests
      set status='failed',completed_at=p_now,schedule_error=left(sqlerrm,1000)
      where id=rec.id;
      v_failed:=v_failed+1;
    end;
  end loop;

  update pipeline.refresh_requests r
  set status='failed',completed_at=p_now,
      schedule_error='Layer 2 scheduled refresh exceeded 45 minute dispatch/reconciliation window.'
  where r.requested_layer=2
    and r.source_profile_id is not null
    and r.status='running'
    and r.created_at<p_now-interval '45 minutes'
    and (r.revalidation_ref is null or r.revalidation_ref not like 'L2BATCH:%');
  get diagnostics v_stale=row_count;

  if p_dispatch then
    for rec in
      select r.id,r.source_profile_id
      from pipeline.refresh_requests r
      join pipeline.layer2_source_profiles p on p.id=r.source_profile_id
      where r.requested_layer=2
        and r.source_profile_id is not null
        and r.status='queued'
        and p.domain='course_facts' and p.enabled and not p.paused
      order by r.created_at
      limit least(greatest(p_limit,1),100)
      for update of r skip locked
    loop
      begin
        select array_agg(distinct dc.course_id order by dc.course_id)
        into v_ids
        from pipeline.layer2_course_discovery_candidates dc
        join pipeline.layer2_source_profiles p on p.id=rec.source_profile_id
        where dc.source_profile_version_id=p.current_version_id
          and dc.selected
          and nullif(dc.discovered_url,'') is not null;

        if coalesce(array_length(v_ids,1),0)=0 then
          update pipeline.refresh_requests
          set status='completed',completed_at=p_now,
              schedule_error='No governed selected Course URLs are available for this profile.'
          where id=rec.id;
          v_nothing:=v_nothing+1;
          continue;
        end if;

        v_result:=public.layer2_scope_profile_batch_service(
          public.layer2_automation_actor(),rec.source_profile_id,v_ids
        );

        if v_result->>'status' in ('started','already_running') then
          update pipeline.refresh_requests
          set status='running',
              dispatched_at=coalesce(dispatched_at,p_now),
              dispatch_request_id=case
                when nullif(v_result->>'dispatch_request_id','') is null then dispatch_request_id
                else (v_result->>'dispatch_request_id')::bigint end,
              revalidation_ref='L2BATCH:'||(v_result->>'batch_id'),
              schedule_error=null
          where id=rec.id;
          v_dispatched:=v_dispatched+1;
        elsif v_result->>'status'='nothing_queueable' then
          update pipeline.refresh_requests
          set status='completed',completed_at=p_now,
              schedule_error='No queueable governed Course URLs were available at dispatch.'
          where id=rec.id;
          v_nothing:=v_nothing+1;
        else
          update pipeline.refresh_requests
          set status='failed',completed_at=p_now,
              schedule_error=left('Unexpected Layer 2 scheduler result: '||coalesce(v_result::text,'null'),1000)
          where id=rec.id;
          v_failed:=v_failed+1;
        end if;
      exception when others then
        update pipeline.refresh_requests
        set status='failed',completed_at=p_now,schedule_error=left(sqlerrm,1000)
        where id=rec.id;
        v_failed:=v_failed+1;
      end;
    end loop;
  end if;

  return jsonb_build_object(
    'ok',true,'reconciled',v_reconciled,'dispatched',v_dispatched,
    'nothing_queueable',v_nothing,'failed',v_failed,'stale_recovered',v_stale,
    'dispatch_enabled',p_dispatch,'at',p_now
  );
end $$;

create or replace function public.svc_layer2_housekeeping()
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline','public'
as $$
declare
  v_attempts int:=0; v_jobs int:=0; v_batches int:=0; rec record;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  with stale as (
    select pa.id
    from pipeline.layer2_provider_attempts pa
    join pipeline.layer2_acquisition_providers ap on ap.id=pa.acquisition_provider_id
    where pa.status='running'
      and coalesce(pa.started_at,pa.created_at) <
          now()-make_interval(secs=>greatest(coalesce(ap.timeout_seconds,30)*2,300))
    for update of pa skip locked
  )
  update pipeline.layer2_provider_attempts pa
  set status='failed',completed_at=now(),extraction_status='not_attempted',
      blocker=coalesce(pa.blocker,'Housekeeping recovered stale provider attempt after provider timeout window.'),
      metrics=coalesce(pa.metrics,'{}'::jsonb)||jsonb_build_object('recovery','layer2_housekeeping_stale_attempt')
  from stale s
  where pa.id=s.id;
  get diagnostics v_attempts=row_count;

  update pipeline.jobs j
  set status='failed',completed_at=now(),
      error_text=coalesce(j.error_text,'Layer 2 housekeeping recovered abandoned running job.'),
      result=coalesce(j.result,'{}'::jsonb)||jsonb_build_object('recovery','layer2_housekeeping_stale_job')
  where j.status='running'
    and j.job_type like 'layer2%'
    and coalesce(j.started_at,j.created_at)<now()-interval '45 minutes'
    and not exists(
      select 1 from pipeline.layer2_provider_attempts pa
      where pa.job_id=j.id and pa.status='running'
    );
  get diagnostics v_jobs=row_count;

  for rec in
    select b.id
    from pipeline.layer2_run_batches b
    join pipeline.layer2_execution_policies ep on ep.profile_id=b.profile_id
    where b.status='running'
      and coalesce(b.heartbeat_at,b.updated_at,b.started_at,b.created_at)
          < now()-make_interval(mins=>coalesce(ep.stale_after_minutes,30))
    order by b.created_at
    limit 50
  loop
    perform public.layer2_run_batch_recover_stuck(rec.id);
    v_batches:=v_batches+1;
  end loop;

  return jsonb_build_object(
    'ok',true,
    'stale_provider_attempts_recovered',v_attempts,
    'stale_jobs_recovered',v_jobs,
    'stale_batches_recovered',v_batches,
    'governed_evidence_deleted',0,
    'profile_versions_deleted',0,
    'provider_attempt_history_deleted',0,
    'run_history_deleted',0,
    'canonical_history_deleted',0,
    'policy','Recovery only: governed Evidence, immutable profile versions, provider-attempt history, run history and canonical history are retained.'
  );
end $$;

create or replace function security.layer2_housekeeping_tick_impl()
returns jsonb
language sql
security definer
set search_path to 'pg_catalog','public'
as $$ select public.svc_layer2_housekeeping() $$;

revoke all on function security.layer2_refresh_scheduler_tick_impl(timestamptz,integer,boolean) from public,anon,authenticated;
revoke all on function public.svc_layer2_housekeeping() from public,anon,authenticated;
revoke all on function security.layer2_housekeeping_tick_impl() from public,anon,authenticated;
grant execute on function security.layer2_refresh_scheduler_tick_impl(timestamptz,integer,boolean) to service_role;
grant execute on function public.svc_layer2_housekeeping() to service_role;
grant execute on function security.layer2_housekeeping_tick_impl() to service_role;

select cron.schedule(
  'coursefinder-layer2-refresh-dispatcher',
  '3,18,33,48 * * * *',
  'select security.layer2_refresh_scheduler_tick_impl(now(),10,true);'
);
select cron.schedule(
  'coursefinder-layer2-housekeeping',
  '27 3 * * *',
  'select security.layer2_housekeeping_tick_impl();'
);

commit;
