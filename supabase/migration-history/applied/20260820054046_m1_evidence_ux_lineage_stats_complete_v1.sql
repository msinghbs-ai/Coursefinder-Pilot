-- M1-EVIDENCE-UX lineage-stat completeness and value/status-change maintenance.
-- Adds the evidence-bearing families omitted from the first derived-stat backfill.

insert into pipeline.evidence_lineage_stats(evidence_id,observation_count,source_null_count,rejected_count,updated_at)
select evidence_id,count(*)::bigint,0::bigint,sum(rejected)::bigint,now()
from (
  select evidence_id,case when lower(coalesce(status,''))='rejected' then 1 else 0 end rejected
    from catalogue.course_academic_options where evidence_id is not null
  union all
  select evidence_id,0 from catalogue.course_collection_memberships where evidence_id is not null
  union all
  select evidence_id,0 from catalogue.course_identifiers where evidence_id is not null
  union all
  select evidence_id,0 from catalogue.outcome_benchmarks where evidence_id is not null
  union all
  select evidence_id,case when lower(coalesce(status,''))='rejected' then 1 else 0 end
    from catalogue.provider_associations where evidence_id is not null
  union all
  select evidence_id,case when lower(coalesce(status,''))='rejected' then 1 else 0 end
    from catalogue.provider_collection_memberships where evidence_id is not null
  union all
  select evidence_id,0 from catalogue.provider_rankings where evidence_id is not null
) x
group by evidence_id
on conflict(evidence_id) do update set
  observation_count=pipeline.evidence_lineage_stats.observation_count+excluded.observation_count,
  source_null_count=pipeline.evidence_lineage_stats.source_null_count+excluded.source_null_count,
  rejected_count=pipeline.evidence_lineage_stats.rejected_count+excluded.rejected_count,
  updated_at=now();

do $$
declare r record;
begin
  for r in select * from (values
    ('catalogue','course_fees'),
    ('catalogue','course_intakes'),
    ('catalogue','course_english_requirements'),
    ('catalogue','course_links'),
    ('catalogue','course_registrations'),
    ('catalogue','course_regulatory_observations'),
    ('catalogue','course_study_level_observations'),
    ('catalogue','course_field_observations'),
    ('catalogue','course_campuses'),
    ('catalogue','campuses'),
    ('catalogue','provider_outcomes'),
    ('catalogue','student_flow_observations'),
    ('catalogue','provider_registrations'),
    ('catalogue','provider_identifiers'),
    ('catalogue','course_academic_options'),
    ('catalogue','course_collection_memberships'),
    ('catalogue','course_identifiers'),
    ('catalogue','outcome_benchmarks'),
    ('catalogue','provider_associations'),
    ('catalogue','provider_collection_memberships'),
    ('catalogue','provider_rankings'),
    ('scholarship','scholarships'),
    ('scholarship','offering_cycles'),
    ('scholarship','application_windows'),
    ('scholarship','scopes'),
    ('scholarship','criterion_groups'),
    ('scholarship','criteria'),
    ('scholarship','award_tiers'),
    ('scholarship','coverage'),
    ('scholarship','identifiers')
  ) as t(schema_name,table_name)
  loop
    execute format('drop trigger if exists %I on %I.%I','evidence_lineage_stats_sync',r.schema_name,r.table_name);
    execute format('create trigger %I after insert or update or delete on %I.%I for each row execute function security.sync_evidence_lineage_stats()','evidence_lineage_stats_sync',r.schema_name,r.table_name);
  end loop;
end $$;
