-- 12 pending entry-requirement items against a limit of 10; 5 are parked by the technical lane (action park), one is a transient hold being retried (counts), 6 are plain decisions
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status)
select ('40000000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid, 'course', gen_random_uuid(), case when g % 2 = 0 then 'course_entry_first_read' else 'entry_matrix_first_run' end, 'pending' from generate_series(1, 12) g;
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status) values ('40000000-0000-0000-0000-000000000099', 'course', gen_random_uuid(), 'course_entry_first_read', 'approved');
insert into pipeline.work_items(lane, entity, work_kind, provider_id, stage, failure_class, unresolved_blocker) values
  ('aer_technical', '40000000-0000-0000-0000-000000000001', 'l4_item', '10000000-0000-0000-0000-000000000001', 'parked', 'aer_row_limit', '{"action":"park","reason":"row limit","next_action":"set a row limit"}'),
  ('aer_technical', '40000000-0000-0000-0000-000000000002', 'l4_item', '10000000-0000-0000-0000-000000000001', 'parked', 'aer_row_limit', '{"action":"park","reason":"row limit","next_action":"set a row limit"}'),
  ('aer_technical', '40000000-0000-0000-0000-000000000003', 'l4_item', '10000000-0000-0000-0000-000000000002', 'parked', 'duplicate', '{"action":"park","reason":"duplicate, not counted as a decision","next_action":"none"}'),
  ('aer_technical', '40000000-0000-0000-0000-000000000004', 'l4_item', '10000000-0000-0000-0000-000000000002', 'parked', 'aer_human_input', '{"action":"park","reason":"manual lock","next_action":"a person decides"}'),
  ('aer_technical', '40000000-0000-0000-0000-000000000005', 'l4_item', '10000000-0000-0000-0000-000000000003', 'parked', 'aer_stale', '{"action":"park","reason":"stale","next_action":"reject"}'),
  ('aer_technical', '40000000-0000-0000-0000-000000000006', 'l4_item', '10000000-0000-0000-0000-000000000003', 'parked', 'transient', '{"action":"retry_backoff","reason":"retrying","next_action":"wait"}'),
  ('aer_technical', '40000000-0000-0000-0000-000000000007', 'l4_item', '10000000-0000-0000-0000-000000000003', 'deferred', 'aer_reread_eligible', '{"action":"defer","reason":"reread","next_action":"aer-replay"}'),
  ('aer_technical', '40000000-0000-0000-0000-000000000099', 'l4_item', '10000000-0000-0000-0000-000000000003', 'parked', 'aer_row_limit', '{"action":"park","reason":"row limit","next_action":"x"}');
