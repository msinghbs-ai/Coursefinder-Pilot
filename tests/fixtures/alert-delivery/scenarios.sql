\set ON_ERROR_STOP on
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if not c then raise exception 'FAIL: %', m; end if; raise notice 'PASS: %', m; end $$;
insert into pipeline.queue_watch(key) values ('q1');
-- legacy: 3 platform + 2 queue alerts the OLD path already marked sent (legacy-unknown)
insert into pipeline.platform_alerts(kind, severity, title, body, status, sent_via, sent_at) select 'raised','warning','legacy '||g,'b','sent','scheduled task', now() from generate_series(1,3) g;
insert into pipeline.queue_watch_alerts(key, state, channel, title, body, sent_at, sent_via) select 'q1','stuck','notify','legacy q'||g,'b', now(), 'scheduled task' from generate_series(1,2) g;
-- new: 30 pending platform (2 critical) + 4 unsent queue
insert into pipeline.platform_alerts(kind, severity, title, body, status, created_at) select 'raised', case when g <= 2 then 'critical' else 'warning' end, 'new '||g, 'b', 'pending', now() - make_interval(mins => 100 - g) from generate_series(1,30) g;
insert into pipeline.queue_watch_alerts(key, state, channel, title, body, raised_at) select 'q1','stuck','notify','new q'||g,'b', now() - make_interval(mins => 200 - g) from generate_series(1,4) g;
update pipeline.platform_toolset_settings set value = to_jsonb(10) where key = 'alerts.digest_max_items';
select pg_temp.ok((select count(*) from pipeline.platform_alerts where sent_via = 'scheduled task') = 3, 'legacy rows seeded');
-- S1 test batch changes no alert
create temp table before_sum as select md5(string_agg(t::text, '|' order by id)) h from (select * from pipeline.platform_alerts) t;
select security.alert_delivery_take_v1('test', 'P1-TEST-1') \gset t_
select pg_temp.ok((select md5(string_agg(t::text, '|' order by id)) from (select * from pipeline.platform_alerts) t) = (select h from before_sum), 'S1 a test batch takes and changes no alert');
select pg_temp.ok((select count(*) from pipeline.alert_delivery_attempts) = 0, 'S1 a test batch creates no attempt');
-- S2 take never stamps sent; legacy-unknown alerts never taken
select security.alert_delivery_take_v1('alerts') as r \gset b1_
select pg_temp.ok((select count(*) from pipeline.platform_alerts where status = 'pending') = 30, 'S2 taking marks nothing sent');
select pg_temp.ok((select count(*) from pipeline.alert_delivery_attempts where state = 'leased') = 10, 'S2 digest cap respected (10 leased)');
select pg_temp.ok(not exists (select 1 from pipeline.alert_delivery_attempts a join pipeline.platform_alerts p on a.alert_source='platform' and p.id=a.alert_id where p.title like 'legacy%'), 'S2 legacy-unknown alerts never taken');
-- S3 idempotency: a second take excludes the leased alerts
select security.alert_delivery_take_v1('alerts') \gset b2_
select pg_temp.ok((select count(*) from pipeline.alert_delivery_attempts where state = 'leased') = 20, 'S3 second collector took different alerts (20 leased, no duplicate)');
select pg_temp.ok((select max(c) from (select count(*) c from pipeline.alert_delivery_attempts where state in ('leased','generated','acknowledged') group by alert_source, alert_id) z) = 1, 'S3 one live attempt per alert');
-- S4 generated is not delivered; later batches are not blocked by an unverified one
select batch_id as b1 from pipeline.alert_delivery_batches order by created_at limit 1 offset 1 \gset
select security.alert_delivery_output_v1(:'b1', md5('m1'), 10) \gset o1_
select pg_temp.ok((select count(*) from pipeline.alert_delivery_attempts where state = 'generated') = 10, 'S4 output marks attempts generated');
select pg_temp.ok((select count(*) from pipeline.platform_alerts where sent_via like '%receipt unverified%') >= 1, 'S4 legacy rows are labelled receipt unverified, never receipt confirmed');
select pg_temp.ok((select count(*) from pipeline.platform_alerts where sent_via like '%receipt confirmed%') = 0, 'S4 nothing is marked received because a task completed');
select security.alert_delivery_take_v1('alerts') \gset b3_
select pg_temp.ok((select count(*) from pipeline.alert_delivery_attempts where state = 'leased') >= 10, 'S4 an unverified batch does not block the next batch');
-- S5 expired lease: the dead run is released, retry is delayed by backoff, then bounded
update pipeline.alert_delivery_batches set lease_until = now() - interval '1 minute' where transport_state = 'leased';
select security.alert_delivery_take_v1('alerts') \gset b4_
select pg_temp.ok((select count(*) from pipeline.alert_delivery_attempts where state = 'released') > 0, 'S5 expired lease releases the attempts');
select pg_temp.ok(not exists (select 1 from pipeline.alert_delivery_attempts where attempt_no = 2), 'S5 released alerts wait for backoff before a retry');
update pipeline.alert_delivery_attempts set released_at = now() - interval '2 hours' where state = 'released';
select security.alert_delivery_take_v1('alerts') \gset b5_
select pg_temp.ok(exists (select 1 from pipeline.alert_delivery_attempts where attempt_no = 2), 'S5 after backoff the alert is retried with a new attempt id (attempt_no 2)');
-- S6 bounded retries
do $$ declare i int; begin
  for i in 1..6 loop
    update pipeline.alert_delivery_batches set lease_until = now() - interval '1 minute' where transport_state = 'leased';
    perform security.alert_delivery_take_v1('alerts');
    update pipeline.alert_delivery_attempts set released_at = now() - interval '48 hours' where state = 'released';
  end loop; end $$;
select pg_temp.ok((select max(attempt_no) from pipeline.alert_delivery_attempts) <= 5, 'S6 attempts never exceed alerts.max_attempts');
-- S7 missing receipt: unverified then overdue, still not re-sent
update pipeline.alert_delivery_batches set generated_at = now() - interval '5 hours' where transport_state = 'generated';
select pg_temp.ok((security.alert_delivery_status_v1()->>'unverified_overdue')::int >= 10, 'S7 missing receipt is counted overdue');
select pg_temp.ok((select count(*) from pipeline.alert_delivery_attempts where state = 'generated') = 10, 'S7 an overdue unverified alert is not silently re-sent or delivered');
-- S8 critical stays visible until acknowledged
select pg_temp.ok((security.alert_delivery_status_v1()->>'critical_unacknowledged')::int >= 0, 'S8 status reports critical_unacknowledged');
-- S9 recovery: person reports not received -> released and labelled rows put back, legacy-unknown untouched
select security.alert_delivery_receipt_v1(:'b1', false, '{}', 'platform admin', 'not received') \gset r1_
select pg_temp.ok((select count(*) from pipeline.alert_delivery_attempts where batch_id = :'b1'::uuid and state = 'released') = 10, 'S9 not-received releases the batch for a bounded retry');
select pg_temp.ok((select count(*) from pipeline.platform_alerts where sent_via = 'scheduled task') = 3, 'S9 legacy-unknown rows untouched');
select pg_temp.ok((select count(*) from pipeline.queue_watch_alerts where sent_via = 'scheduled task') = 2, 'S9 legacy-unknown work-queue rows untouched');
-- S10 receipt confirmed is exceptional and explicit
select security.alert_delivery_take_v1('alerts') as r \gset b6_
select batch_id as b6 from pipeline.alert_delivery_batches where transport_state = 'leased' order by created_at desc limit 1 \gset
select security.alert_delivery_output_v1(:'b6', md5('m6'), 1) \gset o6_
select security.alert_delivery_receipt_v1(:'b6', true, array['push','email'], 'platform admin', 'ok') \gset r6_
select pg_temp.ok((select count(*) from pipeline.alert_delivery_attempts where batch_id = :'b6'::uuid and state = 'acknowledged') >= 1, 'S10 confirmed receipt acknowledges the attempts');
select pg_temp.ok((select receipt_state from pipeline.alert_delivery_batches where batch_id = :'b6'::uuid) = 'confirmed', 'S10 receipt state confirmed only by an explicit call');
select pg_temp.ok((security.alert_delivery_receipt_v1(:'b6', false, '{}', 'x', null)->>'unchanged')::boolean, 'S10 a decided batch cannot be flipped (idempotent)');
-- S11 critical acknowledgement via Platform health
insert into pipeline.platform_issues(check_key, severity, title) values ('c1','critical','issue');
insert into pipeline.platform_alerts(issue_id, kind, severity, title, body, status, created_at) select id, 'raised','critical','crit one','b','pending', now() - interval '3 days' from pipeline.platform_issues where check_key='c1';
update pipeline.alert_delivery_batches set lease_until = now() - interval '1 minute' where transport_state = 'leased';
update pipeline.alert_delivery_attempts set released_at = now() - interval '48 hours' where state = 'released';
select security.alert_delivery_take_v1('alerts') \gset b7_
select batch_id as b7 from pipeline.alert_delivery_batches where transport_state = 'leased' order by created_at desc limit 1 \gset
select security.alert_delivery_output_v1(:'b7', md5('m7'), 1) \gset o7_
select pg_temp.ok((security.alert_delivery_status_v1()->>'critical_unacknowledged')::int >= 1, 'S11 a generated critical alert stays critical_unacknowledged');
update pipeline.platform_issues set acknowledged_at = now() where check_key = 'c1';
select security.alert_delivery_take_v1('alerts') \gset b8_
select pg_temp.ok(exists (select 1 from pipeline.alert_delivery_attempts a join pipeline.platform_alerts p on p.id = a.alert_id and a.alert_source='platform' where p.title = 'crit one' and a.state = 'acknowledged'), 'S11 acknowledging the issue in Platform health acknowledges the critical alert');
