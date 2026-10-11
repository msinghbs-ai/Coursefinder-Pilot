CREATE OR REPLACE FUNCTION public.scholarship_scope_job_execution_context(p_job_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'catalogue'
AS $function$
declare
  v_job record;
  v_profile record;
  v_requested_profile uuid;
  v_requested_url text;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  select * into v_job from pipeline.jobs where id=p_job_id and job_type='scholarship_scope_acquisition' and domain='scholarship';
  if not found then return null; end if;
  begin v_requested_profile:=nullif(v_job.payload->>'profile_id','')::uuid; exception when others then v_requested_profile:=null; end;
  v_requested_url:=nullif(v_job.payload->>'target_url','');
  if v_requested_profile is not null then
    select sp.id profile_id,sp.current_version_id,sp.profile_key,sp.source_id,coalesce(v_requested_url,s.url) target_url,s.trust_rank into v_profile
    from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id
    where sp.id=v_requested_profile and s.provider_id=v_job.provider_id and s.status='active' and sp.domain='scholarship' and sp.enabled and not sp.paused and sp.current_version_id is not null limit 1;
  else
    select sp.id profile_id,sp.current_version_id,sp.profile_key,sp.source_id,s.url target_url,s.trust_rank into v_profile
    from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id
    where s.provider_id=v_job.provider_id and s.status='active' and sp.domain='scholarship' and sp.acquisition_method='scholarship_catalogue' and sp.enabled and not sp.paused and sp.current_version_id is not null
    order by case when sp.profile_key like 'au-scholarship-entry-%' then 0 else 1 end,s.trust_rank desc nulls last,sp.updated_at desc limit 1;
  end if;
  return jsonb_build_object('job_id',v_job.id,'provider_id',v_job.provider_id,'status',v_job.status,'payload',coalesce(v_job.payload,'{}'::jsonb),'result',coalesce(v_job.result,'{}'::jsonb),'profile_id',v_profile.profile_id,'profile_version_id',v_profile.current_version_id,'profile_key',v_profile.profile_key,'source_id',v_profile.source_id,'target_url',v_profile.target_url);
end
$function$
