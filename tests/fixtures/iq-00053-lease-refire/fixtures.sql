-- CF-247 IQ-00053: every case of the change on the migrated fixture database. Each block raises an exception on a wrong result and a notice "ok ..." on a right one.
-- The stub security.enrich_ai_fire_v1 records each call in pipeline.fx_fire (stubs.sql of the course-enrichment fixtures).
create or replace function pg_temp.slice(p_job uuid) returns int language plpgsql as $f$
declare v_before int; begin
  select count(*) into v_before from pipeline.fx_fire;
  perform security.enrich_fields_slice_v1(p_job, 10);
  return (select count(*) from pipeline.fx_fire) - v_before;
end $f$;
insert into pipeline.admin_jobs(id, kind, state, args) values
 ('00000000-0000-0000-0000-00000000f101', 'enrich_fields', 'running', '{"standing": true, "ai": true}'),
 ('00000000-0000-0000-0000-00000000f102', 'enrich_fields', 'running', '{"standing": true, "ai": true}'),
 ('00000000-0000-0000-0000-00000000f103', 'enrich_fields', 'running', '{"standing": true, "ai": true}'),
 ('00000000-0000-0000-0000-00000000f104', 'enrich_fields', 'running', '{"standing": true, "ai": true}');
insert into pipeline.field_enrich_items(job_id, provider_id, field, state, source, attempts, leased_until) values
 ('00000000-0000-0000-0000-00000000f101', '00000000-0000-0000-0000-0000000000b1', 'provider_address', 'leased', 'scraper', 1, now() - interval '5 minutes'),
 ('00000000-0000-0000-0000-00000000f102', '00000000-0000-0000-0000-0000000000b1', 'provider_address', 'leased', 'scraper', 1, now() + interval '3 minutes'),
 ('00000000-0000-0000-0000-00000000f103', '00000000-0000-0000-0000-0000000000b1', 'provider_address', 'leased', 'scraper', 3, now() - interval '5 minutes'),
 ('00000000-0000-0000-0000-00000000f104', '00000000-0000-0000-0000-0000000000b1', 'provider_address', 'ai', 'scraper', 0, null);

-- 1 a task whose only open item is a leased item with an expired lease (the failed call's items) asks the worker again
do $$ begin
  if pg_temp.slice('00000000-0000-0000-0000-00000000f101') <> 1 then raise exception 'FAIL 1: an expired lease must fire the worker again'; end if;
  raise notice 'ok 1 an item left "leased" after a failed call (lease over, fewer than 3 tries) makes the task ask the worker again';
end $$;
-- 2 a lease still running is left alone (the call may still be answering)
do $$ begin
  if pg_temp.slice('00000000-0000-0000-0000-00000000f102') <> 0 then raise exception 'FAIL 2: a running lease must not fire a second call'; end if;
  raise notice 'ok 2 a lease that has not run out does not start a second call';
end $$;
-- 3 an item that has used its 3 tries is settled failed, not asked again
do $$ begin
  if pg_temp.slice('00000000-0000-0000-0000-00000000f103') <> 0 then raise exception 'FAIL 3: a spent item must not fire the worker'; end if;
  if (select state from pipeline.field_enrich_items where job_id = '00000000-0000-0000-0000-00000000f103') <> 'failed' then raise exception 'FAIL 3: a spent item is settled failed'; end if;
  raise notice 'ok 3 an expired lease at 3 tries is settled failed and does not fire the worker';
end $$;
-- 4 the existing behaviour: an item waiting for the AI fires the worker
do $$ begin
  if pg_temp.slice('00000000-0000-0000-0000-00000000f104') <> 1 then raise exception 'FAIL 4: an item in state ai must fire the worker'; end if;
  raise notice 'ok 4 an item in state ai still fires the worker';
end $$;

-- 5 the worker read-out: ok, failed (546), in flight, no recorded answer; other functions and modes are not counted; the task progress carries it
insert into net._http_response(id, status_code, content, created) values (9001, 200, '{"ok":true}', now()), (9002, 546, '{"code":"WORKER_RESOURCE_LIMIT"}', now()),
  (9003, 200, '{"ok":false,"error":"x"}', now()), (9004, 200, '{"ok":true}', now());
insert into pipeline.edge_request_log(slot, request_id, function_name, mode, created_at) values
 (9001, 9001, 'coverage-sweep', 'enrich_ai', now() - interval '20 minutes'), (9002, 9002, 'coverage-sweep', 'enrich_ai', now() - interval '19 minutes'),
 (9003, 9003, 'coverage-sweep', 'enrich_ai', now() - interval '18 minutes'), (9005, 9005, 'coverage-sweep', 'enrich_ai', now() - interval '15 minutes'),
 (9006, 9006, 'coverage-sweep', 'enrich_ai', now() - interval '30 seconds'), (9004, 9004, 'coverage-sweep', 'read', now() - interval '10 minutes'),
 (9007, 9007, 'coverage-sweep', 'enrich_ai', now() - interval '5 hours');
do $$
declare w jsonb;
begin
  w := security.enrich_worker_health_v1();
  if w <> '{"ok": 1, "calls": 5, "failed": 2, "in_flight": 1, "window_minutes": 120, "no_answer_recorded": 1}'::jsonb then raise exception 'FAIL 5: worker health is %', w; end if;
  perform security.enrich_fields_slice_v1('00000000-0000-0000-0000-00000000f102', 10);
  if (select progress->'worker' from pipeline.admin_jobs where id = '00000000-0000-0000-0000-00000000f102') <> w then
    raise exception 'FAIL 5: the task progress must carry the worker read-out: %', (select progress from pipeline.admin_jobs where id = '00000000-0000-0000-0000-00000000f102'); end if;
  raise notice 'ok 5 the worker read-out counts 1 ok, 2 failed (546 and "ok": false), 1 in flight, 1 with no recorded answer; the 5-hour-old and other-mode calls are not counted; the task progress carries it';
end $$;
-- 6 the one setting: 8 with a reason and an audit event; the migration touched nothing else
do $$ begin
  if (select value from pipeline.platform_toolset_settings where key = 'enrich.ai_calls_at_once') <> '8'::jsonb then raise exception 'FAIL 6: enrich.ai_calls_at_once must be 8'; end if;
  if (select reason from pipeline.platform_toolset_settings where key = 'enrich.ai_calls_at_once') !~ 'IQ-00053' then raise exception 'FAIL 6: the setting needs its reason'; end if;
  if (select count(*) from pipeline.admin_control_events where target = 'pipeline/enrich.ai_calls_at_once' and detail->>'to' = '8' and detail->>'from' = '20') <> 1 then raise exception 'FAIL 6: one audit event'; end if;
  raise notice 'ok 6 enrich.ai_calls_at_once 20 -> 8 with its reason and one audit event';
end $$;
