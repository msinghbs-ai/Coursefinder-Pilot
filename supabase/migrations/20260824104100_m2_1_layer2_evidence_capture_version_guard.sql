-- CF-CHG-20260823-029
create unique index if not exists layer2_evidence_group_capture_version_uq
on pipeline.evidence_artifacts(evidence_group_key,capture_version)
where evidence_group_key is not null and capture_version is not null;
