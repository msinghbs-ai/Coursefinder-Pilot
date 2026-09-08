-- CF-241 — harden derived Evidence lineage mutator privileges.
-- The SECURITY DEFINER mutator is trigger-internal and must not be callable directly by browser roles.

revoke all on function security.adjust_evidence_lineage_stats(uuid,bigint,bigint,bigint) from public;
revoke all on function security.adjust_evidence_lineage_stats(uuid,bigint,bigint,bigint) from anon;
revoke all on function security.adjust_evidence_lineage_stats(uuid,bigint,bigint,bigint) from authenticated;

-- The trigger function is likewise internal-only. PostgreSQL trigger execution is owned by
-- the trigger/function owner path; browser roles do not require direct EXECUTE permission.
revoke all on function security.sync_evidence_lineage_stats() from public;
revoke all on function security.sync_evidence_lineage_stats() from anon;
revoke all on function security.sync_evidence_lineage_stats() from authenticated;

comment on function security.adjust_evidence_lineage_stats(uuid,bigint,bigint,bigint) is
  'Internal CF-241 Evidence lineage counter mutator. Direct browser execution revoked; maintained through governed trigger path only.';
