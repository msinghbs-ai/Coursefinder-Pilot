-- CF-247 AER throughput fixtures: the controller's outcome codes the work-continuity contract references (as live), loaded before it.
create table if not exists pipeline.ops_outcome_codes(code text primary key, title text, counts_as_movement boolean);
insert into pipeline.ops_outcome_codes values ('succeeded_with_result', 'x', true), ('succeeded_no_movement', 'x', false), ('not_needed', 'x', false), ('deferred_dependency', 'x', false),
  ('blocked_policy', 'x', false), ('blocked_evidence', 'x', false), ('failed_retryable', 'x', false), ('failed_remediation', 'x', false) on conflict do nothing;
