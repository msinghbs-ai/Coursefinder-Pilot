create or replace function public.layer2_extraction_context(p_attempt_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,pipeline
as $$
declare a pipeline.layer2_provider_attempts%rowtype; p pipeline.layer2_acquisition_providers%rowtype; e pipeline.evidence_artifacts%rowtype; v_eid uuid;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select * into a from pipeline.layer2_provider_attempts where id=p_attempt_id;
 if not found then return null; end if;
 select * into p from pipeline.layer2_acquisition_providers where id=a.acquisition_provider_id;
 v_eid:=coalesce(a.raw_evidence_id,a.html_evidence_id,a.screenshot_evidence_id);
 if v_eid is null then return jsonb_build_object('attempt_id',a.id,'no_evidence',true); end if;
 select * into e from pipeline.evidence_artifacts where id=v_eid;
 return jsonb_build_object(
  'attempt_id',a.id,'job_id',a.job_id,'profile_version_id',a.profile_version_id,'provider_id',a.acquisition_provider_id,'provider_key',p.provider_key,'request_template',p.request_template,
  'raw_evidence_id',a.raw_evidence_id,'html_evidence_id',a.html_evidence_id,'screenshot_evidence_id',a.screenshot_evidence_id,
  'evidence_id',e.id,'source_id',e.source_id,'storage_path',e.storage_path,'mime_type',e.mime_type,'source_url',e.source_url,'source_profile_version_id',e.source_profile_version_id,'content_hash',e.content_hash,'retention_class',e.retention_class,'retain_until',e.retain_until
 );
end $$;
revoke all on function public.layer2_extraction_context(uuid) from public,anon,authenticated;
grant execute on function public.layer2_extraction_context(uuid) to service_role;

create or replace function public.layer2_attempt_normalisation_mark(p_attempt_id uuid,p_status text,p_blocker text,p_metrics jsonb)
returns void language plpgsql security definer set search_path=pg_catalog,public,pipeline as $$
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 update pipeline.layer2_provider_attempts set extraction_status=p_status,blocker=p_blocker,metrics=coalesce(metrics,'{}'::jsonb)||coalesce(p_metrics,'{}'::jsonb) where id=p_attempt_id;
end $$;
revoke all on function public.layer2_attempt_normalisation_mark(uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.layer2_attempt_normalisation_mark(uuid,text,text,jsonb) to service_role;

create or replace function public.layer2_course_extraction_context(p_evidence_id uuid,p_course_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,pipeline,catalogue
as $$
declare e pipeline.evidence_artifacts%rowtype; c catalogue.courses%rowtype;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select * into e from pipeline.evidence_artifacts where id=p_evidence_id;
 if not found or e.evidence_type<>'layer2_extraction_input' then return null; end if;
 select * into c from catalogue.courses where id=p_course_id;
 if not found then return null; end if;
 return jsonb_build_object('evidence',jsonb_build_object('id',e.id,'source_id',e.source_id,'job_id',e.job_id,'evidence_type',e.evidence_type,'source_url',e.source_url,'storage_path',e.storage_path,'content_hash',e.content_hash,'source_profile_version_id',e.source_profile_version_id,'retention_class',e.retention_class,'retain_until',e.retain_until),'course',jsonb_build_object('id',c.id,'provider_id',c.provider_id,'canonical_title',c.canonical_title,'display_title',c.display_title,'course_code',c.course_code,'stable_key',c.stable_key),'baseline_factual',pipeline.layer2_course_factual_snapshot(c.id));
end $$;
revoke all on function public.layer2_course_extraction_context(uuid,uuid) from public,anon,authenticated;
grant execute on function public.layer2_course_extraction_context(uuid,uuid) to service_role;

create or replace function public.layer2_course_candidate_record(p_source_id uuid,p_source_record_id text,p_source_url text,p_course_cricos text,p_content_hash text,p_evidence_id uuid,p_payload jsonb,p_status text,p_error text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public,pipeline as $$
declare v_id uuid;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 insert into pipeline.course_fact_source_records(source_id,source_record_id,source_url,provider_cricos,course_cricos,content_hash,evidence_id,parsed_payload,status,observed_at,error_text)
 values(p_source_id,p_source_record_id,p_source_url,null,p_course_cricos,p_content_hash,p_evidence_id,p_payload,p_status,now(),p_error)
 on conflict do nothing returning id into v_id;
 if v_id is null then select id into v_id from pipeline.course_fact_source_records where source_id=p_source_id and source_record_id=p_source_record_id order by observed_at desc limit 1; end if;
 return v_id;
end $$;
revoke all on function public.layer2_course_candidate_record(uuid,text,text,text,text,uuid,jsonb,text,text) from public,anon,authenticated;
grant execute on function public.layer2_course_candidate_record(uuid,text,text,text,text,uuid,jsonb,text,text) to service_role;

notify pgrst,'reload schema';
