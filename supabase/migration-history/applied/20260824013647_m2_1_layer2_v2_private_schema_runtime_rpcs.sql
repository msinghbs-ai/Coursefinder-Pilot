create or replace function public.layer2_runtime_context(p_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,security,pipeline
as $$
declare v pipeline.layer2_source_profiles%rowtype; vv pipeline.layer2_source_profile_versions%rowtype; vr jsonb;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  select * into v from pipeline.layer2_source_profiles where id=p_profile_id;
  if not found or not v.enabled or v.paused or v.domain not in ('course_facts','scholarship') then return null; end if;
  select * into vv from pipeline.layer2_source_profile_versions where id=v.current_version_id;
  if not found or vv.validation_status<>'valid' then return null; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'provider_id',r.acquisition_provider_id,'priority',r.priority,'required_capabilities',r.required_capabilities,'request_overrides',r.request_overrides,'evidence_policy',r.evidence_policy,'fallback_on',r.fallback_on) order by r.priority),'[]'::jsonb)
    into vr from pipeline.layer2_profile_provider_routes r where r.profile_id=v.id and r.enabled;
  return jsonb_build_object('profile_id',v.id,'profile_key',v.profile_key,'domain',v.domain,'source_id',v.source_id,'version_id',vv.id,'version_no',vv.version_no,'configuration',vv.configuration,'routes',vr);
end $$;
revoke all on function public.layer2_runtime_context(uuid) from public,anon,authenticated;
grant execute on function public.layer2_runtime_context(uuid) to service_role;

create or replace function public.layer2_runtime_job_mark(p_job_id uuid,p_status text,p_payload jsonb default null,p_result jsonb default null,p_error text default null,p_attempt_count integer default null)
returns void language plpgsql security definer set search_path=pg_catalog,public,pipeline as $$
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 update pipeline.jobs set status=p_status,
   started_at=case when p_status='running' then coalesce(started_at,now()) else started_at end,
   completed_at=case when p_status in ('succeeded','failed','cancelled') then now() else completed_at end,
   payload=coalesce(p_payload,payload),result=coalesce(p_result,result),error_text=p_error,
   attempt_count=coalesce(p_attempt_count,attempt_count)
 where id=p_job_id;
end $$;
revoke all on function public.layer2_runtime_job_mark(uuid,text,jsonb,jsonb,text,integer) from public,anon,authenticated;
grant execute on function public.layer2_runtime_job_mark(uuid,text,jsonb,jsonb,text,integer) to service_role;

create or replace function public.layer2_attempt_runtime_set(p_attempt_id uuid,p_runtime jsonb)
returns void language plpgsql security definer set search_path=pg_catalog,public,pipeline as $$
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 update pipeline.layer2_provider_attempts set runtime_platform=p_runtime->>'platform',runtime_region=p_runtime->>'region',runtime_execution_id=p_runtime->>'execution_id',runtime_deployment_id=p_runtime->>'deployment_id',egress_identity=p_runtime->>'egress_identity' where id=p_attempt_id;
end $$;
revoke all on function public.layer2_attempt_runtime_set(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.layer2_attempt_runtime_set(uuid,jsonb) to service_role;

create or replace function public.layer2_evidence_capture(
 p_source_id uuid,p_job_id uuid,p_evidence_type text,p_source_url text,p_storage_path text,p_content_hash text,p_mime_type text,p_profile_version_id uuid,p_group_key text,p_retention_class text,p_retain_until timestamptz,p_metadata jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pipeline as $$
declare prev pipeline.evidence_artifacts%rowtype; v_id uuid; v_cap integer; v_changed boolean; v_now timestamptz:=now();
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select * into prev from pipeline.evidence_artifacts where evidence_group_key=p_group_key order by capture_version desc limit 1 for update;
 v_cap:=coalesce(prev.capture_version,0)+1; v_changed:=prev.id is null or prev.content_hash is distinct from p_content_hash;
 if prev.id is not null then update pipeline.evidence_artifacts set valid_to=v_now where id=prev.id; end if;
 insert into pipeline.evidence_artifacts(source_id,job_id,evidence_type,source_url,storage_path,content_hash,mime_type,captured_at,valid_from,supersedes_evidence_id,source_profile_version_id,retention_class,retain_until,review_state,capture_version,evidence_group_key,metadata)
 values(p_source_id,p_job_id,p_evidence_type,p_source_url,p_storage_path,p_content_hash,p_mime_type,v_now,v_now,prev.id,p_profile_version_id,coalesce(p_retention_class,'standard_365'),p_retain_until,'unreviewed',v_cap,p_group_key,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('content_changed',v_changed)) returning id into v_id;
 return jsonb_build_object('evidence_id',v_id,'capture_version',v_cap,'content_changed',v_changed,'supersedes_evidence_id',prev.id);
end $$;
revoke all on function public.layer2_evidence_capture(uuid,uuid,text,text,text,text,text,uuid,text,text,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.layer2_evidence_capture(uuid,uuid,text,text,text,text,text,uuid,text,text,timestamptz,jsonb) to service_role;

notify pgrst,'reload schema';
