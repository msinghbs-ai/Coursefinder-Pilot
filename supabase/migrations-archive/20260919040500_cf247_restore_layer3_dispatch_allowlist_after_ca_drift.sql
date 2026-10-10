-- CF-CHG-20260915-247
-- Restore the governed Layer 3 dispatcher entry after a later CA runner allowlist
-- replacement dropped it. Preserve all current CA entries; do not broaden beyond
-- explicitly governed functions.
create or replace function pipeline.svc_pilot_invoke_edge(p_function text,p_body jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer
set search_path to 'pipeline','vault','net','public'
as $$
declare v_key text;v_id bigint;v_base text;
begin
 if p_function not in(
  'layer3-work-dispatch',
  'layer1-ca-ab-alis-degrees','layer1-ca-bc-epbc-programs','layer1-ca-qc-university-programs','layer1-ca-sk-programs',
  'layer1-ca-mb-programs','layer1-ca-ns-sk-programs','layer1-ca-cna-programs','layer1-ca-firstparty-catalogues',
  'layer1-ca-provider-geography','layer1-ca-on-college-programs','layer1-ca-algonquin-catalogue',
  'layer1-ca-conestoga-catalogue','layer1-ca-fanshawe-pgwp','layer1-ca-mohawk-catalogue','layer1-ca-durham-programs'
 ) then raise exception 'Edge function is not allowlisted';end if;
 v_key:=public.coursefinder_runtime_automation_key();v_base:=public.coursefinder_runtime_edge_base_url();
 if v_key is null then raise exception 'runtime automation secret missing';end if;
 if v_base is null then raise exception 'runtime Edge base URL missing';end if;
 select net.http_post(url:=rtrim(v_base,'/')||'/'||p_function,headers:=jsonb_build_object('content-type','application/json','x-cf-pilot-key',v_key),body:=coalesce(p_body,'{}'::jsonb),timeout_milliseconds:=30000) into v_id;
 return v_id;
end $$;
