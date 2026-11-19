with ready as (
  select ps.provider_id,ps.id source_id,(ps.metadata->>'candidate_id')::uuid candidate_id,
         sr.id source_record_id,sr.source_record_url,sr.evidence_id,
         c.observed_title,
         case when lower(trim(coalesce(sr.payload->>'name',''))) in ('scholarship','scholarships','find a scholarship','find scholarships')
              then c.observed_title else coalesce(nullif(sr.payload->>'name',''),c.observed_title) end canonical_name,
         nullif(sr.payload->>'award_value_text','') award_text,
         'scholarship:AU:first-party-detail:'||replace(ps.provider_id::text,'-','')||':'||md5(sr.source_record_url) stable_key
  from pipeline.sources ps
  join pipeline.layer2_scholarship_discovery_candidates c on c.id=(ps.metadata->>'candidate_id')::uuid
  join lateral (select x.* from pipeline.scholarship_source_records x where x.source_id=ps.id order by x.created_at desc limit 1) sr on true
  where ps.source_type='scholarship_detail'
    and coalesce(ps.metadata->>'bounded_international_wave_2','false')='true'
    and sr.evidence_id is not null
), cleaned as (
  select r.*,
         case when r.canonical_name ilike '% The %' and length(r.canonical_name)>180
              then trim(split_part(r.canonical_name,' The ',1)) else r.canonical_name end final_name
  from ready r
)
update pipeline.scholarship_source_records sr
set payload=coalesce(sr.payload,'{}'::jsonb)||jsonb_build_object(
  'name',c.final_name,
  'first_party_verified',true,
  'reconciliation_basis','candidate_identity_plus_detail_evidence',
  'canonical_mutation_authorised',false
),status='captured'
from cleaned c where sr.id=c.source_record_id;

with ready as (
  select ps.provider_id,ps.id source_id,(ps.metadata->>'candidate_id')::uuid candidate_id,
         sr.id source_record_id,sr.source_record_url,sr.evidence_id,
         c.observed_title,
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
  on conflict(stable_key) do update set updated_at=now()
  returning id,stable_key
)
insert into scholarship.scholarships(id,stable_key,provider_id,name,scholarship_type,audience,award_value_text,source_url,lifecycle_status,publication_status,source_id,evidence_id,confidence)
select reg.id,r.stable_key,r.provider_id,r.final_name,'provider_scholarship','international',r.award_text,r.source_record_url,'active','unpublished',r.source_id,r.evidence_id,0.95
from cleaned r join reg on reg.stable_key=r.stable_key
on conflict(id) do update set name=excluded.name,source_url=excluded.source_url,source_id=excluded.source_id,evidence_id=excluded.evidence_id,award_value_text=coalesce(excluded.award_value_text,scholarship.scholarships.award_value_text),updated_at=now();

with ready as (
  select ps.provider_id,(ps.metadata->>'candidate_id')::uuid candidate_id,sr.id source_record_id,sr.source_record_url,sr.evidence_id,
         c.observed_title,
         case when lower(trim(coalesce(sr.payload->>'name',''))) in ('scholarship','scholarships','find a scholarship','find scholarships')
              then c.observed_title else coalesce(nullif(sr.payload->>'name',''),c.observed_title) end canonical_name
  from pipeline.sources ps
  join pipeline.layer2_scholarship_discovery_candidates c on c.id=(ps.metadata->>'candidate_id')::uuid
  join lateral (select x.* from pipeline.scholarship_source_records x where x.source_id=ps.id order by x.created_at desc limit 1) sr on true
  where ps.source_type='scholarship_detail' and coalesce(ps.metadata->>'bounded_international_wave_2','false')='true' and sr.evidence_id is not null
), cleaned as (
  select r.*,case when r.canonical_name ilike '% The %' and length(r.canonical_name)>180 then trim(split_part(r.canonical_name,' The ',1)) else r.canonical_name end final_name
  from ready r
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
