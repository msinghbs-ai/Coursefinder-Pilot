-- CF-176..181 — Scholarship queue truth, Evidence reuse and active runtime statistics.
-- Runtime changes already applied to Pilot. This migration reconciles the replayable contract.

-- Reuse Evidence-backed canonical details without refetch.
update pipeline.layer2_scholarship_discovery_candidates c
set status='acquired',classification_reason='CF-176 reused existing canonical Evidence-backed first-party detail',classified_at=now()
where c.status='discovered' and c.classification='detail_ready'
  and exists (
    select 1 from pipeline.sources src
    join pipeline.scholarship_acquisition_trace t on t.provider_id=src.provider_id
      and rtrim(lower(coalesce(t.first_party_detail_url,'')),'/')=rtrim(lower(c.scholarship_url),'/')
      and t.verification_evidence_id is not null and t.scholarship_id is not null
    where src.id=c.source_id
  );

-- External/non-first-party pages never auto-fire as Provider Scholarship details.
update pipeline.layer2_scholarship_discovery_candidates
set classification='needs_review',classification_reason='CF-176 external/non-first-party Scholarship page; retain for human review only',classified_at=now()
where status='discovered' and classification='detail_ready' and scholarship_url ~* '^https?://www\.swissnexindia\.org/';

-- Explicit first-party scholarship_url can become the detail target when the catalogue parser left detail_target_url null.
update pipeline.layer2_scholarship_discovery_candidates
set detail_target_url=scholarship_url,classification_reason='CF-176 first-party scholarship_url promoted to executable detail target',classified_at=now()
where status='discovered' and classification='detail_ready' and detail_target_url is null and scholarship_url ~* '^https?://(www\.)?cdu\.edu\.au/';

-- Keep one executable observation per Provider + detail URL.
with ranked as (
  select c.id,row_number() over(partition by src.provider_id,rtrim(lower(coalesce(c.detail_target_url,c.scholarship_url)),'/') order by c.created_at,c.id) rn
  from pipeline.layer2_scholarship_discovery_candidates c join pipeline.sources src on src.id=c.source_id
  where c.status='discovered' and c.classification='detail_ready' and coalesce(c.detail_target_url,c.scholarship_url) is not null
)
update pipeline.layer2_scholarship_discovery_candidates c
set status='superseded',classification_reason='CF-176 duplicate Provider/detail URL superseded before acquisition',classified_at=now()
from ranked r where c.id=r.id and r.rn>1;

-- CF-177/179: only active discovered candidates can be reclassified/queued; terminal classes cannot re-enter detail firing.
do $$
declare d text;
begin
 select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='scholarship_international_detail_batch_service';
 d:=replace(d,'coalesce(c.status,'''') not in(''rejected'',''duplicate'',''superseded'')','c.status=''discovered''');
 d:=replace(d,'where c.classification=''detail_ready''','where c.status=''discovered'' and c.classification=''detail_ready''');
 d:=replace(d,'coalesce(c.classification,'''') not in(''external_or_out_of_scope'',''support_or_navigation'')','coalesce(c.classification,'''') not in(''external_or_out_of_scope'',''support_or_navigation'',''catalogue_or_filter'')');
 execute d;
end $$;

-- Navigation/support text is never executable detail work.
update pipeline.layer2_scholarship_discovery_candidates
set classification='support_or_navigation',classification_reason='CF-178 navigation/support title excluded from Scholarship detail acquisition',classified_at=now()
where status='discovered' and classification='detail_ready'
  and lower(trim(coalesce(observed_title,''))) in ('skip to main content','menu','go to top','faq','eligibility','guidelines','find a scholarship','scholarships');

-- Catalogue page remains terminal catalogue Evidence.
update pipeline.layer2_scholarship_discovery_candidates
set classification='catalogue_or_filter',classification_reason='CF-179 catalogue page retained as terminal catalogue Evidence; never auto-promote to detail',classified_at=now()
where status='discovered' and scholarship_url='https://www.cdu.edu.au/international/how-apply/scholarships';

-- CF-180: close stale detail-ready rows when canonical + source record + Evidence already exist; create trace if missing.
with ready as (
  select c.id candidate_id,src.provider_id,c.scholarship_url,sr.id source_record_id,sr.evidence_id,sch.id scholarship_id,sch.name
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
  from ready r where not exists(select 1 from pipeline.scholarship_acquisition_trace t where t.scholarship_id=r.scholarship_id and t.verification_evidence_id=r.evidence_id)
  returning discovery_candidate_id
)
update pipeline.layer2_scholarship_discovery_candidates c
set status='acquired',classification_reason='CF-180 reused existing first-party source record, Evidence and canonical unpublished root',classified_at=now()
where c.id in (select candidate_id from ready);

-- CF-181: Admin runtime queue metrics are active queue metrics, not historical classification counts.
do $$
declare d text;
begin
 select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='security' and p.proname='admin_scholarship_runtime_read';
 d:=replace(d,'and d.classification = ''detail_ready''::text','and d.status = ''discovered''::text and d.classification = ''detail_ready''::text');
 d:=replace(d,'and d.classification = ''needs_review''::text','and d.status = ''discovered''::text and d.classification = ''needs_review''::text');
 execute d;
end $$;

comment on function public.scholarship_international_detail_batch_service(uuid,text,text,text,uuid,integer,boolean) is 'CF-177/179 only status=discovered candidates can be reclassified or queued; catalogue/filter, support/navigation and external/out-of-scope are terminal automatic-detail exclusions.';
comment on function security.admin_scholarship_runtime_read(jsonb) is 'CF-181 active Scholarship runtime statistics: detail_ready and needs_review count only status=discovered candidates.';
