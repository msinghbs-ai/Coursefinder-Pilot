-- CF-185 runtime-history reconciliation marker.
-- The Pilot runtime excluded Scholarship terms/conditions PDF records from automatic
-- individual-Scholarship reconciliation at this point in the live hardening sequence.
-- The original intermediate SQL was applied directly to Pilot before repository
-- reconciliation. Its final behaviour is replayed structurally by CF-190/CF-191 and
-- consolidated by the later current-state replay migration. This marker preserves the
-- deployed migration identity without pretending that the exact intermediate statement
-- can be reconstructed after the fact.

comment on column pipeline.layer2_scholarship_discovery_candidates.classification is
'CF-185/CF-190+: supporting documents such as terms and conditions are Evidence, not individual Scholarship canonical records.';
