-- CF-187 runtime-history reconciliation marker.
-- Pilot tightened the verified-detail reconciliation boundary so generic Scholarship
-- collections/navigation did not become canonical Scholarship roots. The exact
-- intermediate cleanup was applied directly to Pilot. CF-191 through CF-193 contain
-- the replayable final generic/support exclusions used by the current runtime.

comment on view pipeline.scholarship_verified_detail_reconciliation_candidates is
'CF-187 history; current reconciliation boundary excludes generic collections, navigation, support, filters and non-individual pages.';
