-- CF-247 s956 (session S1-API-Frontend-Delivery, Lane 1 item 2; India team review of 20 Nov 2026, REQ-106): the Rankings & statistics cards name each
-- dataset in full, so a counsellor knows what QILT and PRISMS are. The cards read their names, descriptions and publisher from the dataset
-- registry (pipeline.statistics_dataset_registry, Rankings & statistics › Datasets); this sets the full forms there. QS and THE already carry
-- their full names (QS World University Rankings; Times Higher Education World University Rankings). Values only: no table, column or function changes.
-- Live on deploy. $0. G1: no job. G2: no operational value. G3: the registry is not part of the consumer API; checked before and after.
-- Parity: live head 20261122030000 read 21 Nov 2026 22:40 AEDT; this file is numbered strictly above it.
-- Replaces: the short names QILT and PRISMS on the cards.
-- Retires: nothing. Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;

update pipeline.statistics_dataset_registry
   set label = 'QILT (Quality Indicators for Learning and Teaching)',
       description = 'The Australian Government''s national surveys of current students and graduates: student experience, graduate outcomes and employment, by provider and study area.'
 where dataset_key = 'qilt' and label = 'QILT';
update pipeline.statistics_dataset_registry
   set label = 'PRISMS (Provider Registration and International Student Management System)',
       description = 'The Australian Government''s register of international student enrolments: enrolment and commencement counts for each provider, by period and student nationality.'
 where dataset_key = 'prisms' and label = 'PRISMS';

do $c$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if (select count(*) from pipeline.statistics_dataset_registry where dataset_key in ('qilt', 'prisms') and label like '%(%)') <> 2 then
    raise exception 'post-check: QILT and PRISMS do not carry their full names';
  end if;
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
