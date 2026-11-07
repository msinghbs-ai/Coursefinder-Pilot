-- CF-247 P1 (Platform Admin 7 Nov 2026 13:17 and 14:27): alert delivery lifecycle. Taking an alert is no longer "sent".
-- Why: security.queue_watch_alerts_take_v1 stamps sent_at when it hands the alert over, and platform_alerts_confirm_v1 is run by the same task straight after it writes its
--   message. "Sent" therefore meant only "the run reached its last step". The supervised run of 7 Nov 01:58Z marked 84 platform and 42 work-queue alerts sent and the
--   Platform Admin received neither push nor email. A scheduled task has no way to see whether its notification was accepted or received.
-- What: an append-only outbox beside the existing alert tables (no historical alert row is read-modified here):
--   pipeline.alert_delivery_batches   one row per delivery try (alerts or a notification-only test): durable batch id, what the run reported, and SEPARATE
--                                     transport and receipt states. transport_state never becomes 'transport_acknowledged' for the scheduled-task channel (no ack exists).
--   pipeline.alert_delivery_attempts  one row per alert per batch. A partial unique index allows one live attempt per alert, so a second collector cannot take it.
--   security.alert_delivery_take_v1   leases up to alerts.digest_max_items alerts (platform pending, work-queue unsent) that have no live attempt; nothing is stamped sent.
--   security.alert_delivery_output_v1 the run records that it wrote its message (md5 and item count). Still not delivered.
--   security.alert_delivery_receipt_v1 the Platform Admin's confirmation (push, email) is the only thing that completes an alert. Not received releases it for retry.
--   security.alert_delivery_status_v1 counts for the watchdog: awaiting, overdue, confirmed, not received.
-- Rules kept: a leased batch whose run died (no output after the lease) expires and its alerts become eligible again; a batch with output but no receipt is NEVER
--   re-sent automatically (that would risk a duplicate); after alerts.receipt_wait_hours it shows as overdue and waits for the Platform Admin to say received or not.
--   Alerts already marked sent by the old path are legacy-unknown and are not taken. Putting one back needs an explicit receipt call with confirmed false.
--   A test batch consumes and modifies no alert.
-- Replaces: security.platform_alerts_take_v1, security.platform_alerts_confirm_v1 and security.queue_watch_alerts_take_v1 as the delivery path (functions stay, marked retiring; the disabled task is repointed after acceptance)
-- Retires: nothing dropped (the three functions are marked retiring in pipeline.component_register with replaced_by and retire_after)
-- Consumer API: untouched (pipeline and security objects only; nothing the website or Zoho reads).

create table if not exists pipeline.alert_delivery_batches (
  batch_id uuid primary key default gen_random_uuid(),
  purpose text not null check (purpose in ('alerts', 'test')),
  test_ref text,
  created_at timestamptz not null default now(),
  created_by text not null default 'scheduled task',
  lease_until timestamptz not null,
  items int not null default 0,
  transport_state text not null default 'leased' check (transport_state in ('leased', 'output_written', 'transport_acknowledged', 'transport_failed', 'expired')),
  output_written_at timestamptz,
  output_md5 text,
  output_items int,
  transport_evidence jsonb not null default '{}'::jsonb,
  receipt_state text not null default 'awaiting' check (receipt_state in ('awaiting', 'overdue', 'confirmed', 'not_received')),
  receipt_channels text[] not null default '{}',
  receipt_by text,
  receipt_at timestamptz,
  receipt_note text
);
comment on table pipeline.alert_delivery_batches is 'CF-247 P1 (7 Nov 2026): append-only alert delivery outbox, one row per delivery try or notification-only test. transport_state (what the run did) and receipt_state (what the Platform Admin received) are separate; a scheduled task cannot observe transport acceptance, so only receipt completes an alert. Never read by the consumer API.';
create table if not exists pipeline.alert_delivery_attempts (
  attempt_id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references pipeline.alert_delivery_batches(batch_id),
  alert_source text not null check (alert_source in ('platform', 'queue_watch')),
  alert_id bigint not null,
  state text not null default 'leased' check (state in ('leased', 'output_written', 'receipt_confirmed', 'released')),
  taken_at timestamptz not null default now(),
  released_at timestamptz,
  release_reason text,
  unique (batch_id, alert_source, alert_id)
);
comment on table pipeline.alert_delivery_attempts is 'CF-247 P1 (7 Nov 2026): one row per alert per delivery batch. The partial unique index alert_delivery_attempts_live_uq allows one live attempt per alert, so delivery is idempotent and a second collector cannot take the same alert. released = eligible for a new attempt; receipt_confirmed = final. Never read by the consumer API.';
create unique index if not exists alert_delivery_attempts_live_uq on pipeline.alert_delivery_attempts (alert_source, alert_id) where state in ('leased', 'output_written', 'receipt_confirmed');
alter table pipeline.alert_delivery_batches enable row level security;
alter table pipeline.alert_delivery_attempts enable row level security;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'alerts.digest_max_items', 'Alerts: most alerts in one message',
  'One delivery message carries at most this many alerts; the rest wait for the next run. Keeps the push and email readable.', 'number',
  to_jsonb(15), 1, 50, 'alerts', 974, 'Alerts', 'security.alert_delivery_take_v1', 'StudySearch P1 (7 Nov 2026): a 126-alert digest was not received'),
 ('pipeline', 'alerts.receipt_wait_hours', 'Alerts: receipt overdue after',
  'A message that was written but not confirmed as received within this time is shown as overdue on the watchdog. It is never re-sent automatically.', 'number',
  to_jsonb(4), 1, 72, 'hours', 975, 'Alerts', 'security.alert_delivery_status_v1, security.alert_delivery_take_v1', 'StudySearch P1 (7 Nov 2026)')
on conflict (toolset_key, key) do nothing;

create or replace function security.alert_delivery_take_v1(p_purpose text default 'alerts', p_test_ref text default null)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_batch uuid; v_max int := security.pipeline_num_v1('alerts.digest_max_items', 15)::int; v_wait numeric := security.pipeline_num_v1('alerts.receipt_wait_hours', 4);
        v_alerts jsonb := '[]'::jsonb; v_left int := 0;
begin
  if p_purpose not in ('alerts', 'test') then raise exception 'purpose must be alerts or test'; end if;
  -- a run that took alerts and never wrote output has died: release them (nothing was composed, so no duplicate risk)
  update pipeline.alert_delivery_attempts a set state = 'released', released_at = now(), release_reason = 'lease expired before output'
   where a.state = 'leased' and exists (select 1 from pipeline.alert_delivery_batches b where b.batch_id = a.batch_id and b.lease_until < now() and b.transport_state = 'leased');
  update pipeline.alert_delivery_batches set transport_state = 'expired' where transport_state = 'leased' and lease_until < now();
  update pipeline.alert_delivery_batches set receipt_state = 'overdue' where receipt_state = 'awaiting' and transport_state = 'output_written' and output_written_at < now() - make_interval(hours => v_wait::int);
  if p_purpose = 'test' then
    insert into pipeline.alert_delivery_batches(purpose, test_ref, lease_until) values ('test', coalesce(p_test_ref, 'TEST-' || to_char(now(), 'YYYYMMDDHH24MISS')), now() + interval '15 minutes') returning batch_id into v_batch;  -- fixed: delivery lease
    return jsonb_build_object('batch_id', v_batch, 'purpose', 'test', 'count', 0, 'alerts', '[]'::jsonb, 'note', 'notification-only test: no alert is taken or changed');
  end if;
  if exists (select 1 from pipeline.alert_delivery_batches b where b.purpose = 'alerts' and b.receipt_state in ('awaiting', 'overdue') and b.transport_state in ('leased', 'output_written')) then
    return jsonb_build_object('count', 0, 'alerts', '[]'::jsonb, 'blocked', 'an earlier delivery is still awaiting receipt; confirm or reject it first (no duplicate sends)');
  end if;
  insert into pipeline.alert_delivery_batches(purpose, lease_until) values ('alerts', now() + interval '15 minutes') returning batch_id into v_batch;  -- fixed: delivery lease
  with cand as (
    select 'platform'::text src, p.id, p.created_at ts, jsonb_build_object('source', 'platform', 'id', p.id, 'kind', p.kind, 'severity', p.severity, 'title', p.title, 'body', p.body, 'raised_at', p.created_at) j
      from pipeline.platform_alerts p
     where p.status = 'pending' and p.next_attempt_at <= now()
       and not exists (select 1 from pipeline.alert_delivery_attempts x where x.alert_source = 'platform' and x.alert_id = p.id and x.state in ('leased', 'output_written', 'receipt_confirmed'))
    union all
    select 'queue_watch', q.id, q.raised_at, jsonb_build_object('source', 'queue_watch', 'id', q.id, 'queue', q.key, 'state', q.state, 'title', q.title, 'body', q.body, 'raised_at', q.raised_at)
      from pipeline.queue_watch_alerts q
     where q.channel = 'notify' and q.sent_at is null
       and not exists (select 1 from pipeline.alert_delivery_attempts x where x.alert_source = 'queue_watch' and x.alert_id = q.id and x.state in ('leased', 'output_written', 'receipt_confirmed'))
  ), pick as (select * from cand order by ts, src, id limit v_max),
  ins as (insert into pipeline.alert_delivery_attempts(batch_id, alert_source, alert_id) select v_batch, src, id from pick returning alert_source, alert_id)
  select coalesce(jsonb_agg(pick.j order by pick.ts, pick.src, pick.id), '[]'::jsonb) into v_alerts from pick join ins on ins.alert_source = pick.src and ins.alert_id = pick.id;
  select count(*) into v_left from (select 1 from pipeline.platform_alerts p where p.status = 'pending' and not exists (select 1 from pipeline.alert_delivery_attempts x where x.alert_source = 'platform' and x.alert_id = p.id and x.state in ('leased', 'output_written', 'receipt_confirmed'))
       union all select 1 from pipeline.queue_watch_alerts q where q.channel = 'notify' and q.sent_at is null and not exists (select 1 from pipeline.alert_delivery_attempts x where x.alert_source = 'queue_watch' and x.alert_id = q.id and x.state in ('leased', 'output_written', 'receipt_confirmed'))) z;
  update pipeline.alert_delivery_batches set items = jsonb_array_length(v_alerts) where batch_id = v_batch;
  return jsonb_build_object('batch_id', v_batch, 'purpose', 'alerts', 'count', jsonb_array_length(v_alerts), 'alerts', v_alerts, 'still_waiting', v_left,
           'next', 'write the message, then select security.alert_delivery_output_v1(batch_id, md5 of the message, item count). Receipt is confirmed only by the Platform Admin.');
end $f$;

create or replace function security.alert_delivery_output_v1(p_batch uuid, p_md5 text, p_items int)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare n int;
begin
  update pipeline.alert_delivery_batches set transport_state = 'output_written', output_written_at = now(), output_md5 = p_md5, output_items = p_items,
         transport_evidence = transport_evidence || jsonb_build_object('note', 'run wrote its message; scheduled-task transport gives no acknowledgement')
   where batch_id = p_batch and transport_state = 'leased';
  get diagnostics n = row_count;
  update pipeline.alert_delivery_attempts set state = 'output_written' where batch_id = p_batch and state = 'leased';
  return jsonb_build_object('batch_id', p_batch, 'recorded', n = 1, 'receipt', 'awaiting Platform Admin confirmation');
end $f$;

create or replace function security.alert_delivery_receipt_v1(p_batch uuid, p_confirmed boolean, p_channels text[] default '{}', p_actor text default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare b pipeline.alert_delivery_batches%rowtype; n int := 0;
begin
  if p_actor is null or length(p_actor) = 0 then raise exception 'actor required'; end if;
  select * into b from pipeline.alert_delivery_batches where batch_id = p_batch for update;
  if not found then raise exception 'unknown batch'; end if;
  if b.receipt_state in ('confirmed', 'not_received') then return jsonb_build_object('batch_id', p_batch, 'unchanged', true, 'receipt_state', b.receipt_state); end if;
  update pipeline.alert_delivery_batches set receipt_state = case when p_confirmed then 'confirmed' else 'not_received' end, receipt_channels = coalesce(p_channels, '{}'),
         receipt_by = p_actor, receipt_at = now(), receipt_note = left(p_note, 500) where batch_id = p_batch;
  if p_confirmed then
    update pipeline.alert_delivery_attempts set state = 'receipt_confirmed' where batch_id = p_batch and state in ('leased', 'output_written');
    get diagnostics n = row_count;
    -- completing an alert is the only time a legacy alert row is touched, and only after confirmed receipt
    update pipeline.platform_alerts a set status = 'sent', sent_at = now(), sent_via = 'scheduled task (receipt confirmed)', lease_until = null
      where a.status in ('pending', 'sending') and a.id in (select alert_id from pipeline.alert_delivery_attempts where batch_id = p_batch and alert_source = 'platform' and state = 'receipt_confirmed');
    update pipeline.queue_watch_alerts q set sent_at = now(), sent_via = 'scheduled task (receipt confirmed)'
      where q.sent_at is null and q.id in (select alert_id from pipeline.alert_delivery_attempts where batch_id = p_batch and alert_source = 'queue_watch' and state = 'receipt_confirmed');
  else
    update pipeline.alert_delivery_attempts set state = 'released', released_at = now(), release_reason = 'Platform Admin: not received (' || p_actor || ')' where batch_id = p_batch and state in ('leased', 'output_written');
    get diagnostics n = row_count;
  end if;
  return jsonb_build_object('batch_id', p_batch, 'receipt_state', case when p_confirmed then 'confirmed' else 'not_received' end, 'alerts', n);
end $f$;

create or replace function security.alert_delivery_status_v1()
returns jsonb language sql security definer set search_path = '' as $f$
  select jsonb_build_object(
    'awaiting_receipt', (select count(*) from pipeline.alert_delivery_batches where purpose = 'alerts' and receipt_state = 'awaiting' and transport_state = 'output_written'),
    'overdue', (select count(*) from pipeline.alert_delivery_batches where purpose = 'alerts' and (receipt_state = 'overdue' or (receipt_state = 'awaiting' and transport_state = 'output_written' and output_written_at < now() - make_interval(hours => security.pipeline_num_v1('alerts.receipt_wait_hours', 4)::int)))),
    'confirmed', (select count(*) from pipeline.alert_delivery_batches where purpose = 'alerts' and receipt_state = 'confirmed'),
    'not_received', (select count(*) from pipeline.alert_delivery_batches where purpose = 'alerts' and receipt_state = 'not_received'),
    'last_receipt_confirmed_at', (select max(receipt_at) from pipeline.alert_delivery_batches where receipt_state = 'confirmed'));
$f$;

revoke all on function security.alert_delivery_take_v1(text, text), security.alert_delivery_output_v1(uuid, text, int), security.alert_delivery_receipt_v1(uuid, boolean, text[], text, text), security.alert_delivery_status_v1() from public, anon, authenticated;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in, note) values
 ('function', 'security.alert_delivery_take_v1', 'security', 'alerts', 'Leases alerts for one delivery batch without stamping them sent', 'active', array['security.platform_alerts_take_v1', 'security.queue_watch_alerts_take_v1'], '20261107030000', 'P1 7 Nov 2026'),
 ('function', 'security.alert_delivery_output_v1', 'security', 'alerts', 'Records that the run wrote its message', 'active', '{}', '20261107030000', 'P1 7 Nov 2026'),
 ('function', 'security.alert_delivery_receipt_v1', 'security', 'alerts', 'Platform Admin receipt confirmation; the only completion of an alert', 'active', array['security.platform_alerts_confirm_v1'], '20261107030000', 'P1 7 Nov 2026'),
 ('function', 'security.alert_delivery_status_v1', 'security', 'alerts', 'Delivery lifecycle counts for the watchdog', 'active', '{}', '20261107030000', 'P1 7 Nov 2026')
on conflict (kind, name) do nothing;
update pipeline.component_register set status = 'retiring', replaced_by = case name when 'security.platform_alerts_confirm_v1' then 'security.alert_delivery_receipt_v1' else 'security.alert_delivery_take_v1' end,
       retire_after = date '2026-11-21', updated_at = now()
 where kind = 'function' and name in ('security.platform_alerts_take_v1', 'security.platform_alerts_confirm_v1', 'security.queue_watch_alerts_take_v1') and status = 'active';
