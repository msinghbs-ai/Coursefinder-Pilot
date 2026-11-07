#!/usr/bin/env bash
# Two collectors take at the same moment; neither may take an alert the other holds.
set -euo pipefail
psql -v ON_ERROR_STOP=1 -q <<'SQL'
truncate pipeline.alert_delivery_attempts, pipeline.alert_delivery_batches cascade;
truncate pipeline.platform_alerts, pipeline.queue_watch_alerts restart identity cascade;
insert into pipeline.queue_watch(key) values ('q1') on conflict do nothing;
insert into pipeline.platform_alerts(kind, severity, title, body, status) select 'raised','warning','c '||g,'b','pending' from generate_series(1,40) g;
update pipeline.platform_toolset_settings set value = to_jsonb(15) where key = 'alerts.digest_max_items';
SQL
for n in 1 2 3; do
  ( psql -v ON_ERROR_STOP=1 -q -At -c "begin; select (security.alert_delivery_take_v1('alerts')->>'count'); select pg_sleep(2); commit;" > /tmp/ad_c$n.out ) &
done
wait
psql -v ON_ERROR_STOP=1 -q <<'SQL'
do $$ declare n int; m int; begin
  select count(*) into n from pipeline.alert_delivery_attempts;
  select max(c) into m from (select count(*) c from pipeline.alert_delivery_attempts where state in ('leased','generated','acknowledged') group by alert_source, alert_id) z;
  if m is distinct from 1 or n < 15 or n > 45 then raise exception 'FAIL concurrent collectors: % attempts, max live per alert %', n, m; end if;
  raise notice 'PASS: concurrent collectors never hold the same alert (% attempts, one live each)', n;
end $$;
SQL
cat /tmp/ad_c*.out | tr '\n' ' '; echo
