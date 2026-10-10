-- M2.4.2 — reconcile Layer 2 operational alert read ACL.
-- The helper remains in the private security schema and enforces auth + rank >=4 internally.

begin;

revoke all on function security.layer2_operational_alerts_read() from public,anon;
grant execute on function security.layer2_operational_alerts_read() to authenticated,service_role;

commit;
