-- CF-131 — Reconcile verified first-party Scholarship detail Evidence to canonical unpublished roots.
-- Exact Provider/title matches are reused first. New verified detail identities become unpublished canonical roots only.
-- No Search/Website/Zoho/Publication admission is performed.

with ready as (
  select t.id trace_id,t.provider_id,t.observed_title,t.first_party_detail_url,t.metadata,
         ps.id source_id,sr.id source_record_id,sr.evidence_id,
         coalesce(nullif(sr.payload->>'award_value_text',''),nullif(t.metadata->>'award_value','')) award_text
  from pipeline.scholarship_acquisition_trace t
  join pipeline.sources ps on ps.provider_id=t.provider_id and ps.source_type='scholarship_detail' and ps.url=t.first_party_detail_url
  join lateral (
    select x.* from pipeline.scholarship_source_records x
    where x.source_id=ps.id and x.source_record_url=t.first_party_detail_url
    order by x.created_at desc limit 1
  ) sr on true
  where t.verification_status='verified_first_party'
    and t.stage='first_party_verified'
    and t.verification_evidence_id is null
    and t.first_party_detail_url is not null
)
update pipeline.scholarship_source_records sr
set payload=coalesce(sr.payload,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object(
      'name',r.observed_title,'award_value_text',r.award_text,'first_party_verified',true,
      'reconciliation_basis','verified_trace_plus_detail_evidence'
    )),status='captured'
from ready r where sr.id=r.source_record_id;

-- Reuse exact Provider + normalised title matches.
with ready as (
  select t.id trace_id,t.provider_id,t.observed_title,t.first_party_detail_url,
         ps.id source_id,sr.id source_record_id,sr.evidence_id,
         coalesce(nullif(sr.payload->>'award_value_text',''),nullif(t.metadata->>'award_value','')) award_text
  from pipeline.scholarship_acquisition_trace t
  join pipeline.sources ps on ps.provider_id=t.provider_id and ps.source_type='scholarship_detail' and ps.url=t.first_party_detail_url
  join lateral (select x.* from pipeline.scholarship_source_records x where x.source_id=ps.id and x.source_record_url=t.first_party_detail_url order by x.created_at desc limit 1) sr on true
  where t.verification_status='verified_first_party' and t.stage='first_party_verified' and t.verification_evidence_id is null
), matched as (
  select r.*,s.id scholarship_id
  from ready r join scholarship.scholarships s on s.provider_id=r.provider_id
   and lower(regexp_replace(s.name,'[^a-z0-9]+','','g'))=lower(regexp_replace(r.observed_title,'[^a-z0-9]+','','g'))
)
update scholarship.scholarships s set
  source_url=m.first_party_detail_url,source_id=m.source_id,evidence_id=m.evidence_id,
  award_value_text=coalesce(m.award_text,s.award_value_text),updated_at=now()
from matched m where s.id=m.scholarship_id;

with ready as (
  select t.id trace_id,t.provider_id,t.observed_title,t.first_party_detail_url,
         ps.id source_id,sr.id source_record_id,sr.evidence_id
  from pipeline.scholarship_acquisition_trace t
  join pipeline.sources ps on ps.provider_id=t.provider_id and ps.source_type='scholarship_detail' and ps.url=t.first_party_detail_url
  join lateral (select x.* from pipeline.scholarship_source_records x where x.source_id=ps.id and x.source_record_url=t.first_party_detail_url order by x.created_at desc limit 1) sr on true
  where t.verification_status='verified_first_party' and t.stage='first_party_verified' and t.verification_evidence_id is null
), matched as (
  select r.*,s.id scholarship_id
  from ready r join scholarship.scholarships s on s.provider_id=r.provider_id
   and lower(regexp_replace(s.name,'[^a-z0-9]+','','g'))=lower(regexp_replace(r.observed_title,'[^a-z0-9]+','','g'))
)
update pipeline.scholarship_acquisition_trace t set
  source_record_id=m.source_record_id,scholarship_id=m.scholarship_id,verification_evidence_id=m.evidence_id,
  stage='canonical_unpublished',verified_at=now(),updated_at=now(),
  metadata=coalesce(t.metadata,'{}'::jsonb)||jsonb_build_object('canonical_match_basis','provider_plus_normalised_title','cf_change','CF-131')
from matched m where t.id=m.trace_id;

-- Create new canonical unpublished roots only where no exact Provider/title identity exists.
with ready as (
  select t.id trace_id,t.provider_id,t.observed_title,t.first_party_detail_url,t.metadata,
         ps.id source_id,sr.id source_record_id,sr.evidence_id,
         coalesce(nullif(sr.payload->>'award_value_text',''),nullif(t.metadata->>'award_value','')) award_text,
         'scholarship:AU:first-party-detail:'||replace(t.provider_id::text,'-','')||':'||md5(t.first_party_detail_url) stable_key
  from pipeline.scholarship_acquisition_trace t
  join pipeline.sources ps on ps.provider_id=t.provider_id and ps.source_type='scholarship_detail' and ps.url=t.first_party_detail_url
  join lateral (select x.* from pipeline.scholarship_source_records x where x.source_id=ps.id and x.source_record_url=t.first_party_detail_url order by x.created_at desc limit 1) sr on true
  where t.verification_status='verified_first_party' and t.stage='first_party_verified' and t.verification_evidence_id is null
    and not exists(
      select 1 from scholarship.scholarships s where s.provider_id=t.provider_id
      and lower(regexp_replace(s.name,'[^a-z0-9]+','','g'))=lower(regexp_replace(t.observed_title,'[^a-z0-9]+','','g'))
    )
), reg as (
  insert into pim.entity_registry(id,entity_type,stable_key,lifecycle_status)
  select scholarship.deterministic_uuid(stable_key),'scholarship',stable_key,'active' from ready
  on conflict(stable_key) do update set updated_at=now()
  returning id,stable_key
)
insert into scholarship.scholarships(
  id,stable_key,provider_id,name,scholarship_type,audience,award_value_text,academic_year,
  source_url,lifecycle_status,publication_status,source_id,evidence_id,confidence
)
select reg.id,r.stable_key,r.provider_id,r.observed_title,'provider_scholarship','international',r.award_text,
       nullif(r.metadata->>'academic_year','')::int,r.first_party_detail_url,'active','unpublished',r.source_id,r.evidence_id,0.90
from ready r join reg on reg.stable_key=r.stable_key
on conflict(id) do update set source_url=excluded.source_url,source_id=excluded.source_id,evidence_id=excluded.evidence_id,
  award_value_text=coalesce(excluded.award_value_text,scholarship.scholarships.award_value_text),updated_at=now();

with ready as (
  select t.id trace_id,t.provider_id,t.first_party_detail_url,ps.id source_id,sr.id source_record_id,sr.evidence_id
  from pipeline.scholarship_acquisition_trace t
  join pipeline.sources ps on ps.provider_id=t.provider_id and ps.source_type='scholarship_detail' and ps.url=t.first_party_detail_url
  join lateral (select x.* from pipeline.scholarship_source_records x where x.source_id=ps.id and x.source_record_url=t.first_party_detail_url order by x.created_at desc limit 1) sr on true
  where t.verification_status='verified_first_party' and t.stage='first_party_verified' and t.verification_evidence_id is null
), canonical as (
  select r.*,s.id scholarship_id from ready r
  join scholarship.scholarships s on s.provider_id=r.provider_id and s.source_url=r.first_party_detail_url
)
update pipeline.scholarship_acquisition_trace t set
  source_record_id=c.source_record_id,scholarship_id=c.scholarship_id,verification_evidence_id=c.evidence_id,
  stage='canonical_unpublished',verified_at=now(),updated_at=now(),
  metadata=coalesce(t.metadata,'{}'::jsonb)||jsonb_build_object('canonical_match_basis','first_party_detail_url','cf_change','CF-131')
from canonical c where t.id=c.trace_id;

insert into scholarship.identifiers(id,scholarship_id,scheme,identifier_value,source_id,evidence_id,is_primary,status)
select scholarship.deterministic_uuid('first-party-detail:'||t.scholarship_id::text||':'||t.first_party_detail_url),
       t.scholarship_id,'first_party_detail_url',t.first_party_detail_url,ps.id,t.verification_evidence_id,true,'active'
from pipeline.scholarship_acquisition_trace t
join pipeline.sources ps on ps.provider_id=t.provider_id and ps.source_type='scholarship_detail' and ps.url=t.first_party_detail_url
where t.stage='canonical_unpublished' and t.scholarship_id is not null and t.verification_evidence_id is not null
on conflict(source_id,scheme,identifier_value) do update set
  scholarship_id=excluded.scholarship_id,evidence_id=excluded.evidence_id,is_primary=true,status='active';

-- Structured value semantics for course-side calculations. Fee basis is set only when explicit.
update scholarship.scholarships s set
  award_value_type='percentage',
  award_percentage=(regexp_match(s.award_value_text,'([0-9]+(?:\.[0-9]+)?)\s*%'))[1]::numeric,
  award_fee_basis=case when s.award_value_text ilike '%tuition%' then 'tuition_fee' else s.award_fee_basis end,
  updated_at=now()
where s.evidence_id is not null and s.publication_status='unpublished'
  and s.award_value_text ~ '[0-9]+(?:\.[0-9]+)?\s*%'
  and exists(select 1 from pipeline.scholarship_acquisition_trace t where t.scholarship_id=s.id and t.verification_evidence_id=s.evidence_id);

update scholarship.scholarships s set
  award_value_type='fixed_amount',
  award_amount=replace((regexp_match(s.award_value_text,'\$\s*([0-9,]+(?:\.[0-9]+)?)'))[1],',','')::numeric,
  award_currency_code=coalesce(s.award_currency_code,'AUD'),updated_at=now()
where s.evidence_id is not null and s.publication_status='unpublished'
  and s.award_value_text ~ '\$\s*[0-9,]+'
  and exists(select 1 from pipeline.scholarship_acquisition_trace t where t.scholarship_id=s.id and t.verification_evidence_id=s.evidence_id);

update pipeline.layer2_scholarship_discovery_candidates c set status='acquired'
where c.status='discovered' and exists(
  select 1 from pipeline.scholarship_acquisition_trace t
  where t.first_party_detail_url=c.scholarship_url
    and t.stage='canonical_unpublished' and t.verification_evidence_id is not null
);
