create or replace function public.scholarship_catalogue_shared_fetch_from_evidence(p_job_id uuid,p_evidence_id uuid)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','pipeline' as $$
declare v_job record;v_e record;v_profile uuid;v_url text;v_provider uuid;v_registered jsonb;
begin
 if current_user not in('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select * into v_job from pipeline.jobs where id=p_job_id and domain='scholarship' and job_type='scholarship_scope_acquisition';
 if not found then return jsonb_build_object('ok',false,'reason','job_not_found'); end if;
 if coalesce(v_job.payload->>'acquisition_stage','scholarship_catalogue')='first_party_detail' then return jsonb_build_object('ok',false,'reason','detail_job'); end if;
 begin v_profile:=nullif(v_job.payload->>'profile_id','')::uuid; exception when others then v_profile:=null; end;
 v_url:=nullif(v_job.payload->>'target_url','');
 select e.*,nullif(e.metadata->>'provider_id','')::uuid acquisition_provider_id into v_e from pipeline.evidence_artifacts e where e.id=p_evidence_id;
 if not found then return jsonb_build_object('ok',false,'reason','evidence_not_found'); end if;
 v_provider:=v_e.acquisition_provider_id;
 if v_profile is null or v_url is null or v_provider is null or v_e.content_hash is null then return jsonb_build_object('ok',false,'reason','incomplete_registration_context'); end if;
 select public.layer2_shared_fetch_register(v_url,p_evidence_id,v_e.content_hash,coalesce(v_e.mime_type,'text/html'),v_provider,v_profile,24) into v_registered;
 return jsonb_build_object('ok',true,'shared_fetch_id',v_registered->>'shared_fetch_id','registration',v_registered,'evidence_id',p_evidence_id,'source_url',v_url);
end $$;
revoke all on function public.scholarship_catalogue_shared_fetch_from_evidence(uuid,uuid) from public,anon,authenticated;
grant execute on function public.scholarship_catalogue_shared_fetch_from_evidence(uuid,uuid) to service_role;
comment on function public.scholarship_catalogue_shared_fetch_from_evidence(uuid,uuid) is 'CF-183 service-only bridge: registers successful Scholarship catalogue Evidence into the shared-fetch cache so catalogue fan-out occurs regardless of acquisition provider.';