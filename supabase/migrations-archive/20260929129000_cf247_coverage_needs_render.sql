-- CF-247 coverage sweep v0.3.2: pages that need a rendering browser (script-only) while the Firecrawl reserve is
-- reached are retried after the monthly budget resets, and the attempt is not counted. Checksum-guarded.
do $patch$
declare v_def text; v_old text; v_new text;
begin
  if (select md5(prosrc) from pg_proc where oid='public.svc_coverage_read_record(uuid,text,int,text,text,text,text,jsonb)'::regprocedure)<>'b4f7655b59b068f211869800dfb17efa' then
    raise exception 'svc_coverage_read_record changed since review; not replaced'; end if;
  v_def:=pg_get_functiondef('public.svc_coverage_read_record(uuid,text,int,text,text,text,text,jsonb)'::regprocedure);
  v_old:=$o$next_read_at=case when p_read_status in ('read','identity_mismatch') then now()+interval '90 days' else now()+interval '6 hours' end$o$;
  v_new:=$n$next_read_at=case when p_read_status in ('read','identity_mismatch') then now()+interval '90 days' when p_read_status='needs_render' then date_trunc('month',now())+interval '1 month 1 hour' else now()+interval '6 hours' end,
         read_attempts=case when p_read_status='needs_render' then greatest(read_attempts-1,0) else read_attempts end$n$;
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old)<>1 then raise exception 'anchor not found exactly once'; end if;
  execute replace(v_def,v_old,v_new);
end $patch$;
