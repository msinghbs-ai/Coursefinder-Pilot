-- CF-154 — Bounded Monash international Scholarship validation profiles.
-- Only the Indonesian Women Impact and John Bush Memorial Top-Up first-party pages are onboarded.
-- Monash University Indonesia Scholarship is deliberately excluded from the AU international-student validation wave.

with target_candidates as (
  select c.id candidate_id,s.provider_id,c.detail_target_url url,
         split_part(coalesce(c.observed_title,'Scholarship'),'…',1) label
  from pipeline.layer2_scholarship_discovery_candidates c
  join pipeline.sources s on s.id=c.source_id
  where s.provider_id=(select id from catalogue.providers where canonical_name='Monash University' limit 1)
    and c.status='discovered' and c.classification='detail_ready'
    and c.detail_target_url in (
      'https://www.monash.edu/study/fees-scholarships/scholarships/find-a-scholarship/indonesian-women-impact-scholarship',
      'https://www.monash.edu/study/fees-scholarships/scholarships/find-a-scholarship/john-bush-memorial-top-up-scholarship'
    )
)
insert into pipeline.sources(source_type,provider_id,country_id,url,label,trust_rank,status,metadata)
select 'scholarship_detail',t.provider_id,p.country_id,t.url,left(t.label,240),100,'active',
       jsonb_build_object('authority','first_party','international_validation_wave',true,'change_control_ref','CF-154')
from target_candidates t join catalogue.providers p on p.id=t.provider_id
where not exists(select 1 from pipeline.sources x where x.provider_id=t.provider_id and x.source_type='scholarship_detail' and x.url=t.url);

with targets as (
 select s.id source_id,s.provider_id,s.url
 from pipeline.sources s
 where s.source_type='scholarship_detail'
   and coalesce(s.metadata->>'international_validation_wave','false')='true'
)
insert into pipeline.layer2_source_profiles(source_id,profile_key,domain,acquisition_method,target_entity_type,authority_class,enabled,paused,operational_owner,freshness_sla_hours,schedule_text)
select t.source_id,'au-scholarship-detail-'||replace(t.provider_id::text,'-','')||'-'||substr(md5(t.url),1,10),
       'scholarship','website','scholarship','first_party',true,false,'PIM/Data Operations',168,
       'weekly; manual international validation wave'
from targets t
where not exists(select 1 from pipeline.layer2_source_profiles sp where sp.source_id=t.source_id);

with targets as (
 select sp.id profile_id,s.url,regexp_replace(s.url,'^(https?://[^/]+).*$','\1') base_domain
 from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id
 where s.source_type='scholarship_detail'
   and coalesce(s.metadata->>'international_validation_wave','false')='true'
   and sp.current_version_id is null
), cfg as (
 select profile_id,jsonb_build_object(
   'retry',jsonb_build_object('backoff','exponential','max_attempts',2),
   'headers',jsonb_build_object('user_agent','CourseFinder deterministic Layer 2 Scholarship detail acquisition'),
   'schedule','weekly; manual international validation wave','base_domain',base_domain,'concurrency',1,
   'url_patterns',jsonb_build_array(url),'discovery_url',url,'robots_policy','respect',
   'fanout_domains',jsonb_build_array('scholarship'),'max_payload_mb',20,'timeout_seconds',60,
   'evidence_required',true,'acquisition_method','website','allowed_mime_types',jsonb_build_array('text/html','application/json'),
   'change_control_ref','CF-154','reuse_shared_fetch',true,'target_entity_type','scholarship','freshness_sla_hours',168,
   'content_change_policy','hash before extraction; no direct publication','rate_limit_per_minute',20,'shared_fetch_ttl_hours',24
 ) configuration from targets
), ins as (
 insert into pipeline.layer2_source_profile_versions(profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,change_control_ref)
 select profile_id,1,configuration,md5(configuration::text),'valid',jsonb_build_object('valid',true,'errors','[]'::jsonb,'validated_at',now()),'CF-154'
 from cfg returning id,profile_id
)
update pipeline.layer2_source_profiles sp set current_version_id=ins.id,updated_at=now() from ins where sp.id=ins.profile_id;

insert into pipeline.layer2_execution_policies(profile_id,schedule_mode,batch_size,routing_strategy,max_paid_attempts_per_entity,max_vendor_units_per_entity,max_cost_usd_per_entity,auto_handoff_layer3,stop_on_identity_mismatch,enabled,max_concurrency,stale_after_minutes)
select sp.id,'manual',1,'direct_then_best_value',2,2,0.10,true,true,true,1,30
from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id
where s.source_type='scholarship_detail' and coalesce(s.metadata->>'international_validation_wave','false')='true'
on conflict(profile_id) do nothing;

with monash_catalogue as (
 select distinct on (s.provider_id) sp.id profile_id,s.provider_id
 from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id
 where sp.domain='scholarship' and s.source_type='scholarship_catalogue'
   and s.provider_id=(select id from catalogue.providers where canonical_name='Monash University' limit 1)
   and sp.enabled and not sp.paused
 order by s.provider_id,sp.updated_at desc
), details as (
 select sp.id profile_id,s.provider_id
 from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id
 where s.source_type='scholarship_detail' and coalesce(s.metadata->>'international_validation_wave','false')='true'
)
insert into pipeline.layer2_profile_provider_routes(profile_id,acquisition_provider_id,priority,enabled,required_capabilities,request_overrides,evidence_policy,fallback_on,change_control_ref)
select d.profile_id,r.acquisition_provider_id,r.priority,r.enabled,r.required_capabilities,r.request_overrides,r.evidence_policy,r.fallback_on,'CF-154'
from details d join monash_catalogue m on m.provider_id=d.provider_id
join pipeline.layer2_profile_provider_routes r on r.profile_id=m.profile_id and r.enabled
on conflict(profile_id,acquisition_provider_id) do nothing;
