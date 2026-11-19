create index if not exists idx_course_identifiers_country_id on catalogue.course_identifiers(country_id) where country_id is not null;
create index if not exists idx_course_identifiers_source_id on catalogue.course_identifiers(source_id) where source_id is not null;
create index if not exists idx_course_identifiers_evidence_id on catalogue.course_identifiers(evidence_id) where evidence_id is not null;
create index if not exists idx_source_record_staging_country_id on pipeline.source_record_staging(country_id);
create index if not exists idx_source_record_staging_provider_id on pipeline.source_record_staging(provider_id) where provider_id is not null;
create index if not exists idx_outcome_benchmarks_study_level_id on catalogue.outcome_benchmarks(study_level_id) where study_level_id is not null;
