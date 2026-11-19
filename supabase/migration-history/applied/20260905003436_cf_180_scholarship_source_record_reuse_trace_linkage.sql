-- CF-180: close stale detail-ready rows when canonical + first-party source record/Evidence already exist.
with ready as (
  select c.id candidate_id,src.provider_id,c.scholarship_url,
         sr.id source_record_id,sr.evidence_id,sch.id scholarship_id,sch.name
  from pipeline.layer2_scholarship_discovery_candidates c
  join pipeline.sources src on src.id=c.source_id
  join lateral (
    select x.* from pipeline.scholarship_source_records x
    where rtrim(lower(x.source_record_url),'/')=rtrim(lower(c.scholarship_url),'/') and x.evidence_id is not null and x.status in('captured','applied')
    order by case x.status when 'applied' then 0 else 1 end,x.created_at desc limit 1
  ) sr on true
  join scholarship.scholarships sch on sch.provider_id=src.provider_id and rtrim(lower(coalesce(sch.source_url,'')),'/')=rtrim(lower(c.scholarship_url),'/')
  where c.status='discovered' and c.classification='detail_ready'
), ins as (
  insert into pipeline.scholarship_acquisition_trace(provider_id,observed_title,first_party_detail_url,discovery_candidate_id,source_record_id,scholarship_id,verification_evidence_id,stage,verification_status,observed_at,verified_at,metadata)
  select r.provider_id,r.name,r.scholarship_url,r.candidate_id,r.source_record_id,r.scholarship_id,r.evidence_id,'canonical_unpublished','verified_first_party',now(),now(),jsonb_build_object('authority','first_party','reuse','existing_source_record_and_canonical','change_control_ref','CF-180')
  from ready r
  where not exists(select 1 from pipeline.scholarship_acquisition_trace t where t.scholarship_id=r.scholarship_id and t.verification_evidence_id=r.evidence_id)
  returning discovery_candidate_id
)
update pipeline.layer2_scholarship_discovery_candidates c
set status='acquired',classification_reason='CF-180 reused existing first-party source record, Evidence and canonical unpublished root',classified_at=now()
where c.id in (select candidate_id from ready);

comment on function public.scholarship_international_detail_batch_service(uuid,text,text,text,uuid,integer,boolean) is 'CF-177/179 detail batching: only status=discovered candidates can be reclassified or queued; catalogue/filter, support/navigation and external/out-of-scope classifications are terminal automatic-detail exclusions.';
