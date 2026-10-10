-- CF-247 platform health: keep every run under ~2 seconds.
-- Measured on 29 Sep 2026 (forced run, all checks): 2,231 ms, of which consumer_snapshot 1,331 ms and search_probe 648 ms.
-- On the (hourly) run that takes the consumer API snapshot - which already exercises search - the separate search probe
-- waits until the next run (10 minutes later). Forced runs still do both. md5-guarded single-line patch.
do $patch$
declare v text;
  v_old text:=$o$  if security.platform_health_due_v1('search_probe',p_force) then$o$;
  v_new text:=$n$  if security.platform_health_due_v1('search_probe',p_force) and (p_force or not ('consumer_snapshot'=any(v_ok))) then$n$;
begin
  if (select md5(prosrc) from pg_proc where oid='security.platform_health_check_v1(boolean)'::regprocedure)<>'6f2ddb7ca454745251c8c4d94375d290' then
    raise exception 'platform_health_check_v1 changed since review; not patched'; end if;
  v:=pg_get_functiondef('security.platform_health_check_v1(boolean)'::regprocedure);
  if (length(v)-length(replace(v,v_old,'')))/length(v_old)<>1 then raise exception 'search_probe anchor not found exactly once'; end if;
  execute replace(v,v_old,v_new);
end $patch$;
