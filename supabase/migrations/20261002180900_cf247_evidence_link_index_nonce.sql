-- CF-247 (Decision 215, 2 Oct 2026). Platform Admin, 07:57: "fix evidence link indexing job error, failing".
-- Cause: job evidence-link-index called the edge function with the long-lived Pilot automation key, which expired at
-- 2026-09-30 13:59 UTC (23:59 Melbourne); every run since was refused (401 invalid_pilot_automation_key), so no stored
-- page has had its links indexed since then. The key is not extended: the job now uses a one-time nonce, like the other
-- current workers (coverage-sweep, layer3-model-routing). The edge function accepts the nonce (deployed with this change).
-- md5 guard on pipeline.svc_pilot_submit_nonce.

do $n$
declare s text; d text; v text;
  o text := $o$'layer3-work-dispatch','layer3-intake-benchmark','layer3-model-routing')$o$;
  n text := $n$'layer3-work-dispatch','layer3-intake-benchmark','layer3-model-routing','evidence-link-index')$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'pipeline' and p.proname = 'svc_pilot_submit_nonce';
  v := md5(s);
  if v is distinct from '007a1af8f142511a3e1e19100a29ce53' then raise exception 'svc_pilot_submit_nonce changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'allow-list end not found once'; end if;
  execute replace(d, o, n);
end $n$;

select cron.schedule('evidence-link-index', '9-59/10 * * * *', $$select pipeline.svc_pilot_submit_nonce('evidence-link-index','{"limit":60}'::jsonb)$$);
