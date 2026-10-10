-- CF M2.4.5: persist the QS 2024/2025 duplicate-edition lifecycle cleanup.
-- The newer governed publisher XLSX revision remains accepted. The older
-- CourseFinder-generated static revision is retained for audit but removed
-- from the active edition lifecycle.

with qs as (
  select id as system_id
  from ranking.systems
  where code='qs_wur'
), candidates as (
  select e.id as edition_id,
         e.source_artifact_id,
         e.edition_year
  from ranking.editions e
  join qs on qs.system_id=e.system_id
  where e.edition_year in (2024,2025)
    and e.source_revision='cf218_qs_static_v1'
    and exists (
      select 1
      from ranking.editions newer
      where newer.system_id=e.system_id
        and newer.edition_year=e.edition_year
        and newer.status='accepted'
        and newer.source_revision='qs_xlsx_evidence_v1'
    )
)
update ranking.editions e
set status='superseded', updated_at=now()
from candidates c
where e.id=c.edition_id
  and e.status<>'superseded';

with qs as (
  select id as system_id
  from ranking.systems
  where code='qs_wur'
), candidates as (
  select e.source_artifact_id
  from ranking.editions e
  join qs on qs.system_id=e.system_id
  where e.edition_year in (2024,2025)
    and e.source_revision='cf218_qs_static_v1'
    and e.status='superseded'
)
update ranking.manual_imports mi
set status='rejected',
    validation_summary=coalesce(mi.validation_summary,'{}'::jsonb)
      || jsonb_build_object(
        'lifecycle_state','superseded',
        'reason','newer accepted publisher revision',
        'superseded_at',coalesce(mi.validation_summary->'superseded_at',to_jsonb(now()))
      ),
    updated_at=now()
from candidates c
where mi.evidence_artifact_id=c.source_artifact_id
  and mi.status<>'rejected';

with qs as (
  select id as system_id
  from ranking.systems
  where code='qs_wur'
), candidates as (
  select e.source_artifact_id
  from ranking.editions e
  join qs on qs.system_id=e.system_id
  where e.edition_year in (2024,2025)
    and e.source_revision='cf218_qs_static_v1'
    and e.status='superseded'
)
update pipeline.evidence_artifacts ea
set metadata=coalesce(ea.metadata,'{}'::jsonb)
  || jsonb_build_object(
    'ranking_lifecycle_state','superseded',
    'ranking_supersession_reason','newer accepted publisher revision',
    'ranking_superseded_at',coalesce(ea.metadata->'ranking_superseded_at',to_jsonb(now()))
  )
from candidates c
where ea.id=c.source_artifact_id
  and coalesce(ea.metadata->>'ranking_lifecycle_state','')<>'superseded';
