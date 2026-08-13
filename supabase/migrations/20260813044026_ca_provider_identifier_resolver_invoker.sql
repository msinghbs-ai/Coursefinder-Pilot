create or replace function public.svc_layer1_resolve_provider_by_identifier(p_country_code text,p_scheme text,p_identifier text)
returns jsonb
language sql stable
set search_path=public,catalogue,ref
as $$
  select to_jsonb(x) from (
    select p.id as provider_id,p.canonical_name,p.display_name,pi.identifier,c.iso_alpha2::text as country_code
    from catalogue.provider_identifiers pi
    join catalogue.providers p on p.id=pi.provider_id
    join ref.countries c on c.id=pi.country_id
    where upper(c.iso_alpha2::text)=upper(p_country_code)
      and lower(pi.scheme)=lower(p_scheme)
      and upper(pi.identifier)=upper(p_identifier)
    order by pi.is_primary desc,pi.verified_at desc nulls last
    limit 1
  ) x;
$$;
revoke all on function public.svc_layer1_resolve_provider_by_identifier(text,text,text) from public,anon,authenticated;
grant execute on function public.svc_layer1_resolve_provider_by_identifier(text,text,text) to service_role;