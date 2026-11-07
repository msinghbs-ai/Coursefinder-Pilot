-- CF-247 P1 (Platform Admin 7 Nov 2026 13:17, 14:27 and 15:19): alert delivery lifecycle. Taking an alert is no longer "sent", and no batch waits for a person.
-- Why: security.queue_watch_alerts_take_v1 stamps sent_at when it hands the alert over, and platform_alerts_confirm_v1 is run by the same task straight after it writes its
--   message. "Sent" therefore meant only "the run reached its last step". The supervised run of 7 Nov 01:58Z marked 84 platform and 42 work-queue alerts sent and the
--   Platform Admin received neither push nor email.
-- Channel limitation (recorded once, accurately): the scheduled-task notification channel exposes NO transport acknowledgement and NO receipt signal to the task or the
--   database. So this lifecycle never marks a message delivered or received because a task completed.
-- What: an append-only outbox beside the existing alert tables.
--   Per alert, durable event identity (alert_source, alert_id) and one attempt row per try (attempt_id, attempt_no). States, kept apart:
--     leased        the alert was taken by a collector; nothing generated yet
--     generated     the run wrote its notification message (md5 and count recorded). NOT delivery. Receipt stays unverified
--     acknowledged  receipt confirmed by a person (exceptional), or a critical alert's issue was acknowledged or resolved in Platform health
--     released      the attempt ended without a notification (lease expired before output) or a person reported not received; eligible for a bounded retry
--   Subsequent batches are NEVER blocked by unverified earlier ones. An unverified alert is not re-sent (idempotent: one live attempt per alert, partial unique index),
--   is counted as unverified and then overdue on alert_delivery_status_v1, and stays auditable. Critical incidents stay escalated by the existing reminder events of
--   security.platform_alerts_evaluate_v1 until the issue is acknowledged; a critical alert with no acknowledgement shows as critical_unacknowledged.
--   Retries only follow a failure to generate (expired lease) or a reported non-receipt, with backoff alerts.retry_minutes doubling and a cap of alerts.max_attempts.
--   Collectors cannot take the same alert twice: concurrent takes insert under the live-attempt unique index and the loser gets different alerts.
--   Alerts the old path already marked sent (including the 84 platform and 42 work-queue alerts of 7 Nov 01:58Z) are legacy-unknown: never taken, never replayed.
--   A test batch takes and changes no alert.
-- Replaces: security.platform_alerts_take_v1, security.platform_alerts_confirm_v1 and security.queue_watch_alerts_take_v1 as the delivery path (functions stay, marked retiring; the disabled task is repointed after validation)
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
  transport_state text not null default 'leased' check (transport_state in ('leased', 'generated', 'transport_acknowledged', 'transport_failed', 'expired')),
  generated_at timestamptz,
  output_md5 text,
  output_items int,
  transport_evidence jsonb not null default '{"channel": "scheduled task", "transport_ack": "not exposed by the channel", "receipt_signal": "not exposed by the channel"}'::jsonb,
  receipt_state text not null default 'unverified' check (receipt_state in ('unverified', 'confirmed', 'not_received')),
  receipt_channels text[] not null default '{}',
  receipt_by text,
  receipt_at timestamptz,
  receipt_note text
);
comment on table pipeline.alert_delivery_batches is 'CF-247 P1 (7 Nov 2026): append-only alert delivery outbox, one row per delivery try or notification-only test. transport_state (what the run did) and receipt_state (what a person confirmed) are separate; the scheduled-task channel exposes no transport acknowledgement or receipt, so a generated batch stays unverified until a person confirms or the issue is acknowledged. Unverified batches do not block later batches. Never read by the consumer API.';
create table if not exists pipeline.alert_delivery_attempts (
  attempt_id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references pipeline.alert_delivery_batches(batch_id),
  alert_source text not null check (alert_source in ('platform', 'queue_watch')),
  alert_id bigint not null,
  attempt_no int not null default 1,
  state text not null default 'leased' check (state in ('leased', 'generated', 'acknowledged', 'released')),
  taken_at timestamptz not null default now(),
  released_at timestamptz,
  release_reason text,
  unique (alert_source, alert_id, attempt_no)
);
comment on table pipeline.alert_delivery_attempts is 'CF-247 P1 (7 Nov 2026): one row per alert per attempt with a durable attempt_id. The partial unique index alert_delivery_attempts_live_uq allows one live attempt per alert (leased, generated or acknowledged), so delivery is idempotent and concurrent collectors cannot take the same alert. released = eligible for a bounded retry. Never read by the consumer API.';
create unique index if not exists alert_delivery_attempts_live_uq on pipeline.alert_delivery_attempts (alert_source, alert_id) where state in ('leased', 'generated', 'acknowledged');
alter table pipeline.alert_delivery_batches enable row level security;
alter table pipeline.alert_delivery_attempts enable row level security;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'alerts.digest_max_items', 'Alerts: most alerts in one message',
  'One delivery message carries at most this many alerts; the rest wait for the next run. Keeps the push and email readable.', 'number',
  to_jsonb(15), 1, 50, 'alerts', 974, 'Alerts', 'security.alert_delivery_take_v1', 'StudySearch P1 (7 Nov 2026): a 126-alert digest was not received'),
 ('pipeline', 'alerts.receipt_wait_hours', 'Alerts: unverified after',
  'A generated message with no confirmed receipt for this long is counted as overdue on the watchdog. It is never re-sent automatically and never blocks later alerts.', 'number',
  to_jsonb(4), 1, 72, 'hours', 975, 'Alerts', 'security.alert_delivery_status_v1', 'StudySearch P1 (7 Nov 2026)')
on conflict (toolset_key, key) do nothing;

create or replace function security.alert_delivery_take_v1(p_purpose text default 'alerts', p_test_ref text default null)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_batch uuid; v_max int := security.pipeline_num_v1('alerts.digest_max_items', 15)::int; v_att int := security.pipeline_num_v1('alerts.max_attempts', 5)::int;
        v_retry numeric := security.pipeline_num_v1('alerts.retry_minutes', 10); v_alerts jsonb := '[]'::jsonb; v_left int := 0;
begin
  if p_purpose not in ('alerts', 'test') then raise exception 'purpose must be alerts or test'; end if;
  -- a run that took alerts and never generated its message has died: release them (no notification was produced, so no duplicate risk)
  update pipeline.alert_delivery_attempts a set state = 'released', released_at = now(), release_reason = 'lease expired before the message was generated'
   where a.state = 'leased' and exists (select 1 from pipeline.alert_delivery_batches b where b.batch_id = a.batch_id and b.lease_until < now() and b.transport_state = 'leased');
  update pipeline.alert_delivery_batches set transport_state = 'expired' where transport_state = 'leased' and lease_until < now();
  -- a critical alert is acknowledged when its issue is acknowledged or resolved in Platform health
  update pipeline.alert_delivery_attempts a set state = 'acknowledged'
   where a.state = 'generated' and a.alert_source = 'platform' and exists (select 1 from pipeline.platform_alerts p join pipeline.platform_issues i on i.id = p.issue_id
          where p.id = a.alert_id and (i.acknowledged_at is not null or i.resolved_at is not null));
  if p_purpose = 'test' then
    insert into pipeline.alert_delivery_batches(purpose, test_ref, lease_until) values ('test', coalesce(p_test_ref, 'TEST-' || to_char(now(), 'YYYYMMDDHH24MISS')), now() + interval '15 minutes') returning batch_id into v_batch;  -- fixed: delivery lease
    return jsonb_build_object('batch_id', v_batch, 'purpose', 'test', 'count', 0, 'alerts', '[]'::jsonb, 'note', 'notification-only test: no alert is taken or changed');
  end if;
  insert into pipeline.alert_delivery_batches(purpose, lease_until) values ('alerts', now() + interval '15 minutes') returning batch_id into v_batch;  -- fixed: delivery lease
  with cand as (
    select 'platform'::text src, p.id, p.created_at ts, n.n + 1 attempt_no, jsonb_build_object('source', 'platform', 'id', p.id, 'kind', p.kind, 'severity', p.severity, 'title', p.title, 'body', p.body, 'raised_at', p.created_at) j
      from pipeline.platform_alerts p
      cross join lateral (select count(*)::int n, max(x.released_at) last_rel from pipeline.alert_delivery_attempts x where x.alert_source = 'platform' and x.alert_id = p.id) n
     where p.status = 'pending' and p.next_attempt_at <= now()
       and not exists (select 1 from pipeline.alert_delivery_attempts x where x.alert_source = 'platform' and x.alert_id = p.id and x.state in ('leased', 'generated', 'acknowledged'))
       and n.n < v_att and (n.last_rel is null or n.last_rel + make_interval(mins => (v_retry * power(2, greatest(n.n - 1, 0)))::int) <= now())
    union all
    select 'queue_watch', q.id, q.raised_at, n.n + 1, jsonb_build_object('source', 'queue_watch', 'id', q.id, 'queue', q.key, 'state', q.state, 'title', q.title, 'body', q.body, 'raised_at', q.raised_at)
      from pipeline.queue_watch_alerts q
      cross join lateral (select count(*)::int n, max(x.released_at) last_rel from pipeline.alert_delivery_attempts x where x.alert_source = 'queue_watch' and x.alert_id = q.id) n
     where q.channel = 'notify' and q.sent_at is null
       and not exists (select 1 from pipeline.alert_delivery_attempts x where x.alert_source = 'queue_watch' and x.alert_id = q.id and x.state in ('leased', 'generated', 'acknowledged'))
       and n.n < v_att and (n.last_rel is null or n.last_rel + make_interval(mins => (v_retry * power(2, greatest(n.n - 1, 0)))::int) <= now())
  ), pick as (select * from cand order by ts, src, id limit v_max),
  ins as (insert into pipeline.alert_delivery_attempts(batch_id, alert_source, alert_id, attempt_no) select v_batch, src, id, attempt_no from pick on conflict do nothing returning alert_source, alert_id, attempt_id, attempt_no)
  select coalesce(jsonb_agg(pick.j || jsonb_build_object('attempt_id', ins.attempt_id, 'attempt_no', ins.attempt_no) order by pick.ts, pick.src, pick.id), '[]'::jsonb) into v_alerts
    from pick join ins on ins.alert_source = pick.src and ins.alert_id = pick.id;
  select count(*) into v_left from (select 1 from pipeline.platform_alerts p where p.status = 'pending'
       and not exists (select 1 from pipeline.alert_delivery_attempts x where x.alert_source = 'platform' and x.alert_id = p.id and x.state in ('leased', 'generated', 'acknowledged'))
       and (select count(*) from pipeline.alert_delivery_attempts x where x.alert_source = 'platform' and x.alert_id = p.id) < v_att
     union all select 1 from pipeline.queue_watch_alerts q where q.channel = 'notify' and q.sent_at is null
       and not exists (select 1 from pipeline.alert_delivery_attempts x where x.alert_source = 'queue_watch' and x.alert_id = q.id and x.state in ('leased', 'generated', 'acknowledged'))
       and (select count(*) from pipeline.alert_delivery_attempts x where x.alert_source = 'queue_watch' and x.alert_id = q.id) < v_att) z;
  update pipeline.alert_delivery_batches set items = jsonb_array_length(v_alerts) where batch_id = v_batch;
  return jsonb_build_object('batch_id', v_batch, 'purpose', 'alerts', 'count', jsonb_array_length(v_alerts), 'alerts', v_alerts, 'still_waiting', greatest(v_left - jsonb_array_length(v_alerts), 0),
           'next', 'write the message, then select security.alert_delivery_output_v1(batch_id, md5 of the message, item count). The message is generated, not delivered: receipt stays unverified.');
end $f$;

create or replace function security.alert_delivery_output_v1(p_batch uuid, p_md5 text, p_items int)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare n int; v_via text := 'scheduled task (generated, receipt unverified)';
begin
  update pipeline.alert_delivery_batches set transport_state = 'generated', generated_at = now(), output_md5 = p_md5, output_items = p_items
   where batch_id = p_batch and transport_state = 'leased';
  get diagnostics n = row_count;
  if n = 1 then
    with g as (update pipeline.alert_delivery_attempts set state = 'generated' where batch_id = p_batch and state = 'leased' returning alert_source, alert_id)
    , pf as (update pipeline.platform_alerts a set status = 'sent', sent_at = now(), sent_via = v_via, lease_until = null
              where a.status in ('pending', 'sending') and a.id in (select alert_id from g where alert_source = 'platform') returning 1)
    update pipeline.queue_watch_alerts q set sent_at = now(), sent_via = v_via where q.sent_at is null and q.id in (select alert_id from g where alert_source = 'queue_watch');
  end if;
  return jsonb_build_object('batch_id', p_batch, 'recorded', n = 1, 'receipt', 'unverified (the channel exposes no acknowledgement)');
end $f$;

-- Exceptional path only: a person confirms (or denies) receipt of a generated batch. Routine batches never need it.
create or replace function security.alert_delivery_receipt_v1(p_batch uuid, p_confirmed boolean, p_channels text[] default '{}', p_actor text default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare b pipeline.alert_delivery_batches%rowtype; n int := 0; v_unv text := 'scheduled task (generated, receipt unverified)';
begin
  if p_actor is null or length(p_actor) = 0 then raise exception 'actor required'; end if;
  select * into b from pipeline.alert_delivery_batches where batch_id = p_batch for update;
  if not found then raise exception 'unknown batch'; end if;
  if b.receipt_state in ('confirmed', 'not_received') then return jsonb_build_object('batch_id', p_batch, 'unchanged', true, 'receipt_state', b.receipt_state); end if;
  update pipeline.alert_delivery_batches set receipt_state = case when p_confirmed then 'confirmed' else 'not_received' end, receipt_channels = coalesce(p_channels, '{}'),
         receipt_by = p_actor, receipt_at = now(), receipt_note = left(p_note, 500) where batch_id = p_batch;
  if p_confirmed then
    with g as (update pipeline.alert_delivery_attempts set state = 'acknowledged' where batch_id = p_batch and state in ('leased', 'generated') returning alert_source, alert_id)
    , pf as (update pipeline.platform_alerts a set sent_via = 'scheduled task (receipt confirmed)' where a.sent_via = v_unv and a.id in (select alert_id from g where alert_source = 'platform') returning 1)
    update pipeline.queue_watch_alerts q set sent_via = 'scheduled task (receipt confirmed)' where q.sent_via = v_unv and q.id in (select alert_id from g where alert_source = 'queue_watch');
  else
    -- reported not received: release for a bounded retry and put back only the rows this lifecycle marked generated-unverified
    with g as (update pipeline.alert_delivery_attempts set state = 'released', released_at = now(), release_reason = 'not received (' || p_actor || ')' where batch_id = p_batch and state in ('leased', 'generated') returning alert_source, alert_id)
    , pf as (update pipeline.platform_alerts a set status = 'pending', sent_at = null, sent_via = null, next_attempt_at = now() where a.sent_via = v_unv and a.id in (select alert_id from g where alert_source = 'platform') returning 1)
    update pipeline.queue_watch_alerts q set sent_at = null, sent_via = null where q.sent_via = v_unv and q.id in (select alert_id from g where alert_source = 'queue_watch');
  end if;
  select count(*) into n from pipeline.alert_delivery_attempts where batch_id = p_batch;
  return jsonb_build_object('batch_id', p_batch, 'receipt_state', case when p_confirmed then 'confirmed' else 'not_received' end, 'alerts', n);
end $f$;

create or replace function security.alert_delivery_status_v1()
returns jsonb language sql security definer set search_path = '' as $f$
  select jsonb_build_object(
    'channel_limitation', 'scheduled-task push and email expose no transport acknowledgement or receipt signal; generated means a message was written, not delivered',
    'unverified', (select count(*) from pipeline.alert_delivery_attempts where state = 'generated'),
    'unverified_overdue', (select count(*) from pipeline.alert_delivery_attempts a join pipeline.alert_delivery_batches b using (batch_id)
        where a.state = 'generated' and b.generated_at < now() - make_interval(hours => security.pipeline_num_v1('alerts.receipt_wait_hours', 4)::int)),
    'critical_unacknowledged', (select count(*) from pipeline.alert_delivery_attempts a join pipeline.platform_alerts p on a.alert_source = 'platform' and p.id = a.alert_id
        where a.state = 'generated' and p.severity = 'critical' and p.kind <> 'recovered'),
    'acknowledged', (select count(*) from pipeline.alert_delivery_attempts where state = 'acknowledged'),
    'released', (select count(*) from pipeline.alert_delivery_attempts where state = 'released'),
    'retries_exhausted', (select count(*) from (select alert_source, alert_id from pipeline.alert_delivery_attempts group by 1, 2
        having count(*) >= security.pipeline_num_v1('alerts.max_attempts', 5)::int and bool_and(state = 'released')) z),
    'last_receipt_confirmed_at', (select max(receipt_at) from pipeline.alert_delivery_batches where receipt_state = 'confirmed'));
$f$;

revoke all on function security.alert_delivery_take_v1(text, text), security.alert_delivery_output_v1(uuid, text, int), security.alert_delivery_receipt_v1(uuid, boolean, text[], text, text), security.alert_delivery_status_v1() from public, anon, authenticated;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in, note) values
 ('function', 'security.alert_delivery_take_v1', 'security', 'alerts', 'Leases alerts for one delivery batch without stamping them sent', 'active', array['security.platform_alerts_take_v1', 'security.queue_watch_alerts_take_v1'], '20261107030000', 'P1 7 Nov 2026'),
 ('function', 'security.alert_delivery_output_v1', 'security', 'alerts', 'Records that the run generated its message (not delivery)', 'active', '{}', '20261107030000', 'P1 7 Nov 2026'),
 ('function', 'security.alert_delivery_receipt_v1', 'security', 'alerts', 'Exceptional person confirmation of receipt', 'active', array['security.platform_alerts_confirm_v1'], '20261107030000', 'P1 7 Nov 2026'),
 ('function', 'security.alert_delivery_status_v1', 'security', 'alerts', 'Delivery lifecycle counts for the watchdog', 'active', '{}', '20261107030000', 'P1 7 Nov 2026')
on conflict (kind, name) do nothing;
update pipeline.component_register set status = 'retiring', replaced_by = case name when 'security.platform_alerts_confirm_v1' then 'security.alert_delivery_receipt_v1' else 'security.alert_delivery_take_v1' end,
       retire_after = date '2026-11-21', updated_at = now()
 where kind = 'function' and name in ('security.platform_alerts_take_v1', 'security.platform_alerts_confirm_v1', 'security.queue_watch_alerts_take_v1') and status = 'active';
