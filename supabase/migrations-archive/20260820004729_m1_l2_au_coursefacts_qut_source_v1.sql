begin;
insert into integration.systems(code,name,system_type,base_url,status,config)
values('au_qut_course_pages','Queensland University of Technology official course pages','provider_course_pages','https://www.qut.edu.au','active',jsonb_build_object('country_code','AU','provider_cricos','00213J','identity_mapping','exact_cricos_course_code'))
on conflict(code) do update set name=excluded.name,system_type=excluded.system_type,base_url=excluded.base_url,status='active',config=integration.systems.config||excluded.config,updated_at=now();
insert into pipeline.sources(source_type,system_id,provider_id,country_id,url,label,trust_rank,status,metadata)
select 'provider_course_page',sys.id,p.id,p.country_id,'https://www.qut.edu.au/courses','Queensland University of Technology official course pages',95,'active',jsonb_build_object('facts',jsonb_build_array('course_link','international_fee','intake','english_requirement'),'course_identity','exact_cricos_course_code','provider_cricos','00213J')
from integration.systems sys join catalogue.providers p on p.stable_key='provider:cricos:00213j'
where sys.code='au_qut_course_pages' and not exists(select 1 from pipeline.sources s where s.system_id=sys.id and s.provider_id=p.id and s.status='active');
insert into pipeline.course_fact_source_qualifications(country_id,source_id,source_key,authority_name,source_class,provider_cricos,mapping_strategy,evidence_strategy,qualification_status,admitted_domains,notes,metadata)
select p.country_id,s.id,'au_qut_official_course_pages','Queensland University of Technology','provider_owned_course_pages','00213J','exact_provider_cricos_plus_course_cricos','fresh_html_snapshot_sha256','bounded',array['official_course_url','international_fee','intake','english_requirement']::text[],'Third AU Provider source class; bounded qualification required before source-class acceptance.',jsonb_build_object('gate','M1-L2-AU-COURSE-FACTS','worker','coursefacts-au-qut','apply_admitted',true,'search_admitted',false,'identity_authority',false,'source_class_uat','pending')
from pipeline.sources s join catalogue.providers p on p.id=s.provider_id join integration.systems sys on sys.id=s.system_id and sys.code='au_qut_course_pages'
on conflict(source_key) do update set source_id=excluded.source_id,qualification_status='bounded',admitted_domains=excluded.admitted_domains,notes=excluded.notes,metadata=pipeline.course_fact_source_qualifications.metadata||excluded.metadata,updated_at=now();
create or replace function pipeline.svc_pilot_submit_nonce(p_function text,p_body jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path to 'pipeline','net','public','extensions' as $$
declare v_nonce uuid:=extensions.gen_random_uuid(); v_id bigint;
begin
 if p_function not in ('layer1-ca-niagara-catalogue','qilt-au-etl','prisms-au-etl','layer1-au-depth','layer1-au-completeness','coursefacts-au-rmit','coursefacts-au-uq','coursefacts-au-qut','layer1-au-cricos-facts') then raise exception 'one-time Pilot Edge function is not allowlisted'; end if;
 insert into pipeline.pilot_edge_nonces(id,function_name,expires_at) values(v_nonce,p_function,now()+interval '2 minutes');
 select net.http_post(url:='https://fxcwkweaxjtknorudmwp.supabase.co/functions/v1/'||p_function,headers:=jsonb_build_object('content-type','application/json','x-cf-run-nonce',v_nonce::text),body:=coalesce(p_body,'{}'::jsonb),timeout_milliseconds:=120000) into v_id;
 return v_id;
end $$;
revoke all on function pipeline.svc_pilot_submit_nonce(text,jsonb) from public,anon,authenticated;
grant execute on function pipeline.svc_pilot_submit_nonce(text,jsonb) to service_role;
commit;
