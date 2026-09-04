-- CF-150 — Reconcile CDU Australia Awards first-party Evidence to canonical unpublished Scholarship.
-- No award amount is asserted because the acquired Evidence did not establish one.

with target as (
  select p.id provider_id,c.id candidate_id,c.detail_target_url url,sr.id source_record_id,sr.evidence_id,
         'Australia Award Scholarships'::text name,
         'scholarship:AU:first-party-detail:'||replace(p.id::text,'-','')||':'||md5(c.detail_target_url) stable_key,
         ds.id source_id
  from pipeline.layer2_scholarship_discovery_candidates c
  join pipeline.sources cs on cs.id=c.source_id
  join catalogue.providers p on p.id=cs.provider_id and p.canonical_name='Charles Darwin University'
  join pipeline.sources ds on ds.provider_id=p.id and ds.source_type='scholarship_detail' and ds.url=c.detail_target_url
  join lateral (select x.* from pipeline.scholarship_source_records x where x.source_id=ds.id and x.source_record_url=c.detail_target_url order by x.created_at desc limit 1) sr on true
  where c.detail_target_url='https://www.cdu.edu.au/international/how-apply/scholarships/australia-award-scholarships' limit 1
), reg as (
  insert into pim.entity_registry(id,entity_type,stable_key,lifecycle_status)
  select scholarship.deterministic_uuid(stable_key),'scholarship',stable_key,'active' from target
  on conflict(stable_key) do update set updated_at=now()
  returning id,stable_key
)
insert into scholarship.scholarships(id,stable_key,provider_id,name,scholarship_type,audience,source_url,lifecycle_status,publication_status,source_id,evidence_id,confidence)
select reg.id,t.stable_key,t.provider_id,t.name,'provider_scholarship','international',t.url,'active','unpublished',t.source_id,t.evidence_id,0.90
from target t join reg on reg.stable_key=t.stable_key
where not exists(select 1 from scholarship.scholarships s where s.provider_id=t.provider_id and lower(regexp_replace(s.name,'[^a-z0-9]+','','g'))=lower(regexp_replace(t.name,'[^a-z0-9]+','','g')))
on conflict(id) do update set source_url=excluded.source_url,source_id=excluded.source_id,evidence_id=excluded.evidence_id,updated_at=now();

with target as (
  select p.id provider_id,c.id candidate_id,c.detail_target_url url,sr.id source_record_id,sr.evidence_id,ds.id source_id
  from pipeline.layer2_scholarship_discovery_candidates c
  join pipeline.sources cs on cs.id=c.source_id
  join catalogue.providers p on p.id=cs.provider_id and p.canonical_name='Charles Darwin University'
  join pipeline.sources ds on ds.provider_id=p.id and ds.source_type='scholarship_detail' and ds.url=c.detail_target_url
  join lateral (select x.* from pipeline.scholarship_source_records x where x.source_id=ds.id and x.source_record_url=c.detail_target_url order by x.created_at desc limit 1) sr on true
  where c.detail_target_url='https://www.cdu.edu.au/international/how-apply/scholarships/australia-award-scholarships' limit 1
), canonical as (
 select t.*,s.id scholarship_id,s.name from target t join scholarship.scholarships s on s.provider_id=t.provider_id and s.source_url=t.url
)
insert into pipeline.scholarship_acquisition_trace(provider_id,observed_title,first_party_detail_url,discovery_candidate_id,source_record_id,scholarship_id,verification_evidence_id,stage,verification_status,observed_at,verified_at,metadata)
select provider_id,name,url,candidate_id,source_record_id,scholarship_id,evidence_id,'canonical_unpublished','verified_first_party',now(),now(),jsonb_build_object('authority','first_party','cf_change','CF-150','financial_value_status','not_asserted_from_evidence')
from canonical
where not exists(select 1 from pipeline.scholarship_acquisition_trace t where t.provider_id=canonical.provider_id and t.first_party_detail_url=canonical.url and t.scholarship_id=canonical.scholarship_id);

update pipeline.layer2_scholarship_discovery_candidates c
set status='acquired',classification_reason='first_party_detail_acquired_and_canonical_unpublished',classified_at=now()
where c.detail_target_url='https://www.cdu.edu.au/international/how-apply/scholarships/australia-award-scholarships' and c.status='discovered';
