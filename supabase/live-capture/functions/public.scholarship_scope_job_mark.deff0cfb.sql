CREATE OR REPLACE FUNCTION public.scholarship_scope_job_mark(p_job_id uuid, p_status text, p_result jsonb DEFAULT NULL::jsonb, p_error text DEFAULT NULL::text, p_execution jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline'
AS $function$
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
end $function$
