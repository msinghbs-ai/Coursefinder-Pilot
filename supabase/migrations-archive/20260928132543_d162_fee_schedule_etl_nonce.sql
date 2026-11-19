-- CF-247 Decision 162 step 2: allow the fee-schedule worker to be invoked with a one-time Pilot nonce (checksum-guarded).
do $patch$
declare v_def text;
begin
  v_def:=pg_get_functiondef('pipeline.svc_pilot_submit_nonce(text,jsonb)'::regprocedure);
  if v_def like '%''fee-schedule-etl''%' then return; end if;
  if md5(v_def)<>'48714a9e5498bc62c0f57b00b480347c' then raise exception 'svc_pilot_submit_nonce changed since review; not replaced'; end if;
  if (select count(*) from regexp_matches(v_def,'''statistics-edition-discovery'',','g'))<>1 then raise exception 'allow-list anchor not found exactly once'; end if;
  execute replace(v_def,'''statistics-edition-discovery'',','''statistics-edition-discovery'',''fee-schedule-etl'',');
end $patch$;
