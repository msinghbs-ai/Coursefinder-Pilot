create or replace function pipeline.svc_pilot_invoke_layer2(p_function text, p_body jsonb default '{}'::jsonb)
returns bigint
language plpgsql security definer
set search_path='pipeline','vault','net','public'
as $$
declare v_key text;v_id bigint;v_base text;
begin
 if p_function not in(
   'layer2-acquire-v2','layer2-extract-v2','layer2-course-fact-extract-v2','layer2-scholarship-extract',
   'layer2-scholarship-catalogue-enumerate','layer2-provider-page-fanout','layer2-provider-asset-promote',
   'layer2-hotcourses-directory-parse','scholarship-scope-job-execute'
 ) then raise exception 'Layer2 automation function not allowlisted';end if;
 v_key:=public.coursefinder_runtime_automation_key();v_base:=public.coursefinder_runtime_edge_base_url();
 if v_key is null then raise exception 'runtime automation secret missing';end if;
 if v_base is null then raise exception 'runtime Edge base URL missing';end if;
 select net.http_post(url:=rtrim(v_base,'/')||'/'||p_function,headers:=jsonb_build_object('content-type','application/json','x-cf-pilot-key',v_key),body:=coalesce(p_body,'{}'::jsonb),timeout_milliseconds:=120000) into v_id;
 return v_id;
end $$;

create or replace function security.scholarship_scope_scheduler_tick_impl(p_now timestamptz default now(),p_limit integer default 5,p_dispatch boolean default true)
returns jsonb
language plpgsql security definer
set search_path='pg_catalog','security','pipeline','public'
as $$
declare r record;v_dispatched int:=0;v_failed int:=0;v_recovered int:=0;v_request bigint;
begin
 update pipeline.jobs set status='queued',started_at=null,error_text=coalesce(error_text,'')||case when coalesce(error_text,'')='' then '' else '; ' end||'stale scoped Scholarship dispatch lease recovered',payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object('lease_recovered_at',p_now)
 where job_type='scholarship_scope_acquisition' and domain='scholarship' and status='running' and started_at<p_now-interval '30 minutes';
 get diagnostics v_recovered=row_count;
 if not p_dispatch then return jsonb_build_object('ok',true,'dispatch_enabled',false,'recovered',v_recovered,'dispatched',0,'failed',0);end if;
 for r in select id from pipeline.jobs where job_type='scholarship_scope_acquisition' and domain='scholarship' and status='queued' order by created_at limit greatest(1,least(coalesce(p_limit,5),20)) for update skip locked loop
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
 return jsonb_build_object('ok',true,'dispatch_enabled',true,'recovered',v_recovered,'dispatched',v_dispatched,'failed',v_failed);
end $$;
