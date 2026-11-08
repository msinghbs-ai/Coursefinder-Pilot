-- Guards: Platform Admin directive 8 Nov 2026 (run readiness assessment for newly replayed items; complete technical recovery and review-ready progression; no AI approval).
-- AFTER the migration 20261108150000: the replay has the items it creates assessed in the same run. Every block raises on a failed check.
\set ON_ERROR_STOP 1
set client_min_messages = notice;
create function pg_temp.ok(p boolean, p_what text) returns void language plpgsql as $f$ begin if p is distinct from true then raise exception 'FAIL: %', p_what; end if; end $f$;
create function pg_temp.newitem(p_item uuid) returns uuid language sql as $f$ select new_item_id from pipeline.aer_read_supersessions where old_item_id = p_item and state = 'superseded' $f$;
update pipeline.platform_toolset_settings set value = to_jsonb(array['d1000000-0000-4000-8000-000000000000=9']) where key = 'entry.max_rows_by_provider';
update pipeline.platform_toolset_settings set value = to_jsonb(100) where key = 'aer.replay_daily_max';

-- 1 a preview recovers nothing and assesses nothing
do $t$ declare v_old uuid := public.fx_seed('c3000000-0000-4000-8000-000000000001', 'Diploma of Fixtures One'); p jsonb; begin
  p := security.aer_replay_v1(true);
  perform pg_temp.ok((p->>'can_be_recovered')::int >= 1 and (p->>'replaced')::int = 0 and p->'readiness' = 'null'::jsonb, 'the preview sees the read, replaces nothing and assesses nothing: ' || p::text);
  perform pg_temp.ok((select count(*) from public.readiness_calls) = 0, 'the preview calls no assessment');
  raise notice 'PASS preview';
end $t$;

-- 2 a real run: the new item is created, the old one superseded, and exactly the new item is assessed in the same run
do $t$ declare v_old uuid := (select item_id from pipeline.layer4_item_readiness r join pipeline.layer4_review_items i on i.id = r.item_id where i.entity_id = 'c3000000-0000-4000-8000-000000000001');
               v_new uuid; p jsonb; v_calls int; begin
  p := security.aer_replay_v1(false);
  v_new := pg_temp.newitem(v_old);
  perform pg_temp.ok(v_new is not null and (select status from pipeline.layer4_review_items where id = v_new) = 'pending', 'a new waiting item carries the recovered read: ' || p::text);
  perform pg_temp.ok((select status from pipeline.layer4_review_items where id = v_old) = 'superseded', 'the old item is superseded (history kept)');
  select count(*) into v_calls from public.readiness_calls;
  perform pg_temp.ok(v_calls = 1, 'one assessment call in the run: ' || v_calls);
  perform pg_temp.ok((select items from public.readiness_calls limit 1) = array[v_new], 'the call names exactly the new item');
  perform pg_temp.ok((p->'readiness'->>'classified')::int = 1, 'the result carries the assessment: ' || p::text);
  perform pg_temp.ok((select count(*) from catalogue.course_entry_requirements where status = 'active') = 0 and (select count(*) from pipeline.layer4_decisions) = 0, 'nothing is approved or admitted');
  raise notice 'PASS real run assesses the new item';
end $t$;

-- 3 a run that recovers nothing makes no assessment call (no new items)
do $t$ declare p jsonb; v_before int := (select count(*) from public.readiness_calls); begin
  p := security.aer_replay_v1(false);
  perform pg_temp.ok((p->>'replaced')::int = 0 and p->'readiness' = 'null'::jsonb and (select count(*) from public.readiness_calls) = v_before, 'no replacement, no call: ' || p::text);
  raise notice 'PASS no replacement, no call';
end $t$;

-- 4 two items in one run are assessed in one call
do $t$ declare a uuid := public.fx_seed('c3000000-0000-4000-8000-000000000002', 'Diploma of Fixtures Two'); b uuid := public.fx_seed('c3000000-0000-4000-8000-000000000003', 'Diploma of Fixtures Three');
               p jsonb; v_items uuid[]; begin
  p := security.aer_replay_v1(false);
  select items into v_items from public.readiness_calls order by id desc limit 1;
  perform pg_temp.ok(cardinality(v_items) = 2 and v_items @> array[pg_temp.newitem(a), pg_temp.newitem(b)], 'both new items are in the one call: ' || p::text);
  raise notice 'PASS several items, one call';
end $t$;

-- 5 a failing assessment is reported and never undoes the replay
do $t$ declare a uuid := public.fx_seed('c3000000-0000-4000-8000-000000000004', 'Diploma of Fixtures Four'); p jsonb; begin
  perform set_config('aerrr.fail', '1', false);
  p := security.aer_replay_v1(false);
  perform set_config('aerrr.fail', '0', false);
  perform pg_temp.ok((p->>'replaced')::int = 1 and p->'readiness'->>'error' like '%failed on purpose%', 'the failure is reported: ' || p::text);
  perform pg_temp.ok(pg_temp.newitem(a) is not null and (select status from pipeline.layer4_review_items where id = pg_temp.newitem(a)) = 'pending' and (select status from pipeline.layer4_review_items where id = a) = 'superseded', 'the replay stands');
  raise notice 'PASS a failing assessment does not undo the replay';
end $t$;

-- 6 the switch still stops the run before anything is replaced or assessed
do $t$ declare p jsonb; v_before int := (select count(*) from public.readiness_calls); begin
  update pipeline.platform_toolset_settings set value = to_jsonb(0) where key = 'aer.replay_on';
  p := security.aer_replay_v1(false);
  update pipeline.platform_toolset_settings set value = to_jsonb(1) where key = 'aer.replay_on';
  perform pg_temp.ok(p->>'held' = 'aer.replay_on is 0' and (select count(*) from public.readiness_calls) = v_before, 'aer.replay_on = 0 stops it: ' || p::text);
  raise notice 'PASS switch';
end $t$;
