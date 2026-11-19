begin;

create or replace function public.layer2_provider_asset_fetch_routes()
returns jsonb
language sql
security definer
set search_path='pg_catalog','pipeline','public'
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,
    'provider_key',p.provider_key,
    'priority',p.priority
  ) order by p.priority,p.provider_key),'[]'::jsonb)
  from pipeline.layer2_acquisition_providers p
  where p.enabled
    and p.provider_key in ('scrape-do','scraperapi','zenrows')
$$;

revoke all on function public.layer2_provider_asset_fetch_routes() from public,anon,authenticated;
grant execute on function public.layer2_provider_asset_fetch_routes() to service_role;

commit;
