-- CF-089: persist provider connection probe telemetry through a service-role-only boundary.
create or replace function public.layer2_provider_probe_record_service(
  p_provider_id uuid,
  p_status text,
  p_http_status integer default null,
  p_error text default null
) returns void
language plpgsql
security definer
set search_path='pg_catalog','public','pipeline'
as $$
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  update pipeline.layer2_acquisition_providers
  set last_tested_at=now(),
      last_test_status=left(coalesce(nullif(p_status,''),'failed'),30),
      last_test_http_status=p_http_status,
      last_test_error=nullif(left(coalesce(p_error,''),1000),''),
      updated_at=now()
  where id=p_provider_id;
  if not found then raise exception 'provider not found' using errcode='22023'; end if;
end
$$;
revoke all on function public.layer2_provider_probe_record_service(uuid,text,integer,text) from public, anon, authenticated;
grant execute on function public.layer2_provider_probe_record_service(uuid,text,integer,text) to service_role;
