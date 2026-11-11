-- Three waiting reads of P1 (eligible, AU) courses, as production holds them on 11 Nov 2026:
--   A cut at the row limit, limit raised since the read: the rule makes it eligible (class changed_conditions, route row_limit)
--   B cut at the row limit under the same limit: the rule refuses it (class row_limit)
--   C complete except rows a person leaves out
-- and the last 24 hours as production: 200 new reads used the cap, 0 corrected reads.
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status) values
 ('5a000000-0000-0000-0000-00000000000a', 'course', '30000000-0000-0000-0000-000000000001', 'course_entry_first_read', 'pending'),
 ('5a000000-0000-0000-0000-00000000000b', 'course', '30000000-0000-0000-0000-000000000002', 'course_entry_first_read', 'pending'),
 ('5a000000-0000-0000-0000-00000000000c', 'course', '30000000-0000-0000-0000-000000000003', 'course_entry_first_read', 'pending');
insert into fx.item_state values
 ('5a000000-0000-0000-0000-00000000000a', '{"complete":false,"rows_cut":7,"shared_page":[],"drops_uncovered":[]}', '{"eligible":true,"class":"changed_conditions","route":"row_limit"}', true),
 ('5a000000-0000-0000-0000-00000000000b', '{"complete":false,"rows_cut":62,"shared_page":[],"drops_uncovered":[]}', '{"eligible":false,"class":"row_limit","route":"source_is_matrix","next_action":"read the entry matrix"}', true),
 ('5a000000-0000-0000-0000-00000000000c', '{"complete":false,"rows_cut":0,"shared_page":[],"drops_uncovered":[]}', '{"eligible":false,"class":"decision"}', true);
update pipeline.platform_toolset_settings set value = '600' where key = 'aer.schedule_layer4_max';
insert into pipeline.platform_toolset_settings values ('pipeline', 'batch.aer_schedule_held', '10');
insert into pipeline.aer_schedule_runs(ran_at, course_reads, corrections) values (now() - interval '20 hours', 200, 0);
