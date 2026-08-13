create or replace function public.svc_layer1_resolve_provider_sources(p_provider_id uuid)
returns jsonb
language sql
stable
set search_path=public,pipeline,integration
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'source_id',s.id,'source_type',s.source_type,'source_label',s.label,'source_url',s.url,'trust_rank',s.trust_rank,
    'source_metadata',s.metadata,'system_code',i.code,'system_name',i.name,'system_type',i.system_type,
    'system_base_url',i.base_url,'system_config',i.config
  ) order by s.trust_rank,s.label),'[]'::jsonb)
  from pipeline.sources s
  left join integration.systems i on i.id=s.system_id
  where s.provider_id=p_provider_id and s.status='active' and coalesce(i.status,'active')='active';
$$;
revoke all on function public.svc_layer1_resolve_provider_sources(uuid) from public,anon,authenticated;
grant execute on function public.svc_layer1_resolve_provider_sources(uuid) to service_role;