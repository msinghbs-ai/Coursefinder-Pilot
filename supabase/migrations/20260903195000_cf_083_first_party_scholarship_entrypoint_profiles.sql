begin;

create temp table cf083_scholarship_seed(
 provider_id uuid,
 candidate_id uuid,
 source_url text,
 label text
) on commit drop;

insert into cf083_scholarship_seed values
 ('030992c3-72c6-452d-8a3b-10ceb0fd77f2','e7e306a3-d0b7-4ddd-8064-971c208a391b','https://www.acu.edu.au/international-students/scholarships2026','ACU International Scholarships'),
 ('e47a940d-186f-4a17-bb22-2b794b73248c','0b993b70-98e0-4334-97fe-d1b406abf538','https://study.anu.edu.au/scholarships','ANU Scholarships'),
 ('6f5cb7f7-7c70-4c06-970f-f368c3a786e2','96e70c70-c0fb-46e4-8ad3-f936ef6607b7','https://www.cdu.edu.au/international/how-apply/scholarships','CDU International Scholarships'),
 ('982fb12f-41ed-4358-9d1b-d7422b3089dd','4afdf6c2-db2a-4263-96c3-9928ee9dfb2a','https://www.curtin.edu.au/study/scholarships/','Curtin Scholarships'),
 ('f34fae5e-b5b9-4c82-a6ca-44bf0803020e','4e0d16af-e78c-4aef-a46c-b9c22c013ed6','https://study.csu.edu.au/international/scholarships','Charles Sturt International Scholarships'),
 ('c5c5d225-3d4c-4e41-8275-78eddd261073','b26666f3-df1e-4f2a-86b9-f9f4feee0b82','https://www.deakin.edu.au/study/fees-and-scholarships','Deakin Fees and Scholarships'),
 ('fac03540-a412-4c76-a5ab-cd338d7760db','b3fbca75-0f2b-4031-93f1-c727e5c42d22','https://www.ecu.edu.au/scholarships','ECU Scholarships');

-- Refresh candidate IDs from the live candidate table by provider/url in case bounded UAT UUIDs differ.
update cf083_scholarship_seed t
set candidate_id=d.id
from pipeline.layer2_scholarship_discovery_candidates d
join pipeline.sources s on s.id=d.source_id
where s.provider_id=t.provider_id and d.scholarship_url=t.source_url;

insert into pipeline.sources(
 id,source_type,system_id,provider_id,country_id,url,label,trust_rank,status,metadata
)
select extensions.gen_random_uuid(),'scholarship_catalogue',null,t.provider_id,p.country_id,t.source_url,t.label,95,'active',
 jsonb_build_object('authority','first_party','origin','CF-083 provider-page discovery','candidate_id',t.candidate_id,'change_control_ref','CF-CHG-20260903-083')
from cf083_scholarship_seed t
join catalogue.providers p on p.id=t.provider_id
where not exists(
 select 1 from pipeline.sources s where s.provider_id=t.provider_id and s.url=t.source_url
);

with src as(
 select s.id source_id,s.provider_id,s.url,t.label,t.candidate_id
 from cf083_scholarship_seed t
 join pipeline.sources s on s.provider_id=t.provider_id and s.url=t.source_url
)
insert into pipeline.layer2_source_profiles(
 source_id,profile_key,domain,acquisition_method,target_entity_type,authority_class,
 enabled,paused,operational_owner,freshness_sla_hours,schedule_text
)
select source_id,
 'au-scholarship-entry-'||replace(provider_id::text,'-','')||'-'||substr(encode(extensions.digest(url,'sha256'),'hex'),1,8),
 'scholarship','scholarship_catalogue','scholarship','first_party',
 true,false,'PIM/Data Operations',168,'weekly; accelerate around application deadlines or changed hash'
from src
on conflict(profile_key) do nothing;

do $$
declare r record;cfg jsonb;h text;val jsonb;vid uuid;vno int;
begin
 for r in
  select p.id profile_id,p.current_version_id,p.acquisition_method,p.target_entity_type,p.freshness_sla_hours,p.schedule_text,s.url
  from pipeline.layer2_source_profiles p
  join pipeline.sources s on s.id=p.source_id
  where p.profile_key like 'au-scholarship-entry-%'
    and s.metadata->>'change_control_ref'='CF-CHG-20260903-083'
    and p.current_version_id is null
 loop
  cfg:=jsonb_build_object(
    'acquisition_method','scholarship_catalogue',
    'base_domain',regexp_replace(r.url,'^(https?://[^/]+).*$','\1'),
    'discovery_url',r.url,
    'url_patterns',jsonb_build_array(r.url),
    'headers',jsonb_build_object('user_agent','CourseFinder deterministic Layer 2 scholarship acquisition'),
    'rate_limit_per_minute',20,'concurrency',1,'timeout_seconds',60,
    'retry',jsonb_build_object('max_attempts',2,'backoff','exponential'),
    'robots_policy','respect',
    'allowed_mime_types',jsonb_build_array('text/html','application/json'),
    'max_payload_mb',20,
    'target_entity_type','scholarship',
    'evidence_required',true,
    'freshness_sla_hours',168,
    'schedule','weekly; accelerate around application deadlines or changed hash',
    'shared_fetch_ttl_hours',24,
    'reuse_shared_fetch',true,
    'fanout_domains',jsonb_build_array('scholarship','provider_asset'),
    'content_change_policy','hash before downstream extraction; no direct canonical mutation',
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
 where p.profile_key like 'au-scholarship-entry-%'
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