-- CF-194 — current-state queue closure after the CF-185..CF-193 hardening sequence.
with evidenced as (
  select distinct d.id
  from pipeline.layer2_scholarship_discovery_candidates d
  join pipeline.sources ds on ds.id=d.source_id
  join pipeline.scholarship_source_records sr on rtrim(lower(sr.source_record_url),'/')=rtrim(lower(coalesce(nullif(d.detail_target_url,''),nullif(d.scholarship_url,''))),'/')
  join pipeline.sources ss on ss.id=sr.source_id and ss.provider_id=ds.provider_id
  where d.status='discovered' and d.classification='detail_ready' and sr.status in('captured','applied')
)
update pipeline.layer2_scholarship_discovery_candidates d
set status='acquired',classification_reason=coalesce(d.classification_reason,'')||case when coalesce(d.classification_reason,'')='' then '' else '; ' end||'CF-194 current-state replay closure: same-provider first-party source record already captured/applied',classified_at=now()
from evidenced e where d.id=e.id;
update pipeline.jobs j
set status='succeeded',completed_at=coalesce(completed_at,now()),started_at=coalesce(started_at,created_at),result=coalesce(result,'{}'::jsonb)||jsonb_build_object('skipped',true,'reason','CF-194 candidate already evidenced or terminal','publication_changed',false,'canonical_mutation_authorised',false),error_text=null
where j.domain='scholarship' and j.job_type='scholarship_scope_acquisition' and j.status in('queued','running') and nullif(j.payload->>'candidate_id','') is not null
  and exists(select 1 from pipeline.layer2_scholarship_discovery_candidates d where d.id=(j.payload->>'candidate_id')::uuid and not(d.status='discovered' and d.classification='detail_ready'));
comment on function public.scholarship_international_detail_batch_service(uuid,text,text,text,uuid,integer,boolean) is 'CF-194 current-state Scholarship detail service: discovered-only, first-party semantic qualification, terminal support/catalogue exclusions, source-record reuse, no publication.';
comment on view pipeline.scholarship_verified_detail_reconciliation_candidates is 'CF-194 current-state reconciliation boundary: captured/applied Evidence only; individual first-party international Scholarship details only; generic/support/filter records remain review/unmapped.';
