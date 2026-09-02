begin;

create temp table cf083_detail_seed(
 provider_id uuid,
 candidate_id uuid,
 source_url text,
 label text
) on commit drop;

insert into cf083_detail_seed values
 ('6f5cb7f7-7c70-4c06-970f-f368c3a786e2','41c2e832-26e2-46c2-9060-993a629470bc','https://www.cdu.edu.au/international/how-apply/scholarships/vice-chancellors-high-achievers-scholarship-vcihas-application','CDU Vice-Chancellor High Achievers Scholarship'),
 ('f34fae5e-b5b9-4c82-a6ca-44bf0803020e','e848cdcb-6e5e-4d9b-9156-46c755f856b8','https://www.csu.edu.au/scholarships/scholarships-grants/find-scholarship/international/international-joint-cooperation-program-scholarship','Charles Sturt International Joint Cooperation Program Scholarship'),
 ('f34fae5e-b5b9-4c82-a6ca-44bf0803020e','a633c1b3-73ee-4ac2-aa06-269529dd9480','https://www.csu.edu.au/scholarships/scholarships-grants/find-scholarship/international/international-student-success-merit-scholarship','Charles Sturt International Student Success Merit Scholarship'),
 ('f34fae5e-b5b9-4c82-a6ca-44bf0803020e','166f7f13-f0d4-4465-a926-288b7bb06966','https://www.csu.edu.au/scholarships/scholarships-grants/find-scholarship/international/international-student-success-scholarship','Charles Sturt International Student Success Scholarship'),
 ('f34fae5e-b5b9-4c82-a6ca-44bf0803020e','5c64d77c-f7c3-4296-be2a-55cf84394705','https://www.csu.edu.au/scholarships/scholarships-grants/find-scholarship/international/regional-accommodation-bursary','Charles Sturt Regional Accommodation Bursary for International Students'),
 ('f34fae5e-b5b9-4c82-a6ca-44bf0803020e','dfade488-131d-4902-9b44-cc2b089e7e14','https://www.csu.edu.au/scholarships/scholarships-grants/find-scholarship/international/vice-chancellor-international-scholarship','Charles Sturt Vice-Chancellor International Excellence Scholarship');

insert into pipeline.sources(
 id,source_type,system_id,provider_id,country_id,url,label,trust_rank,status,metadata
)
select extensions.gen_random_uuid(),'scholarship_detail',null,t.provider_id,p.country_id,t.source_url,t.label,100,'active',
 jsonb_build_object(
   'authority','first_party',
   'origin','CF-083 Scholarship catalogue enumeration',
   'candidate_id',t.candidate_id,
   'parent_kind','scholarship_catalogue',
   'change_control_ref','CF-CHG-20260903-083'
 )
from cf083_detail_seed t
join catalogue.providers p on p.id=t.provider_id
where not exists(select 1 from pipeline.sources s where s.provider_id=t.provider_id and s.url=t.source_url);

with src as(
 select s.id source_id,s.provider_id,s.url,t.label,t.candidate_id
 from cf083_detail_seed t
 join pipeline.sources s on s.provider_id=t.provider_id and s.url=t.source_url
)
insert into pipeline.layer2_source_profiles(
 source_id,profile_key,domain,acquisition_method,target_entity_type,authority_class,
 enabled,paused,operational_owner,freshness_sla_hours,schedule_text
)
select source_id,
 'au-scholarship-detail-'||replace(provider_id::text,'-','')||'-'||substr(encode(extensions.digest(url,'sha256'),'hex'),1,10),
 'scholarship','website','scholarship','first_party',
 true,false,'PIM/Data Operations',168,'weekly; accelerate inside application deadline window or changed hash'
from src
on conflict(profile_key) do nothing;

do $$
declare r record;cfg jsonb;h text;val jsonb;vid uuid;vno int;
begin
 for r in
  select p.id profile_id,p.current_version_id,s.url
  from pipeline.layer2_source_profiles p
  join pipeline.sources s on s.id=p.source_id
  where p.profile_key like 'au-scholarship-detail-%'
    and s.metadata->>'change_control_ref'='CF-CHG-20260903-083'
    and p.current_version_id is null
 loop
  cfg:=jsonb_build_object(
    'acquisition_method','website',
    'base_domain',regexp_replace(r.url,'^(https?://[^/]+).*$','\1'),
    'discovery_url',r.url,
    'url_patterns',jsonb_build_array(r.url),
    'headers',jsonb_build_object('user_agent','CourseFinder deterministic Layer 2 Scholarship detail acquisition'),
    'rate_limit_per_minute',20,
    'concurrency',1,
    'timeout_seconds',60,
    'retry',jsonb_build_object('max_attempts',2,'backoff','exponential'),
    'robots_policy','respect',
    'allowed_mime_types',jsonb_build_array('text/html','application/json'),
    'max_payload_mb',20,
    'target_entity_type','scholarship',
    'evidence_required',true,
    'freshness_sla_hours',168,
    'schedule','weekly; accelerate inside application deadline window or changed hash',
    'shared_fetch_ttl_hours',24,
    'reuse_shared_fetch',true,
    'fanout_domains',jsonb_build_array('scholarship'),
    'content_change_policy','hash before detail extraction; no direct canonical mutation',
    'change_control_ref','CF-CHG-20260903-083'
  );
  h:=encode(extensions.digest(cfg::text,'sha256'),'hex');
  val:=security.layer2_validate_profile_config(cfg);
  select coalesce(max(version_no),0)+1 into vno from pipeline.layer2_source_profile_versions where profile_id=r.profile_id;

  insert into pipeline.layer2_source_profile_versions(
    profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,change_control_ref
  ) values(
    r.profile_id,vno,cfg,h,
    case when (val->>'valid')::boolean then 'valid' else 'invalid' end,
    val,'CF-CHG-20260903-083'
  )
  on conflict(profile_id,configuration_hash) do update set validation_result=excluded.validation_result
  returning id into vid;

  update pipeline.layer2_source_profiles set current_version_id=vid,updated_at=now() where id=r.profile_id;
 end loop;
end $$;

with ap as(
 select id,provider_key from pipeline.layer2_acquisition_providers
 where provider_key in('direct-http','parsebot','firecrawl','zenrows')
),
prof as(
 select p.id
 from pipeline.layer2_source_profiles p
 join pipeline.sources s on s.id=p.source_id
 where p.profile_key like 'au-scholarship-detail-%'
   and s.metadata->>'change_control_ref'='CF-CHG-20260903-083'
)
insert into pipeline.layer2_profile_provider_routes(
 profile_id,acquisition_provider_id,priority,enabled,required_capabilities,request_overrides,evidence_policy,fallback_on,change_control_ref
)
select prof.id,ap.id,
 case ap.provider_key when 'direct-http' then 10 when 'parsebot' then 20 when 'firecrawl' then 40 else 50 end,
 true,'{}'::jsonb,'{}'::jsonb,
 case when ap.provider_key='firecrawl'
   then '{"capture_raw":true,"capture_html":true,"capture_screenshot_on_failure":true,"capture_screenshot_on_extraction_failure":true}'::jsonb
   else '{"capture_raw":true,"capture_html":true,"capture_screenshot_on_failure":false}'::jsonb end,
 '["blocked","timeout","403","429","5xx","extraction_failed"]'::jsonb,
 'CF-CHG-20260903-083'
from prof cross join ap
on conflict(profile_id,acquisition_provider_id) do update set
 priority=excluded.priority,enabled=excluded.enabled,evidence_policy=excluded.evidence_policy,
 fallback_on=excluded.fallback_on,change_control_ref=excluded.change_control_ref,updated_at=now();

commit;