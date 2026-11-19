create or replace function public.svc_layer2a_resolve_sources(p_country_code text)
returns jsonb
language sql stable security definer
set search_path to 'public','pipeline','integration','ref'
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'source_id',s.id,'source_type',s.source_type,'source_label',s.label,'source_url',s.url,'trust_rank',s.trust_rank,
    'system_code',i.code,'system_name',i.name,'system_type',i.system_type,'system_base_url',i.base_url,'system_config',i.config,'source_metadata',s.metadata
  ) order by s.trust_rank,s.label),'[]'::jsonb)
  from ref.countries c
  join pipeline.sources s on s.country_id=c.id and s.provider_id is null and s.status='active' and s.source_type='structured_outcomes'
  left join integration.systems i on i.id=s.system_id
  where upper(c.iso_alpha2::text)=upper(p_country_code) and coalesce(i.status,'active')='active';
$$;

create or replace function public.svc_layer2a_start_job(p_country_code text,p_source_id uuid,p_payload jsonb default '{}'::jsonb)
returns uuid
language plpgsql security definer
set search_path to 'public','pipeline','ref'
as $$
declare v_id uuid; v_country uuid;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  select id into v_country from ref.countries where upper(iso_alpha2::text)=upper(p_country_code);
  if v_country is null then raise exception 'country missing: %',p_country_code; end if;
  insert into pipeline.jobs(job_type,domain,source_id,status,payload,result,started_at)
  values('layer2a_outcomes','outcomes',p_source_id,'running',coalesce(p_payload,'{}'::jsonb),'{}'::jsonb,now()) returning id into v_id;
  return v_id;
end $$;

create or replace function public.svc_layer2a_finish_job(p_job_id uuid,p_status text,p_result jsonb default '{}'::jsonb,p_error text default null)
returns void
language plpgsql security definer
set search_path to 'public','pipeline'
as $$
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  update pipeline.jobs set status=p_status,result=coalesce(p_result,'{}'::jsonb),error_text=p_error,completed_at=now() where id=p_job_id;
end $$;

create or replace function public.svc_layer2a_record_evidence(p_source_id uuid,p_job_id uuid,p_source_url text,p_storage_path text,p_content_hash text,p_mime_type text,p_metadata jsonb default '{}'::jsonb)
returns uuid
language plpgsql security definer
set search_path to 'public','pipeline'
as $$
declare v_id uuid;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.evidence_artifacts(source_id,job_id,evidence_type,source_url,storage_path,content_hash,mime_type,metadata)
  values(p_source_id,p_job_id,'layer2a_source_file',p_source_url,p_storage_path,p_content_hash,p_mime_type,coalesce(p_metadata,'{}'::jsonb)) returning id into v_id;
  return v_id;
end $$;

create or replace function public.svc_layer2a_source_health(p_source_id uuid,p_success boolean,p_error text default null,p_metadata jsonb default '{}'::jsonb)
returns void
language plpgsql security definer
set search_path to 'public','pipeline'
as $$
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  update pipeline.sources set last_checked_at=now(),last_success_at=case when p_success then now() else last_success_at end,last_failure_at=case when not p_success then now() else last_failure_at end,last_error=case when p_success then null else p_error end,metadata=coalesce(metadata,'{}'::jsonb)||coalesce(p_metadata,'{}'::jsonb),updated_at=now() where id=p_source_id;
end $$;

revoke all on function public.svc_layer2a_resolve_sources(text) from public,anon,authenticated;
revoke all on function public.svc_layer2a_start_job(text,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.svc_layer2a_finish_job(uuid,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.svc_layer2a_record_evidence(uuid,uuid,text,text,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.svc_layer2a_source_health(uuid,boolean,text,jsonb) from public,anon,authenticated;
grant execute on function public.svc_layer2a_resolve_sources(text) to service_role;
grant execute on function public.svc_layer2a_start_job(text,uuid,jsonb) to service_role;
grant execute on function public.svc_layer2a_finish_job(uuid,text,jsonb,text) to service_role;
grant execute on function public.svc_layer2a_record_evidence(uuid,uuid,text,text,text,text,jsonb) to service_role;
grant execute on function public.svc_layer2a_source_health(uuid,boolean,text,jsonb) to service_role;
