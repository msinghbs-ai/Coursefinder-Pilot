-- CF-247 (Decision 204): the one-time pass for a scheduled worker call lasts 5 minutes instead of 2. Worker calls go
-- through the database's outbound queue, which sends in rounds and waits for the slowest call (up to 2 minutes), so a
-- call can wait close to 2 minutes before it is sent; on 1 Oct 2026, 6 to 12 calls an hour arrived after their pass
-- expired and were refused. The pass is still single-use and bound to the named function.
-- Guard: replaces pipeline.svc_pilot_submit_nonce only if its live body is the one checked on 1 Oct 2026.

do $nonce$
declare s text; d text; v text;
  o text := 'now()+interval ''2 minutes''';
  n text := 'now()+interval ''5 minutes''';
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'pipeline' and p.proname = 'svc_pilot_submit_nonce';
  v := md5(s);
  if v is distinct from '0644561a85ac14533c9c0100ca727e77' then raise exception 'svc_pilot_submit_nonce changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'svc_pilot_submit_nonce: expiry not found once'; end if;
  execute replace(d, o, n);
end $nonce$;
