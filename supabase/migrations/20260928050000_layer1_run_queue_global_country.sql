-- CF-247: global sources (QS and THE rankings, which have no country) could not be queued.
-- Both queue paths looked up the source country and wrote NULL into layer1_run_queue.country_code
-- (NOT NULL), so "Run now" and background runs for a ranking source failed. They now record 'GLOBAL',
-- the same code the Layer 1 card and validation already use for these sources.
-- The column was char(2), so it is widened to text (AU/NZ values unchanged; no views depend on it).
-- Checksum-guarded: each function is only changed if the live definition matches what was reviewed.
alter table pipeline.layer1_run_queue alter column country_code type text;

do $m$
declare d text; n text;
begin
  d:=pg_get_functiondef('security.layer1_queue_system_run_v1(uuid,text,bigint,uuid,text)'::regprocedure);
  if md5(d)<>'52e3b73a51acf4d1937ec0aaabb21eae' then raise exception 'layer1_queue_system_run_v1 changed since review (%); not patched', md5(d); end if;
  n:=replace(d,'where s.id=p_source_id;
  insert into pipeline.layer1_run_queue','where s.id=p_source_id;
  v_country:=coalesce(v_country,''GLOBAL'');
  insert into pipeline.layer1_run_queue');
  if n=d then raise exception 'layer1_queue_system_run_v1 patch point not found'; end if;
  execute n;

  d:=pg_get_functiondef('security.admin_layer1_command(text,jsonb)'::regprocedure);
  if md5(d)<>'9f9d1371527e2890fa4ea2df59264277' then raise exception 'admin_layer1_command changed since review (%); not patched', md5(d); end if;
  n:=replace(d,'where s.id=v_source; v_mode:=','where s.id=v_source; v_country:=coalesce(v_country,''GLOBAL''); v_mode:=');
  if n=d then raise exception 'admin_layer1_command patch point not found'; end if;
  execute n;
end $m$;
