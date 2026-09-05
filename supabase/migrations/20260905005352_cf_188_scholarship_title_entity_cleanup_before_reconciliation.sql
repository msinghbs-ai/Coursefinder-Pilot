-- CF-188 runtime-history reconciliation marker.
-- Pilot normalised HTML entity artefacts in extracted Scholarship titles before the
-- verified-detail reconciliation apply. The exact intermediate data cleanup was applied
-- directly to Pilot; CF-191's semantic guard and subsequent reconciliation boundary
-- provide the replay-safe current behaviour for future acquisitions.

comment on function pipeline.scholarship_candidate_semantic_terminal_guard() is
'CF-188/CF-191+: Scholarship semantic comparison normalises common HTML entity artefacts before terminal classification.';
