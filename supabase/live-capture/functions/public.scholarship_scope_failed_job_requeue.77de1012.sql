CREATE OR REPLACE FUNCTION public.scholarship_scope_failed_job_requeue(p_job_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline'
AS $function$
declare v_job record;
begin
 if current_user not in('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select * into v_job from pipeline.jobs where id=p_job_id and domain='scholarship' and job_type='scholarship_scope_acquisition';
 if not found then return jsonb_build_object('ok',false,'reason','job_not_found'); end if;
 if v_job.status<>'failed' then return jsonb_build_object('ok',false,'reason','job_not_failed','status',v_job.status); end if;
 update pipeline.jobs set status='queued',started_at=null,completed_at=null,error_text=null,result='{}'::jsonb where id=p_job_id;
 return jsonb_build_object('ok',true,'job_id',p_job_id,'status','queued');
end $function$
