-- CF-247 complete coverage: allow the coverage-sweep worker to be invoked with a one-time Pilot nonce (checksum-guarded).
do $patch$
declare v_def text;
begin
  v_def:=pg_get_functiondef('pipeline.svc_pilot_submit_nonce(text,jsonb)'::regprocedure);
  if v_def like '%''coverage-sweep''%' then return; end if;
  if md5(v_def)<>'d7a9353c89bfd4a1eeb4c1138d4490dd' then raise exception 'svc_pilot_submit_nonce changed since review; not replaced'; end if;
  if (select count(*) from regexp_matches(v_def,'''fee-schedule-etl'',','g'))<>1 then raise exception 'allow-list anchor not found exactly once'; end if;
  execute replace(v_def,'''fee-schedule-etl'',','''fee-schedule-etl'',''coverage-sweep'',');
end $patch$;
