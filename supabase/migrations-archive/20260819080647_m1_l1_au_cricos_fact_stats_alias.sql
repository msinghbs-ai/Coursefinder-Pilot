create or replace function public.svc_layer1_au_cricos_fact_stats()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.svc_layer1_au_cricos_facts_stats();
$$;

revoke all on function public.svc_layer1_au_cricos_fact_stats() from public, anon, authenticated;
grant execute on function public.svc_layer1_au_cricos_fact_stats() to service_role;
