-- CF-149 — Onboard CDU Australia Awards as a bounded first-party Scholarship detail profile.
-- Reuses the Provider's governed Scholarship catalogue acquisition routes.

with target as (
  select p.id provider_id,p.country_id,
         'https://www.cdu.edu.au/international/how-apply/scholarships/australia-award-scholarships'::text url,
         'Australia Awards Scholarships at CDU'::text label
  from catalogue.providers p where p.canonical_name='Charles Darwin University' limit 1
)
insert into pipeline.sources(source_type,provider_id,country_id,url,label,trust_rank,status,metadata)
select 'scholarship_detail',provider_id,country_id,url,label,100,'active',jsonb_build_object('authority','first_party','change_control_ref','CF-149')
from target
where not exists(select 1 from pipeline.sources s where s.provider_id=target.provider_id and s.source_type='scholarship_detail' and s.url=target.url);

with target as (
 select s.id source_id,s.provider_id,s.url
 from pipeline.sources s join catalogue.providers p on p.id=s.provider_id
 where p.canonical_name='Charles Darwin University' and s.source_type='scholarship_detail'
   and s.url='https://www.cdu.edu.au/international/how-apply/scholarships/australia-award-scholarships'
)
insert into pipeline.layer2_source_profiles(source_id,profile_key,domain,acquisition_method,target_entity_type,authority_class,enabled,paused,operational_owner,freshness_sla_hours,schedule_text)
select source_id,'au-scholarship-detail-'||replace(provider_id::text,'-','')||'-'||substr(md5(url),1,10),'scholarship','website','scholarship','first_party',true,false,'PIM/Data Operations',168,'weekly; accelerate near application windows'
from target
where not exists(select 1 from pipeline.layer2_source_profiles sp where sp.source_id=target.source_id);

with target as (
 select sp.id profile_id,s.url,regexp_replace(s.url,'^(https?://[^/]+).*$','\1') base_domain
 from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id join catalogue.providers p on p.id=s.provider_id
 where p.canonical_name='Charles Darwin University' and s.source_type='scholarship_detail'
   and s.url='https://www.cdu.edu.au/international/how-apply/scholarships/australia-award-scholarships' and sp.current_version_id is null
), cfg as (
 select profile_id,jsonb_build_object('retry',jsonb_build_object('backoff','exponential','max_attempts',2),'headers',jsonb_build_object('user_agent','CourseFinder deterministic Layer 2 Scholarship detail acquisition'),'schedule','weekly; accelerate near application windows','base_domain',base_domain,'concurrency',1,'url_patterns',jsonb_build_array('https://www.cdu.edu.au/international/how-apply/scholarships/australia-award-scholarships'),'discovery_url','https://www.cdu.edu.au/international/how-apply/scholarships/australia-award-scholarships','robots_policy','respect','fanout_domains',jsonb_build_array('scholarship'),'max_payload_mb',20,'timeout_seconds',60,'evidence_required',true,'acquisition_method','website','allowed_mime_types',jsonb_build_array('text/html','application/json'),'change_control_ref','CF-149','reuse_shared_fetch',true,'target_entity_type','scholarship','freshness_sla_hours',168,'content_change_policy','hash before extraction; no direct publication','rate_limit_per_minute',20,'shared_fetch_ttl_hours',24) configuration
 from target
), ins as (
 insert into pipeline.layer2_source_profile_versions(profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,change_control_ref)
 select profile_id,1,configuration,md5(configuration::text),'valid',jsonb_build_object('valid',true,'errors','[]'::jsonb,'validated_at',now()),'CF-149' from cfg
 returning id,profile_id
)
update pipeline.layer2_source_profiles sp set current_version_id=ins.id,updated_at=now() from ins where sp.id=ins.profile_id;

insert into pipeline.layer2_execution_policies(profile_id,schedule_mode,batch_size,routing_strategy,max_paid_attempts_per_entity,max_vendor_units_per_entity,max_cost_usd_per_entity,auto_handoff_layer3,stop_on_identity_mismatch,enabled,max_concurrency,stale_after_minutes)
select sp.id,'manual',1,'direct_then_best_value',2,2,0.10,true,true,true,1,30
from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id join catalogue.providers p on p.id=s.provider_id
where p.canonical_name='Charles Darwin University' and s.source_type='scholarship_detail' and s.url='https://www.cdu.edu.au/international/how-apply/scholarships/australia-award-scholarships'
on conflict(profile_id) do nothing;

with detail as (
 select sp.id detail_profile_id,s.provider_id
 from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id join catalogue.providers p on p.id=s.provider_id
 where p.canonical_name='Charles Darwin University' and s.source_type='scholarship_detail' and s.url='https://www.cdu.edu.au/international/how-apply/scholarships/australia-award-scholarships'
), catalogue as (
 select distinct on (s.provider_id) sp.id catalogue_profile_id,s.provider_id
 from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id join catalogue.providers p on p.id=s.provider_id
 where p.canonical_name='Charles Darwin University' and s.source_type='scholarship_catalogue' and sp.enabled and not sp.paused
 order by s.provider_id,sp.updated_at desc
)
insert into pipeline.layer2_profile_provider_routes(profile_id,acquisition_provider_id,priority,enabled,required_capabilities,request_overrides,evidence_policy,fallback_on,change_control_ref)
select d.detail_profile_id,r.acquisition_provider_id,r.priority,r.enabled,r.required_capabilities,r.request_overrides,r.evidence_policy,r.fallback_on,'CF-149'
from detail d join catalogue c on c.provider_id=d.provider_id join pipeline.layer2_profile_provider_routes r on r.profile_id=c.catalogue_profile_id and r.enabled
on conflict(profile_id,acquisition_provider_id) do nothing;
