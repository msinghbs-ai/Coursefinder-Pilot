create or replace function public.layer2_course_extraction_context(p_evidence_id uuid,p_course_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,pipeline,catalogue
as $$
declare e pipeline.evidence_artifacts%rowtype; c catalogue.courses%rowtype; v_provider_cricos text;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select * into e from pipeline.evidence_artifacts where id=p_evidence_id;
 if not found or e.evidence_type<>'layer2_extraction_input' then return null; end if;
 select * into c from catalogue.courses where id=p_course_id;
 if not found then return null; end if;
 select registration_code into v_provider_cricos from catalogue.provider_registrations where provider_id=c.provider_id and lower(registration_scheme)='cricos' order by (status='active') desc,checked_at desc nulls last limit 1;
 return jsonb_build_object('evidence',jsonb_build_object('id',e.id,'source_id',e.source_id,'job_id',e.job_id,'evidence_type',e.evidence_type,'source_url',e.source_url,'storage_path',e.storage_path,'content_hash',e.content_hash,'source_profile_version_id',e.source_profile_version_id,'retention_class',e.retention_class,'retain_until',e.retain_until),'course',jsonb_build_object('id',c.id,'provider_id',c.provider_id,'provider_cricos',v_provider_cricos,'canonical_title',c.canonical_title,'display_title',c.display_title,'course_code',c.course_code,'stable_key',c.stable_key),'baseline_factual',pipeline.layer2_course_factual_snapshot(c.id));
end $$;
revoke all on function public.layer2_course_extraction_context(uuid,uuid) from public,anon,authenticated;
grant execute on function public.layer2_course_extraction_context(uuid,uuid) to service_role;

create or replace function public.layer2_course_candidate_record(p_source_id uuid,p_source_record_id text,p_source_url text,p_provider_cricos text,p_course_cricos text,p_content_hash text,p_evidence_id uuid,p_payload jsonb,p_status text,p_error text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public,pipeline as $$
declare v_id uuid;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 if nullif(trim(p_provider_cricos),'') is null then raise exception 'provider_cricos required'; end if;
 insert into pipeline.course_fact_source_records(source_id,source_record_id,source_url,provider_cricos,course_cricos,content_hash,evidence_id,parsed_payload,status,observed_at,error_text)
 values(p_source_id,p_source_record_id,p_source_url,p_provider_cricos,p_course_cricos,p_content_hash,p_evidence_id,p_payload,p_status,now(),p_error)
 on conflict do nothing returning id into v_id;
 if v_id is null then select id into v_id from pipeline.course_fact_source_records where source_id=p_source_id and source_record_id=p_source_record_id order by observed_at desc limit 1; end if;
 return v_id;
end $$;
revoke all on function public.layer2_course_candidate_record(uuid,text,text,text,text,text,uuid,jsonb,text,text) from public,anon,authenticated;
grant execute on function public.layer2_course_candidate_record(uuid,text,text,text,text,text,uuid,jsonb,text,text) to service_role;
notify pgrst,'reload schema';
