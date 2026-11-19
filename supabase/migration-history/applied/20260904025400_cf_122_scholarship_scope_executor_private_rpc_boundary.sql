create or replace function public.scholarship_scope_job_execution_context(p_job_id uuid)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','pipeline','catalogue'
as $$
declare v_job record;v_profile record;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501';end if;
 select * into v_job from pipeline.jobs where id=p_job_id and job_type='scholarship_scope_acquisition' and domain='scholarship';
 if not found then return null;end if;
 select sp.id profile_id,sp.current_version_id,sp.profile_key,sp.source_id,s.url target_url,s.trust_rank
 into v_profile
 from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id
 where s.provider_id=v_job.provider_id and s.status='active' and sp.domain='scholarship' and sp.acquisition_method='scholarship_catalogue' and sp.enabled and not sp.paused and sp.current_version_id is not null
 order by case when sp.profile_key like 'au-scholarship-entry-%' then 0 else 1 end,s.trust_rank desc nulls last,sp.updated_at desc limit 1;
 return jsonb_build_object('job_id',v_job.id,'provider_id',v_job.provider_id,'status',v_job.status,'payload',coalesce(v_job.payload,'{}'::jsonb),'profile_id',v_profile.profile_id,'profile_version_id',v_profile.current_version_id,'profile_key',v_profile.profile_key,'source_id',v_profile.source_id,'target_url',v_profile.target_url);
end $$;
revoke all on function public.scholarship_scope_job_execution_context(uuid) from public,anon,authenticated;
grant execute on function public.scholarship_scope_job_execution_context(uuid) to service_role;

create or replace function public.scholarship_scope_job_mark(p_job_id uuid,p_status text,p_result jsonb default null,p_error text default null,p_execution jsonb default null)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','pipeline'
as $$
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501';end if;
 if p_status not in ('running','succeeded','failed') then raise exception 'invalid status' using errcode='22023';end if;
 update pipeline.jobs set status=p_status,
   started_at=case when p_status='running' then coalesce(started_at,now()) else started_at end,
   completed_at=case when p_status in ('succeeded','failed') then now() else null end,
   result=case when p_result is null then result else p_result end,
   error_text=p_error,
   source_id=coalesce(nullif(p_execution->>'source_id','')::uuid,source_id),
   source_profile_version_id=coalesce(nullif(p_execution->>'profile_version_id','')::uuid,source_profile_version_id),
   payload=coalesce(payload,'{}'::jsonb)||coalesce(p_execution,'{}'::jsonb)
 where id=p_job_id and job_type='scholarship_scope_acquisition' and domain='scholarship';
 if not found then raise exception 'scope job not found' using errcode='P0002';end if;
 return jsonb_build_object('ok',true,'job_id',p_job_id,'status',p_status);
end $$;
revoke all on function public.scholarship_scope_job_mark(uuid,text,jsonb,text,jsonb) from public,anon,authenticated;
grant execute on function public.scholarship_scope_job_mark(uuid,text,jsonb,text,jsonb) to service_role;
