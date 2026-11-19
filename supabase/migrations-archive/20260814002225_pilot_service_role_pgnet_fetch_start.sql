create or replace function public.svc_pilot_source_fetch_start(p_source_code text)
returns bigint
language plpgsql
security invoker
set search_path = public, pipeline, integration, net
as $$
declare v_url text; v_id bigint;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  select s.url into v_url from pipeline.sources s join integration.systems i on i.id=s.system_id
  where i.code=p_source_code and p_source_code='ca_on_fleming_programs' and s.status='active' limit 1;
  if v_url is null then raise exception 'Pilot source not allowlisted or active'; end if;
  select net.http_get(url:=v_url, timeout_milliseconds:=20000) into v_id;
  return v_id;
end;
$$;
