-- CF-247 AER recovery selector fixtures: lane aer_technical as in production at 16:32 AEDT, on top of ../aer-review-queue/seed.sql. Fixture data.
-- Each refused corrected read has the enrich item that read it, on the stored copy the course page holds (production: 69 of 71 refusals in
-- 24 hours were on an unchanged copy); refusals happened before the lifecycle settings existed (their creation is not a change).
insert into pipeline.field_enrich_items(id, course_id, field, state, evidence_id, reason, value, cost_usd)
select 800000 + row_number() over (order by s.requested_at, s.id), s.course_id, 'entry_requirements', case when s.state = 'requested' then 'queued' else 'skipped' end,
       pg.evidence_id, coalesce(s.outcome, 'reading'), '{}'::jsonb, 0.0061
  from pipeline.aer_read_supersessions s join pipeline.coverage_course_pages pg on pg.course_id = s.course_id where s.enrich_item_id is null;
update pipeline.aer_read_supersessions s set enrich_item_id = f.id from pipeline.field_enrich_items f where f.id >= 800000 and f.course_id = s.course_id and s.enrich_item_id is null;
update pipeline.platform_toolset_settings set updated_at = '2026-10-01 00:00:00+10' where toolset_key = 'pipeline' and (key like 'entry.%' or key like 'layer4.re%');
-- one shared page already has its Human input needed item (production: 16 aer_course_identity items were raised by v2.15.470)
select security.layer4_intervention_raise_v1(jsonb_build_object('class', 'aer_course_identity', 'entity', i.id::text, 'provider_id', c.provider_id, 'course_id', c.id,
         'attempts', 99, 'subject', 'confirm the course', 'signature', 'fixture',
         'resume_target', jsonb_build_object('operation', 'AER technical check of the held item', 'work_item', jsonb_build_object('lane', 'aer_technical', 'entity', i.id::text, 'kind', 'l4_item'))))
  from pipeline.layer4_review_items i join fx.gate f on f.item_id = i.id join catalogue.courses c on c.id = i.entity_id
 where fx.cls(f.g) = 'shared_page' and f.g->>'rule' = 'E13' order by i.created_at limit 1;
-- the row limit by university, as live (empty), set long before any refusal
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value, updated_at) values ('pipeline', 'entry.max_rows_by_provider', 'list', '[]', '2026-10-01 00:00:00+10')
on conflict (toolset_key, key) do update set value = '[]', updated_at = '2026-10-01 00:00:00+10';
