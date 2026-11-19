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
