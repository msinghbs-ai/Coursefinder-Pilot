-- CF-138..140 — Bounded international Scholarship detail wave, canonical reconciliation and provider stats.
-- This source migration is idempotent and reproduces the final Pilot state without broad Publication.

with selected as (
  select distinct on (p.id,c.detail_target_url) p.id provider_id,p.country_id,c.id candidate_id,c.detail_target_url,c.observed_title
  from pipeline.layer2_scholarship_discovery_candidates c join pipeline.sources src on src.id=c.source_id join catalogue.providers p on p.id=src.provider_id
  where c.status='discovered' and c.classification='detail_ready' and c.detail_target_url is not null
    and (coalesce(c.observed_title,'') ilike '%international%' or coalesce(c.observed_title,'') ilike '%ASEAN%')
    and p.canonical_name in ('Monash University','Edith Cowan University')
    and not exists(select 1 from pipeline.scholarship_acquisition_trace t where t.provider_id=p.id and t.first_party_detail_url=c.detail_target_url)
    and not exists(select 1 from scholarship.scholarships s where s.provider_id=p.id and s.source_url=c.detail_target_url)
  order by p.id,c.detail_target_url,c.created_at desc limit 12
)
insert into pipeline.sources(source_type,provider_id,country_id,url,label,trust_rank,status,metadata)
select 'scholarship_detail',s.provider_id,s.country_id,s.detail_target_url,left(coalesce(s.observed_title,'Scholarship detail'),180),100,'active',
  jsonb_build_object('authority','first_party','candidate_id',s.candidate_id,'bounded_international_wave',true,'change_control_ref','CF-138')
from selected s where not exists(select 1 from pipeline.sources x where x.provider_id=s.provider_id and x.source_type='scholarship_detail' and x.url=s.detail_target_url);

-- Runtime profile/version/policy/route records use the same deterministic detail-profile contract as CF-127..130.
-- Existing deployments may already contain these records; Production replay must create them before dispatch.

-- Reconcile Evidence produced by the bounded wave to canonical unpublished records.
with ready as (
  select ps.provider_id,ps.id source_id,(ps.metadata->>'candidate_id')::uuid candidate_id,sr.id source_record_id,sr.source_record_url,sr.evidence_id,
         nullif(sr.payload->>'name','') name,nullif(sr.payload->>'award_value_text','') award_text,
         'scholarship:AU:first-party-detail:'||replace(ps.provider_id::text,'-','')||':'||md5(sr.source_record_url) stable_key
  from pipeline.sources ps join lateral (select x.* from pipeline.scholarship_source_records x where x.source_id=ps.id order by x.created_at desc limit 1) sr on true
  where ps.source_type='scholarship_detail' and coalesce(ps.metadata->>'bounded_international_wave','false')='true'
    and nullif(sr.payload->>'name','') is not null and sr.evidence_id is not null
), reg as (
  insert into pim.entity_registry(id,entity_type,stable_key,lifecycle_status)
  select scholarship.deterministic_uuid(stable_key),'scholarship',stable_key,'active' from ready r
  where not exists(select 1 from scholarship.scholarships s where s.provider_id=r.provider_id and lower(regexp_replace(s.name,'[^a-z0-9]+','','g'))=lower(regexp_replace(r.name,'[^a-z0-9]+','','g')))
  on conflict(stable_key) do update set updated_at=now() returning id,stable_key
)
insert into scholarship.scholarships(id,stable_key,provider_id,name,scholarship_type,audience,award_value_text,source_url,lifecycle_status,publication_status,source_id,evidence_id,confidence)
select reg.id,r.stable_key,r.provider_id,r.name,'provider_scholarship','international',r.award_text,r.source_record_url,'active','unpublished',r.source_id,r.evidence_id,0.95
from ready r join reg on reg.stable_key=r.stable_key
on conflict(id) do update set source_url=excluded.source_url,source_id=excluded.source_id,evidence_id=excluded.evidence_id,award_value_text=coalesce(excluded.award_value_text,scholarship.scholarships.award_value_text),updated_at=now();

with ready as (
  select ps.provider_id,ps.id source_id,(ps.metadata->>'candidate_id')::uuid candidate_id,sr.id source_record_id,sr.source_record_url,sr.evidence_id,
         nullif(sr.payload->>'name','') name,nullif(sr.payload->>'award_value_text','') award_text
  from pipeline.sources ps join lateral (select x.* from pipeline.scholarship_source_records x where x.source_id=ps.id order by x.created_at desc limit 1) sr on true
  where ps.source_type='scholarship_detail' and coalesce(ps.metadata->>'bounded_international_wave','false')='true' and sr.evidence_id is not null
), canon as (
  select r.*,s.id scholarship_id from ready r join scholarship.scholarships s on s.provider_id=r.provider_id
    and (s.source_url=r.source_record_url or lower(regexp_replace(s.name,'[^a-z0-9]+','','g'))=lower(regexp_replace(r.name,'[^a-z0-9]+','','g')))
)
update scholarship.scholarships s set source_url=c.source_record_url,source_id=c.source_id,evidence_id=c.evidence_id,award_value_text=coalesce(c.award_text,s.award_value_text),updated_at=now()
from canon c where s.id=c.scholarship_id;

with ready as (
  select ps.provider_id,(ps.metadata->>'candidate_id')::uuid candidate_id,sr.id source_record_id,sr.source_record_url,sr.evidence_id,
         nullif(sr.payload->>'name','') name,s.id scholarship_id
  from pipeline.sources ps join lateral (select x.* from pipeline.scholarship_source_records x where x.source_id=ps.id order by x.created_at desc limit 1) sr on true
  join scholarship.scholarships s on s.provider_id=ps.provider_id and s.source_url=sr.source_record_url
  where ps.source_type='scholarship_detail' and coalesce(ps.metadata->>'bounded_international_wave','false')='true'
)
insert into pipeline.scholarship_acquisition_trace(provider_id,observed_title,first_party_detail_url,discovery_candidate_id,source_record_id,scholarship_id,verification_evidence_id,stage,verification_status,observed_at,verified_at,metadata)
select r.provider_id,r.name,r.source_record_url,r.candidate_id,r.source_record_id,r.scholarship_id,r.evidence_id,'canonical_unpublished','verified_first_party',now(),now(),jsonb_build_object('authority','first_party','bounded_international_wave',true,'cf_change','CF-139')
from ready r where not exists(select 1 from pipeline.scholarship_acquisition_trace t where t.provider_id=r.provider_id and t.first_party_detail_url=r.source_record_url);

update scholarship.scholarships s set award_value_type='percentage',award_percentage=(regexp_match(s.award_value_text,'([0-9]+(?:\.[0-9]+)?)\s*%'))[1]::numeric,
  award_fee_basis=case when s.award_value_text ilike '%tuition%' or s.award_value_text ilike '%course fee%' then 'tuition_fee' else s.award_fee_basis end,updated_at=now()
where s.publication_status='unpublished' and s.award_value_text ~ '[0-9]+(?:\.[0-9]+)?\s*%'
  and exists(select 1 from pipeline.sources ps where ps.id=s.source_id and coalesce(ps.metadata->>'bounded_international_wave','false')='true');
update scholarship.scholarships s set award_value_type='fixed_amount',award_amount=replace((regexp_match(s.award_value_text,'\$\s*([0-9,]+(?:\.[0-9]+)?)'))[1],',','')::numeric,
  award_currency_code=coalesce(s.award_currency_code,'AUD'),updated_at=now()
where s.publication_status='unpublished' and s.award_value_text ~ '\$\s*[0-9,]+'
  and exists(select 1 from pipeline.sources ps where ps.id=s.source_id and coalesce(ps.metadata->>'bounded_international_wave','false')='true');
update pipeline.layer2_scholarship_discovery_candidates c set status='acquired'
where c.id in (select (metadata->>'candidate_id')::uuid from pipeline.sources where source_type='scholarship_detail' and coalesce(metadata->>'bounded_international_wave','false')='true');

-- Provider stats includes candidate classification progress; browser access remains through scholarship_operations_read().
create or replace view pipeline.scholarship_provider_stats as
with canonical as (select provider_id,count(*)::int canonical_total,count(*) filter(where publication_status='published')::int published_total,count(*) filter(where publication_status<>'published')::int unpublished_total from scholarship.scholarships group by provider_id),
trace as (select provider_id,count(*)::int trace_total,count(*) filter(where verification_status='verified_first_party')::int first_party_verified_total,count(*) filter(where review_queue_id is not null)::int layer4_linked_total,count(*) filter(where scholarship_id is not null)::int canonical_linked_total,count(*) filter(where publication_decision_id is not null)::int publication_decision_linked_total,count(*) filter(where verification_evidence_id is not null and source_record_id is not null)::int evidence_acquired_total,max(updated_at) trace_last_updated_at from pipeline.scholarship_acquisition_trace group by provider_id),
candidates as (select s.provider_id,count(*)::int candidate_total,count(*) filter(where c.status='discovered' and c.classification='detail_ready')::int detail_ready_total,count(*) filter(where c.status='discovered' and c.classification='needs_review')::int candidate_needs_review_total,count(*) filter(where c.status='rejected')::int candidate_rejected_total,count(*) filter(where c.status='acquired')::int candidate_acquired_total,max(c.classified_at) candidate_last_classified_at from pipeline.layer2_scholarship_discovery_candidates c join pipeline.sources s on s.id=c.source_id where s.provider_id is not null group by s.provider_id),
latest_benchmark as (select distinct on(provider_id) provider_id,observed_count landscape_benchmark_total,observed_at benchmark_observed_at from pipeline.scholarship_coverage_benchmarks where benchmark_scope='provider' and provider_id is not null order by provider_id,observed_at desc)
select p.id provider_id,p.canonical_name provider_name,coalesce(c.canonical_total,0) canonical_total,coalesce(c.published_total,0) published_total,coalesce(c.unpublished_total,0) unpublished_total,coalesce(t.trace_total,0) trace_total,coalesce(t.first_party_verified_total,0) first_party_verified_total,coalesce(t.layer4_linked_total,0) layer4_linked_total,coalesce(t.canonical_linked_total,0) canonical_linked_total,coalesce(t.publication_decision_linked_total,0) publication_decision_linked_total,lb.landscape_benchmark_total,case when lb.landscape_benchmark_total is null then null else greatest(lb.landscape_benchmark_total-coalesce(c.canonical_total,0),0) end indicative_gap_to_landscape,case when lb.landscape_benchmark_total is null or lb.landscape_benchmark_total=0 then null else round(coalesce(c.canonical_total,0)::numeric/lb.landscape_benchmark_total::numeric*100,1) end canonical_to_landscape_pct,lb.benchmark_observed_at,t.trace_last_updated_at,coalesce(t.evidence_acquired_total,0) evidence_acquired_total,coalesce(k.candidate_total,0) candidate_total,coalesce(k.detail_ready_total,0) detail_ready_total,coalesce(k.candidate_needs_review_total,0) candidate_needs_review_total,coalesce(k.candidate_rejected_total,0) candidate_rejected_total,coalesce(k.candidate_acquired_total,0) candidate_acquired_total,k.candidate_last_classified_at
from catalogue.providers p left join canonical c on c.provider_id=p.id left join trace t on t.provider_id=p.id left join candidates k on k.provider_id=p.id left join latest_benchmark lb on lb.provider_id=p.id
where coalesce(c.canonical_total,0)>0 or coalesce(t.trace_total,0)>0 or coalesce(k.candidate_total,0)>0 or lb.provider_id is not null;
revoke all on pipeline.scholarship_provider_stats from public,anon,authenticated;
grant select on pipeline.scholarship_provider_stats to service_role;
