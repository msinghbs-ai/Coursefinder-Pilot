-- M2.4.4 A19 — Scholarship scheduled ETL and maintenance
begin;

create table if not exists pipeline.scholarship_etl_schedules(
  feed text primary key check(feed in('study_australia','australia_awards')),
  source_key text not null,
  enabled boolean not null default true,
  cadence_hours integer not null check(cadence_hours between 1 and 744),
  mode text not null default 'apply' check(mode in('dry_run','apply')),
  max_records integer,
  page_start integer,
  page_end integer,
  next_due_at timestamptz not null,
  last_dispatched_at timestamptz,
  last_request_id bigint,
  last_nonce uuid,
  last_dispatch jsonb not null default '{}'::jsonb,
  last_error text,
  updated_at timestamptz not null default now()
);
create table if not exists pipeline.scholarship_maintenance_runs(
  id uuid primary key default gen_random_uuid(),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  status text not null default 'running' check(status in('running','completed','failed')),
  deterministic_mappings integer not null default 0,
  mapping_candidates integer not null default 0,
  source_records integer not null default 0,
  unapplied_source_records integer not null default 0,
  discovery_candidates integer not null default 0,
  stale_source_records integer not null default 0,
  evidence_deleted integer not null default 0,
  source_records_deleted integer not null default 0,
  notes jsonb not null default '{}'::jsonb
);
alter table pipeline.scholarship_etl_schedules enable row level security;
alter table pipeline.scholarship_maintenance_runs enable row level security;
revoke all on pipeline.scholarship_etl_schedules,pipeline.scholarship_maintenance_runs from public,anon,authenticated;
insert into pipeline.scholarship_etl_schedules(feed,source_key,enabled,cadence_hours,mode,max_records,page_start,page_end,next_due_at)
values
 ('study_australia','au_study_australia_scholarships',true,24,'apply',50,1,5,now()+interval '24 hours'),
 ('australia_awards','au_dfat_australia_awards',true,168,'apply',null,null,null,now()+interval '168 hours')
on conflict(feed) do update set source_key=excluded.source_key,enabled=excluded.enabled,cadence_hours=excluded.cadence_hours,mode=excluded.mode,max_records=excluded.max_records,page_start=excluded.page_start,page_end=excluded.page_end,updated_at=now();

CREATE OR REPLACE FUNCTION public.scholarship_operations_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'security', 'pipeline', 'scholarship', 'auth'
AS $function$
declare v_rank integer;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

  return jsonb_build_object(
    'schedules',(select coalesce(jsonb_agg(jsonb_build_object(
      'feed',feed,'enabled',enabled,'cadence_hours',cadence_hours,'mode',mode,
      'max_records',max_records,'page_start',page_start,'page_end',page_end,
      'next_due_at',next_due_at,'last_dispatched_at',last_dispatched_at,
      'last_request_id',last_request_id,'last_error',last_error
    ) order by feed),'[]'::jsonb) from pipeline.scholarship_etl_schedules),
    'qualifications',(select coalesce(jsonb_agg(jsonb_build_object(
      'source_key',source_key,'authority_name',authority_name,'qualification_status',qualification_status,
      'source_url',source_url,'updated_at',updated_at
    ) order by source_key),'[]'::jsonb) from pipeline.scholarship_source_qualifications),
    'source_records',(select jsonb_build_object(
      'total',count(*),
      'applied',count(*) filter(where status='applied' and applied_at is not null),
      'unapplied',count(*) filter(where status<>'applied' or applied_at is null),
      'stale_45d',count(*) filter(where observed_at<now()-interval '45 days'),
      'latest_observed_at',max(observed_at)
    ) from pipeline.scholarship_source_records),
    'discovery_candidates',(select jsonb_build_object(
      'discovered',count(*) filter(where status='discovered'),
      'total',count(*)
    ) from pipeline.layer2_scholarship_discovery_candidates),
    'course_mapping',(select jsonb_build_object(
      'mapped',count(*) filter(where mapping_state='mapped'),
      'needs_review',(select count(*) from scholarship.course_mapping_candidates where status='needs_review')
    ) from scholarship.course_mappings),
    'latest_maintenance',(select to_jsonb(x) from (
      select id,started_at,completed_at,status,deterministic_mappings,mapping_candidates,
             source_records,unapplied_source_records,discovery_candidates,stale_source_records,
             evidence_deleted,source_records_deleted
      from pipeline.scholarship_maintenance_runs order by started_at desc limit 1
    ) x)
  );
end $function$
;

CREATE OR REPLACE FUNCTION security.scholarship_maintenance_tick_impl(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'scholarship', 'catalogue'
AS $function$
declare
  v_run uuid;
  v_mappings integer:=0;
  v_candidates integer:=0;
  v_source_records integer:=0;
  v_unapplied integer:=0;
  v_discovery integer:=0;
  v_stale integer:=0;
begin
  if current_user not in('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  insert into pipeline.scholarship_maintenance_runs(status) values('running') returning id into v_run;

  with deterministic as(
    select distinct s.id scholarship_id,c.id course_id,sc.id scope_id,coalesce(sc.evidence_id,s.evidence_id) evidence_id,
      case when sc.scope_type='course' then 'explicit_course_scope' else 'explicit_provider_scope' end basis
    from scholarship.scholarships s
    join scholarship.scopes sc on sc.scholarship_id=s.id and sc.include_exclude='include'
    join catalogue.courses c
      on (sc.scope_type='course' and sc.course_id=c.id)
      or (sc.scope_type='provider' and sc.provider_id=c.provider_id)
    where sc.scope_type in('course','provider')
      and not exists(
        select 1 from scholarship.scopes ex
        where ex.scholarship_id=s.id and ex.include_exclude='exclude'
          and ((ex.scope_type='course' and ex.course_id=c.id)
            or (ex.scope_type='provider' and ex.provider_id=c.provider_id))
      )
  ), upserted as(
    insert into scholarship.course_mappings(
      scholarship_id,course_id,mapping_state,mapping_basis,source_scope_id,evidence_id,mapped_by,updated_at
    )
    select scholarship_id,course_id,'mapped',basis,scope_id,evidence_id,null,p_now
    from deterministic
    on conflict(scholarship_id,course_id) do update set
      mapping_state='mapped',
      mapping_basis=excluded.mapping_basis,
      source_scope_id=excluded.source_scope_id,
      evidence_id=excluded.evidence_id,
      updated_at=p_now
    returning 1
  )
  select count(*) into v_mappings from upserted;

  select count(*) into v_candidates
  from scholarship.course_mapping_candidates where status='needs_review';

  select count(*) into v_source_records from pipeline.scholarship_source_records;
  select count(*) into v_unapplied
  from pipeline.scholarship_source_records where status<>'applied' or applied_at is null;
  select count(*) into v_discovery
  from pipeline.layer2_scholarship_discovery_candidates where status='discovered';
  select count(*) into v_stale
  from pipeline.scholarship_source_records
  where observed_at<p_now-interval '45 days';

  update pipeline.scholarship_maintenance_runs
  set completed_at=p_now,status='completed',
      deterministic_mappings=v_mappings,
      mapping_candidates=v_candidates,
      source_records=v_source_records,
      unapplied_source_records=v_unapplied,
      discovery_candidates=v_discovery,
      stale_source_records=v_stale,
      evidence_deleted=0,
      source_records_deleted=0,
      notes=jsonb_build_object(
        'mapping_rule','explicit course/provider include scopes only',
        'evidence_retained',true,
        'source_history_retained',true
      )
  where id=v_run;

  return jsonb_build_object(
    'ok',true,'run_id',v_run,'deterministic_mappings',v_mappings,
    'mapping_candidates',v_candidates,'source_records',v_source_records,
    'unapplied_source_records',v_unapplied,'discovery_candidates',v_discovery,
    'stale_source_records',v_stale,'evidence_deleted',0,'source_records_deleted',0
  );
exception when others then
  if v_run is not null then
    update pipeline.scholarship_maintenance_runs
    set completed_at=now(),status='failed',notes=jsonb_build_object('error',sqlerrm)
    where id=v_run;
  end if;
  raise;
end $function$
;

CREATE OR REPLACE FUNCTION security.scholarship_scheduler_tick_impl(p_now timestamp with time zone DEFAULT now(), p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline'
AS $function$
declare
  r record;
  v_dispatch jsonb;
  v_results jsonb:='[]'::jsonb;
  v_count integer:=0;
begin
  if current_user not in('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  for r in
    select s.*
    from pipeline.scholarship_etl_schedules s
    where s.enabled
      and s.next_due_at<=p_now
      and exists(
        select 1
        from pipeline.scholarship_source_qualifications q
        where q.source_key=s.source_key and q.qualification_status='qualified'
      )
    order by s.next_due_at,s.feed
    limit greatest(1,least(coalesce(p_limit,5),10))
    for update skip locked
  loop
    begin
      v_dispatch:=pipeline.svc_pilot_invoke_scholarship_edge(
        jsonb_strip_nulls(jsonb_build_object(
          'mode',r.mode,
          'feed',r.feed,
          'max_records',r.max_records,
          'page_start',r.page_start,
          'page_end',r.page_end
        ))
      );

      update pipeline.scholarship_etl_schedules
      set last_dispatched_at=p_now,
          last_request_id=nullif(v_dispatch->>'request_id','')::bigint,
          last_nonce=nullif(v_dispatch->>'nonce','')::uuid,
          last_dispatch=v_dispatch,
          last_error=null,
          next_due_at=p_now+make_interval(hours=>cadence_hours),
          updated_at=p_now
      where feed=r.feed;

      v_results:=v_results||jsonb_build_array(jsonb_build_object(
        'feed',r.feed,'status','dispatched','request_id',v_dispatch->>'request_id',
        'next_due_at',p_now+make_interval(hours=>r.cadence_hours)
      ));
      v_count:=v_count+1;
    exception when others then
      update pipeline.scholarship_etl_schedules
      set last_error=sqlerrm,next_due_at=p_now+interval '1 hour',updated_at=p_now
      where feed=r.feed;
      v_results:=v_results||jsonb_build_array(jsonb_build_object('feed',r.feed,'status','failed','error',sqlerrm));
    end;
  end loop;

  return jsonb_build_object('ok',true,'dispatched_count',v_count,'results',v_results);
end $function$
;

revoke all on function security.scholarship_scheduler_tick_impl(timestamptz,integer) from public,anon,authenticated;
grant execute on function security.scholarship_scheduler_tick_impl(timestamptz,integer) to service_role;
revoke all on function security.scholarship_maintenance_tick_impl(timestamptz) from public,anon,authenticated;
grant execute on function security.scholarship_maintenance_tick_impl(timestamptz) to service_role;
revoke all on function public.scholarship_operations_read() from public,anon;
grant execute on function public.scholarship_operations_read() to authenticated,service_role;
do $$
begin
 if exists(select 1 from cron.job where jobname='coursefinder-scholarship-etl-scheduler') then perform cron.unschedule((select jobid from cron.job where jobname='coursefinder-scholarship-etl-scheduler' limit 1)); end if;
 if exists(select 1 from cron.job where jobname='coursefinder-scholarship-maintenance') then perform cron.unschedule((select jobid from cron.job where jobname='coursefinder-scholarship-maintenance' limit 1)); end if;
 perform cron.schedule('coursefinder-scholarship-etl-scheduler','43 * * * *','select security.scholarship_scheduler_tick_impl(now(),5);');
 perform cron.schedule('coursefinder-scholarship-maintenance','20 5 * * *','select security.scholarship_maintenance_tick_impl(now());');
end $$;
commit;
