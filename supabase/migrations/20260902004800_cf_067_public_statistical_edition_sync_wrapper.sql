begin;
create or replace function public.sync_layer1_statistical_edition(p_source_id uuid)
returns void
language sql
security definer
set search_path to 'pg_catalog','pipeline','public'
as $$
  select pipeline.sync_layer1_statistical_edition(p_source_id);
$$;
revoke all on function public.sync_layer1_statistical_edition(uuid) from public,anon,authenticated;
grant execute on function public.sync_layer1_statistical_edition(uuid) to service_role;
commit;