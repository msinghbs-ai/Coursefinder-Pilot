-- Guards: F-CDESC (Platform Admin decision 10 Nov 2026): the four existing measures that 20261110060100 edits (summary, capacity, sample report, reviewer pace) answer exactly as before while no machine decision exists.
-- Run BEFORE the migrations: puts a person's Layer 4 decisions on a described course (approved, rejected, spaced 4 minutes apart as a reviewer would) and keeps the four answers in public.g_measure_before.
-- measures_after.sql (run after both migrations) compares them: the same, except the new keys the migration adds. The scenarios clear these rows afterwards.
\set ON_ERROR_STOP 1
create table public.g_measure_before(fn text primary key, answer jsonb);
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, status, change_control_ref, decided_at)
select ('00000000-0000-4000-c300-0000000009' || lpad(k::text, 2, '0'))::uuid, 'course', c.id, 'course_description_first_read', null, '{"description": null}'::jsonb,
       jsonb_build_object('description', case when k = 0 then c.description else 'A person decided text number ' || k end),
       case when k < 7 then 'approved' else 'rejected' end, 'x', now() - interval '1 hour'
  from generate_series(0, 8) k cross join (select id, description from catalogue.courses where nullif(btrim(description), '') is not null order by id limit 1) c;
insert into pipeline.layer4_decisions(review_item_id, action, actor_id, reason, layer2_state, layer3_state, change_control_ref, created_at)
select ('00000000-0000-4000-c300-0000000009' || lpad(k::text, 2, '0'))::uuid, case when k < 7 then 'approve' else 'reject' end, '00000000-0000-4000-a000-000000000001'::uuid, '[other] x', '{}'::jsonb, '{}'::jsonb, 'x',
       now() - interval '4 minutes' * (9 - k)
  from generate_series(0, 8) k;
insert into public.g_measure_before values
 ('summary', security.course_description_summary_v1(null, false)), ('capacity', security.course_description_capacity_v1()),
 ('sample', security.course_description_sample_report_v1()), ('pace', security.layer4_pace_v1());
select 'before: summary admitted_by_person=' || (answer->>'admitted_by_person') from public.g_measure_before where fn = 'summary';
