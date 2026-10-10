-- A15: normalize contact-discovery transport URLs without mutating canonical Provider website,
-- and expose service-role-only acquisition provider lookup by key.

update pipeline.provider_contact_profiles pcp
set base_url = regexp_replace(pcp.base_url,'^https://https://','https://','i'),
    domain = lower(regexp_replace(regexp_replace(regexp_replace(pcp.base_url,'^https://https://','https://','i'),'^https?://','','i'),'/.*$','','g')),
    last_error = case when pcp.last_error like '%https://https/%' then null else pcp.last_error end,
    updated_at = now()
where pcp.base_url ~* '^https://https://';

update pipeline.provider_contact_profiles
set domain=regexp_replace(domain,'^www\.','','i'), updated_at=now()
where domain like 'www.%';

create or replace function public.provider_contact_acquisition_provider_service(p_provider_key text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline'
as $$
declare v_id uuid;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  select id into v_id
  from pipeline.layer2_acquisition_providers
  where provider_key=p_provider_key
  limit 1;
  if v_id is null then return null; end if;
  return public.layer2_provider_runtime_config(v_id);
end $$;

revoke all on function public.provider_contact_acquisition_provider_service(text) from public,anon,authenticated;
grant execute on function public.provider_contact_acquisition_provider_service(text) to service_role,postgres;
