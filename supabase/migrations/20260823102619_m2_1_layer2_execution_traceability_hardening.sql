-- M2.1 execution traceability hardening · CF-CHG-20260823-029
create or replace function security.layer2_assert_profile_executable(p_profile_id uuid)
returns uuid language plpgsql stable security definer set search_path='pg_catalog','security','pipeline' as $$
declare v_enabled boolean;v_paused boolean;v_version_id uuid;v_status text;
begin
 select p.enabled,p.paused,p.current_version_id,v.validation_status into v_enabled,v_paused,v_version_id,v_status from pipeline.layer2_source_profiles p left join pipeline.layer2_source_profile_versions v on v.id=p.current_version_id where p.id=p_profile_id;
 if not found then raise exception 'Layer 2 profile not found' using errcode='22023'; end if;
 if not v_enabled then raise exception 'Layer 2 profile is disabled' using errcode='55000'; end if;
 if v_paused then raise exception 'Layer 2 profile is paused' using errcode='55000'; end if;
 if v_version_id is null then raise exception 'Layer 2 profile has no current version' using errcode='55000'; end if;
 if v_status<>'valid' then raise exception 'Layer 2 profile current version is not valid' using errcode='55000'; end if;
 return v_version_id;
end $$;

create or replace function public.layer2_prepare_job(p_actor uuid,p_profile_id uuid,p_job_type text default 'layer2_acquisition')
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','security','pipeline' as $$
declare v_rank integer:=0;v_source_id uuid;v_provider_id uuid;v_domain text;v_version_id uuid;v_job_id uuid;
begin
 if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
 select coalesce(max(r.rank),0) into v_rank from security.user_roles ur join security.roles r on r.code=ur.role_code where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
 if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
 v_version_id:=security.layer2_assert_profile_executable(p_profile_id);
 select p.source_id,s.provider_id,p.domain into v_source_id,v_provider_id,v_domain from pipeline.layer2_source_profiles p join pipeline.sources s on s.id=p.source_id where p.id=p_profile_id;
 insert into pipeline.jobs(job_type,domain,source_id,provider_id,status,requested_by,payload,source_profile_version_id) values(coalesce(nullif(p_job_type,''),'layer2_acquisition'),v_domain,v_source_id,v_provider_id,'queued',p_actor,jsonb_build_object('layer','2','profile_id',p_profile_id,'configuration_version_id',v_version_id,'canonical_mutation_authorised',false),v_version_id) returning id into v_job_id;
 return jsonb_build_object('job_id',v_job_id,'source_id',v_source_id,'source_profile_version_id',v_version_id,'status','queued');
end $$;
revoke all on function public.layer2_prepare_job(uuid,uuid,text) from public,anon,authenticated;grant execute on function public.layer2_prepare_job(uuid,uuid,text) to service_role;

create or replace function pipeline.layer2_evidence_version_guard() returns trigger language plpgsql set search_path='pg_catalog','pipeline' as $$
declare v_job_version uuid;begin if new.job_id is not null then select source_profile_version_id into v_job_version from pipeline.jobs where id=new.job_id;if v_job_version is not null then if new.source_profile_version_id is null then new.source_profile_version_id:=v_job_version;elsif new.source_profile_version_id<>v_job_version then raise exception 'Evidence configuration version does not match Job configuration version' using errcode='23514';end if;end if;end if;return new;end $$;
drop trigger if exists layer2_evidence_version_guard on pipeline.evidence_artifacts;create trigger layer2_evidence_version_guard before insert or update of job_id,source_profile_version_id on pipeline.evidence_artifacts for each row execute function pipeline.layer2_evidence_version_guard();

create or replace function public.layer2_config_control(p_actor uuid,p_action text,p_profile_id uuid) returns jsonb language plpgsql security definer set search_path='pg_catalog','public','security','pipeline' as $$
declare v_rank integer:=0;v_version pipeline.layer2_source_profile_versions%rowtype;v_validation jsonb;begin
 if p_actor is null then raise exception 'actor required' using errcode='42501';end if;select coalesce(max(r.rank),0) into v_rank from security.user_roles ur join security.roles r on r.code=ur.role_code where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';if v_rank<6 then raise exception 'platform_admin role required' using errcode='42501';end if;
 if p_action='validate' then select v.* into v_version from pipeline.layer2_source_profiles p join pipeline.layer2_source_profile_versions v on v.id=p.current_version_id where p.id=p_profile_id for update of v;if v_version.id is null then raise exception 'profile/current version not found' using errcode='22023';end if;v_validation:=security.layer2_validate_profile_config(v_version.configuration);update pipeline.layer2_source_profile_versions set validation_result=v_validation,validation_status=case when (v_validation->>'valid')::boolean then 'valid' else 'invalid' end where id=v_version.id;elsif p_action='pause' then update pipeline.layer2_source_profiles set paused=true,updated_at=now() where id=p_profile_id;elsif p_action='resume' then update pipeline.layer2_source_profiles set paused=false,updated_at=now() where id=p_profile_id;elsif p_action='disable' then update pipeline.layer2_source_profiles set enabled=false,paused=true,updated_at=now() where id=p_profile_id;elsif p_action='enable' then update pipeline.layer2_source_profiles set enabled=true,paused=false,updated_at=now() where id=p_profile_id;else raise exception 'unsupported action' using errcode='22023';end if;if not found and p_action<>'validate' then raise exception 'profile not found' using errcode='22023';end if;return jsonb_build_object('ok',true,'profile_id',p_profile_id,'action',p_action,'validation',v_validation);end $$;
revoke all on function public.layer2_config_control(uuid,text,uuid) from public,anon,authenticated;grant execute on function public.layer2_config_control(uuid,text,uuid) to service_role;