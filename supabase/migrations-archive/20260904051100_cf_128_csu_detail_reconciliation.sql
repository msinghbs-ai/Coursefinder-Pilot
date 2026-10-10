-- CF-128 — Charles Sturt Scholarship detail reconciliation.
-- Exact Provider + first-party detail URL is the canonical match basis. Publication remains unchanged.

with csu as (
  select id provider_id from catalogue.providers where canonical_name='Charles Sturt University' limit 1
), matched as (
  select sr.id source_record_id,sr.source_record_url,sr.evidence_id,s.id scholarship_id,s.name
  from pipeline.scholarship_source_records sr
  join pipeline.sources ps on ps.id=sr.source_id
  join csu on csu.provider_id=ps.provider_id
  join scholarship.scholarships s on s.provider_id=csu.provider_id and s.source_url=sr.source_record_url
)
update pipeline.scholarship_source_records sr
set payload=coalesce(sr.payload,'{}'::jsonb)||jsonb_build_object(
      'name',m.name,'canonical_match_id',m.scholarship_id,
      'canonical_match_basis','provider_plus_first_party_detail_url'
    ),status='captured'
from matched m where sr.id=m.source_record_id;

with csu as (select id provider_id from catalogue.providers where canonical_name='Charles Sturt University' limit 1)
update pipeline.layer2_scholarship_discovery_candidates c set status='acquired'
from pipeline.sources ps,csu
where c.source_id=ps.id and ps.provider_id=csu.provider_id and c.status='discovered'
  and exists(select 1 from scholarship.scholarships s where s.provider_id=csu.provider_id and s.source_url=c.scholarship_url);

with csu as (select id provider_id from catalogue.providers where canonical_name='Charles Sturt University' limit 1), src as (
  select distinct on (sr.source_record_url) sr.source_record_url,sr.evidence_id,sr.payload->>'award_value_text' award_text
  from pipeline.scholarship_source_records sr
  join pipeline.sources ps on ps.id=sr.source_id join csu on csu.provider_id=ps.provider_id
  order by sr.source_record_url,sr.created_at desc
)
update scholarship.scholarships s
set award_value_type='percentage',
    award_percentage=(regexp_match(src.award_text,'([0-9]+(?:\.[0-9]+)?)\s*%'))[1]::numeric,
    award_fee_basis=case when src.award_text ilike '%tuition%' then 'tuition_fee' else award_fee_basis end,
    evidence_id=coalesce(src.evidence_id,s.evidence_id),updated_at=now()
from src,csu
where s.provider_id=csu.provider_id and s.source_url=src.source_record_url
  and src.award_text ~ '[0-9]+(?:\.[0-9]+)?\s*%';
