-- CF-172 documents the runtime correction applied immediately after CF-171 validation.
-- PostgreSQL has no min(uuid); use a text cast for the unique-title fallback.
-- The full reconciler body is maintained by the preceding migration and runtime CREATE OR REPLACE.
-- This migration is intentionally replay-safe and records the corrected helper expression contract.
comment on function scholarship.reconcile_verified_detail_records(uuid,text,text,uuid,integer) is
'CF-171/172 verified first-party Scholarship detail reconciler. Unique exact-title fallback uses min(id::text)::uuid; canonical roots remain unpublished.';