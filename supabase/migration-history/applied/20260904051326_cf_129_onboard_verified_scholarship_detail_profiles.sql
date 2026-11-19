with targets as (
  select distinct t.provider_id,t.first_party_detail_url url,t.observed_title
  from pipeline.scholarship_acquisition_trace t
  where t.verification_status='verified_first_party' and t.stage='first_party_verified'
    and t.first_party_detail_url is not null and t.verification_evidence_id is null
)
insert into pipeline.sources(source_type,provider_id,country_id,url,label,trust_rank,status,metadata)
select 'scholarship_detail',x.provider_id,p.country_id,x.url,x.observed_title,100,'active',jsonb_build_object('authority','first_party','trace_onboarded',true,'change_control_ref','CF-129')
from targets x join catalogue.providers p on p.id=x.provider_id
where not exists(select 1 from pipeline.sources s where s.provider_id=x.provider_id and s.source_type='scholarship_detail' and s.url=x.url);

with targets as (
  select s.id source_id,s.provider_id,s.url,s.label
  from pipeline.sources s
  where s.source_type='scholarship_detail' and coalesce(s.metadata->>'trace_onboarded','false')='true'
), ins as (
  insert into pipeline.layer2_source_profiles(source_id,profile_key,domain,acquisition_method,target_entity_type,authority_class,enabled,paused,operational_owner,freshness_sla_hours,schedule_text)
  select t.source_id,'au-scholarship-detail-'||replace(t.provider_id::text,'-','')||'-'||substr(md5(t.url),1,10),'scholarship','website','scholarship','first_party',true,false,'PIM/Data Operations',168,'weekly; accelerate inside application deadline window or changed hash'
  from targets t where not exists(select 1 from pipeline.layer2_source_profiles sp where sp.source_id=t.source_id)
  returning id,source_id
)
select 1;

with targets as (
  select sp.id profile_id,s.url,
    regexp_replace(s.url,'^(https?://[^/]+).*$','\1') base_domain
  from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id
  where sp.domain='scholarship' and s.source_type='scholarship_detail' and coalesce(s.metadata->>'trace_onboarded','false')='true' and sp.current_version_id is null
), cfg as (
  select profile_id,url,jsonb_build_object(
    'retry',jsonb_build_object('backoff','exponential','max_attempts',2),
    'headers',jsonb_build_object('user_agent','CourseFinder deterministic Layer 2 Scholarship detail acquisition'),
    'schedule','weekly; accelerate inside application deadline window or changed hash',
    'base_domain',base_domain,'concurrency',1,'url_patterns',jsonb_build_array(url),'discovery_url',url,
    'robots_policy','respect','fanout_domains',jsonb_build_array('scholarship'),'max_payload_mb',20,'timeout_seconds',60,
    'evidence_required',true,'acquisition_method','website','allowed_mime_types',jsonb_build_array('text/html','application/json'),
    'change_control_ref','CF-129','reuse_shared_fetch',true,'target_entity_type','scholarship','freshness_sla_hours',168,
    'content_change_policy','hash before detail extraction; no direct canonical mutation','rate_limit_per_minute',20,'shared_fetch_ttl_hours',24
  ) configuration
  from targets
), ins as (
  insert into pipeline.layer2_source_profile_versions(profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,change_control_ref)
  select profile_id,1,configuration,md5(configuration::text),'valid',jsonb_build_object('valid',true,'errors','[]'::jsonb,'validated_at',now()),'CF-129'
  from cfg returning id,profile_id
)
update pipeline.layer2_source_profiles sp set current_version_id=ins.id,updated_at=now() from ins where sp.id=ins.profile_id;

insert into pipeline.layer2_execution_policies(profile_id,schedule_mode,batch_size,routing_strategy,max_paid_attempts_per_entity,max_vendor_units_per_entity,max_cost_usd_per_entity,auto_handoff_layer3,stop_on_identity_mismatch,enabled,max_concurrency,stale_after_minutes)
select sp.id,'manual',1,'direct_then_best_value',2,2,0.10,true,true,true,1,30
from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id
where sp.domain='scholarship' and s.source_type='scholarship_detail' and sp.enabled and not sp.paused
on conflict(profile_id) do nothing;
