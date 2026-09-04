-- CF-144/145 — Second bounded international Scholarship detail wave.
-- Runtime dispatch is operational and is not replayed by migration. This file reconciles
-- the deterministic source/profile/route state and Evidence-backed canonical-unpublished result.

with selected as (
  select distinct on (p.id,c.detail_target_url)
    p.id provider_id,p.country_id,c.id candidate_id,c.detail_target_url,c.observed_title
  from pipeline.layer2_scholarship_discovery_candidates c
  join pipeline.sources src on src.id=c.source_id
  join catalogue.providers p on p.id=src.provider_id
  where c.classification='detail_ready'
    and c.detail_target_url is not null
    and (
      lower(coalesce(c.observed_title,'')) like '%international school leaver%'
      or lower(coalesce(c.observed_title,'')) like '%asean award%'
      or lower(coalesce(c.observed_title,'')) like '%asean international scholarship%'
    )
    and p.canonical_name in ('Monash University','Edith Cowan University')
  order by p.id,c.detail_target_url,c.created_at desc
)
insert into pipeline.sources(source_type,provider_id,country_id,url,label,trust_rank,status,metadata)
select 'scholarship_detail',s.provider_id,s.country_id,s.detail_target_url,left(coalesce(s.observed_title,'Scholarship detail'),180),100,'active',
       jsonb_build_object('authority','first_party','candidate_id',s.candidate_id,'bounded_international_wave_2',true,'change_control_ref','CF-144')
from selected s
where not exists(select 1 from pipeline.sources x where x.provider_id=s.provider_id and x.source_type='scholarship_detail' and x.url=s.detail_target_url);

with targets as (
 select s.id source_id,s.provider_id,s.url
 from pipeline.sources s
 where s.source_type='scholarship_detail' and coalesce(s.metadata->>'bounded_international_wave_2','false')='true'
)
insert into pipeline.layer2_source_profiles(source_id,profile_key,domain,acquisition_method,target_entity_type,authority_class,enabled,paused,operational_owner,freshness_sla_hours,schedule_text)
select t.source_id,'au-scholarship-detail-'||replace(t.provider_id::text,'-','')||'-'||substr(md5(t.url),1,10),'scholarship','website','scholarship','first_party',true,false,'PIM/Data Operations',168,'weekly; accelerate inside application deadline window or changed hash'
from targets t
where not exists(select 1 from pipeline.layer2_source_profiles sp where sp.source_id=t.source_id);

with targets as (
 select sp.id profile_id,s.url,regexp_replace(s.url,'^(https?://[^/]+).*$','\1') base_domain
 from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id
 where sp.domain='scholarship' and s.source_type='scholarship_detail' and coalesce(s.metadata->>'bounded_international_wave_2','false')='true' and sp.current_version_id is null
), cfg as (
 select profile_id,jsonb_build_object(
   'retry',jsonb_build_object('backoff','exponential','max_attempts',2),
   'headers',jsonb_build_object('user_agent','CourseFinder deterministic Layer 2 Scholarship detail acquisition'),
   'schedule','weekly; accelerate inside application deadline window or changed hash',
   'base_domain',base_domain,'concurrency',1,'url_patterns',jsonb_build_array(url),'discovery_url',url,
   'robots_policy','respect','fanout_domains',jsonb_build_array('scholarship'),'max_payload_mb',20,'timeout_seconds',60,
   'evidence_required',true,'acquisition_method','website','allowed_mime_types',jsonb_build_array('text/html','application/json'),
   'change_control_ref','CF-144','reuse_shared_fetch',true,'target_entity_type','scholarship','freshness_sla_hours',168,
   'content_change_policy','hash before detail extraction; no direct canonical mutation','rate_limit_per_minute',20,'shared_fetch_ttl_hours',24
 ) configuration from targets
), ins as (
 insert into pipeline.layer2_source_profile_versions(profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,change_control_ref)
 select profile_id,1,configuration,md5(configuration::text),'valid',jsonb_build_object('valid',true,'errors','[]'::jsonb,'validated_at',now()),'CF-144'
 from cfg returning id,profile_id
)
update pipeline.layer2_source_profiles sp set current_version_id=ins.id,updated_at=now() from ins where sp.id=ins.profile_id;

insert into pipeline.layer2_execution_policies(profile_id,schedule_mode,batch_size,routing_strategy,max_paid_attempts_per_entity,max_vendor_units_per_entity,max_cost_usd_per_entity,auto_handoff_layer3,stop_on_identity_mismatch,enabled,max_concurrency,stale_after_minutes)
select sp.id,'manual',1,'direct_then_best_value',2,2,0.10,true,true,true,1,30
from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id
where sp.domain='scholarship' and s.source_type='scholarship_detail' and coalesce(s.metadata->>'bounded_international_wave_2','false')='true'
on conflict(profile_id) do nothing;

with detail_profiles as (
 select dsp.id detail_profile_id,ds.provider_id
 from pipeline.layer2_source_profiles dsp join pipeline.sources ds on ds.id=dsp.source_id
 where dsp.domain='scholarship' and ds.source_type='scholarship_detail' and coalesce(ds.metadata->>'bounded_international_wave_2','false')='true'
), catalogue_profiles as (
 select distinct on (s.provider_id) sp.id catalogue_profile_id,s.provider_id
 from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id
 where sp.domain='scholarship' and s.source_type='scholarship_catalogue' and sp.enabled and not sp.paused
 order by s.provider_id,sp.updated_at desc
)
insert into pipeline.layer2_profile_provider_routes(profile_id,acquisition_provider_id,priority,enabled,required_capabilities,request_overrides,evidence_policy,fallback_on,change_control_ref)
select d.detail_profile_id,r.acquisition_provider_id,r.priority,r.enabled,r.required_capabilities,r.request_overrides,r.evidence_policy,r.fallback_on,'CF-144'
from detail_profiles d join catalogue_profiles c on c.provider_id=d.provider_id join pipeline.layer2_profile_provider_routes r on r.profile_id=c.catalogue_profile_id and r.enabled
on conflict(profile_id,acquisition_provider_id) do nothing;

-- Evidence-backed reconciliation. Generic page headings such as "Scholarships" are replaced by
-- the already-recorded candidate identity rather than accepted as canonical Scholarship names.
with ready as (
  select ps.provider_id,ps.id source_id,(ps.metadata->>'candidate_id')::uuid candidate_id,
         sr.id source_record_id,sr.source_record_url,sr.evidence_id,c.observed_title,
         case when lower(trim(coalesce(sr.payload->>'name',''))) in ('scholarship','scholarships','find a scholarship','find scholarships')
              then c.observed_title else coalesce(nullif(sr.payload->>'name',''),c.observed_title) end canonical_name,
         nullif(sr.payload->>'award_value_text','') award_text,
         'scholarship:AU:first-party-detail:'||replace(ps.provider_id::text,'-','')||':'||md5(sr.source_record_url) stable_key
  from pipeline.sources ps
  join pipeline.layer2_scholarship_discovery_candidates c on c.id=(ps.metadata->>'candidate_id')::uuid
  join lateral (select x.* from pipeline.scholarship_source_records x where x.source_id=ps.id order by x.created_at desc limit 1) sr on true
  where ps.source_type='scholarship_detail' and coalesce(ps.metadata->>'bounded_international_wave_2','false')='true' and sr.evidence_id is not null
), cleaned as (
  select r.*,case when r.canonical_name ilike '% The %' and length(r.canonical_name)>180 then trim(split_part(r.canonical_name,' The ',1)) else r.canonical_name end final_name
  from ready r
), reg as (
  insert into pim.entity_registry(id,entity_type,stable_key,lifecycle_status)
  select scholarship.deterministic_uuid(stable_key),'scholarship',stable_key,'active'
  from cleaned r
  where not exists(select 1 from scholarship.scholarships s where s.provider_id=r.provider_id and (s.source_url=r.source_record_url or lower(regexp_replace(s.name,'[^a-z0-9]+','','g'))=lower(regexp_replace(r.final_name,'[^a-z0-9]+','','g'))))
  on conflict(stable_key) do update set updated_at=now() returning id,stable_key
)
insert into scholarship.scholarships(id,stable_key,provider_id,name,scholarship_type,audience,award_value_text,source_url,lifecycle_status,publication_status,source_id,evidence_id,confidence)
select reg.id,r.stable_key,r.provider_id,r.final_name,'provider_scholarship','international',r.award_text,r.source_record_url,'active','unpublished',r.source_id,r.evidence_id,0.95
from cleaned r join reg on reg.stable_key=r.stable_key
on conflict(id) do update set name=excluded.name,source_url=excluded.source_url,source_id=excluded.source_id,evidence_id=excluded.evidence_id,award_value_text=coalesce(excluded.award_value_text,scholarship.scholarships.award_value_text),updated_at=now();

with ready as (
  select ps.provider_id,(ps.metadata->>'candidate_id')::uuid candidate_id,sr.id source_record_id,sr.source_record_url,sr.evidence_id,
         c.observed_title,case when lower(trim(coalesce(sr.payload->>'name',''))) in ('scholarship','scholarships','find a scholarship','find scholarships') then c.observed_title else coalesce(nullif(sr.payload->>'name',''),c.observed_title) end canonical_name
  from pipeline.sources ps join pipeline.layer2_scholarship_discovery_candidates c on c.id=(ps.metadata->>'candidate_id')::uuid
  join lateral (select x.* from pipeline.scholarship_source_records x where x.source_id=ps.id order by x.created_at desc limit 1) sr on true
  where ps.source_type='scholarship_detail' and coalesce(ps.metadata->>'bounded_international_wave_2','false')='true' and sr.evidence_id is not null
), cleaned as (
 select r.*,case when r.canonical_name ilike '% The %' and length(r.canonical_name)>180 then trim(split_part(r.canonical_name,' The ',1)) else r.canonical_name end final_name from ready r
), canon as (
 select r.*,s.id scholarship_id from cleaned r join scholarship.scholarships s on s.provider_id=r.provider_id and (s.source_url=r.source_record_url or lower(regexp_replace(s.name,'[^a-z0-9]+','','g'))=lower(regexp_replace(r.final_name,'[^a-z0-9]+','','g')))
)
insert into pipeline.scholarship_acquisition_trace(provider_id,observed_title,first_party_detail_url,discovery_candidate_id,source_record_id,scholarship_id,verification_evidence_id,stage,verification_status,observed_at,verified_at,metadata)
select c.provider_id,c.final_name,c.source_record_url,c.candidate_id,c.source_record_id,c.scholarship_id,c.evidence_id,'canonical_unpublished','verified_first_party',now(),now(),jsonb_build_object('authority','first_party','bounded_international_wave_2',true,'canonical_match_basis','provider_plus_detail_evidence','cf_change','CF-145')
from canon c where not exists(select 1 from pipeline.scholarship_acquisition_trace t where t.provider_id=c.provider_id and t.first_party_detail_url=c.source_record_url);

update scholarship.scholarships s set award_value_type='percentage',award_percentage=(regexp_match(s.award_value_text,'([0-9]+(?:\.[0-9]+)?)\s*%'))[1]::numeric,
  award_fee_basis=case when s.award_value_text ilike '%tuition%' or s.award_value_text ilike '%course fee%' then 'tuition_fee' else s.award_fee_basis end,updated_at=now()
where s.publication_status='unpublished' and s.award_value_text ~ '[0-9]+(?:\.[0-9]+)?\s*%'
  and exists(select 1 from pipeline.sources ps where ps.id=s.source_id and coalesce(ps.metadata->>'bounded_international_wave_2','false')='true');

update scholarship.scholarships s set award_value_type='fixed_amount',award_amount=replace((regexp_match(s.award_value_text,'\$\s*([0-9,]+(?:\.[0-9]+)?)'))[1],',','')::numeric,
  award_currency_code=coalesce(s.award_currency_code,'AUD'),updated_at=now()
where s.publication_status='unpublished' and s.award_value_text ~ '\$\s*[0-9,]+'
  and exists(select 1 from pipeline.sources ps where ps.id=s.source_id and coalesce(ps.metadata->>'bounded_international_wave_2','false')='true');

update pipeline.layer2_scholarship_discovery_candidates c set status='acquired'
where c.id in (select (metadata->>'candidate_id')::uuid from pipeline.sources where source_type='scholarship_detail' and coalesce(metadata->>'bounded_international_wave_2','false')='true');
