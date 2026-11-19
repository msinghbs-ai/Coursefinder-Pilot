insert into ref.outcome_metrics(survey_id,code,name,category,unit,higher_is_better,description,status)
select s.id,v.code,v.name,v.category,v.unit,true,v.description,'active'
from ref.outcome_surveys s
join (values
 ('qilt_gos','fte','Full-time employment','employment','percent','Published institution outcome; source confidence interval retained when available.'),
 ('qilt_gos','oe','Overall employment','employment','percent','Published institution outcome; source confidence interval retained when available.'),
 ('qilt_gos','lf','Labour force participation rate','employment','percent','Published institution outcome; source confidence interval retained when available.'),
 ('qilt_gos','salary','Median annual full-time salaries','salary','AUD','Published institution median salary in Australian dollars.'),
 ('qilt_ses','skills_development','Skills Development','experience','percent','Published positive-rating indicator.'),
 ('qilt_ses','peer_engagement','Peer Engagement','experience','percent','Published positive-rating indicator.'),
 ('qilt_ses','teaching_quality_engagement','Teaching Quality and Engagement','experience','percent','Published positive-rating indicator.'),
 ('qilt_ses','student_support_services','Student Support and Services','experience','percent','Published positive-rating indicator.'),
 ('qilt_ses','learning_resources','Learning Resources','experience','percent','Published positive-rating indicator.'),
 ('qilt_ses','overall_educational_experience','Quality of entire educational experience','experience','percent','Published positive-rating indicator.'),
 ('qilt_gosl','medium_fte','Medium-term full-time employment','employment','percent','Published medium-term domestic outcome from GOS-L.'),
 ('qilt_gosl','medium_oe','Medium-term overall employment','employment','percent','Published medium-term domestic outcome from GOS-L.'),
 ('qilt_gosl','medium_salary','Medium-term median salary','salary','AUD','Published medium-term domestic median salary from GOS-L.'),
 ('qilt_ess','foundation_skills','Foundation skills','employer_satisfaction','percent','Published employer satisfaction with graduate foundation skills.'),
 ('qilt_ess','adaptive_skills','Adaptive skills','employer_satisfaction','percent','Published employer satisfaction with graduate adaptive skills.'),
 ('qilt_ess','collaborative_skills','Collaborative skills','employer_satisfaction','percent','Published employer satisfaction with graduate collaborative skills.'),
 ('qilt_ess','technical_skills','Technical skills','employer_satisfaction','percent','Published employer satisfaction with graduate technical skills.'),
 ('qilt_ess','employability_skills','Employability skills','employer_satisfaction','percent','Published employer satisfaction with graduate employability skills.'),
 ('qilt_ess','overall_satisfaction','Overall satisfaction','employer_satisfaction','percent','Published employer overall satisfaction.')
) as v(survey_code,code,name,category,unit,description) on v.survey_code=s.code
on conflict (survey_id,code) do update set
 name=excluded.name,category=excluded.category,unit=excluded.unit,higher_is_better=excluded.higher_is_better,
 description=excluded.description,status='active',updated_at=now();

create or replace function public.svc_qilt_context(p_survey_code text)
returns jsonb
language sql
security definer
set search_path='catalogue','ref','public','extensions'
as $function$
with survey as (
 select id,code from ref.outcome_surveys where code=p_survey_code and source_family='QILT' and status='active'
), metrics as (
 select coalesce(jsonb_object_agg(m.code,m.id),'{}'::jsonb) j
 from ref.outcome_metrics m join survey s on s.id=m.survey_id where m.status='active'
), au as (
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'stable_key',p.stable_key,'canonical_name',p.canonical_name,'display_name',p.display_name) order by p.stable_key),'[]'::jsonb) j
 from catalogue.providers p join ref.countries c on c.id=p.country_id where c.iso_alpha2='AU'
)
select jsonb_build_object('survey_id',(select id from survey),'metric_ids',(select j from metrics),'providers',(select j from au));
$function$;

create or replace function public.svc_qilt_prepare_source(p_survey_code text,p_label text,p_url text,p_collection_version integer)
returns uuid
language plpgsql
security definer
set search_path='pipeline','ref','public','extensions'
as $function$
declare v_id uuid; v_country uuid;
begin
 if not exists(select 1 from ref.outcome_surveys where code=p_survey_code and source_family='QILT') then raise exception 'invalid QILT survey'; end if;
 select id into v_country from ref.countries where iso_alpha2='AU';
 select id into v_id from pipeline.sources where label=p_label and url=p_url limit 1;
 if v_id is null then
  insert into pipeline.sources(source_type,country_id,url,label,trust_rank,status,metadata)
  values('structured_outcomes',v_country,p_url,p_label,95,'active',jsonb_build_object('layer','2A','publisher','QILT','survey_code',p_survey_code,'collection_version',p_collection_version,'identity_authority',false))
  returning id into v_id;
 else
  update pipeline.sources set source_type='structured_outcomes',country_id=v_country,trust_rank=95,status='active',
   metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('layer','2A','publisher','QILT','survey_code',p_survey_code,'collection_version',p_collection_version,'identity_authority',false),updated_at=now()
  where id=v_id;
 end if;
 return v_id;
end $function$;

create or replace function public.svc_qilt_register_evidence(p_source_id uuid,p_source_url text,p_storage_path text,p_content_hash text,p_survey_code text,p_collection_version integer,p_worker_version text)
returns uuid
language plpgsql
security definer
set search_path='pipeline','public','extensions'
as $function$
declare v_id uuid;
begin
 select id into v_id from pipeline.evidence_artifacts
 where source_id=p_source_id and evidence_type='qilt_source_zip' and content_hash=p_content_hash
 order by captured_at desc limit 1;
 if v_id is null then
  insert into pipeline.evidence_artifacts(source_id,evidence_type,source_url,storage_path,content_hash,mime_type,metadata)
  values(p_source_id,'qilt_source_zip',p_source_url,p_storage_path,p_content_hash,'application/zip',
   jsonb_build_object('layer','2A','publisher','QILT','survey_code',p_survey_code,'collection_version',p_collection_version,'worker_version',p_worker_version))
  returning id into v_id;
 end if;
 return v_id;
end $function$;

create or replace function public.svc_qilt_upsert_mappings(p_source_id uuid,p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path='pipeline','catalogue','ref','public','extensions'
as $function$
declare r jsonb; v_count int:=0;
begin
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>3000 then raise exception 'bounded mapping array required'; end if;
 for r in select value from jsonb_array_elements(p_rows) loop
  if nullif(r->>'provider_id','') is not null and not exists(
   select 1 from catalogue.providers p join ref.countries c on c.id=p.country_id
   where p.id=(r->>'provider_id')::uuid and c.iso_alpha2='AU'
  ) then raise exception 'mapping target must be existing AU CRICOS provider'; end if;
  insert into pipeline.source_provider_mappings(source_id,source_entity_key,source_entity_name,provider_id,match_method,match_confidence,status,verified_at,metadata)
  values(p_source_id,r->>'source_entity_key',r->>'source_entity_name',nullif(r->>'provider_id','')::uuid,
   coalesce(nullif(r->>'match_method',''),'unmatched'),nullif(r->>'match_confidence','')::numeric,
   coalesce(nullif(r->>'status',''),'unmatched'),nullif(r->>'verified_at','')::timestamptz,coalesce(r->'metadata','{}'::jsonb))
  on conflict(source_id,source_entity_key) do update set
   source_entity_name=excluded.source_entity_name,provider_id=excluded.provider_id,match_method=excluded.match_method,
   match_confidence=excluded.match_confidence,status=excluded.status,verified_at=excluded.verified_at,metadata=excluded.metadata,updated_at=now();
  v_count:=v_count+1;
 end loop;
 return jsonb_build_object('seen',v_count);
end $function$;

create or replace function public.svc_qilt_apply_observations(p_rows jsonb)
returns jsonb
language sql
security definer
set search_path='pipeline','public'
as $function$ select pipeline.svc_qilt_apply_observations(p_rows); $function$;

create or replace function public.svc_qilt_touch_source(p_source_id uuid,p_ok boolean,p_error text default null)
returns void
language plpgsql
security definer
set search_path='pipeline','public'
as $function$
begin
 update pipeline.sources set last_checked_at=now(),last_success_at=case when p_ok then now() else last_success_at end,
  last_failure_at=case when not p_ok then now() else last_failure_at end,last_error=case when p_ok then null else p_error end,updated_at=now()
 where id=p_source_id;
end $function$;

revoke all on function public.svc_qilt_context(text) from public,anon,authenticated;
revoke all on function public.svc_qilt_prepare_source(text,text,text,integer) from public,anon,authenticated;
revoke all on function public.svc_qilt_register_evidence(uuid,text,text,text,text,integer,text) from public,anon,authenticated;
revoke all on function public.svc_qilt_upsert_mappings(uuid,jsonb) from public,anon,authenticated;
revoke all on function public.svc_qilt_apply_observations(jsonb) from public,anon,authenticated;
revoke all on function public.svc_qilt_touch_source(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.svc_qilt_context(text) to service_role,postgres;
grant execute on function public.svc_qilt_prepare_source(text,text,text,integer) to service_role,postgres;
grant execute on function public.svc_qilt_register_evidence(uuid,text,text,text,text,integer,text) to service_role,postgres;
grant execute on function public.svc_qilt_upsert_mappings(uuid,jsonb) to service_role,postgres;
grant execute on function public.svc_qilt_apply_observations(jsonb) to service_role,postgres;
grant execute on function public.svc_qilt_touch_source(uuid,boolean,text) to service_role,postgres;
