create or replace function public.layer2_course_candidate_record(p_source_id uuid,p_source_record_id text,p_source_url text,p_provider_cricos text,p_course_cricos text,p_content_hash text,p_evidence_id uuid,p_payload jsonb,p_status text,p_error text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public,pipeline as $$
declare v_id uuid;v_status text;v_payload jsonb;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 if nullif(trim(p_provider_cricos),'') is null then raise exception 'provider_cricos required'; end if;
 v_status:=case when p_status in ('observed','applied','rejected','error') then p_status else 'observed' end;
 v_payload:=coalesce(p_payload,'{}'::jsonb)||jsonb_build_object('source_record_resolution_status',coalesce(nullif(p_status,''),'observed'));
 insert into pipeline.course_fact_source_records(source_id,source_record_id,source_url,provider_cricos,course_cricos,content_hash,evidence_id,parsed_payload,status,observed_at,error_text)
 values(p_source_id,p_source_record_id,p_source_url,p_provider_cricos,p_course_cricos,p_content_hash,p_evidence_id,v_payload,v_status,now(),p_error)
 on conflict do nothing returning id into v_id;
 if v_id is null then select id into v_id from pipeline.course_fact_source_records where source_id=p_source_id and source_record_id=p_source_record_id order by observed_at desc limit 1; end if;
 return v_id;
end $$;
revoke all on function public.layer2_course_candidate_record(uuid,text,text,text,text,text,uuid,jsonb,text,text) from public,anon,authenticated;
grant execute on function public.layer2_course_candidate_record(uuid,text,text,text,text,text,uuid,jsonb,text,text) to service_role;
notify pgrst,'reload schema';
