-- CF-148 — Deduplicate Scholarship detail-ready candidates before acquisition.
-- One candidate is retained per canonical Provider + first-party detail URL; repeats are superseded.

with ranked as (
  select c.id,
         row_number() over (
           partition by s.provider_id, c.detail_target_url
           order by c.created_at asc, c.id asc
         ) as rn
  from pipeline.layer2_scholarship_discovery_candidates c
  join pipeline.sources s on s.id=c.source_id
  where c.status='discovered'
    and c.classification='detail_ready'
    and c.detail_target_url is not null
)
update pipeline.layer2_scholarship_discovery_candidates c
set status='superseded',
    classification_reason='duplicate_provider_detail_url_superseded_before_acquisition',
    classified_at=now()
from ranked r
where c.id=r.id and r.rn>1;
