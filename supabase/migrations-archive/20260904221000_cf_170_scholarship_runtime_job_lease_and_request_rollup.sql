create or replace function security.scholarship_scope_scheduler_tick_impl(p_now timestamptz default now(),p_limit integer default 5,p_dispatch boolean default true)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','security','pipeline','public' as $$
declare r record;v_dispatched int:=0;v_failed int:=0;v_recovered int:=0;v_request bigint;v_exhausted int:=0;
begin
 update pipeline.jobs set status='failed',completed_at=p_now,error_text=coalesce(error_text,'')||case when coalesce(error_text,'')='' then '' else '; ' end||'scoped Scholarship dispatch retry limit exhausted'
 where job_type='scholarship_scope_acquisition' and domain='scholarship' and status in('queued','running') and coalesce(attempt_count,0)>=3 and (status='queued' or started_at<p_now-interval '10 minutes');
 get diagnostics v_exhausted=row_count;
 update pipeline.jobs set status='queued',started_at=null,error_text=coalesce(error_text,'')||case when coalesce(error_text,'')='' then '' else '; ' end||'stale scoped Scholarship dispatch lease recovered',payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object('lease_recovered_at',p_now)
 where job_type='scholarship_scope_acquisition' and domain='scholarship' and status='running' and started_at<p_now-interval '10 minutes' and coalesce(attempt_count,0)<3;
 get diagnostics v_recovered=row_count;
 if not p_dispatch then return jsonb_build_object('ok',true,'dispatch_enabled',false,'recovered',v_recovered,'retry_exhausted',v_exhausted,'dispatched',0,'failed',0);end if;
 for r in select id from pipeline.jobs where job_type='scholarship_scope_acquisition' and domain='scholarship' and status='queued' and coalesce(attempt_count,0)<3 order by created_at limit greatest(1,least(coalesce(p_limit,5),20)) for update skip locked loop
  begin
   update pipeline.jobs set status='running',started_at=p_now,attempt_count=coalesce(attempt_count,0)+1,error_text=null where id=r.id;
   select pipeline.svc_pilot_invoke_layer2('scholarship-scope-job-execute',jsonb_build_object('job_id',r.id,'scheduler','scholarship_scope_scheduler')) into v_request;
   update pipeline.jobs set payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object('dispatch_request_id',v_request,'dispatched_at',p_now,'scheduler','scholarship_scope_scheduler') where id=r.id;
   v_dispatched:=v_dispatched+1;
  exception when others then
   v_failed:=v_failed+1;
   update pipeline.jobs set status='queued',started_at=null,error_text=sqlerrm where id=r.id;
  end;
 end loop;
 return jsonb_build_object('ok',true,'dispatch_enabled',true,'recovered',v_recovered,'retry_exhausted',v_exhausted,'dispatched',v_dispatched,'failed',v_failed);
end $$;

create or replace function public.scholarship_scope_job_mark(p_job_id uuid,p_status text,p_result jsonb default null,p_error text default null,p_execution jsonb default null)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','pipeline' as $$
declare v_request_id uuid;v_remaining integer:=0;v_failed integer:=0;
begin
 if current_user not in('service_role','postgres') then raise exception 'service_role required' using errcode='42501';end if;
 if p_status not in('running','succeeded','failed') then raise exception 'invalid status' using errcode='22023';end if;
 update pipeline.jobs set status=p_status,
   started_at=case when p_status='running' then coalesce(started_at,now()) else started_at end,
   completed_at=case when p_status in('succeeded','failed') then now() else null end,
   result=case when p_result is null then result else p_result end,
   error_text=p_error,
   source_id=coalesce(nullif(p_execution->>'source_id','')::uuid,source_id),
   source_profile_version_id=coalesce(nullif(p_execution->>'profile_version_id','')::uuid,source_profile_version_id),
   payload=coalesce(payload,'{}'::jsonb)||coalesce(p_execution,'{}'::jsonb)
 where id=p_job_id and job_type='scholarship_scope_acquisition' and domain='scholarship'
 returning nullif(payload->>'request_id','')::uuid into v_request_id;
 if not found then raise exception 'scope job not found' using errcode='P0002';end if;
 if p_status in('succeeded','failed') and v_request_id is not null then
   select count(*) filter(where status in('queued','running')),count(*) filter(where status='failed') into v_remaining,v_failed
   from pipeline.jobs where domain='scholarship' and job_type='scholarship_scope_acquisition' and payload->>'request_id'=v_request_id::text;
   if v_remaining=0 then
     update pipeline.scholarship_scope_acquisition_requests
     set status=case when v_failed>0 then 'completed_with_errors' else 'completed' end,completed_at=now(),metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('failed_jobs',v_failed,'rollup_completed_at',now())
     where id=v_request_id;
   end if;
 end if;
 return jsonb_build_object('ok',true,'job_id',p_job_id,'status',p_status,'request_id',v_request_id);
end $$;