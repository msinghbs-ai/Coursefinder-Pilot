create or replace function public.layer2_provider_runtime_config(p_provider_id uuid)
returns jsonb language sql security definer set search_path='pg_catalog','public','pipeline','vault' as $$
 select jsonb_build_object('id',p.id,'provider_key',p.provider_key,'display_name',p.display_name,'adapter_type',p.adapter_type,'base_url',p.base_url,'auth_scheme',p.auth_scheme,'auth_field_name',p.auth_field_name,'secret',ds.decrypted_secret,'capabilities',p.capabilities,'request_template',p.request_template,'enabled',p.enabled,'rate_limit_per_minute',p.rate_limit_per_minute,'concurrency',p.concurrency,'timeout_seconds',p.timeout_seconds)
 from pipeline.layer2_acquisition_providers p left join vault.decrypted_secrets ds on ds.id=p.vault_secret_id where p.id=p_provider_id
$$;
revoke all on function public.layer2_provider_runtime_config(uuid) from public,anon,authenticated;
grant execute on function public.layer2_provider_runtime_config(uuid) to service_role;

create or replace function public.layer2_provider_attempt_start(p_job_id uuid,p_provider_id uuid,p_request_url text)
returns uuid language plpgsql security definer set search_path='pg_catalog','pipeline','public' as $$
declare v_version uuid;v_attempt int;v_id uuid;begin
 select source_profile_version_id into v_version from pipeline.jobs where id=p_job_id;if v_version is null then raise exception 'versioned Layer 2 job required' using errcode='22023';end if;
 select coalesce(max(attempt_no),0)+1 into v_attempt from pipeline.layer2_provider_attempts where job_id=p_job_id;
 insert into pipeline.layer2_provider_attempts(job_id,profile_version_id,acquisition_provider_id,attempt_no,status,request_url,started_at) values(p_job_id,v_version,p_provider_id,v_attempt,'running',p_request_url,now()) returning id into v_id;return v_id;end$$;
revoke all on function public.layer2_provider_attempt_start(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.layer2_provider_attempt_start(uuid,uuid,text) to service_role;

create or replace function public.layer2_provider_attempt_finish(p_attempt_id uuid,p_status text,p_http_status int,p_mime text,p_raw_evidence uuid,p_html_evidence uuid,p_screenshot_evidence uuid,p_extraction_status text,p_blocker text,p_metrics jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path='pg_catalog','pipeline','public' as $$begin
 if p_status not in ('succeeded','failed','blocked','extraction_failed') then raise exception 'invalid attempt status' using errcode='22023';end if;
 update pipeline.layer2_provider_attempts set status=p_status,response_http_status=p_http_status,response_mime_type=p_mime,raw_evidence_id=p_raw_evidence,html_evidence_id=p_html_evidence,screenshot_evidence_id=p_screenshot_evidence,extraction_status=p_extraction_status,blocker=p_blocker,metrics=coalesce(p_metrics,'{}'::jsonb),completed_at=now() where id=p_attempt_id;
end$$;
revoke all on function public.layer2_provider_attempt_finish(uuid,text,int,text,uuid,uuid,uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.layer2_provider_attempt_finish(uuid,text,int,text,uuid,uuid,uuid,text,text,jsonb) to service_role;
