with ready as (
  select ps.provider_id,ps.id source_id,(ps.metadata->>'candidate_id')::uuid candidate_id,
         sr.id source_record_id,sr.source_record_url,sr.evidence_id,
         nullif(sr.payload->>'name','') name,nullif(sr.payload->>'award_value_text','') award_text,
         'scholarship:AU:first-party-detail:'||replace(ps.provider_id::text,'-','')||':'||md5(sr.source_record_url) stable_key
  from pipeline.sources ps
  join lateral (
    select x.* from pipeline.scholarship_source_records x where x.source_id=ps.id order by x.created_at desc limit 1
  ) sr on true
  where ps.source_type='scholarship_detail' and coalesce(ps.metadata->>'bounded_international_wave','false')='true'
    and nullif(sr.payload->>'name','') is not null and sr.evidence_id is not null
), matched as (
  select r.*,s.id scholarship_id from ready r join scholarship.scholarships s on s.provider_id=r.provider_id
   and lower(regexp_replace(s.name,'[^a-z0-9]+','','g'))=lower(regexp_replace(r.name,'[^a-z0-9]+','','g'))
)
update scholarship.scholarships s set source_url=m.source_record_url,source_id=m.source_id,evidence_id=m.evidence_id,
  award_value_text=coalesce(m.award_text,s.award_value_text),audience=coalesce(s.audience,'international'),updated_at=now()
from matched m where s.id=m.scholarship_id;

with ready as (
  select ps.provider_id,ps.id source_id,(ps.metadata->>'candidate_id')::uuid candidate_id,
         sr.id source_record_id,sr.source_record_url,sr.evidence_id,
         nullif(sr.payload->>'name','') name,nullif(sr.payload->>'award_value_text','') award_text,
         'scholarship:AU:first-party-detail:'||replace(ps.provider_id::text,'-','')||':'||md5(sr.source_record_url) stable_key
  from pipeline.sources ps
  join lateral (select x.* from pipeline.scholarship_source_records x where x.source_id=ps.id order by x.created_at desc limit 1) sr on true
  where ps.source_type='scholarship_detail' and coalesce(ps.metadata->>'bounded_international_wave','false')='true'
    and nullif(sr.payload->>'name','') is not null and sr.evidence_id is not null
    and not exists(select 1 from scholarship.scholarships s where s.provider_id=ps.provider_id
      and lower(regexp_replace(s.name,'[^a-z0-9]+','','g'))=lower(regexp_replace(sr.payload->>'name','[^a-z0-9]+','','g')))
), reg as (
  insert into pim.entity_registry(id,entity_type,stable_key,lifecycle_status)
  select scholarship.deterministic_uuid(stable_key),'scholarship',stable_key,'active' from ready
  on conflict(stable_key) do update set updated_at=now()
  returning id,stable_key
)
insert into scholarship.scholarships(id,stable_key,provider_id,name,scholarship_type,audience,award_value_text,source_url,lifecycle_status,publication_status,source_id,evidence_id,confidence)
select reg.id,r.stable_key,r.provider_id,r.name,'provider_scholarship','international',r.award_text,r.source_record_url,'active','unpublished',r.source_id,r.evidence_id,0.95
from ready r join reg on reg.stable_key=r.stable_key
on conflict(id) do update set source_url=excluded.source_url,source_id=excluded.source_id,evidence_id=excluded.evidence_id,
  award_value_text=coalesce(excluded.award_value_text,scholarship.scholarships.award_value_text),updated_at=now();

-- Create end-to-end trace rows for the newly detail-verified set, or attach an existing trace for the same first-party URL.
with ready as (
  select ps.provider_id,ps.id source_id,(ps.metadata->>'candidate_id')::uuid candidate_id,
         sr.id source_record_id,sr.source_record_url,sr.evidence_id,
         nullif(sr.payload->>'name','') name,
         s.id scholarship_id
  from pipeline.sources ps
  join lateral (select x.* from pipeline.scholarship_source_records x where x.source_id=ps.id order by x.created_at desc limit 1) sr on true
  join scholarship.scholarships s on s.provider_id=ps.provider_id and s.source_url=sr.source_record_url
  where ps.source_type='scholarship_detail' and coalesce(ps.metadata->>'bounded_international_wave','false')='true'
)
insert into pipeline.scholarship_acquisition_trace(provider_id,observed_title,first_party_detail_url,discovery_candidate_id,source_record_id,scholarship_id,verification_evidence_id,stage,verification_status,observed_at,verified_at,metadata)
select r.provider_id,r.name,r.source_record_url,r.candidate_id,r.source_record_id,r.scholarship_id,r.evidence_id,
       'canonical_unpublished','verified_first_party',now(),now(),jsonb_build_object('authority','first_party','bounded_international_wave',true,'cf_change','CF-139')
from ready r
where not exists(select 1 from pipeline.scholarship_acquisition_trace t where t.provider_id=r.provider_id and t.first_party_detail_url=r.source_record_url);

with ready as (
  select ps.provider_id,(ps.metadata->>'candidate_id')::uuid candidate_id,sr.id source_record_id,sr.source_record_url,sr.evidence_id,
         nullif(sr.payload->>'name','') name,s.id scholarship_id
  from pipeline.sources ps
  join lateral (select x.* from pipeline.scholarship_source_records x where x.source_id=ps.id order by x.created_at desc limit 1) sr on true
  join scholarship.scholarships s on s.provider_id=ps.provider_id and s.source_url=sr.source_record_url
  where ps.source_type='scholarship_detail' and coalesce(ps.metadata->>'bounded_international_wave','false')='true'
)
update pipeline.scholarship_acquisition_trace t set discovery_candidate_id=coalesce(t.discovery_candidate_id,r.candidate_id),source_record_id=r.source_record_id,
  scholarship_id=r.scholarship_id,verification_evidence_id=r.evidence_id,stage='canonical_unpublished',verification_status='verified_first_party',
  verified_at=coalesce(t.verified_at,now()),updated_at=now(),metadata=coalesce(t.metadata,'{}'::jsonb)||jsonb_build_object('bounded_international_wave',true,'cf_change','CF-139')
from ready r where t.provider_id=r.provider_id and t.first_party_detail_url=r.source_record_url;

insert into scholarship.identifiers(id,scholarship_id,scheme,identifier_value,source_id,evidence_id,is_primary,status)
select scholarship.deterministic_uuid('first-party-detail:'||s.id::text||':'||s.source_url),s.id,'first_party_detail_url',s.source_url,s.source_id,s.evidence_id,true,'active'
from scholarship.scholarships s
join pipeline.sources ps on ps.id=s.source_id
where ps.source_type='scholarship_detail' and coalesce(ps.metadata->>'bounded_international_wave','false')='true'
on conflict(source_id,scheme,identifier_value) do update set scholarship_id=excluded.scholarship_id,evidence_id=excluded.evidence_id,is_primary=true,status='active';

update scholarship.scholarships s set award_value_type='percentage',
  award_percentage=(regexp_match(s.award_value_text,'([0-9]+(?:\.[0-9]+)?)\s*%'))[1]::numeric,
  award_fee_basis=case when s.award_value_text ilike '%tuition%' or s.award_value_text ilike '%course fee%' then 'tuition_fee' else s.award_fee_basis end,updated_at=now()
where s.publication_status='unpublished' and s.award_value_text ~ '[0-9]+(?:\.[0-9]+)?\s*%'
  and exists(select 1 from pipeline.sources ps where ps.id=s.source_id and coalesce(ps.metadata->>'bounded_international_wave','false')='true');

update scholarship.scholarships s set award_value_type='fixed_amount',
  award_amount=replace((regexp_match(s.award_value_text,'\$\s*([0-9,]+(?:\.[0-9]+)?)'))[1],',','')::numeric,
  award_currency_code=coalesce(s.award_currency_code,'AUD'),updated_at=now()
where s.publication_status='unpublished' and s.award_value_text ~ '\$\s*[0-9,]+'
  and exists(select 1 from pipeline.sources ps where ps.id=s.source_id and coalesce(ps.metadata->>'bounded_international_wave','false')='true');

update pipeline.layer2_scholarship_discovery_candidates c set status='acquired'
where c.id in (select (metadata->>'candidate_id')::uuid from pipeline.sources where source_type='scholarship_detail' and coalesce(metadata->>'bounded_international_wave','false')='true');
