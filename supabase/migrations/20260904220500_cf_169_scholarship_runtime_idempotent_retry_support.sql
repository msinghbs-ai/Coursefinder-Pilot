create or replace function public.scholarship_scope_failed_job_requeue(p_job_id uuid)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','pipeline' as $$
declare v_job record;
begin
 if current_user not in('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select * into v_job from pipeline.jobs where id=p_job_id and domain='scholarship' and job_type='scholarship_scope_acquisition';
 if not found then return jsonb_build_object('ok',false,'reason','job_not_found'); end if;
 if v_job.status<>'failed' then return jsonb_build_object('ok',false,'reason','job_not_failed','status',v_job.status); end if;
 update pipeline.jobs set status='queued',started_at=null,completed_at=null,error_text=null,result='{}'::jsonb where id=p_job_id;
 return jsonb_build_object('ok',true,'job_id',p_job_id,'status','queued');
end $$;
revoke all on function public.scholarship_scope_failed_job_requeue(uuid) from public,anon,authenticated;
grant execute on function public.scholarship_scope_failed_job_requeue(uuid) to service_role;

-- scholarship_candidate_mark_catalogue(uuid,text) was introduced by the preceding catalogue-skip runtime change and is reused by worker v5.
