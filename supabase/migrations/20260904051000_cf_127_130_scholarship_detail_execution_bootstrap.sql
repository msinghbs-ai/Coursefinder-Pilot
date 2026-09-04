-- CF-127..130 — Scholarship detail acquisition execution bootstrap.
-- Reconciles Pilot runtime detail-profile execution policies, first-party detail profile onboarding,
-- and provider-route inheritance. No canonical or Publication mutation is authorised here.

insert into pipeline.layer2_execution_policies(
  profile_id,schedule_mode,batch_size,routing_strategy,max_paid_attempts_per_entity,
  max_vendor_units_per_entity,max_cost_usd_per_entity,auto_handoff_layer3,
  stop_on_identity_mismatch,enabled,max_concurrency,stale_after_minutes
)
select sp.id,'manual',1,'direct_then_best_value',2,2,0.10,true,true,true,1,30
from pipeline.layer2_source_profiles sp
join pipeline.sources s on s.id=sp.source_id
where sp.domain='scholarship' and s.source_type='scholarship_detail' and sp.enabled and not sp.paused
on conflict(profile_id) do nothing;

with targets as (
  select distinct t.provider_id,t.first_party_detail_url url,t.observed_title
  from pipeline.scholarship_acquisition_trace t
  where t.verification_status='verified_first_party'
    and t.first_party_detail_url is not null
    and t.verification_evidence_id is null
)
insert into pipeline.sources(source_type,provider_id,country_id,url,label,trust_rank,status,metadata)
select 'scholarship_detail',x.provider_id,p.country_id,x.url,x.observed_title,100,'active',
       jsonb_build_object('authority','first_party','trace_onboarded',true,'change_control_ref','CF-129')
from targets x join catalogue.providers p on p.id=x.provider_id
where not exists(
  select 1 from pipeline.sources s
  where s.provider_id=x.provider_id and s.source_type='scholarship_detail' and s.url=x.url
);

with targets as (
  select s.id source_id,s.provider_id,s.url
  from pipeline.sources s
  where s.source_type='scholarship_detail'
    and coalesce(s.metadata->>'trace_onboarded','false')='true'
)
insert into pipeline.layer2_source_profiles(
  source_id,profile_key,domain,acquisition_method,target_entity_type,authority_class,
  enabled,paused,operational_owner,freshness_sla_hours,schedule_text
)
select t.source_id,
       'au-scholarship-detail-'||replace(t.provider_id::text,'-','')||'-'||substr(md5(t.url),1,10),
       'scholarship','website','scholarship','first_party',true,false,'PIM/Data Operations',168,
       'weekly; accelerate inside application deadline window or changed hash'
from targets t
where not exists(select 1 from pipeline.layer2_source_profiles sp where sp.source_id=t.source_id);

with targets as (
  select sp.id profile_id,s.url,
         regexp_replace(s.url,'^(https?://[^/]+).*$','\1') base_domain
  from pipeline.layer2_source_profiles sp
  join pipeline.sources s on s.id=sp.source_id
  where sp.domain='scholarship' and s.source_type='scholarship_detail'
    and coalesce(s.metadata->>'trace_onboarded','false')='true'
    and sp.current_version_id is null
), cfg as (
  select profile_id,url,jsonb_build_object(
    'retry',jsonb_build_object('backoff','exponential','max_attempts',2),
    'headers',jsonb_build_object('user_agent','CourseFinder deterministic Layer 2 Scholarship detail acquisition'),
    'schedule','weekly; accelerate inside application deadline window or changed hash',
    'base_domain',base_domain,'concurrency',1,'url_patterns',jsonb_build_array(url),'discovery_url',url,
    'robots_policy','respect','fanout_domains',jsonb_build_array('scholarship'),
    'max_payload_mb',20,'timeout_seconds',60,'evidence_required',true,'acquisition_method','website',
    'allowed_mime_types',jsonb_build_array('text/html','application/json'),
    'change_control_ref','CF-129','reuse_shared_fetch',true,'target_entity_type','scholarship',
    'freshness_sla_hours',168,'content_change_policy','hash before detail extraction; no direct canonical mutation',
    'rate_limit_per_minute',20,'shared_fetch_ttl_hours',24
  ) configuration
  from targets
), ins as (
  insert into pipeline.layer2_source_profile_versions(
    profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,change_control_ref
  )
  select profile_id,1,configuration,md5(configuration::text),'valid',
         jsonb_build_object('valid',true,'errors','[]'::jsonb,'validated_at',now()),'CF-129'
  from cfg
  returning id,profile_id
)
update pipeline.layer2_source_profiles sp
set current_version_id=ins.id,updated_at=now()
from ins where sp.id=ins.profile_id;

insert into pipeline.layer2_execution_policies(
  profile_id,schedule_mode,batch_size,routing_strategy,max_paid_attempts_per_entity,
  max_vendor_units_per_entity,max_cost_usd_per_entity,auto_handoff_layer3,
  stop_on_identity_mismatch,enabled,max_concurrency,stale_after_minutes
)
select sp.id,'manual',1,'direct_then_best_value',2,2,0.10,true,true,true,1,30
from pipeline.layer2_source_profiles sp
join pipeline.sources s on s.id=sp.source_id
where sp.domain='scholarship' and s.source_type='scholarship_detail' and sp.enabled and not sp.paused
on conflict(profile_id) do nothing;

with detail_profiles as (
  select dsp.id detail_profile_id,ds.provider_id
  from pipeline.layer2_source_profiles dsp
  join pipeline.sources ds on ds.id=dsp.source_id
  where dsp.domain='scholarship' and ds.source_type='scholarship_detail' and dsp.enabled and not dsp.paused
), catalogue_profiles as (
  select distinct on (s.provider_id) sp.id catalogue_profile_id,s.provider_id
  from pipeline.layer2_source_profiles sp
  join pipeline.sources s on s.id=sp.source_id
  where sp.domain='scholarship' and s.source_type='scholarship_catalogue' and sp.enabled and not sp.paused
  order by s.provider_id,sp.updated_at desc
)
insert into pipeline.layer2_profile_provider_routes(
  profile_id,acquisition_provider_id,priority,enabled,required_capabilities,request_overrides,
  evidence_policy,fallback_on,change_control_ref
)
select d.detail_profile_id,r.acquisition_provider_id,r.priority,r.enabled,r.required_capabilities,
       r.request_overrides,r.evidence_policy,r.fallback_on,'CF-130'
from detail_profiles d
join catalogue_profiles c on c.provider_id=d.provider_id
join pipeline.layer2_profile_provider_routes r on r.profile_id=c.catalogue_profile_id and r.enabled
on conflict(profile_id,acquisition_provider_id) do nothing;
