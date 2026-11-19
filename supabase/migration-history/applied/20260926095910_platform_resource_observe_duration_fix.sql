do $patch$
declare d text; n int;
  a1 constant text := 'round(max(extract(epoch from coalesce(end_time,now())-start_time))::numeric,1)';
  b1 constant text := 'round(max(extract(epoch from coalesce(end_time, case when status in (''running'',''starting'',''sending'',''connecting'') then now() end)-start_time))::numeric,1)';
  a2 constant text := 'and coalesce(b.end_time,now()) > a.start_time';
  b2 constant text := 'and coalesce(b.end_time, case when b.status in (''running'',''starting'',''sending'',''connecting'') then now() else b.start_time end) > a.start_time';
begin
  select pg_get_functiondef('security.platform_resource_observe_v1()'::regprocedure) into d;
  n := (length(d)-length(replace(d,a1,'')))/length(a1); if n<>1 then raise exception 'a1 found % times', n; end if;
  n := (length(d)-length(replace(d,a2,'')))/length(a2); if n<>1 then raise exception 'a2 found % times', n; end if;
  execute replace(replace(d,a1,b1),a2,b2);
end $patch$;
select security.platform_resource_observe_v1()->>'cron_max_seconds' corrected_max_s;
