-- CF-176: make Scholarship detail-ready queue truthful and reuse existing Evidence before new acquisition.
-- 1) Existing canonical + Evidence-backed Provider/detail URL rows become acquired without refetch.
update pipeline.layer2_scholarship_discovery_candidates c
set status='acquired', classification_reason='CF-176 reused existing canonical Evidence-backed first-party detail', classified_at=now()
where c.status='discovered' and c.classification='detail_ready'
  and exists (
    select 1 from pipeline.sources src
    join pipeline.scholarship_acquisition_trace t on t.provider_id=src.provider_id
    where src.id=c.source_id
      and rtrim(lower(coalesce(t.first_party_detail_url,'')),'/')=rtrim(lower(c.scholarship_url),'/')
      and t.verification_evidence_id is not null and t.scholarship_id is not null
  );

-- 2) External/non-first-party detail candidates are review-only in Provider Scholarship acquisition.
update pipeline.layer2_scholarship_discovery_candidates c
set classification='needs_review', classification_reason='CF-176 external/non-first-party Scholarship page; retain for human review only', classified_at=now()
where c.status='discovered' and c.classification='detail_ready'
  and exists (select 1 from pipeline.sources src where src.id=c.source_id and src.provider_id is not null)
  and c.scholarship_url ~* '^https?://www\.swissnexindia\.org/';

-- 3) A resolved first-party scholarship_url is the detail target when the prior classifier left detail_target_url null.
update pipeline.layer2_scholarship_discovery_candidates c
set detail_target_url=c.scholarship_url, classification_reason='CF-176 first-party scholarship_url promoted to executable detail target', classified_at=now()
where c.status='discovered' and c.classification='detail_ready' and c.detail_target_url is null
  and c.scholarship_url ~* '^https?://(www\.)?cdu\.edu\.au/';

-- 4) Keep one executable row per Provider + normalised detail URL; supersede duplicates without deletion.
with ranked as (
  select c.id,row_number() over(partition by src.provider_id,rtrim(lower(coalesce(c.detail_target_url,c.scholarship_url)),'/') order by c.created_at asc,c.id asc) rn
  from pipeline.layer2_scholarship_discovery_candidates c join pipeline.sources src on src.id=c.source_id
  where c.status='discovered' and c.classification='detail_ready' and coalesce(c.detail_target_url,c.scholarship_url) is not null
)
update pipeline.layer2_scholarship_discovery_candidates c
set status='superseded',classification_reason='CF-176 duplicate Provider/detail URL superseded before acquisition',classified_at=now()
from ranked r where c.id=r.id and r.rn>1;
