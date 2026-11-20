-- CF-247 s856 (Platform Admin 20 Nov 2026 19:15 AEDT, chat S1-Fees-Intakes): the deterministic fee, intake and deadline sweep is paced so a tick stays short and the
-- worker is never sent a burst.
-- Found live (rolled-back read-back, 20 Nov 2026 19:18 AEDT, runs 44701411953 and 44701584244), first two hours of s852: 74 of 74 job runs succeeded and 2,100 pages
--   were read, but (1) a tick that recorded the five replies of a batch (150 pages) in one transaction took 84 to 120 s, holding catalogue row locks that long; and
--   (2) at 18:50 all five calls of one batch went to coverage-sweep at once and every one failed with WORKER_RESOURCE_LIMIT (HTTP 546), with the other lanes' sweeps
--   on the same function. Those 150 pages are offered again in the next pass (their pages were never recorded).
-- First merged as 20261120193000 (Pilot #1437); Deploy on merge refused it before applying anything, because it widened a check with a top-level drop. That file
--   was never applied and is removed; this file does the same without any drop: queued calls wait in their own table.
-- What changes (the 100 to 250 course batch is unchanged): a new batch is cut into calls of fid.items_per_call that wait in pipeline.fid_det_call_queue; each
--   minute the job sends at most one queued call while fewer than fid.calls_open_max are waiting for a reply, and records at most fid.replies_per_tick replies. A
--   tick now records about 30 pages (about 20 s) and the worker sees at most two calls at a time from this lane. Throughput stays about 1,800 pages an hour.
-- Objects (no new public function, table or view): table pipeline.fid_det_call_queue; function security.fid_det_tick_v1 replaced
--   (signature unchanged; its live body is the one merged in 20261120175100, read back 19:18 AEDT); two settings; watchdog row fid_det counts queued and sent calls.
-- G1: no new job. G2: both new values are settings. G3: no consumer API object; checked before and after (75 functions, 48 relations, no drift).
-- Parity: newest migration on main 20261120181000 (S1-Build s881) read 20 Nov 2026 19:20 AEDT; lane block s850 to s859.
-- Replaces: the s852 burst (every call of a batch sent in one tick, every reply recorded in one tick).
-- Retires: nothing. Nothing dropped, deleted or renamed.
-- Rollback: set fid.calls_open_max and fid.replies_per_tick to 5 (the old burst), or fid.sweep_on to 0.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
  ('pipeline', 'fid.calls_open_max', 'Deterministic fee, intake and deadline reader: calls waiting at once',
   'Worker calls of this reader that may be waiting for a reply at the same time; one more is sent each minute while fewer are out. Keeps the shared coverage-sweep worker from a burst.',
   'number', to_jsonb(2), 1, 5, 'calls', 998, 'Fees and intakes', 'fid-det-sweep (security.fid_det_tick_v1)', 'CF-247 s856 (Platform Admin 20 Nov 2026 19:15)'),
  ('pipeline', 'fid.replies_per_tick', 'Deterministic fee, intake and deadline reader: replies recorded a minute',
   'Worker replies recorded (gated and admitted) in one run of the job; each reply is one call of pages. One keeps a run to about 20 seconds.',
   'number', to_jsonb(1), 1, 5, 'replies', 999, 'Fees and intakes', 'fid-det-sweep (security.fid_det_tick_v1)', 'CF-247 s856 (Platform Admin 20 Nov 2026 19:15)')
on conflict (toolset_key, key) do nothing;

create table if not exists pipeline.fid_det_call_queue (
  id bigserial primary key,
  items integer not null,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  run_id bigint
);
create index if not exists fid_det_call_queue_waiting on pipeline.fid_det_call_queue (id) where run_id is null;
alter table pipeline.fid_det_call_queue enable row level security;
revoke all on table pipeline.fid_det_call_queue from public, anon, authenticated;
comment on table pipeline.fid_det_call_queue is 'CF-247 s856: the calls of a deterministic fee, intake and deadline batch waiting to be sent (run_id null); job fid-det-sweep sends one a minute and sets run_id to the pipeline.fid_det_runs row it became.';

create or replace function security.fid_det_tick_v1()
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare r record; v_resp record; v_items jsonb; v_call jsonb; v_per int; v_n int; v_sent int := 0; v_rec jsonb := '[]'::jsonb; v_req bigint; v_run bigint;
        v_ext constant text := 'fid-det-v1.0';  -- fixed: the extractor version this database records (fid-det-reader.ts FID_DET_VERSION)
        v_settle jsonb; v_done int := 0;
        v_rpt int := greatest(1, least(security.pipeline_num_v1('fid.replies_per_tick', 1)::int, 5));  -- fixed: bounds of the setting
        v_open int := greatest(1, least(security.pipeline_num_v1('fid.calls_open_max', 2)::int, 5));   -- fixed: bounds of the setting
begin
  if not pg_try_advisory_xact_lock(hashtext('fid_det_tick')) then return jsonb_build_object('skipped', 'a run is already going'); end if;
  -- s850: AI fee reader items whose third lease ran out are settled here every minute (cheap, indexed by state)
  v_settle := security.fee_reader_queue_settle_v1();
  if security.pipeline_num_v1('fid.sweep_on', 1) < 1 then return jsonb_build_object('skipped', 'switched off (fid.sweep_on)', 'fee_reader', v_settle); end if;
  -- 1 at most fid.replies_per_tick replies that have come back (oldest first); a call with no reply in time is closed as expired
  for r in select * from pipeline.fid_det_runs where state = 'sent' order by id loop
    select status_code, content, timed_out, error_msg into v_resp from net._http_response where id = r.request_id;
    if not found then
      if r.sent_at < now() - make_interval(mins => security.pipeline_num_v1('fid.reply_wait_minutes', 15)::int) then
        update pipeline.fid_det_runs set state = 'expired', recorded_at = now(), result = jsonb_build_object('reason', 'no reply in time') where id = r.id;
      end if;
      continue;
    end if;
    exit when v_done >= v_rpt;
    v_done := v_done + 1;
    if v_resp.status_code is distinct from 200 or v_resp.content is null then
      update pipeline.fid_det_runs set state = 'failed', recorded_at = now(), result = jsonb_build_object('status', v_resp.status_code, 'error', left(coalesce(v_resp.error_msg, v_resp.content, ''), 300)) where id = r.id;
      continue;
    end if;
    begin
      v_call := v_resp.content::jsonb;
      if v_call->>'extractor' is distinct from v_ext then raise exception 'the worker answered with extractor % (expected %)', v_call->>'extractor', v_ext; end if;
      v_call := security.fid_det_record_v1(r.id, v_call);
      update pipeline.fid_det_runs set state = 'recorded', recorded_at = now(), result = v_call where id = r.id;
      v_rec := v_rec || v_call;
    exception when others then
      update pipeline.fid_det_runs set state = 'failed', recorded_at = now(), result = jsonb_build_object('error', left(sqlerrm, 300)) where id = r.id;
    end;
  end loop;
  -- 2 a new batch, cut into queued calls, on its minute and only when nothing of the last batch is waiting or out
  if (extract(epoch from date_trunc('minute', now())) / 60)::bigint % greatest(security.pipeline_num_v1('fid.run_every_minutes', 5)::int, 1) = 0
     and not exists (select 1 from pipeline.fid_det_runs where state = 'sent')
     and not exists (select 1 from pipeline.fid_det_call_queue where run_id is null) then
    v_items := security.fid_det_batch_v1(security.pipeline_num_v1('fid.batch_size', 150)::int, v_ext);
    v_per := greatest(5, least(security.pipeline_num_v1('fid.items_per_call', 30)::int, 40));  -- fixed: the worker reads at most 40 pages a call
    v_n := jsonb_array_length(v_items);
    for i in 0 .. greatest(0, (v_n - 1) / v_per) loop
      exit when v_n = 0;
      insert into pipeline.fid_det_call_queue(items, payload)
      values (least(v_per, v_n - i * v_per),
              (select jsonb_agg(x) from jsonb_array_elements(v_items) with ordinality t(x, o) where o > i * v_per and o <= (i + 1) * v_per));
    end loop;
  end if;
  -- 3 send at most one queued call a minute, while fewer than fid.calls_open_max are waiting for a reply
  if (select count(*) from pipeline.fid_det_runs where state = 'sent') < v_open then
    select id, items, payload into r from pipeline.fid_det_call_queue where run_id is null order by id limit 1 for update skip locked;
    if found then
      insert into pipeline.fid_det_runs(items) values (r.items) returning id into v_run;
      v_req := pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'fid_det_read', 'run_id', v_run, 'items', r.payload));
      update pipeline.fid_det_runs set request_id = v_req where id = v_run;
      update pipeline.fid_det_call_queue set run_id = v_run where id = r.id;
      v_sent := 1;
    end if;
  end if;
  return jsonb_build_object('recorded', v_rec, 'sent', v_sent, 'queued', (select count(*) from pipeline.fid_det_call_queue where run_id is null), 'fee_reader', v_settle);
end $function$;
comment on function security.fid_det_tick_v1() is 'CF-247 s852, paced by s856: job fid-det-sweep. Settles exhausted AI fee reader items (s850), records at most fid.replies_per_tick fid_det_read replies, cuts a new batch of stored course pages into queued calls on its minute, and sends one queued call a minute while fewer than fid.calls_open_max are out. $0: no model, no Firecrawl.';

update pipeline.queue_watch
   set pending_sql = 'select (select count(*) from pipeline.fid_det_runs where state = ''sent'') + (select count(*) from pipeline.fid_det_call_queue where run_id is null)'
 where key = 'fid_det';

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('function', 'security.fid_det_tick_v1 (s856 pacing)', 'Layer 2', 'Fees and intakes', 'The deterministic sweep job, paced: one call a minute, one reply recorded a minute', 'active', '{}', '20261120200000'),
  ('table', 'pipeline.fid_det_call_queue', 'Layer 2', 'Fees and intakes', 'Calls of a deterministic batch waiting to be sent', 'active', '{}', '20261120200000')
on conflict do nothing;

-- post-checks: inside a subtransaction that is always rolled back (no row is left), a tick with two calls waiting sends one call and records at most one reply;
-- then the consumer API has not moved
do $c$
declare v jsonb; v_api jsonb; v_t timestamptz; v_ms numeric; v_sent int; v_recorded int;
begin
  begin
    insert into pipeline.fid_det_call_queue(items, payload) values (1, '[]'::jsonb), (1, '[]'::jsonb);
    v_t := clock_timestamp();
    v := security.fid_det_tick_v1();
    v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
    v_sent := (select count(*) from pipeline.fid_det_runs where state = 'sent' and sent_at >= v_t);
    v_recorded := jsonb_array_length(coalesce(v->'recorded', '[]'::jsonb));
    raise exception using errcode = 'P0002', message = 's856-probe-rollback';
  exception when sqlstate 'P0002' then null;
  end;
  raise notice 's856 post-check: sent %, recorded %, % ms', v_sent, v_recorded, round(v_ms);
  if v_sent > 1 then raise exception 'post-check: a tick sent % calls (at most one)', v_sent; end if;
  if v_recorded > security.pipeline_num_v1('fid.replies_per_tick', 1) then raise exception 'post-check: a tick recorded % replies', v_recorded; end if;
  if exists (select 1 from pipeline.fid_det_call_queue where payload = '[]'::jsonb) then raise exception 'post-check: a test call was left behind'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
