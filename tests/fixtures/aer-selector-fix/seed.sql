-- CF-247 AER selector fix: production at 19:13 AEDT 4 Nov 2026 (read only, 20:08-20:13).
-- 1 entry settings as live: all entry.% touched 3 Nov 20:07 AEDT after the items were read (values unchanged); the row limit set 28 Oct 21:38;
--   entry.max_rows_by_provider (empty) inserted 2 Nov 06:43
update pipeline.platform_toolset_settings set updated_at = '2026-11-03 09:07:09.670112+00' where toolset_key = 'pipeline' and key like 'entry.%';
update pipeline.platform_toolset_settings set updated_at = '2026-10-28 10:38:37.661455+00' where toolset_key = 'pipeline' and key = 'entry.max_rows_per_course';
update pipeline.platform_toolset_settings set updated_at = '2026-11-01 19:43:26.950319+00' where toolset_key = 'pipeline' and key = 'entry.max_rows_by_provider';
-- 2 the earlier fixture's end-to-end recovery happened two hours ago
update pipeline.work_items set recovered_at = recovered_at - interval '2 hours' where lane = 'aer_technical' and recovered_at is not null;
update pipeline.aer_read_supersessions set requested_at = requested_at - interval '2 hours', closed_at = closed_at - interval '2 hours';
-- 3 two corrected reads that replaced their read (18:14) and one refused, none with a lane item (they were never technically blocked)
insert into pipeline.aer_read_supersessions(old_item_id, course_id, state, new_item_id, outcome, requested_at, closed_at)
select o.id, o.entity_id, s.state, case when s.state = 'superseded' then n.id end, s.outcome, now() - interval '20 minutes', now() - interval '19 minutes'
  from (values (1, 'superseded', null), (2, 'superseded', null), (3, 'refused', 'the corrected read still drops 3 printed requirement(s)')) s(k, state, outcome)
  join lateral (select i.id, i.entity_id from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code = 'course_entry_first_read'
                  and not exists (select 1 from pipeline.work_items w where w.entity = i.id::text) order by i.id offset s.k limit 1) o on true
  join lateral (select i.id from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code = 'course_entry_first_read' order by i.id desc offset s.k limit 1) n on true;
-- 4 the lane's run at 19:13 under the live rule
select security.aer_technical_recovery_v1();
-- 5 the held step's last checks: the items the rule makes eligible were checked last, the others earlier (as at 19:13: its 40 were holds)
insert into pipeline.aer_schedule_checks(item_id, checked_at, outcome)
select i.id, case when w.unresolved_blocker->>'class' = 'reread_eligible' then now() - interval '1 hour' else now() - interval '3 hours' end, 'seed'
  from pipeline.layer4_review_items i left join pipeline.work_items w on w.lane = 'aer_technical' and w.entity = i.id::text and w.work_kind = 'l4_item'
 where i.status = 'pending' and i.field_code = 'course_entry_first_read'
on conflict (item_id) do update set checked_at = excluded.checked_at, outcome = excluded.outcome;
