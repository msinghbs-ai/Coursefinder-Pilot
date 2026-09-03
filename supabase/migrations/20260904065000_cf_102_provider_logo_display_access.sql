begin;

-- CF-CHG-20260904-102 — project approved Provider logos into governed UI surfaces.

create or replace function public.svc_provider_asset_access_descriptor(p_provider_id uuid)
returns jsonb
language sql
security definer
set search_path='pg_catalog','catalogue','public'
as $$
  select coalesce((
    select jsonb_build_object(
      'provider_id',a.provider_id,
      'provider_asset_id',a.id,
      'asset_type',a.asset_type,
      'storage_path',a.storage_path,
      'mime_type',a.mime_type,
      'content_hash',a.content_hash,
      'verified_at',a.verified_at,
      'source_url',a.source_url
    )
    from catalogue.provider_assets a
    where a.provider_id=p_provider_id
      and a.is_primary
      and a.status='approved'
      and a.asset_type in('logo','logo_dark','logo_light')
      and a.storage_path is not null
    order by
      case a.asset_type when 'logo' then 0 when 'logo_light' then 1 else 2 end,
      a.verified_at desc nulls last,
      a.id
    limit 1
  ),'{}'::jsonb)
$$;

revoke all on function public.svc_provider_asset_access_descriptor(uuid) from public,anon,authenticated;
grant execute on function public.svc_provider_asset_access_descriptor(uuid) to service_role;

commit;
