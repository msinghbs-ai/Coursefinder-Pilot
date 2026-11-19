-- CF-247 (Decision 227, 2 Oct 2026). The stored copies of provider documents (English policy, academic calendar) are
-- listed for the worker so it can parse them again without reading the site again (no Firecrawl credit), and so a
-- person can check what was read. Read only.

create or replace function public.svc_provider_facts_docs(p_ids uuid[], p_kind text, p_limit integer)
returns jsonb language plpgsql stable security definer set search_path to '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('id', f.id, 'provider_id', f.provider_id, 'kind', f.kind, 'url', f.url, 'rank', f.rank,
             'provider', p.canonical_name, 'country', k.iso_alpha2, 'storage_path', e.storage_path, 'sha256', f.content_hash) x
      from pipeline.provider_fact_sources f
      join pipeline.evidence_artifacts e on e.id = f.evidence_id
      join catalogue.providers p on p.id = f.provider_id
      left join ref.countries k on k.id = p.country_id
     where f.status in ('read', 'parsed', 'no_values') and e.storage_path is not null
       and (p_ids is null or cardinality(p_ids) = 0 or f.id = any(p_ids))
       and (p_kind is null or f.kind = p_kind)
     order by f.read_at desc nulls last
     limit greatest(1, least(coalesce(p_limit, 20), 400))) s), '[]'::jsonb);
end $f$;
revoke all on function public.svc_provider_facts_docs(uuid[], text, integer) from public, anon, authenticated;
grant execute on function public.svc_provider_facts_docs(uuid[], text, integer) to service_role;
