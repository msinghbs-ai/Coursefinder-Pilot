with csu as (
  select id provider_id from catalogue.providers where canonical_name='Charles Sturt University' limit 1
), matched as (
  select sr.id source_record_id,sr.source_record_url,sr.evidence_id,s.id scholarship_id,s.name,s.award_value_text
  from pipeline.scholarship_source_records sr
  join pipeline.sources ps on ps.id=sr.source_id
  join csu on csu.provider_id=ps.provider_id
  join scholarship.scholarships s on s.provider_id=csu.provider_id and s.source_url=sr.source_record_url
  where sr.created_at >= now()-interval '1 day'
)
update pipeline.scholarship_source_records sr
set payload = coalesce(sr.payload,'{}'::jsonb) || jsonb_build_object('name',m.name,'canonical_match_id',m.scholarship_id,'canonical_match_basis','provider_plus_first_party_detail_url'),
    status='captured'
from matched m where sr.id=m.source_record_id;

with csu as (select id provider_id from catalogue.providers where canonical_name='Charles Sturt University' limit 1), urls as (
  select s.source_url from scholarship.scholarships s join csu on csu.provider_id=s.provider_id
)
update pipeline.layer2_scholarship_discovery_candidates c
set status='acquired'
from pipeline.sources ps, csu
where c.source_id=ps.id and ps.provider_id=csu.provider_id and c.status='discovered' and c.scholarship_url in (select source_url from urls);

with csu as (select id provider_id from catalogue.providers where canonical_name='Charles Sturt University' limit 1), src as (
  select distinct on (sr.source_record_url) sr.source_record_url,sr.evidence_id,sr.payload->>'award_value_text' award_text
  from pipeline.scholarship_source_records sr join pipeline.sources ps on ps.id=sr.source_id join csu on csu.provider_id=ps.provider_id
  where sr.created_at>=now()-interval '1 day' order by sr.source_record_url,sr.created_at desc
)
update scholarship.scholarships s
set award_value_type='percentage',
    award_percentage=(regexp_match(src.award_text,'([0-9]+(?:\.[0-9]+)?)\s*%'))[1]::numeric,
    award_fee_basis=case when src.award_text ilike '%tuition%' then 'tuition_fee' else award_fee_basis end,
    updated_at=now()
from src,csu
where s.provider_id=csu.provider_id and s.source_url=src.source_record_url and src.award_text ~ '[0-9]+(?:\.[0-9]+)?\s*%';

with csu as (select id provider_id from catalogue.providers where canonical_name='Charles Sturt University' limit 1), base as (
 select s.id scholarship_id,s.name,s.source_url,
   (select c.id from pipeline.layer2_scholarship_discovery_candidates c join pipeline.sources ps on ps.id=c.source_id where ps.provider_id=csu.provider_id and c.scholarship_url=s.source_url order by c.created_at desc limit 1) discovery_candidate_id,
   (select sr.id from pipeline.scholarship_source_records sr join pipeline.sources ps on ps.id=sr.source_id where ps.provider_id=csu.provider_id and sr.source_record_url=s.source_url order by sr.created_at desc limit 1) source_record_id,
   (select sr.evidence_id from pipeline.scholarship_source_records sr join pipeline.sources ps on ps.id=sr.source_id where ps.provider_id=csu.provider_id and sr.source_record_url=s.source_url order by sr.created_at desc limit 1) verification_evidence_id
 from scholarship.scholarships s,csu where s.provider_id=csu.provider_id and s.publication_status='unpublished'
)
insert into pipeline.scholarship_acquisition_trace(provider_id,observed_title,first_party_detail_url,discovery_candidate_id,source_record_id,scholarship_id,verification_evidence_id,stage,verification_status,observed_at,verified_at,metadata)
select csu.provider_id,b.name,b.source_url,b.discovery_candidate_id,b.source_record_id,b.scholarship_id,b.verification_evidence_id,'canonical_unpublished','verified_first_party',now(),now(),jsonb_build_object('authority','first_party','reconciliation_basis','provider_plus_detail_url','cf_change','CF-128')
from base b,csu
where b.source_record_id is not null and b.verification_evidence_id is not null and not exists(select 1 from pipeline.scholarship_acquisition_trace t where t.scholarship_id=b.scholarship_id and t.verification_evidence_id=b.verification_evidence_id);
