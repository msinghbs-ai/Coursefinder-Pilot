-- CF-113: Federation/RMIT first-party Scholarship detail evidence wave.
-- Runtime migration uses provider/source lookups rather than generated IDs and advances only verified detail pages to detail_acquired.
-- See change-control/40-layer2-enrichment/CF-CHG-20260904-113-federation-rmit-scholarship-detail-evidence.md for governed facts and execution evidence.

-- Replay note: the deployed migration creates/reuses Evidence by source URL + content hash,
-- creates/reuses scholarship_source_records by source + trace-derived record key + content hash,
-- and updates pipeline.scholarship_acquisition_trace only after both links exist.
-- No canonical Scholarship or publication state is created by this migration.
