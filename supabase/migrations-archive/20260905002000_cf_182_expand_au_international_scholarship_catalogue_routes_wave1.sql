-- CF-182 — expand qualified first-party AU international Scholarship catalogue coverage.
with targets(provider_name,url,label) as (values
 ('The University of Sydney','https://www.sydney.edu.au/scholarships/international.html','International scholarships'),
 ('University of Technology Sydney (UTS)','https://www.uts.edu.au/for-students/admissions-entry/scholarships/international','International scholarships'),
 ('Flinders University','https://www.flinders.edu.au/international/apply/scholarships','International scholarships'),
 ('Macquarie University','https://www.mq.edu.au/study/admissions-and-entry/scholarships/international','International scholarships'),
 ('Swinburne University of Technology','https://www.swinburne.edu.au/courses/scholarships/international-scholarships/','International scholarships'),
 ('University of Wollongong','https://www.uow.edu.au/study/scholarships/international/','International scholarships'),
 ('Griffith University','https://www.griffith.edu.au/international/scholarships-finance','International scholarships and finance'),
 ('Queensland University of Technology','https://www.qut.edu.au/study/international/scholarship-opportunities','International scholarship opportunities')
), prepared as (
 select p.id provider_id,p.country_id,t.url,t.label from targets t join catalogue.providers p on p.canonical_name=t.provider_name
)
insert into pipeline.sources(source_type,provider_id,country_id,url,label,trust_rank,status,metadata)
select 'scholarship_catalogue',x.provider_id,x.country_id,x.url,x.label,100,'active',jsonb_build_object('authority','first_party','audience','international','change_control_ref','CF-182','qualified_at',now())
from prepared x where not exists(select 1 from pipeline.sources s where s.provider_id=x.provider_id and s.source_type='scholarship_catalogue' and rtrim(lower(s.url),'/')=rtrim(lower(x.url),'/'));

with src as (select s.id source_id,s.provider_id,s.url from pipeline.sources s where s.source_type='scholarship_catalogue' and coalesce(s.metadata->>'change_control_ref','')='CF-182')
insert into pipeline.layer2_source_profiles(source_id,profile_key,domain,acquisition_method,target_entity_type,authority_class,enabled,paused,operational_owner,freshness_sla_hours,schedule_text)
select x.source_id,'au-scholarship-entry-'||replace(x.provider_id::text,'-','')||'-'||substr(md5(x.url),1,8),'scholarship','scholarship_catalogue','scholarship','first_party',true,false,'CourseFinder PIM',168,'weekly; international catalogue; hash-gated detail fanout'
from src x where not exists(select 1 from pipeline.layer2_source_profiles sp where sp.source_id=x.source_id);

with cfg as (
 select sp.id profile_id,s.url,jsonb_build_object('retry',jsonb_build_object('backoff','exponential','max_attempts',2),'headers',jsonb_build_object('user_agent','CourseFinder deterministic Layer 2 Scholarship catalogue acquisition'),'schedule','weekly; international catalogue; hash-gated detail fanout','base_domain',regexp_replace(s.url,'^(https?://[^/]+).*','\1'),'concurrency',1,'url_patterns',jsonb_build_array(s.url),'discovery_url',s.url,'robots_policy','respect','fanout_domains',jsonb_build_array('scholarship'),'max_payload_mb',20,'timeout_seconds',60,'evidence_required',true,'acquisition_method','scholarship_catalogue','allowed_mime_types',jsonb_build_array('text/html','application/json'),'change_control_ref','CF-182','reuse_shared_fetch',true,'target_entity_type','scholarship','freshness_sla_hours',168,'content_change_policy','hash before enumeration; no direct canonical mutation','rate_limit_per_minute',20,'shared_fetch_ttl_hours',24,'international_only',true) configuration
 from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id where s.source_type='scholarship_catalogue' and coalesce(s.metadata->>'change_control_ref','')='CF-182' and sp.current_version_id is null
), ins as (
 insert into pipeline.layer2_source_profile_versions(profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,change_control_ref)
 select profile_id,1,configuration,encode(extensions.digest(configuration::text,'sha256'),'hex'),'valid',jsonb_build_object('valid',true,'international_only',true,'validated_at',now()),'CF-182' from cfg returning id,profile_id
)
update pipeline.layer2_source_profiles sp set current_version_id=ins.id,updated_at=now() from ins where sp.id=ins.profile_id;

insert into pipeline.layer2_execution_policies(profile_id,schedule_mode,batch_size,routing_strategy,max_paid_attempts_per_entity,max_vendor_units_per_entity,max_cost_usd_per_entity,auto_handoff_layer3,stop_on_identity_mismatch,enabled,max_concurrency,stale_after_minutes)
select sp.id,'manual',1,'direct_then_best_value',2,2,0.10,true,true,true,1,30 from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id where s.source_type='scholarship_catalogue' and coalesce(s.metadata->>'change_control_ref','')='CF-182'
on conflict(profile_id) do nothing;

insert into pipeline.layer2_profile_provider_routes(profile_id,acquisition_provider_id,priority,enabled,required_capabilities,request_overrides,evidence_policy,fallback_on,change_control_ref)
select sp.id,ap.id,case ap.provider_key when 'direct-http' then 10 when 'parsebot' then 20 when 'firecrawl' then 40 else 50 end,true,'{}'::jsonb,'{}'::jsonb,jsonb_build_object('capture_raw',true,'capture_html',true,'capture_screenshot_on_failure',ap.provider_key='firecrawl','capture_screenshot_on_extraction_failure',ap.provider_key='firecrawl'),'["blocked","timeout","403","429","5xx","extraction_failed"]'::jsonb,'CF-182'
from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id cross join pipeline.layer2_acquisition_providers ap where s.source_type='scholarship_catalogue' and coalesce(s.metadata->>'change_control_ref','')='CF-182' and ap.enabled and ap.provider_key in('direct-http','parsebot','firecrawl','zenrows')
on conflict(profile_id,acquisition_provider_id) do nothing;
