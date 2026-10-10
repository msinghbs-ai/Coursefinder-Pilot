-- CF-155 — Reconcile the bounded Monash international validation wave to canonical unpublished Scholarships.
-- Identity is Provider + exact first-party detail URL / verified catalogue identity. No automatic Publication.

with target as (
  select c.id candidate_id,src.provider_id,c.detail_target_url url,
         case c.detail_target_url
           when 'https://www.monash.edu/study/fees-scholarships/scholarships/find-a-scholarship/indonesian-women-impact-scholarship' then 'Indonesian Women Impact Scholarship'
           when 'https://www.monash.edu/study/fees-scholarships/scholarships/find-a-scholarship/john-bush-memorial-top-up-scholarship' then 'John Bush Memorial Top-Up Scholarship'
         end canonical_name,
         ds.id source_id,sr.id source_record_id,sr.evidence_id,sr.payload->>'award_value_text' award_text,
         case when c.detail_target_url like '%john-bush-memorial%' then 'inactive' else 'active' end lifecycle_status,
         'scholarship:AU:first-party-detail:'||replace(src.provider_id::text,'-','')||':'||md5(c.detail_target_url) stable_key
  from pipeline.layer2_scholarship_discovery_candidates c
  join pipeline.sources src on src.id=c.source_id
  join pipeline.sources ds on ds.provider_id=src.provider_id and ds.source_type='scholarship_detail' and ds.url=c.detail_target_url
  join lateral (
    select x.* from pipeline.scholarship_source_records x
    where x.source_id=ds.id and x.source_record_url=c.detail_target_url
    order by x.created_at desc limit 1
  ) sr on true
  where c.detail_target_url in (
    'https://www.monash.edu/study/fees-scholarships/scholarships/find-a-scholarship/indonesian-women-impact-scholarship',
    'https://www.monash.edu/study/fees-scholarships/scholarships/find-a-scholarship/john-bush-memorial-top-up-scholarship'
  )
), reg as (
  insert into pim.entity_registry(id,entity_type,stable_key,lifecycle_status)
  select scholarship.deterministic_uuid(stable_key),'scholarship',stable_key,lifecycle_status from target
  on conflict(stable_key) do update set lifecycle_status=excluded.lifecycle_status,updated_at=now()
  returning id,stable_key
)
insert into scholarship.scholarships(
  id,stable_key,provider_id,name,scholarship_type,audience,award_value_text,source_url,
  lifecycle_status,publication_status,source_id,evidence_id,confidence,
  award_value_type,award_amount,award_currency_code
)
select r.id,t.stable_key,t.provider_id,t.canonical_name,'provider_scholarship','international',t.award_text,t.url,
       t.lifecycle_status,'unpublished',t.source_id,t.evidence_id,0.95,
       case when t.award_text ~ '\$\s*[0-9,]+' then 'fixed_amount' else 'text_only' end,
       case when t.award_text ~ '\$\s*[0-9,]+' then replace((regexp_match(t.award_text,'\$\s*([0-9,]+(?:\.[0-9]+)?)'))[1],',','')::numeric else null end,
       case when t.award_text ~ '\$\s*[0-9,]+' then 'AUD' else null end
from target t join reg r on r.stable_key=t.stable_key
on conflict(id) do update set
  name=excluded.name,audience='international',award_value_text=excluded.award_value_text,
  source_url=excluded.source_url,lifecycle_status=excluded.lifecycle_status,publication_status='unpublished',
  source_id=excluded.source_id,evidence_id=excluded.evidence_id,confidence=excluded.confidence,
  award_value_type=excluded.award_value_type,award_amount=excluded.award_amount,
  award_currency_code=excluded.award_currency_code,updated_at=now();

with target as (
  select c.id candidate_id,src.provider_id,c.detail_target_url url,ds.id source_id,sr.id source_record_id,sr.evidence_id,
         case c.detail_target_url
           when 'https://www.monash.edu/study/fees-scholarships/scholarships/find-a-scholarship/indonesian-women-impact-scholarship' then 'Indonesian Women Impact Scholarship'
           when 'https://www.monash.edu/study/fees-scholarships/scholarships/find-a-scholarship/john-bush-memorial-top-up-scholarship' then 'John Bush Memorial Top-Up Scholarship'
         end canonical_name
  from pipeline.layer2_scholarship_discovery_candidates c
  join pipeline.sources src on src.id=c.source_id
  join pipeline.sources ds on ds.provider_id=src.provider_id and ds.source_type='scholarship_detail' and ds.url=c.detail_target_url
  join lateral (select x.* from pipeline.scholarship_source_records x where x.source_id=ds.id and x.source_record_url=c.detail_target_url order by x.created_at desc limit 1) sr on true
  where c.detail_target_url in (
    'https://www.monash.edu/study/fees-scholarships/scholarships/find-a-scholarship/indonesian-women-impact-scholarship',
    'https://www.monash.edu/study/fees-scholarships/scholarships/find-a-scholarship/john-bush-memorial-top-up-scholarship'
  )
), linked as (
 select t.*,s.id scholarship_id from target t join scholarship.scholarships s on s.provider_id=t.provider_id and s.source_url=t.url
)
insert into pipeline.scholarship_acquisition_trace(
 provider_id,observed_title,first_party_detail_url,discovery_candidate_id,source_record_id,scholarship_id,
 verification_evidence_id,stage,verification_status,observed_at,verified_at,metadata
)
select l.provider_id,l.canonical_name,l.url,l.candidate_id,l.source_record_id,l.scholarship_id,l.evidence_id,
       'canonical_unpublished','verified_first_party',now(),now(),
       jsonb_build_object('authority','first_party','audience','international','reconciliation_basis','provider_plus_first_party_detail_url','change_control_ref','CF-155')
from linked l
where not exists(select 1 from pipeline.scholarship_acquisition_trace x where x.scholarship_id=l.scholarship_id and x.verification_evidence_id=l.evidence_id);

update pipeline.layer2_scholarship_discovery_candidates c
set status='acquired',classification_reason='international_only_gate: first-party detail verified and canonical-unpublished reconciled',classified_at=now()
where c.detail_target_url in (
 'https://www.monash.edu/study/fees-scholarships/scholarships/find-a-scholarship/indonesian-women-impact-scholarship',
 'https://www.monash.edu/study/fees-scholarships/scholarships/find-a-scholarship/john-bush-memorial-top-up-scholarship'
);
